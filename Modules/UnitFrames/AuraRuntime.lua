---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local UnitCanAssist = UnitCanAssist
local UnitCanAttack = UnitCanAttack
local UnitIsVisible = UnitIsVisible
local ipairs, next, pairs, setmetatable, type =
    ipairs, next, pairs, setmetatable, type

local CONFIG_COMMIT_DELAY = 0.15

local STATE_NEW = "NEW"
local STATE_WAITING_FOR_UNIT = "WAITING_FOR_UNIT"
local STATE_READY = "READY"
local STATE_EMPTY = "EMPTY"
local STATE_PARTITION_DEFERRED = "PARTITION_DEFERRED"
local STATE_ERROR = "ERROR"
local STATE_DESTROYED = "DESTROYED"
local GROUP_EMPTY_UNIT = "none"

---------------------------------------------------------------------
-- native aura data-provider observation
---------------------------------------------------------------------
local nativeProviderSupported = UF.HasNativeAuraContainerBackend() == true
local providerUsesTestData
local providerRuntimes = setmetatable({}, {__mode = "k"})
local runtimeStats = {
    runtimesCreated = 0,
    runtimesDestroyed = 0,
    providerSwitchEvents = 0,
    testProviderActivations = 0,
    liveProviderRestorations = 0,
    lateBuildDeferrals = 0,
    lateBuildResumptions = 0,
}

local function IsCleanUnitToken(unit)
    return F.isValueNonSecret(unit)
        and type(unit) == "string"
        and unit ~= ""
end

local function DeepEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then
        return false
    end

    seen = seen or {}
    if seen[left] then
        return seen[left] == right
    end
    seen[left] = right

    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

---------------------------------------------------------------------
-- shared active-runtime watcher
---------------------------------------------------------------------
local activeRuntimes = {}
local watcherRegistered
local watcherSweepScheduled
local watcherPendingRuntimes = {}
local RuntimeSignal
local WATCH_EVENTS = {
    "UNIT_FACTION",
    "UNIT_PHASE",
    "UNIT_NAME_UPDATE",
    "PARTY_MEMBER_ENABLE",
    "PARTY_MEMBER_DISABLE",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
}
local UNIT_ROUTED_EVENTS = {
    UNIT_FACTION = true,
    UNIT_PHASE = true,
    UNIT_NAME_UPDATE = true,
    PARTY_MEMBER_ENABLE = true,
    PARTY_MEMBER_DISABLE = true,
}

local function SweepActiveRuntimes()
    for runtime in pairs(activeRuntimes) do
        runtime:Update(true)
    end
end

local function QueueWatchedRuntime(runtime)
    watcherPendingRuntimes[runtime] = true
end

local function QueueAllWatchedRuntimes()
    for runtime in pairs(activeRuntimes) do
        QueueWatchedRuntime(runtime)
    end
end

local function MatchesStableUnit(runtime, unit)
    return runtime._unit == unit or runtime.root.unit == unit
end

local function FlushWatchedRuntimes()
    local pending = watcherPendingRuntimes
    watcherPendingRuntimes = {}
    watcherSweepScheduled = nil

    for runtime in pairs(pending) do
        if activeRuntimes[runtime] then
            runtime:Update(true)
        end
    end
end

RuntimeSignal = function(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        for runtime in pairs(activeRuntimes) do
            if MatchesStableUnit(runtime, "target") then
                QueueWatchedRuntime(runtime)
            end
        end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        for runtime in pairs(activeRuntimes) do
            if MatchesStableUnit(runtime, "focus") then
                QueueWatchedRuntime(runtime)
            end
        end
    elseif event == "UNIT_FACTION" and unit == "player" then
        -- Player relationship changes can alter visibility/partition policy
        -- for every watched unit even though their own token did not fire.
        QueueAllWatchedRuntimes()
    elseif UNIT_ROUTED_EVENTS[event] and type(unit) == "string" then
        for runtime in pairs(activeRuntimes) do
            if runtime._unit == unit or runtime.root.unit == unit then
                QueueWatchedRuntime(runtime)
            end
        end
    else
        QueueAllWatchedRuntimes()
    end

    if next(watcherPendingRuntimes) and not watcherSweepScheduled then
        watcherSweepScheduled = true
        C_Timer.After(0.05, FlushWatchedRuntimes)
    end

    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, SweepActiveRuntimes)
        C_Timer.After(6, SweepActiveRuntimes)
    end
end

local function SetRuntimeWatched(runtime, watched)
    if watched then
        activeRuntimes[runtime] = true
    else
        activeRuntimes[runtime] = nil
    end

    if next(activeRuntimes) and not watcherRegistered then
        watcherRegistered = true
        for _, event in ipairs(WATCH_EVENTS) do
            UF:RegisterEvent(event, RuntimeSignal)
        end
    elseif watcherRegistered and not next(activeRuntimes) then
        watcherRegistered = nil
        for _, event in ipairs(WATCH_EVENTS) do
            UF:UnregisterEvent(event, RuntimeSignal)
        end
    end
end

---------------------------------------------------------------------
-- shared configuration commit queue
---------------------------------------------------------------------
local combatPendingRuntimes = {}
local combatCommitRegistered
local Commit
local FlushCombatCommits

local function RemoveCombatCommit(runtime)
    combatPendingRuntimes[runtime] = nil
    if combatCommitRegistered and not next(combatPendingRuntimes) then
        combatCommitRegistered = nil
        UF:UnregisterEvent("PLAYER_REGEN_ENABLED", FlushCombatCommits)
    end
end

local function QueueCombatCommit(runtime)
    combatPendingRuntimes[runtime] = true
    runtime._commitScheduled = true
    if not combatCommitRegistered then
        combatCommitRegistered = true
        UF:RegisterEvent("PLAYER_REGEN_ENABLED", FlushCombatCommits)
    end
end

FlushCombatCommits = function()
    if InCombatLockdown() then return end

    local pending = combatPendingRuntimes
    combatPendingRuntimes = {}

    for runtime in pairs(pending) do
        local queuedRuntime = runtime
        C_Timer.After(0, function()
            Commit(queuedRuntime)
        end)
    end
end

---------------------------------------------------------------------
-- state
---------------------------------------------------------------------
local function ResolveUnit(runtime)
    local root = runtime.root

    -- Config mode temporarily rewrites every root to player. Preserve the
    -- last real token (or oldUnit) and never compile/retarget native auras to
    -- that preview-only identity.
    if runtime._configMode or root.inConfigMode then
        if runtime._unit then
            return runtime._unit
        end
        if not F.isValueNonSecret(root.oldUnit) then
            return nil
        end
        return root.oldUnit
    end

    if not F.isValueNonSecret(root.effectiveUnit) then
        return nil
    end
    if root.effectiveUnit ~= nil then
        return root.effectiveUnit
    end
    if not F.isValueNonSecret(root.unit) then
        return nil
    end
    if root.unit ~= nil then
        return root.unit
    end
    return runtime._unit
end

local function ResolveRuntimeUnit(runtime)
    local unit = ResolveUnit(runtime)
    if runtime._groupManaged and not IsCleanUnitToken(unit) then
        -- Fixed-capacity group children are fully configured before combat,
        -- even while empty. "none" registers no useful UNIT_AURA stream and
        -- leaves the first real assignment as a pure live SetUnit/Update.
        return GROUP_EMPTY_UNIT
    end
    return unit
end

local function ShouldEnableNative(runtime)
    return runtime.enabled == true
        and runtime._config ~= nil
        and runtime._config.enabled ~= false
        and runtime.root.enabled ~= false
        and not runtime._reloadRequired
        and not runtime._configMode
        and not runtime.root.inConfigMode
end

local function PassesGate(value)
    if F.isValueNonSecret(value) then
        return value ~= false
    end
    return true
end

local function PassesVisibility(runtime)
    local descriptor = runtime._descriptor
    local unit = runtime._unit
    if not descriptor or not unit then return false end

    -- Blizzard's Edit Mode provider supplies synthetic data for the native
    -- container independent of the live unit's visibility or assistability.
    -- Relation partitions remain controller-owned and are resolved separately.
    if providerUsesTestData then return true end

    local visibility = descriptor.visibility
    -- The compiler exposes aggregate group requirements, so a definite gate
    -- failure intentionally hides the whole plain holder. Ordinary category
    -- gates retain their established fail-open behavior. Spell-ID maps are
    -- stricter: secret, missing, or opposite unit reaction can bypass the
    -- native map for secret-capable auras, so those cases fail closed.
    if visibility.requiresVisible
        and not PassesGate(UnitIsVisible(unit))
    then
        return false
    end
    if visibility.spellIDFilterRequiresPublicAssist
        or visibility.spellIDFilterRequiresPublicNonAssist
    then
        local canAssist = UnitCanAssist("player", unit)
        if not F.isValueNonSecret(canAssist) then
            return false
        end
        if visibility.spellIDFilterRequiresPublicAssist
            and canAssist ~= true
        then
            return false
        end
        if visibility.spellIDFilterRequiresPublicNonAssist
            and canAssist ~= false
        then
            return false
        end
    elseif visibility.requiresAssist
        and not PassesGate(UnitCanAssist("player", unit))
    then
        return false
    end
    return true
end

local function ResolvePartitionVariant(runtime)
    local partition = runtime._descriptor
        and runtime._descriptor.partition
    local selector = partition and partition.selector
    if not runtime._partitionCapable
        or type(selector) ~= "table"
        or selector.kind ~= "unitCanAttack"
    then
        return "friendly"
    end

    local canAttack = UnitCanAttack(
        selector.actorUnit or "player",
        runtime._unit
    )
    if F.isValueNonSecret(canAttack) and canAttack == true then
        return "hostile"
    end
    return "friendly"
end

local function ShouldShowNative(runtime)
    return runtime._state == STATE_READY
        and runtime._active
        and not runtime._configDirty
        and ShouldEnableNative(runtime)
        and PassesVisibility(runtime)
end

local function SyncWatcher(runtime)
    local visibility = runtime._descriptor
        and runtime._descriptor.visibility
    local hasLiveGate = not providerUsesTestData
        and visibility
        and (
            visibility.requiresVisible
            or visibility.requiresAssist
            or visibility.spellIDFilterRequiresPublicAssist
            or visibility.spellIDFilterRequiresPublicNonAssist
        )
    local hasDynamicUnit = MatchesStableUnit(runtime, "target")
        or MatchesStableUnit(runtime, "focus")
    local hasPartitionSelector = runtime._partitionCapable
        and runtime._descriptor
        and runtime._descriptor.partition
        and runtime._descriptor.partition.selector ~= nil
    SetRuntimeWatched(
        runtime,
        runtime._active
            and runtime._state == STATE_READY
            and (
                hasLiveGate
                or hasDynamicUnit
                or hasPartitionSelector
            )
            and ShouldEnableNative(runtime)
            and not runtime._destroyed
    )
end

local function Quiesce(runtime)
    if runtime._built then
        runtime._controller:SetShown(false)
        runtime._controller:SetEnabled(false)
    end
    SyncWatcher(runtime)
end

local function QuiesceForReload(runtime)
    SetRuntimeWatched(runtime, false)
    if not runtime._built then return end

    -- The plain holder can be hidden immediately through the controller's
    -- hover-safe visibility path. Disabling the native container remains
    -- runtime-owned OOC work so a topology change cannot smuggle a protected
    -- mutation through an enable/disable or config-mode lifecycle call.
    runtime._controller:SetShown(false)
    if InCombatLockdown() then
        runtime._reloadQuiescePending = true
        QueueCombatCommit(runtime)
        return
    end

    runtime._reloadQuiescePending = nil
    RemoveCombatCommit(runtime)
    runtime._controller:SetEnabled(false)
end

local function SyncLifecycle(runtime)
    if runtime._reloadRequired then
        QuiesceForReload(runtime)
        return
    end

    if not runtime._built then
        SyncWatcher(runtime)
        return
    end

    local enabled = runtime._state == STATE_READY
        and ShouldEnableNative(runtime)
    local shown = enabled and ShouldShowNative(runtime)

    if runtime._partitionCapable then
        runtime._partitionVariant = ResolvePartitionVariant(runtime)
        runtime._controller:SetVariant(runtime._partitionVariant)
    end
    if not shown then
        runtime._controller:SetShown(false)
    end
    runtime._controller:SetEnabled(enabled)
    if shown then
        runtime._controller:SetShown(true)
    end
    SyncWatcher(runtime)
end

local function Compile(runtime, unit)
    if not IsCleanUnitToken(unit) then
        runtime._unit = nil
        runtime._descriptor = nil
        runtime._error = nil
        runtime._partitionVariant = nil
        runtime._state = STATE_WAITING_FOR_UNIT
        runtime._providerBuildDeferred = nil
        return
    end

    runtime._unit = unit
    local descriptor, compileError = UF.CompileNativeAuraSpec(
        unit,
        runtime.auraFilter,
        runtime._config
    )
    runtime._descriptor = descriptor
    runtime._error = compileError

    if not descriptor then
        runtime._state = STATE_ERROR
    elseif descriptor.empty then
        runtime._state = STATE_EMPTY
    elseif not descriptor.migrationReady
        or (descriptor.partition and not runtime._partitionCapable)
    then
        runtime._state = STATE_PARTITION_DEFERRED
    else
        runtime._state = STATE_READY
    end

    if runtime._state ~= STATE_READY then
        runtime._providerBuildDeferred = nil
    end

    if runtime._partitionCapable and descriptor and descriptor.partition then
        runtime._partitionVariant = ResolvePartitionVariant(runtime)
    else
        runtime._partitionVariant = nil
    end
end

local BuildControllerDescriptor

local function RequiresReloadForDescriptor(runtime, descriptor)
    local controllerDescriptor = descriptor
        and BuildControllerDescriptor(runtime, descriptor)
    return runtime._built == true
        and controllerDescriptor ~= nil
        and descriptor.migrationReady == true
        and descriptor.empty ~= true
        and (descriptor.partition == nil or runtime._partitionCapable)
        and controllerDescriptor.constructionKey ~= nil
        and not DeepEqual(
            runtime._constructionKey,
            controllerDescriptor.constructionKey
        )
end

local function CompileComparisonDescriptor(runtime, config)
    local unit = ResolveRuntimeUnit(runtime)
    if not IsCleanUnitToken(unit) then
        unit = runtime._appliedUnit
    end
    if not IsCleanUnitToken(unit) then return nil end

    local descriptor = UF.CompileNativeAuraSpec(
        unit,
        runtime.auraFilter,
        AF.Copy(config)
    )
    return descriptor
end

local function CancelPendingCommitWork(runtime)
    runtime._commitGeneration = runtime._commitGeneration + 1
    runtime._commitScheduled = nil
    runtime._configDirty = nil
    runtime._unitDirty = nil
    runtime._deferredCommit = nil
    runtime._reloadQuiescePending = nil
    RemoveCombatCommit(runtime)
end

local function SetReloadRequired(runtime, required)
    if not required then
        if runtime._reloadRequired or runtime._reloadQuiescePending then
            runtime._reloadRequired = nil
            runtime._reloadQuiescePending = nil
            -- A same-topology config that supersedes the reload state in
            -- combat still needs the already-owned regen turn for its latest
            -- tuning. Preserve that queue; only cancel a reload quiesce when
            -- the replacement config can be committed immediately.
            if not InCombatLockdown() or not runtime._configDirty then
                runtime._commitScheduled = nil
                RemoveCombatCommit(runtime)
            end
        end
        return false
    end

    runtime._reloadRequired = true
    CancelPendingCommitWork(runtime)
    QuiesceForReload(runtime)
    return true
end

local function ApplyPlacement(runtime, descriptor)
    local placement = AF.Copy(descriptor.placement)
    local root = runtime.root

    runtime._controller:ApplyHolderConfig(function(holder)
        AF.SetFrameLevel(holder, placement.frameLevel, root)
        UF.LoadIndicatorPosition(
            holder,
            placement.position,
            placement.anchorTo
        )
    end)
end

local function GetVariantField(variant, field)
    return variant and variant[field] or nil
end

local function CopyOptional(value)
    return type(value) == "table" and AF.Copy(value) or value
end

BuildControllerDescriptor = function(runtime, descriptor)
    if not runtime._partitionCapable then
        return {
            completeSpec = descriptor.completeSpec,
            tuningSpec = descriptor.tuningSpec,
            constructionKey = descriptor.constructionKey,
        }
    end

    local partition = descriptor.partition
    local hostile = partition and partition.hostile
    local main = hostile and hostile.main
    local complement = hostile and hostile.complement
    local holder = partition
        and partition.holder
        or descriptor.completeSpec.holder

    runtime._partitionVariant = ResolvePartitionVariant(runtime)
    return {
        completeSpec = {
            unit = runtime._unit,
            enabled = true,
            shown = false,
            variant = runtime._partitionVariant,
            holder = AF.Copy(holder),
            friendly = AF.Copy(descriptor.completeSpec),
            main = CopyOptional(GetVariantField(main, "completeSpec")),
            complement = CopyOptional(
                GetVariantField(complement, "completeSpec")
            ),
            attachment = CopyOptional(hostile and hostile.attachment),
        },
        tuningSpec = {
            holder = AF.Copy(holder),
            friendly = AF.Copy(descriptor.tuningSpec),
            main = CopyOptional(GetVariantField(main, "tuningSpec")),
            complement = CopyOptional(
                GetVariantField(complement, "tuningSpec")
            ),
            attachment = CopyOptional(hostile and hostile.attachment),
        },
        -- Construction-only button styles differ between the friendly,
        -- hostile main, and hostile complement variants. Include every
        -- prebuilt topology so subframe appearance changes rebuild instead
        -- of being submitted as unsupported tuning.
        constructionKey = {
            kind = "relationPartition",
            friendly = AF.Copy(descriptor.constructionKey),
            main = CopyOptional(
                GetVariantField(main, "constructionKey")
            ),
            complement = CopyOptional(
                GetVariantField(complement, "constructionKey")
            ),
        },
    }
end

Commit = function(runtime)
    runtime._commitScheduled = nil
    if runtime._destroyed then
        RemoveCombatCommit(runtime)
        return
    end

    if runtime._reloadRequired then
        runtime._configDirty = nil
        runtime._unitDirty = nil
        runtime._deferredCommit = nil
        QuiesceForReload(runtime)
        return
    end

    if RequiresReloadForDescriptor(runtime, runtime._descriptor) then
        SetReloadRequired(runtime, true)
        return
    end

    if runtime._configMode or runtime.root.inConfigMode then
        RemoveCombatCommit(runtime)
        runtime._deferredCommit = true
        return
    end

    if runtime._state ~= STATE_READY then
        RemoveCombatCommit(runtime)
        -- A secret/temporarily unavailable unit prevents compilation against
        -- the latest config. Keep that config dirty for an existing native
        -- container so the first clean-unit recovery applies its tuning and
        -- placement instead of performing only a retarget. There is no
        -- reschedule here, so WAITING remains dormant until a unit signal.
        -- Terminal compiler results still supersede and quiesce pending work.
        if runtime._state ~= STATE_WAITING_FOR_UNIT
            or not runtime._built
        then
            runtime._configDirty = nil
        end
        runtime._unitDirty = nil
        runtime._deferredCommit = nil
        Quiesce(runtime)
        return
    end

    if not ShouldEnableNative(runtime) then
        RemoveCombatCommit(runtime)
        runtime._deferredCommit = true
        SyncLifecycle(runtime)
        return
    end

    -- A provider switch is Blizzard-owned. If Edit Mode test data became
    -- active before this runtime's first native build, wait for the real
    -- provider restoration instead of allocating from BFI during the test
    -- session. Existing containers continue to consume the provider switch
    -- intrinsically and never pass through this construction guard.
    if runtime._configDirty
        and not runtime._built
        and providerUsesTestData
    then
        RemoveCombatCommit(runtime)
        if not runtime._providerBuildDeferred then
            runtime._providerBuildDeferred = true
            runtimeStats.lateBuildDeferrals =
                runtimeStats.lateBuildDeferrals + 1
        end
        runtime._deferredCommit = true
        SyncWatcher(runtime)
        return
    end

    -- Never submit configuration/replacement work to the controller until it
    -- can finish synchronously. This lets a later empty/error/disabled config
    -- supersede the pending descriptor without allocating stale restricted
    -- button batches after combat. Holder visibility is owned by the
    -- controller's ordinary write ledger and must not be observed here.
    if runtime._configDirty and InCombatLockdown() then
        -- A group child's clean token can still change while an unrelated
        -- structural config edit waits for regen. Retarget the already-built
        -- container now; keep it hidden and leave the config commit queued.
        if runtime._groupManaged
            and runtime._built
            and runtime._unitDirty
        then
            runtime._controller:SetUnit(runtime._unit)
            runtime._appliedUnit = runtime._unit
            runtime._unitDirty = nil
        end
        QueueCombatCommit(runtime)
        return
    end
    RemoveCombatCommit(runtime)

    local descriptor = runtime._descriptor
    local controllerDescriptor = BuildControllerDescriptor(
        runtime,
        descriptor
    )
    local constructionChanged = not runtime._built
        or not DeepEqual(
            runtime._constructionKey,
            controllerDescriptor.constructionKey
        )

    if runtime._configDirty then
        ApplyPlacement(runtime, descriptor)

        if constructionChanged then
            local completeSpec = AF.Copy(
                controllerDescriptor.completeSpec
            )
            completeSpec.unit = runtime._unit
            completeSpec.enabled = true
            completeSpec.shown = ShouldShowNative(runtime)
            runtime._controller:Rebuild(completeSpec)
            runtime._built = true
        else
            runtime._controller:ApplyTuning(
                controllerDescriptor.tuningSpec
            )
            if runtime._appliedUnit ~= runtime._unit then
                runtime._controller:SetUnit(runtime._unit)
            end
        end

        runtime._constructionKey = AF.Copy(
            controllerDescriptor.constructionKey
        )
    elseif runtime._unitDirty and runtime._built then
        runtime._controller:SetShown(false)
        runtime._controller:SetUnit(runtime._unit)
    end

    runtime._appliedUnit = runtime._unit
    runtime._configDirty = nil
    runtime._unitDirty = nil
    runtime._deferredCommit = nil
    SyncLifecycle(runtime)
end

local function ScheduleCommit(runtime, immediate)
    runtime._commitGeneration = runtime._commitGeneration + 1
    local generation = runtime._commitGeneration
    runtime._commitScheduled = true

    if immediate then
        Commit(runtime)
        return
    end

    -- Trailing-edge generation checks coalesce tuning and the initial native
    -- build across intermediate slider/filter edits. Construction changes
    -- after that build are reload-only. Old callbacks cannot apply stale
    -- configuration.
    C_Timer.After(CONFIG_COMMIT_DELAY, function()
        if not runtime._destroyed
            and generation == runtime._commitGeneration
        then
            Commit(runtime)
        end
    end)
end

local function SyncProviderVisibility(runtime)
    if runtime._destroyed or not runtime._built then return end

    -- SetShown updates the controller's write-only presentation ledger. Do
    -- not rebuild, tune, retarget, refresh, or drive Blizzard update methods
    -- in response to a provider switch.
    runtime._controller:SetShown(ShouldShowNative(runtime) == true)
end

local function NativeAuraProviderSignal(_, _, useRealDataProvider)
    runtimeStats.providerSwitchEvents =
        runtimeStats.providerSwitchEvents + 1

    local useTestData = useRealDataProvider == false
    providerUsesTestData = useTestData or nil
    if useTestData then
        runtimeStats.testProviderActivations =
            runtimeStats.testProviderActivations + 1
    else
        runtimeStats.liveProviderRestorations =
            runtimeStats.liveProviderRestorations + 1
    end

    for runtime in pairs(providerRuntimes) do
        if not useTestData
            and not runtime._built
            and runtime._providerBuildDeferred
        then
            runtime._providerBuildDeferred = nil
            runtimeStats.lateBuildResumptions =
                runtimeStats.lateBuildResumptions + 1
            ScheduleCommit(runtime, true)
        else
            SyncProviderVisibility(runtime)
            SyncWatcher(runtime)
        end
    end
end

-- Retail 12.1.0.69273 (wow-ui-source eb941aad) exposes
-- AURA_DATA_PROVIDER_SWITCH as a synchronous
-- boolean real-provider state signal (Blizzard_APIDocumentationGenerated /
-- UnitAuraDocumentation.lua). BFI observes that state only; Blizzard Edit
-- Mode and AuraContainer remain the sole owners of provider switching.
if nativeProviderSupported then
    UF:RegisterEvent(
        "AURA_DATA_PROVIDER_SWITCH",
        NativeAuraProviderSignal
    )
end

function UF.GetNativeAuraRuntimeStats()
    local liveRuntimes = 0
    for runtime in pairs(providerRuntimes) do
        if not runtime._destroyed then
            liveRuntimes = liveRuntimes + 1
        end
    end

    -- Always return a fresh, flat scalar snapshot. Construction/allocation
    -- totals are owned separately by UF.GetNativeAuraConstructionStats().
    return {
        nativeBackendAvailable = nativeProviderSupported,
        runtimesCreated = runtimeStats.runtimesCreated,
        runtimesDestroyed = runtimeStats.runtimesDestroyed,
        liveRuntimes = liveRuntimes,
        providerSwitchEvents = runtimeStats.providerSwitchEvents,
        testProviderActivations = runtimeStats.testProviderActivations,
        liveProviderRestorations = runtimeStats.liveProviderRestorations,
        lateBuildDeferrals = runtimeStats.lateBuildDeferrals,
        lateBuildResumptions = runtimeStats.lateBuildResumptions,
        testProviderActive = providerUsesTestData == true,
    }
end

local function StageUnit(runtime, unit)
    local unitIsNonSecret = F.isValueNonSecret(unit)
    local unitIsEmpty = unitIsNonSecret
        and (type(unit) ~= "string" or unit == "")
    if unitIsEmpty
        and runtime._unit == nil
        and runtime._state == STATE_WAITING_FOR_UNIT
    then
        return false
    end

    if not unitIsNonSecret or unitIsEmpty then
        if runtime._built then
            runtime._controller:SetShown(false)
        end
        runtime._unit = nil
        runtime._descriptor = nil
        runtime._error = nil
        runtime._partitionVariant = nil
        runtime._state = STATE_WAITING_FOR_UNIT
        runtime._providerBuildDeferred = nil
        runtime._unitDirty = true
        return true
    end

    if unit == runtime._unit then return false end

    if runtime._built then
        runtime._controller:SetShown(false)
    end

    if runtime._descriptor and type(unit) == "string" and unit ~= "" then
        runtime._unit = unit
        if runtime._descriptor.completeSpec then
            runtime._descriptor.completeSpec.unit = unit
        end
    else
        Compile(runtime, unit)
        if runtime._state == STATE_READY and not runtime._built then
            runtime._configDirty = true
        end
    end
    runtime._unitDirty = true
    return true
end

---------------------------------------------------------------------
-- config preview
---------------------------------------------------------------------
local function EnsurePreview(runtime)
    if runtime._preview then return runtime._preview end

    runtime._preview = UF.CreateAuras(
        runtime.root,
        runtime:GetName() .. "_ConfigPreview",
        runtime.auraFilter,
        runtime._hasSubFrame
    )
    return runtime._preview
end

local function DisablePreview(runtime)
    if not runtime._preview then return end

    runtime._preview:DisableConfigMode()
    runtime._preview:Disable()
end

local function SyncPreview(runtime)
    local preview = EnsurePreview(runtime)
    preview.enabled = runtime.enabled
    if runtime._config then
        preview:LoadConfig(AF.Copy(runtime._config))
    end
    preview:EnableConfigMode()
end

---------------------------------------------------------------------
-- indicator methods
---------------------------------------------------------------------
local function NativeAuras_LoadConfig(self, config)
    if self._destroyed then return end

    if self._configMode and not self.root.inConfigMode then
        DisablePreview(self)
        self._configMode = nil
        self._resumeAfterConfigMode = nil
    end

    local firstConfig = self._config == nil
    self._config = AF.Copy(config)
    self._configDirty = true

    Compile(self, ResolveRuntimeUnit(self))

    local comparisonDescriptor = self._descriptor
    if self._built and not comparisonDescriptor then
        comparisonDescriptor = CompileComparisonDescriptor(
            self,
            self._config
        )
    end
    local reloadRequired = RequiresReloadForDescriptor(
        self,
        comparisonDescriptor
    )
    SetReloadRequired(self, reloadRequired)

    if reloadRequired then
        if self._configMode or self.root.inConfigMode then
            SyncPreview(self)
        end
        return
    end

    SyncWatcher(self)

    if self._built then
        self._controller:SetShown(false)
        if not ShouldEnableNative(self) then
            self._controller:SetEnabled(false)
        end
    end

    if self._configMode or self.root.inConfigMode then
        self._commitGeneration = self._commitGeneration + 1
        self._commitScheduled = nil
        self._deferredCommit = true
        SyncPreview(self)
        return
    end

    ScheduleCommit(self, firstConfig)
end

local function NativeAuras_Enable(self)
    if self._destroyed then return end
    if self.root.inConfigMode then
        self:EnableConfigMode()
        return
    end

    if self._configMode then
        DisablePreview(self)
    end
    self._configMode = nil
    self._resumeAfterConfigMode = nil
    self._active = true

    local unitChanged = StageUnit(self, ResolveRuntimeUnit(self))
    if unitChanged or self._configDirty or self._deferredCommit then
        ScheduleCommit(self, true)
    else
        SyncLifecycle(self)
        if self._built
            and self._state == STATE_READY
            and not providerUsesTestData
        then
            self._controller:Refresh()
        end
    end
end

local function NativeAuras_Disable(self)
    if self._destroyed then return end

    self._active = nil
    SetRuntimeWatched(self, false)
    if self._reloadRequired then
        QuiesceForReload(self)
    elseif self._built then
        self._controller:SetShown(false)
        if self.root.inConfigMode or self._configMode then
            self._controller:SetEnabled(false)
        elseif not ShouldEnableNative(self) then
            self._controller:SetEnabled(false)
        end
    end

    if self._resumeAfterConfigMode and not self.root.inConfigMode then
        self._resumeAfterConfigMode = nil
        StageUnit(self, ResolveRuntimeUnit(self))
        ScheduleCommit(self, true)
    end
end

local function NativeAuras_Update(self)
    if self._destroyed or self._configMode or self.root.inConfigMode then
        return
    end

    if StageUnit(self, ResolveRuntimeUnit(self)) then
        ScheduleCommit(self, true)
        return
    end

    SyncLifecycle(self)
    if self._built
        and self._state == STATE_READY
        and not self._reloadRequired
        and not providerUsesTestData
    then
        -- Stable tokens such as target/focus can change entity without their
        -- text changing. The native dirty mark remains aura-data opaque.
        self._controller:Refresh()
    end
end

local function NativeAuras_SetUnit(self, unit)
    if self._destroyed or self._configMode or self.root.inConfigMode then
        return
    end

    if StageUnit(self, unit) then
        ScheduleCommit(self, true)
    else
        self:Update(true)
    end
end

local function NativeAuras_RefreshVisibility(self)
    if self._destroyed then return end
    SyncLifecycle(self)
end

local function NativeAuras_EnableConfigMode(self)
    if self._destroyed then return end

    self._active = nil
    self._configMode = true
    SetRuntimeWatched(self, false)
    if self._reloadRequired then
        QuiesceForReload(self)
    elseif self._built then
        self._controller:SetShown(false)
        self._controller:SetEnabled(false)
    end
    SyncPreview(self)
end

local function NativeAuras_DisableConfigMode(self)
    if self._destroyed or not self._configMode then return end

    if self._preview then
        DisablePreview(self)
    end

    self._configMode = nil
    self._resumeAfterConfigMode = true
    self._deferredCommit = not self._reloadRequired or nil
    if self._reloadRequired then
        QuiesceForReload(self)
    elseif self._built then
        self._controller:SetShown(false)
        self._controller:SetEnabled(false)
    end
end

local function NativeAuras_RequiresReloadForConfig(self, config)
    if self._destroyed
        or not self._built
        or type(config) ~= "table"
    then
        return false
    end

    local descriptor = CompileComparisonDescriptor(self, config)
    return RequiresReloadForDescriptor(self, descriptor)
end

local function NativeAuras_GetState(self)
    local descriptor = self._descriptor
    return {
        state = self._state,
        error = self._error,
        unit = self._unit,
        active = self._active == true,
        built = self._built == true,
        pending = self._commitScheduled == true
            or self._configDirty == true
            or self._unitDirty == true
            or self._deferredCommit == true
            or self._reloadQuiescePending == true,
        configMode = self._configMode == true,
        reloadRequired = self._reloadRequired == true,
        providerMode = providerUsesTestData and "test" or "live",
        providerBuildDeferred = self._providerBuildDeferred == true,
        migrationReady = descriptor and descriptor.migrationReady or false,
        empty = descriptor and descriptor.empty or false,
        visibility = CopyOptional(
            descriptor and descriptor.visibility
        ),
        partition = CopyOptional(
            descriptor and descriptor.partition
        ),
        partitionVariant = self._partitionVariant,
        diagnostics = CopyOptional(
            descriptor and descriptor.diagnostics
        ) or {},
        degradations = CopyOptional(
            descriptor and descriptor.degradations
        ) or {},
        metrics = CopyOptional(
            descriptor and descriptor.metrics
        ) or {},
    }
end

local function NativeAuras_Destroy(self)
    if self._destroyed then return end

    self._destroyed = true
    self._state = STATE_DESTROYED
    self._commitGeneration = self._commitGeneration + 1
    self._commitScheduled = nil
    self._configDirty = nil
    self._unitDirty = nil
    self._deferredCommit = nil
    self._resumeAfterConfigMode = nil
    self._active = nil
    self._configMode = nil
    self._reloadRequired = nil
    self._reloadQuiescePending = nil
    self._providerBuildDeferred = nil
    providerRuntimes[self] = nil
    runtimeStats.runtimesDestroyed = runtimeStats.runtimesDestroyed + 1
    SetRuntimeWatched(self, false)
    RemoveCombatCommit(self)

    if self._preview then
        self._preview.enabled = false
        self._preview:DisableConfigMode()
        self._preview:Disable()
        if AF.RemoveFromPixelUpdater then
            AF.RemoveFromPixelUpdater(self._preview)
        end
    end
    if AF.RemoveFromPixelUpdater then
        AF.RemoveFromPixelUpdater(self)
    end
    self._controller:Destroy()
end

local function NativeAuras_UpdatePixels(self)
    if self._destroyed or self._reloadRequired then return end

    self._controller:ApplyHolderConfig(function(holder)
        AF.ReSize(holder)
        AF.RePoint(holder)
    end)
end

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function InitializeNativeAuraIndicator(
    parent,
    auraFilter,
    hasSubFrame,
    controller,
    partitionCapable,
    groupManaged
)
    local frame = controller:GetFrame()
    frame.root = parent
    frame.auraFilter = auraFilter
    frame._hasSubFrame = hasSubFrame == true
    frame._partitionCapable = partitionCapable == true
    frame._controller = controller
    frame._groupManaged = groupManaged == true
    frame._state = STATE_NEW
    frame._commitGeneration = 0
    providerRuntimes[frame] = true
    runtimeStats.runtimesCreated = runtimeStats.runtimesCreated + 1

    frame.LoadConfig = NativeAuras_LoadConfig
    frame.Enable = NativeAuras_Enable
    frame.Disable = NativeAuras_Disable
    frame.Update = NativeAuras_Update
    frame.SetUnit = NativeAuras_SetUnit
    frame.RefreshVisibility = NativeAuras_RefreshVisibility
    frame.EnableConfigMode = NativeAuras_EnableConfigMode
    frame.DisableConfigMode = NativeAuras_DisableConfigMode
    frame.RequiresReloadForConfig = NativeAuras_RequiresReloadForConfig
    frame.GetNativeAuraState = NativeAuras_GetState
    frame.Destroy = NativeAuras_Destroy

    AF.AddToPixelUpdater_Auto(frame, NativeAuras_UpdatePixels, true)
    return frame
end

function UF.CreateNativeAuraIndicator(parent, name, auraFilter, hasSubFrame)
    if not UF.HasNativeAuraContainerBackend() then
        return nil, "NATIVE_AURA_BACKEND_UNAVAILABLE"
    end

    local controller = UF.CreateNativeAuraContainerController(parent, name)
    if not controller then
        return nil, "NATIVE_AURA_BACKEND_UNAVAILABLE"
    end
    return InitializeNativeAuraIndicator(
        parent,
        auraFilter,
        hasSubFrame,
        controller,
        false,
        false
    )
end

function UF.CreateNativePartitionedAuraIndicator(
    parent,
    name,
    auraFilter,
    hasSubFrame
)
    if not UF.HasNativeAuraContainerBackend() then
        return nil, "NATIVE_AURA_BACKEND_UNAVAILABLE"
    end

    local controller = UF.CreateNativeAuraPartitionController(
        parent,
        name
    )
    if not controller then
        return nil, "NATIVE_AURA_BACKEND_UNAVAILABLE"
    end

    return InitializeNativeAuraIndicator(
        parent,
        auraFilter,
        hasSubFrame,
        controller,
        true,
        false
    )
end

function UF.CreateNativeGroupAuraIndicator(
    parent,
    name,
    auraFilter,
    seedContainer
)
    if not UF.HasNativeAuraContainerBackend() then
        return nil, "NATIVE_AURA_BACKEND_UNAVAILABLE"
    end

    local controller = UF.CreateNativeGroupAuraContainerController(
        parent,
        name,
        seedContainer
    )
    if not controller then
        return nil, "NATIVE_AURA_BACKEND_UNAVAILABLE"
    end
    return InitializeNativeAuraIndicator(
        parent,
        auraFilter,
        false,
        controller,
        false,
        true
    )
end

-- Group-frame integrations provide a per-child map of explicitly allocated
-- native shells. The backend check comes first so an unavailable backend
-- neither accesses that map nor sets native header/container state.
function UF.CreateGroupNativeAuras(parent, name, auraFilter, containerKey)
    if not UF.HasNativeAuraContainerBackend() then
        return UF.CreateAuras(parent, name, auraFilter)
    end

    local containers = parent._nativeAuraContainers
    local seedContainer = containers and containers[containerKey]
    assert(seedContainer, "native group aura container seed is missing")
    return UF.CreateNativeGroupAuraIndicator(
        parent,
        name,
        auraFilter,
        seedContainer
    )
end

-- Keep Target's complementary subframe on the established fallback until a
-- frame-specific PR explicitly adopts a migration-ready native contract.
function UF.CreateNativeAuras(parent, name, auraFilter, hasSubFrame)
    if hasSubFrame or not UF.HasNativeAuraContainerBackend() then
        return UF.CreateAuras(parent, name, auraFilter, hasSubFrame)
    end
    return UF.CreateNativeAuraIndicator(
        parent,
        name,
        auraFilter,
        hasSubFrame
    )
end

-- Opt-in builder for frame integrations that have accepted the compiled
-- relation-partition contract. The legacy implementation remains the exact
-- fallback when the 12.1 native backend is unavailable.
function UF.CreateNativePartitionedAuras(
    parent,
    name,
    auraFilter,
    hasSubFrame
)
    if not UF.HasNativeAuraContainerBackend() then
        return UF.CreateAuras(parent, name, auraFilter, hasSubFrame)
    end
    return UF.CreateNativePartitionedAuraIndicator(
        parent,
        name,
        auraFilter,
        hasSubFrame
    )
end
