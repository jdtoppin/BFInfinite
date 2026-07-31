---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local C_Timer = C_Timer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local floor, huge = math.floor, math.huge
local ipairs, next, pairs, type = ipairs, next, pairs, type

-- Retail 12.1.0.68914 (wow-ui-source d3915c78) makes native aura
-- groups/slots add-only and restricts their buttons after initialization.
-- This controller owns only configuration-derived state and never reads aura
-- data, live buttons, native container geometry, or native visibility.
-- AF #22/r34 includes caller-supplied static Block colors for native groups.
local REQUIRED_AF_VERSION = 34
local NATIVE_GROUP_AURA_TEMPLATE = "CustomAuraContainerTemplate"
-- CustomAuraContainerConstants.FrameCreationBatchSize in the pinned build.
local NATIVE_INITIAL_GROUP_RESERVATIONS = 10
local REQUIRED_AF_METHODS = {
    "AddCustomAuraGroup",
    "AddCustomAuraSlot",
    "CreateCustomAuraContainer",
    "GetCustomAuraContainerConstructionStats",
    "GetCustomAuraContainerConstructionTotals",
    "HasCustomAuraContainer",
    "SetCustomAuraContainerEnabled",
    "SetCustomAuraContainerFlowLayout",
    "SetCustomAuraContainerProcessingPolicy",
    "SetCustomAuraContainerUnit",
    "SetCustomAuraGroupCandidateFilters",
    "SetCustomAuraGroupFilterString",
    "SetCustomAuraGroupLayout",
    "SetCustomAuraGroupMaxFrameCount",
    "SetCustomAuraGroupSortMethod",
    "SetCustomAuraSlotCandidateFilters",
    "SetCustomAuraSlotFilterString",
    "SetCustomAuraSlotSortMethod",
    "UpdateCustomAuraContainer",
}

local constructionStats = {
    controllersCreated = 0,
    destroyRequests = 0,
    destroyCompletions = 0,
    seedsAllocated = 0,
    seedsClaimed = 0,
    buildAttempts = 0,
    buildCompletions = 0,
    frameworkBuilds = 0,
    adoptedBuilds = 0,
    expectedGroups = 0,
    expectedSlots = 0,
    expectedInitialReservations = 0,
    retiredNativeShells = 0,
    retiredInitialReservations = 0,
    strandedNativeShells = 0,
    strandedInitialReservations = 0,
}

local AF_CONSTRUCTION_TOTAL_FIELDS = {
    containerCreateAttempts = "afContainerCreateAttempts",
    containerAllocations = "afContainerAllocations",
    containerCreateCompletions = "afContainerCreateCompletions",
    trackedContainers = "afTrackedContainers",
    externalContainersObserved = "afExternalContainersObserved",
    groupAddAttempts = "afGroupAddAttempts",
    groupsAdded = "afGroupsAdded",
    slotAddAttempts = "afSlotAddAttempts",
    slotsAdded = "afSlotsAdded",
    itemEnchantmentAddAttempts = "afItemEnchantmentAddAttempts",
    itemEnchantmentsAdded = "afItemEnchantmentsAdded",
    initialFrameReservationsAttempted = "afInitialFrameReservationsAttempted",
    initialFrameReservationsCompleted = "afInitialFrameReservationsCompleted",
}

-- This is an explicit, cold-path snapshot. It combines BFI's logical
-- ownership ledger with AF's construction ledger without reading native
-- containers, groups, slots, restricted buttons, or aura data.
function UF.GetNativeAuraConstructionStats()
    local result = {}
    for field, value in pairs(constructionStats) do
        result[field] = value
    end
    result.liveControllers =
        constructionStats.controllersCreated - constructionStats.destroyCompletions
    result.incompleteBuilds =
        constructionStats.buildAttempts - constructionStats.buildCompletions

    if type(AF.GetCustomAuraContainerConstructionTotals) == "function" then
        local afTotals = AF.GetCustomAuraContainerConstructionTotals()
        for sourceField, resultField in pairs(AF_CONSTRUCTION_TOTAL_FIELDS) do
            result[resultField] = afTotals[sourceField] or 0
        end
    else
        for _, resultField in pairs(AF_CONSTRUCTION_TOTAL_FIELDS) do
            result[resultField] = 0
        end
    end

    return result
end

local function IsNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function IsNonNegativeIntegerOrInfinity(value)
    return value == huge
        or (type(value) == "number" and value >= 0 and value == floor(value))
end

function UF.HasNativeAuraContainerBackend()
    if not AF.isRetail or (tonumber(AF.versionNum) or 0) < REQUIRED_AF_VERSION then
        return false
    end

    for _, methodName in ipairs(REQUIRED_AF_METHODS) do
        if type(AF[methodName]) ~= "function" then
            return false
        end
    end

    return AF.HasCustomAuraContainer()
end

-- Retail 12.1 SecureGroupHeaderTemplate creates one unconfigured
-- AuraContainer for each child when this attribute is present before the
-- child is born. 12.0.7 does not know the attribute, so callers must use
-- this capability-gated helper instead of setting it unconditionally.
function UF.PrepareNativeGroupAuraHeader(header)
    if not UF.HasNativeAuraContainerBackend() then
        return false
    end

    header:SetAttribute("auraContainerTemplate", NATIVE_GROUP_AURA_TEMPLATE)
    return true
end

-- Group frames can need more than Blizzard's single header-born container
-- when displays have independent anchors and flow layouts. Create those
-- bounded extra shells eagerly, before combat and before indicator setup.
function UF.CreateNativeGroupAuraContainerSeed(parent)
    if not UF.HasNativeAuraContainerBackend() then
        return nil
    end

    local container = AF.CreateCustomAuraContainer(parent)
    constructionStats.seedsAllocated = constructionStats.seedsAllocated + 1
    -- A newly allocated/header-adjacent shell must be visually inert even if
    -- it is created while protected visibility writes are unavailable.
    container:SetAlpha(0)
    if not InCombatLockdown() then
        container:Hide()
        AF.SetCustomAuraContainerEnabled(container, false)
    end
    return container
end

local function CopyTable(value)
    return type(value) == "table" and AF.Copy(value) or value
end

local function NormalizePoint(point, defaultPoint)
    point = point or defaultPoint
    assert(type(point) == "table", "aura container point must be a table")
    assert(IsNonEmptyString(point.point), "aura container point must be a non-empty string")
    assert(IsNonEmptyString(point.relativePoint), "aura container relativePoint must be a non-empty string")

    return {
        point = point.point,
        relativePoint = point.relativePoint,
        x = point.x or 0,
        y = point.y or 0,
    }
end

local function NormalizeHolder(holder)
    assert(type(holder) == "table", "aura container holder must be a table")
    assert(type(holder.width) == "number" and holder.width > 0,
        "aura container holder width must be positive")
    assert(type(holder.height) == "number" and holder.height > 0,
        "aura container holder height must be positive")

    return {
        width = holder.width,
        height = holder.height,
    }
end

local function NormalizeProcessing(processing)
    if processing == nil then
        return {
            policy = CustomAuraContainerAuraProcessingPolicy.None,
        }
    end

    assert(type(processing) == "table", "aura processing policy must be a table")
    assert(processing.policy ~= nil, "aura processing policy is required")
    return {
        policy = processing.policy,
        options = CopyTable(processing.options),
    }
end

local function NormalizeSort(sortMethod, sortDirection)
    if sortMethod == nil then
        sortMethod = AuraContainerSortMethod.Default
    end
    if sortDirection == nil then
        sortDirection = AuraContainerSortDirection.Normal
    end
    return sortMethod, sortDirection
end

local function ClaimKey(seenKeys, key)
    assert(IsNonEmptyString(key), "aura source key must be a non-empty string")
    assert(not seenKeys[key], "aura source keys must be unique")
    seenKeys[key] = true
end

local function NormalizeGroup(group, seenKeys, includeStyle)
    assert(type(group) == "table", "aura group must be a table")
    ClaimKey(seenKeys, group.key)
    assert(IsNonEmptyString(group.filterString), "aura group filterString must be a non-empty string")
    assert(IsNonNegativeIntegerOrInfinity(group.maxFrameCount),
        "aura group maxFrameCount must be a non-negative integer or infinity")

    local sortMethod, sortDirection = NormalizeSort(group.sortMethod, group.sortDirection)
    local normalized = {
        key = group.key,
        filterString = group.filterString,
        maxFrameCount = group.maxFrameCount,
        candidateFilters = CopyTable(group.candidateFilters),
        sortMethod = sortMethod,
        sortDirection = sortDirection,
        layout = CopyTable(group.layout),
    }
    if includeStyle then
        normalized.buttonStyle = CopyTable(group.buttonStyle or {})
    end
    return normalized
end

local function NormalizeSlot(slot, seenKeys, includeStyle)
    assert(type(slot) == "table", "aura slot must be a table")
    ClaimKey(seenKeys, slot.key)
    assert(IsNonEmptyString(slot.filterString), "aura slot filterString must be a non-empty string")

    local sortMethod, sortDirection = NormalizeSort(slot.sortMethod, slot.sortDirection)
    local normalized = {
        key = slot.key,
        filterString = slot.filterString,
        candidateFilters = CopyTable(slot.candidateFilters),
        sortMethod = sortMethod,
        sortDirection = sortDirection,
    }
    if includeStyle then
        normalized.point = NormalizePoint(slot.point, {
            point = "CENTER",
            relativePoint = "CENTER",
        })
        normalized.buttonStyle = CopyTable(slot.buttonStyle or {})
    end
    return normalized
end

local function NormalizeSources(groups, slots, includeStyle)
    local normalizedGroups = {}
    local normalizedSlots = {}
    local seenKeys = {}

    for index, group in ipairs(groups or {}) do
        normalizedGroups[index] = NormalizeGroup(group, seenKeys, includeStyle)
    end
    for index, slot in ipairs(slots or {}) do
        normalizedSlots[index] = NormalizeSlot(slot, seenKeys, includeStyle)
    end

    assert(#normalizedGroups > 0 or #normalizedSlots > 0,
        "aura container requires at least one group or slot")
    return normalizedGroups, normalizedSlots
end

local function NormalizeCompleteSpec(spec)
    assert(type(spec) == "table", "complete aura container spec must be a table")
    assert(IsNonEmptyString(spec.unit), "aura container unit must be a non-empty string")
    assert(spec.enabled == nil or type(spec.enabled) == "boolean",
        "aura container enabled must be a boolean")
    assert(spec.shown == nil or type(spec.shown) == "boolean",
        "aura container shown must be a boolean")

    local groups, slots = NormalizeSources(spec.groups, spec.slots, true)
    return {
        unit = spec.unit,
        enabled = spec.enabled ~= false,
        shown = spec.shown ~= false,
        holder = NormalizeHolder(spec.holder),
        containerPoint = NormalizePoint(spec.containerPoint, {
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
        }),
        flowLayout = CopyTable(spec.flowLayout or {}),
        processing = NormalizeProcessing(spec.processing),
        groups = groups,
        slots = slots,
    }
end

local function NormalizeTuning(tuning)
    assert(type(tuning) == "table", "aura container tuning must be a table")
    local groups, slots = NormalizeSources(tuning.groups, tuning.slots, false)
    return {
        holder = NormalizeHolder(tuning.holder),
        containerPoint = NormalizePoint(tuning.containerPoint, {
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
        }),
        flowLayout = CopyTable(tuning.flowLayout or {}),
        processing = NormalizeProcessing(tuning.processing),
        groups = groups,
        slots = slots,
    }
end

local function AssertMatchingTopology(spec, tuning)
    assert(#spec.groups == #tuning.groups, "aura group topology requires Rebuild")
    assert(#spec.slots == #tuning.slots, "aura slot topology requires Rebuild")
    for index, group in ipairs(spec.groups) do
        assert(group.key == tuning.groups[index].key, "aura group key/order changes require Rebuild")
    end
    for index, slot in ipairs(spec.slots) do
        assert(slot.key == tuning.slots[index].key, "aura slot key/order changes require Rebuild")
    end
end

local function MergeTuning(spec, tuning)
    spec.holder = tuning.holder
    spec.containerPoint = tuning.containerPoint
    spec.flowLayout = tuning.flowLayout
    spec.processing = tuning.processing

    for index, dynamic in ipairs(tuning.groups) do
        local group = spec.groups[index]
        group.filterString = dynamic.filterString
        group.maxFrameCount = dynamic.maxFrameCount
        group.candidateFilters = dynamic.candidateFilters
        group.sortMethod = dynamic.sortMethod
        group.sortDirection = dynamic.sortDirection
        group.layout = dynamic.layout
    end
    for index, dynamic in ipairs(tuning.slots) do
        local slot = spec.slots[index]
        slot.filterString = dynamic.filterString
        slot.candidateFilters = dynamic.candidateFilters
        slot.sortMethod = dynamic.sortMethod
        slot.sortDirection = dynamic.sortDirection
    end
end

local pendingControllers = {}
local regenRegistered
local FlushPendingControllers

local function UnregisterRegenIfIdle()
    if regenRegistered and next(pendingControllers) == nil then
        regenRegistered = nil
        UF:UnregisterEvent("PLAYER_REGEN_ENABLED", FlushPendingControllers)
    end
end

local function QueueController(controller)
    pendingControllers[controller] = true
    if not regenRegistered then
        regenRegistered = true
        UF:RegisterEvent("PLAYER_REGEN_ENABLED", FlushPendingControllers)
    end
end

local ControllerMixin = {}
ControllerMixin.__index = ControllerMixin

local function HasNativeMutation(controller)
    return controller._destroyRequested
        or controller._needsClaimInitialization
        or controller._holderConfig
        or controller._needsRebuild
        or controller._needsTuning
        or controller._needsRetarget
        or controller._needsEnabled
        or controller._needsRefresh
end

local function HasPendingMutation(controller)
    return HasNativeMutation(controller) or controller._needsVisibility
end

function ControllerMixin:_QueueRegenDispatch()
    if self._regenDispatchScheduled then return end

    self._regenDispatchScheduled = true
    C_Timer.After(0, function()
        self._regenDispatchScheduled = nil
        if not pendingControllers[self] then
            UnregisterRegenIfIdle()
            return
        end

        -- Each controller receives its own timer callback so a deterministic
        -- configuration/native assertion cannot unwind the rest of the
        -- shared regen drain. Native work itself is not wrapped or hidden.
        self:_ApplyPending()
        UnregisterRegenIfIdle()
    end)
end

local function SetHolderCurtained(controller, curtained)
    local alpha = curtained and 0 or 1
    if curtained then
        controller._presentationApplied = nil
    end
    if controller._holderAlpha == alpha then return end

    -- This is BFI's own plain holder, never a native aura container or
    -- restricted child. Alpha provides an immediate fail-closed curtain while
    -- the complete presentation is changed through constant writes.
    controller.frame:SetAlpha(alpha)
    controller._holderAlpha = alpha
end

local function SetExternalContainerCurtained(controller, curtained)
    if not controller._containerIsExternal or not controller._container then
        return
    end

    local alpha = curtained and 0 or 1
    if controller._containerAlpha == alpha then return end

    -- A seeded container is not parented to the plain holder, so curtain its
    -- inherited Frame alpha separately. The 12.1.0.68914/d3915c78
    -- SimpleRegion contract permits this constant SetAlpha write. This
    -- remains a write-only gate: BFI never reads native visibility, children,
    -- or aura state.
    controller._container:SetAlpha(alpha)
    controller._containerAlpha = alpha
end

local function SetPresentationCurtained(controller, curtained)
    SetHolderCurtained(controller, curtained)
    SetExternalContainerCurtained(controller, curtained)
end

local function SetHolderShownSafe(controller, shown)
    if not shown then
        SetHolderCurtained(controller, true)
    end
    if controller._holderShown == shown then
        return true
    end
    if controller._alphaOnlyVisibility then
        -- Nameplate aura holders remain ordinary shown addon frames and use
        -- the write-only alpha curtain as their sole visibility gate. This
        -- avoids protected Show/Hide/SetShown calls while a 12.1 container is
        -- created or retargeted during combat.
        controller._holderShown = shown
        return true
    end
    if InCombatLockdown() then
        return false
    end

    -- Retail 12.1.0.68914 can make visibility and hover accessors secret when
    -- a holder is anchored to a native aura container. Keep an ordinary
    -- write-only ledger instead of inspecting frame state.
    controller.frame:SetShown(shown)
    controller._holderShown = shown
    return true
end

local function SetExternalContainerShownSafe(controller, shown)
    if not controller._containerIsExternal
        or not controller._container
        or controller._containerShown == shown
    then
        return true
    end
    if InCombatLockdown() then
        return false
    end

    if shown then
        controller._container:Show()
    else
        controller._container:Hide()
    end
    controller._containerShown = shown
    return true
end

local function IsControllerVisibilityApplied(controller, shown)
    if controller._holderShown ~= shown then
        return false
    end
    return not controller._containerIsExternal
        or not controller._container
        or controller._containerShown == shown
end

local function SetControllerShownSafe(controller, shown)
    -- A header-born/seeded container is parented to the secure unit button,
    -- not to BFI's plain holder. Hide it explicitly before hiding the holder;
    -- show it only after the holder is restored. No native visibility is
    -- read: _containerShown tracks only BFI's own successful writes.
    SetPresentationCurtained(controller, true)
    if controller._alphaOnlyVisibility then
        SetHolderShownSafe(controller, shown)
        if shown then
            SetPresentationCurtained(controller, false)
        end
        return true
    end
    if InCombatLockdown() then
        if not IsControllerVisibilityApplied(controller, shown) then
            return false
        end
        if shown then
            SetPresentationCurtained(controller, false)
        end
        return true
    end
    if not shown and not SetExternalContainerShownSafe(controller, false) then
        return false
    end
    if not SetHolderShownSafe(controller, shown) then
        return false
    end
    if shown and not SetExternalContainerShownSafe(controller, true) then
        return false
    end
    -- Hidden, deferred, and destroyed presentations stay behind the alpha
    -- curtain. Show/Hide/SetShown can be protected for header-born frames,
    -- while constant SetAlpha writes remain permitted by the pinned 12.1
    -- contract. Only expose a completely applied shown presentation.
    if shown then
        SetPresentationCurtained(controller, false)
    end
    return true
end

local function RestoreControllerVisibility(controller)
    local spec = controller._spec
    local applied = SetControllerShownSafe(
        controller,
        spec ~= nil and spec.enabled and spec.shown
    )
    if applied then
        controller._presentationApplied = true
    end
    return applied
end

local function PositionContainer(container, holder, point)
    container:ClearAllPoints()
    container:SetPoint(point.point, holder, point.relativePoint, point.x, point.y)
end

local function SyncExternalContainerLayer(controller, container)
    if not container then return end

    -- A holder-owned container inherits the holder's z-order. A seed remains
    -- parented to the secure unit button, so reproduce that child level
    -- explicitly without reading any native container state.
    AF.SetFrameLevel(container, 1, controller.frame)
end

local function ApplyNativeTuning(controller)
    local container = controller._container
    local spec = controller._spec

    AF.SetSize(controller.frame, spec.holder.width, spec.holder.height)
    PositionContainer(container, controller.frame, spec.containerPoint)
    AF.SetCustomAuraContainerFlowLayout(container, spec.flowLayout)
    AF.SetCustomAuraContainerProcessingPolicy(
        container,
        spec.processing.policy,
        spec.processing.options
    )

    for _, group in ipairs(spec.groups) do
        AF.SetCustomAuraGroupFilterString(container, group.key, group.filterString)
        AF.SetCustomAuraGroupMaxFrameCount(container, group.key, group.maxFrameCount)
        AF.SetCustomAuraGroupCandidateFilters(container, group.key, group.candidateFilters)
        AF.SetCustomAuraGroupSortMethod(
            container,
            group.key,
            group.sortMethod,
            group.sortDirection
        )
        AF.SetCustomAuraGroupLayout(container, group.key, group.layout)
    end
    for _, slot in ipairs(spec.slots) do
        AF.SetCustomAuraSlotFilterString(container, slot.key, slot.filterString)
        AF.SetCustomAuraSlotCandidateFilters(container, slot.key, slot.candidateFilters)
        AF.SetCustomAuraSlotSortMethod(
            container,
            slot.key,
            slot.sortMethod,
            slot.sortDirection
        )
    end

    AF.UpdateCustomAuraContainer(container)
end

local function MarkBuildShellStranded(controller)
    assert(not controller._nativeShellStranded,
        "aura container controller native shell already claimed")
    controller._nativeShellStranded = true
    constructionStats.strandedNativeShells =
        constructionStats.strandedNativeShells + 1
end

local function AddKnownBuildReservations(controller, count)
    controller._knownInitialReservations =
        (controller._knownInitialReservations or 0) + count
    constructionStats.strandedInitialReservations =
        constructionStats.strandedInitialReservations + count
end

function ControllerMixin:_Build()
    assert(not self._buildAttempted and not self._container,
        "aura container controller initial build already attempted")
    -- Claim this controller's only native construction attempt before any
    -- fallible holder or native setup. Groups/slots are add-only, so a
    -- partially configured container can never be completed by retrying the
    -- same spec or safely replaced by adopting/allocating another shell.
    self._buildAttempted = true

    local spec = self._spec
    local holder = self.frame
    local combatInitialBuild = self._allowCombatInitialBuild
        and InCombatLockdown()
    constructionStats.buildAttempts = constructionStats.buildAttempts + 1
    constructionStats.expectedGroups =
        constructionStats.expectedGroups + #spec.groups
    constructionStats.expectedSlots =
        constructionStats.expectedSlots + #spec.slots
    constructionStats.expectedInitialReservations =
        constructionStats.expectedInitialReservations
        + (#spec.groups * NATIVE_INITIAL_GROUP_RESERVATIONS)
        + #spec.slots

    -- Build the complete container while the public holder is hidden by the
    -- write-only presentation gate. Native groups/slots are add-only, so this
    -- controller deliberately has no replacement/rebuild path after this.
    local container = self._seedContainer
    local containerIsExternal = container ~= nil
    self._seedContainer = nil
    if container then
        -- Record a consumed seed before even plain-holder setup can fail so
        -- Destroy can still retire it and no later build can adopt a second
        -- container.
        self._container = container
        self._containerIsExternal = true
        self._containerShown = false
        -- The seed was curtained at claim time, before any deferred build
        -- work. Adopt that known write state without reading it back.
        self._containerAlpha = 0
        MarkBuildShellStranded(self)
    end

    AF.SetSize(holder, spec.holder.width, spec.holder.height)

    if not container then
        container = AF.CreateCustomAuraContainer(holder)
        -- Claim a newly created shell immediately, before its first native
        -- mutation, for the same one-shot and cleanup guarantees as a seed.
        self._container = container
        self._containerIsExternal = false
        self._containerShown = false
        self._containerAlpha = nil
        MarkBuildShellStranded(self)
    end
    if not self._alphaOnlyVisibility then
        container:Hide()
    end
    if not combatInitialBuild then
        AF.SetCustomAuraContainerEnabled(container, false)
    end
    PositionContainer(container, holder, spec.containerPoint)
    if containerIsExternal then
        SyncExternalContainerLayer(self, container)
    end
    AF.SetCustomAuraContainerFlowLayout(container, spec.flowLayout)
    AF.SetCustomAuraContainerProcessingPolicy(
        container,
        spec.processing.policy,
        spec.processing.options
    )

    for _, group in ipairs(spec.groups) do
        AF.AddCustomAuraGroup(container, group.key, group.filterString, {
            maxFrameCount = group.maxFrameCount,
            candidateFilters = group.candidateFilters,
            sortMethod = group.sortMethod,
            sortDirection = group.sortDirection,
            layout = group.layout,
        }, group.buttonStyle)
        AddKnownBuildReservations(self, NATIVE_INITIAL_GROUP_RESERVATIONS)
    end

    for _, slot in ipairs(spec.slots) do
        AF.AddCustomAuraSlot(container, slot.key, slot.filterString, {
            candidateFilters = slot.candidateFilters,
            sortMethod = slot.sortMethod,
            sortDirection = slot.sortDirection,
            anchor = {
                point = slot.point.point,
                relativeTo = holder,
                relativePoint = slot.point.relativePoint,
                x = slot.point.x,
                y = slot.point.y,
            },
        }, slot.buttonStyle)
        AddKnownBuildReservations(self, 1)
    end

    -- Unit is assigned only after every source and construction-time slot
    -- anchor exists. Enabling remains the final native lifecycle transition.
    AF.SetCustomAuraContainerUnit(container, spec.unit)
    AF.UpdateCustomAuraContainer(container)
    -- SetEnabled is a secure-delegated inbound AuraContainer method in the
    -- pinned 12.1 build. Submit the final configured state explicitly even
    -- for a combat-created container so event registration never depends on
    -- template initialization details.
    AF.SetCustomAuraContainerEnabled(container, spec.enabled)

    if not containerIsExternal and not self._alphaOnlyVisibility then
        container:Show()
    end

    self._buildCompleted = true
    constructionStats.buildCompletions = constructionStats.buildCompletions + 1
    if containerIsExternal then
        constructionStats.adoptedBuilds = constructionStats.adoptedBuilds + 1
    else
        constructionStats.frameworkBuilds = constructionStats.frameworkBuilds + 1
    end
    constructionStats.strandedNativeShells =
        constructionStats.strandedNativeShells - 1
    constructionStats.strandedInitialReservations =
        constructionStats.strandedInitialReservations
        - self._knownInitialReservations
    self._nativeShellStranded = nil
end

local function ApplyLiveUnitRetarget(controller)
    if not controller._liveUnitChanges
        or controller._destroyRequested
        or not controller._container
        or not controller._needsRetarget
    then
        return false
    end

    -- 12.1.0.68914 exposes SetUnit and UpdateAllAuras as inbound,
    -- combat-live operations on an already-built container. This is the
    -- only native mutation group controllers may perform before regen.
    AF.SetCustomAuraContainerUnit(controller._container, controller._spec.unit)
    AF.UpdateCustomAuraContainer(controller._container)
    controller._needsRetarget = nil
    controller._needsRefresh = nil
    return true
end

function ControllerMixin:_ApplyPending()
    if not HasPendingMutation(self) then
        pendingControllers[self] = nil
        return
    end

    -- A pure public-holder visibility change is render-side only and may run
    -- in combat. Holder state is tracked only through BFI-owned writes.
    if not HasNativeMutation(self) then
        if RestoreControllerVisibility(self) then
            self._needsVisibility = nil
            pendingControllers[self] = nil
        else
            QueueController(self)
        end
        return
    end

    -- Native configuration and initial-build work is OOC-only. Hide the
    -- complete BFI-owned presentation before applying native mutations.
    local holderHidden = SetControllerShownSafe(self, false)
    if InCombatLockdown() then
        if self._allowCombatInitialBuild and self._needsRebuild then
            -- PTR 7 permits addon AuraContainers to be created during combat.
            -- This opt-in path is used only by nameplates born after combat
            -- starts. The complete presentation stays behind the plain
            -- holder's alpha curtain, and native visibility methods are not
            -- called while restricted.
            if self._holderConfig then
                local configure = self._holderConfig
                self._holderConfig = nil
                configure(self.frame)
            end
            self._needsClaimInitialization = nil
            self:_Build()
            self._needsRebuild = nil
            self._needsTuning = nil
            self._needsRetarget = nil
            self._needsEnabled = nil
            self._needsRefresh = nil
            self._needsVisibility = true
            if RestoreControllerVisibility(self) then
                self._needsVisibility = nil
                pendingControllers[self] = nil
            else
                QueueController(self)
            end
            return
        end

        -- SetUnit/UpdateAllAuras are the only native operations explicitly
        -- supported live. The alpha curtain is already active; protected
        -- Show/Hide/SetShown calls are deferred until regen.
        -- Register recovery before the supported inbound calls as well: an
        -- unexpected adapter error must not strand a curtained controller.
        QueueController(self)
        ApplyLiveUnitRetarget(self)
        if HasNativeMutation(self) then
            QueueController(self)
        else
            self._needsVisibility = true
            if RestoreControllerVisibility(self) then
                self._needsVisibility = nil
                pendingControllers[self] = nil
            else
                QueueController(self)
            end
        end
        return
    end
    if not holderHidden then
        return
    end

    if self._destroyRequested then
        if self._container then
            AF.SetCustomAuraContainerEnabled(self._container, false)
            self._container:Hide()
            constructionStats.retiredNativeShells =
                constructionStats.retiredNativeShells + 1
            constructionStats.retiredInitialReservations =
                constructionStats.retiredInitialReservations
                + (self._knownInitialReservations or 0)
            if self._nativeShellStranded then
                constructionStats.strandedNativeShells =
                    constructionStats.strandedNativeShells - 1
                constructionStats.strandedInitialReservations =
                    constructionStats.strandedInitialReservations
                    - (self._knownInitialReservations or 0)
            end
            self._container = nil
        end
        if self._seedContainer then
            AF.SetCustomAuraContainerEnabled(self._seedContainer, false)
            self._seedContainer:Hide()
            constructionStats.retiredNativeShells =
                constructionStats.retiredNativeShells + 1
            self._seedContainer = nil
        end
        self._containerIsExternal = nil
        self._containerShown = nil
        self._containerAlpha = nil
        self._nativeShellStranded = nil
        self._knownInitialReservations = nil
        self._needsClaimInitialization = nil
        self._spec = nil
        self._holderShown = nil
        self._destroyed = true
        constructionStats.destroyCompletions =
            constructionStats.destroyCompletions + 1
        pendingControllers[self] = nil
        return
    end

    if self._needsClaimInitialization then
        if self._seedContainer then
            self._seedContainer:Hide()
            AF.SetCustomAuraContainerEnabled(self._seedContainer, false)
        end
        self._needsClaimInitialization = nil
    end

    if self._holderConfig then
        local configure = self._holderConfig
        self._holderConfig = nil
        configure(self.frame)
        if self._containerIsExternal then
            SyncExternalContainerLayer(self, self._container)
        end
    end

    -- Holder-only placement/configuration is allowed before the first
    -- complete native spec. When it is the only pending work, restore the
    -- configured visibility of an existing spec and stop here.
    if not HasNativeMutation(self) then
        if self._spec then
            self._needsVisibility = true
            if RestoreControllerVisibility(self) then
                self._needsVisibility = nil
                pendingControllers[self] = nil
            end
        else
            pendingControllers[self] = nil
        end
        return
    end

    if self._needsRebuild then
        self:_Build()
        self._needsRebuild = nil
        self._needsTuning = nil
        self._needsRetarget = nil
        self._needsEnabled = nil
        self._needsRefresh = nil
        self._needsVisibility = true
        if RestoreControllerVisibility(self) then
            self._needsVisibility = nil
            pendingControllers[self] = nil
        end
        return
    end

    local container = self._container
    assert(container, "aura container controller requires a built container")

    if self._needsTuning then
        ApplyNativeTuning(self)
        self._needsTuning = nil
        self._needsRefresh = nil
    end
    if self._needsRetarget then
        AF.SetCustomAuraContainerUnit(container, self._spec.unit)
        AF.UpdateCustomAuraContainer(container)
        self._needsRetarget = nil
        self._needsRefresh = nil
    end
    if self._needsEnabled then
        AF.SetCustomAuraContainerEnabled(container, self._spec.enabled)
        self._needsEnabled = nil
    end
    if self._needsRefresh then
        AF.UpdateCustomAuraContainer(container)
        self._needsRefresh = nil
    end

    self._needsVisibility = true
    if RestoreControllerVisibility(self) then
        self._needsVisibility = nil
        pendingControllers[self] = nil
    end
end

FlushPendingControllers = function()
    if InCombatLockdown() then return end

    for controller in pairs(pendingControllers) do
        controller:_QueueRegenDispatch()
    end

    UnregisterRegenIfIdle()
end

local function AssertMutable(controller)
    assert(not controller._destroyed and not controller._destroyRequested,
        "aura container controller is destroyed")
    assert(controller._spec, "aura container controller requires a complete spec")
end

local function RequestMutation(controller)
    controller:_ApplyPending()
    -- An ordinary out-of-combat update may beat the queued regen event.
    UnregisterRegenIfIdle()
end

function ControllerMixin:GetFrame()
    return self.frame
end

function ControllerMixin:IsPresentationApplied()
    local spec = self._spec
    return self._presentationApplied == true
        and not self._destroyed
        and not self._destroyRequested
        and spec ~= nil
        and spec.enabled
        and spec.shown
end

-- Expose only the native frame reference needed for forbidden-aspect-safe
-- dependent anchoring. Callers must never inspect its size, visibility,
-- children, aura data, or other restricted state.
function ControllerMixin:GetNativeFrame()
    return self._container
end

-- Queue the latest configuration-only holder mutation behind the same
-- combat gate as native work. This is intentionally a callback:
-- indicator placement can resolve anchors only through UnitFrames/Common.
function ControllerMixin:ApplyHolderConfig(configure)
    assert(not self._destroyed and not self._destroyRequested,
        "aura container controller is destroyed")
    assert(type(configure) == "function",
        "aura container holder configuration must be a function")

    self._holderConfig = configure
    RequestMutation(self)
end

function ControllerMixin:Rebuild(completeSpec)
    assert(not self._destroyed and not self._destroyRequested,
        "aura container controller is destroyed")
    assert(not self._buildAttempted and not self._container,
        "aura container controller initial build already attempted")

    local previousUnit = self._spec and self._spec.unit
    self._spec = NormalizeCompleteSpec(completeSpec)
    self._needsRebuild = true
    self._needsTuning = nil
    self._needsRetarget = self._liveUnitChanges
        and self._container ~= nil
        and previousUnit ~= self._spec.unit
        or nil
    self._needsEnabled = nil
    self._needsVisibility = nil
    self._needsRefresh = nil
    RequestMutation(self)
end

function ControllerMixin:ApplyTuning(tuning)
    AssertMutable(self)

    tuning = NormalizeTuning(tuning)
    AssertMatchingTopology(self._spec, tuning)
    MergeTuning(self._spec, tuning)
    if self._needsRebuild then
        RequestMutation(self)
        return
    end

    self._needsTuning = true
    RequestMutation(self)
end

function ControllerMixin:SetUnit(unit)
    AssertMutable(self)
    assert(IsNonEmptyString(unit), "aura container unit must be a non-empty string")
    if self._spec.unit == unit then return end

    self._spec.unit = unit
    if not self._needsRebuild
        or (self._liveUnitChanges and self._container)
    then
        self._needsRetarget = true
    end
    RequestMutation(self)
end

function ControllerMixin:SetEnabled(enabled)
    AssertMutable(self)
    assert(type(enabled) == "boolean", "aura container enabled must be a boolean")
    if self._spec.enabled == enabled then return end

    self._spec.enabled = enabled
    if not self._needsRebuild then
        self._needsEnabled = true
        self._needsVisibility = true
    end
    RequestMutation(self)
end

function ControllerMixin:SetShown(shown)
    AssertMutable(self)
    assert(type(shown) == "boolean", "aura container shown must be a boolean")
    if self._spec.shown == shown then return end

    self._spec.shown = shown
    if not self._needsRebuild then
        self._needsVisibility = true
    end
    RequestMutation(self)
end

function ControllerMixin:Refresh()
    AssertMutable(self)
    if self._needsRebuild or not self._container then
        self._needsRefresh = true
        RequestMutation(self)
        return
    end

    -- 68914's inbound UpdateAllAuras only marks a full native dirty rebuild.
    -- It does not expose aura values and is safe for stable-token refreshes.
    AF.UpdateCustomAuraContainer(self._container)
end

function ControllerMixin:Destroy()
    if self._destroyed or self._destroyRequested then return end

    self._destroyRequested = true
    constructionStats.destroyRequests = constructionStats.destroyRequests + 1
    self._holderConfig = nil
    self._needsRebuild = nil
    self._needsTuning = nil
    self._needsRetarget = nil
    self._needsEnabled = nil
    self._needsVisibility = nil
    self._needsRefresh = nil
    RequestMutation(self)
end

local claimedGroupAuraContainers = {}

local function CreateController(parent, name, completeSpec, options)
    if not UF.HasNativeAuraContainerBackend() then
        return nil
    end

    options = options or {}
    if options.seedContainer then
        assert(not claimedGroupAuraContainers[options.seedContainer],
            "native group aura container seed is already claimed")
    end

    local controller = setmetatable({}, ControllerMixin)
    controller._alphaOnlyVisibility =
        options.alphaOnlyVisibility == true
    controller._allowCombatInitialBuild =
        options.allowCombatInitialBuild == true
    controller.frame = CreateFrame(
        "Frame",
        name,
        parent,
        options.frameTemplate
    )
    controller.frame:SetAlpha(0)
    controller._holderAlpha = 0
    if controller._alphaOnlyVisibility then
        -- CreateFrame returns a shown plain frame. Track the requested state
        -- independently and keep it visually inert until a complete native
        -- presentation has been committed.
        controller._holderShown = false
    elseif not InCombatLockdown() then
        controller.frame:Hide()
        controller._holderShown = false
    end
    controller._seedContainer = options.seedContainer
    controller._liveUnitChanges = options.liveUnitChanges == true
    constructionStats.controllersCreated = constructionStats.controllersCreated + 1
    if InCombatLockdown() and not controller._allowCombatInitialBuild then
        controller._needsClaimInitialization = true
        QueueController(controller)
    end

    if controller._seedContainer then
        claimedGroupAuraContainers[controller._seedContainer] = true
        constructionStats.seedsClaimed = constructionStats.seedsClaimed + 1
        -- A header-born seed can exist before its controller receives a
        -- complete spec. Curtain it immediately so combat-deferred build work
        -- cannot expose Blizzard's baseline or a stale prior assignment even
        -- if the protected Hide call is blocked.
        controller._seedContainer:SetAlpha(0)
        if not InCombatLockdown() then
            controller._seedContainer:Hide()
            AF.SetCustomAuraContainerEnabled(controller._seedContainer, false)
        end
    end

    if completeSpec then
        controller:Rebuild(completeSpec)
    end
    return controller
end

function UF.CreateNativeAuraContainerController(
    parent,
    name,
    completeSpec,
    frameTemplate,
    options
)
    options = options or {}
    return CreateController(parent, name, completeSpec, {
        frameTemplate = frameTemplate,
        liveUnitChanges = options.liveUnitChanges,
        allowCombatInitialBuild = options.allowCombatInitialBuild,
        alphaOnlyVisibility = options.alphaOnlyVisibility,
    })
end

function UF.CreateNativeGroupAuraContainerController(
    parent,
    name,
    seedContainer,
    completeSpec
)
    if not UF.HasNativeAuraContainerBackend() then
        return nil
    end

    assert(seedContainer, "native group aura container seed is required")
    return CreateController(parent, name, completeSpec, {
        seedContainer = seedContainer,
        liveUnitChanges = true,
    })
end

---------------------------------------------------------------------
-- relation-partition controller
---------------------------------------------------------------------
local PARTITION_FRIENDLY = "friendly"
local PARTITION_HOSTILE = "hostile"
local PARTITION_VARIANTS = {
    PARTITION_FRIENDLY,
    "main",
    "complement",
}

local function NormalizePartitionVariant(value)
    assert(
        value == PARTITION_FRIENDLY or value == PARTITION_HOSTILE,
        "aura partition variant must be friendly or hostile"
    )
    return value
end

local function NormalizePartitionAttachment(attachment)
    if attachment == nil then return nil end

    assert(type(attachment) == "table",
        "aura partition attachment must be a table")
    assert(IsNonEmptyString(attachment.point),
        "aura partition attachment point must be a non-empty string")
    assert(IsNonEmptyString(attachment.relativePoint),
        "aura partition attachment relativePoint must be a non-empty string")
    assert(type(attachment.x) == "number",
        "aura partition attachment x must be a number")
    assert(type(attachment.y) == "number",
        "aura partition attachment y must be a number")

    return {
        point = attachment.point,
        relativePoint = attachment.relativePoint,
        x = attachment.x,
        y = attachment.y,
    }
end

local function NormalizePartitionCompleteSpec(spec)
    assert(type(spec) == "table",
        "complete aura partition spec must be a table")
    assert(IsNonEmptyString(spec.unit),
        "aura partition unit must be a non-empty string")
    assert(spec.enabled == nil or type(spec.enabled) == "boolean",
        "aura partition enabled must be a boolean")
    assert(spec.shown == nil or type(spec.shown) == "boolean",
        "aura partition shown must be a boolean")
    assert(type(spec.friendly) == "table",
        "aura partition requires a friendly spec")
    assert(spec.main == nil or type(spec.main) == "table",
        "aura partition main spec must be a table")
    assert(spec.complement == nil or type(spec.complement) == "table",
        "aura partition complement spec must be a table")
    assert(
        spec.attachment == nil
            or (spec.main ~= nil and spec.complement ~= nil),
        "aura partition attachment requires main and complement specs"
    )

    return {
        unit = spec.unit,
        enabled = spec.enabled ~= false,
        shown = spec.shown ~= false,
        variant = NormalizePartitionVariant(
            spec.variant or PARTITION_FRIENDLY
        ),
        holder = NormalizeHolder(spec.holder),
        friendly = CopyTable(spec.friendly),
        main = CopyTable(spec.main),
        complement = CopyTable(spec.complement),
        attachment = NormalizePartitionAttachment(spec.attachment),
    }
end

local function NormalizePartitionTuning(tuning)
    assert(type(tuning) == "table",
        "aura partition tuning must be a table")
    assert(type(tuning.friendly) == "table",
        "aura partition tuning requires a friendly spec")
    assert(tuning.main == nil or type(tuning.main) == "table",
        "aura partition main tuning must be a table")
    assert(tuning.complement == nil or type(tuning.complement) == "table",
        "aura partition complement tuning must be a table")
    assert(
        tuning.attachment == nil
            or (tuning.main ~= nil and tuning.complement ~= nil),
        "aura partition tuning attachment requires both hostile specs"
    )

    return {
        holder = NormalizeHolder(tuning.holder),
        friendly = CopyTable(tuning.friendly),
        main = CopyTable(tuning.main),
        complement = CopyTable(tuning.complement),
        attachment = NormalizePartitionAttachment(tuning.attachment),
    }
end

local PartitionControllerMixin = {}
PartitionControllerMixin.__index = PartitionControllerMixin
setmetatable(PartitionControllerMixin, {
    __index = ControllerMixin,
})

local function PartitionChildBuilt(child)
    return child and child._spec ~= nil
end

local function SetPartitionChildShown(child, shown)
    if PartitionChildBuilt(child) then
        child:SetShown(shown)
    end
end

local function SyncPartitionVisibility(controller)
    local spec = controller._spec
    local shown = spec ~= nil and spec.enabled and spec.shown
    local variant = controller._variant or PARTITION_FRIENDLY

    SetHolderCurtained(controller, true)
    if InCombatLockdown() then
        local applied = controller._holderShown == shown
            and (not shown or controller._shownVariant == variant)
        if applied and shown then
            SetHolderCurtained(controller, false)
            controller._presentationApplied = true
        elseif applied then
            controller._shownVariant = nil
        end
        return applied
    end
    if not shown then
        if not SetHolderShownSafe(controller, false) then
            return false
        end
        for _, key in ipairs(PARTITION_VARIANTS) do
            SetPartitionChildShown(controller[key], false)
        end
        controller._shownVariant = nil
        -- Hidden partitions remain behind the write-only curtain. Protected
        -- visibility writes must never be the sole stale-row suppression.
        return true
    end

    local swapping = controller._holderShown == true
        and controller._shownVariant ~= variant
    if swapping and not SetHolderShownSafe(controller, false) then
        return false
    end

    local friendlyShown = variant == PARTITION_FRIENDLY
    if friendlyShown then
        -- Hide the old presentation before showing its replacement so event
        -- scripts cannot observe both relation variants at once.
        SetPartitionChildShown(controller.main, false)
        SetPartitionChildShown(controller.complement, false)
        SetPartitionChildShown(controller.friendly, true)
    else
        SetPartitionChildShown(controller.friendly, false)
        SetPartitionChildShown(
            controller.main,
            spec.main ~= nil
        )
        SetPartitionChildShown(
            controller.complement,
            spec.complement ~= nil
        )
    end

    if not SetHolderShownSafe(controller, true) then
        return false
    end
    controller._shownVariant = variant
    SetHolderCurtained(controller, false)
    controller._presentationApplied = true
    return true
end

local function AnchorPartitionChild(controller, child, childSpec)
    if not childSpec or not PartitionChildBuilt(child) then return end

    local frame = child:GetFrame()
    local point = childSpec.containerPoint.point
    frame:ClearAllPoints()
    frame:SetPoint(point, controller.frame, point, 0, 0)
end

local function AnchorPartitionComplement(controller)
    local spec = controller._spec
    local complement = controller.complement
    if not spec
        or not spec.complement
        or not PartitionChildBuilt(complement)
    then
        return
    end

    local attachment = spec.attachment
    if not attachment then
        AnchorPartitionChild(
            controller,
            complement,
            spec.complement
        )
        return
    end

    local mainFrame = controller.main:GetNativeFrame()
    assert(mainFrame,
        "aura partition attachment requires a built main container")
    local frame = complement:GetFrame()
    frame:ClearAllPoints()
    frame:SetPoint(
        attachment.point,
        mainFrame,
        attachment.relativePoint,
        attachment.x,
        attachment.y
    )
end

local function DisablePartitionChild(child)
    if not PartitionChildBuilt(child) then return end
    child:SetShown(false)
    child:SetEnabled(false)
end

local function BuildPartitionChild(
    controller,
    child,
    childSpec
)
    if not childSpec then
        DisablePartitionChild(child)
        return
    end

    local spec = AF.Copy(childSpec)
    spec.unit = controller._spec.unit
    spec.enabled = controller._spec.enabled
    spec.shown = false
    child:Rebuild(spec)
end

local function BuildPartition(controller)
    local spec = controller._spec
    AF.SetSize(controller.frame, spec.holder.width, spec.holder.height)

    BuildPartitionChild(
        controller,
        controller.friendly,
        spec.friendly
    )
    BuildPartitionChild(controller, controller.main, spec.main)
    BuildPartitionChild(
        controller,
        controller.complement,
        spec.complement
    )

    AnchorPartitionChild(
        controller,
        controller.friendly,
        spec.friendly
    )
    AnchorPartitionChild(controller, controller.main, spec.main)
    AnchorPartitionComplement(controller)
end

local function ApplyPartitionTuning(controller)
    local tuning = controller._pendingTuning
    local spec = controller._spec
    AF.SetSize(
        controller.frame,
        tuning.holder.width,
        tuning.holder.height
    )

    controller.friendly:ApplyTuning(tuning.friendly)
    AssertMatchingTopology(spec.friendly, tuning.friendly)
    MergeTuning(spec.friendly, tuning.friendly)
    if tuning.main then
        controller.main:ApplyTuning(tuning.main)
        AssertMatchingTopology(spec.main, tuning.main)
        MergeTuning(spec.main, tuning.main)
    end
    if tuning.complement then
        controller.complement:ApplyTuning(tuning.complement)
        AssertMatchingTopology(spec.complement, tuning.complement)
        MergeTuning(spec.complement, tuning.complement)
    end

    spec.holder = tuning.holder
    spec.attachment = tuning.attachment
    AnchorPartitionChild(
        controller,
        controller.friendly,
        spec.friendly
    )
    AnchorPartitionChild(controller, controller.main, spec.main)
    AnchorPartitionComplement(controller)
end

function PartitionControllerMixin:_ApplyPending()
    if not HasPendingMutation(self) then
        pendingControllers[self] = nil
        return
    end

    if not HasNativeMutation(self) then
        if SyncPartitionVisibility(self) then
            self._needsVisibility = nil
            pendingControllers[self] = nil
        else
            QueueController(self)
        end
        return
    end

    SetHolderCurtained(self, true)
    if InCombatLockdown() then
        QueueController(self)
        return
    end
    local holderHidden = SetHolderShownSafe(self, false)
    if not holderHidden then
        return
    end

    if self._destroyRequested then
        for _, key in ipairs(PARTITION_VARIANTS) do
            self[key]:Destroy()
        end
        self._holderShown = nil
        self._spec = nil
        self._destroyed = true
        pendingControllers[self] = nil
        return
    end

    if self._holderConfig then
        local configure = self._holderConfig
        self._holderConfig = nil
        configure(self.frame)
    end

    if self._needsRebuild then
        BuildPartition(self)
        self._needsRebuild = nil
        self._needsTuning = nil
        self._pendingTuning = nil
        self._needsRetarget = nil
        self._needsEnabled = nil
    else
        if self._needsTuning then
            ApplyPartitionTuning(self)
            self._needsTuning = nil
            self._pendingTuning = nil
        end
        if self._needsRetarget then
            for _, key in ipairs(PARTITION_VARIANTS) do
                local child = self[key]
                if self._spec[key] and PartitionChildBuilt(child) then
                    child:SetUnit(self._spec.unit)
                end
            end
            self._needsRetarget = nil
        end
        if self._needsEnabled then
            for _, key in ipairs(PARTITION_VARIANTS) do
                local child = self[key]
                if PartitionChildBuilt(child) then
                    child:SetEnabled(
                        self._spec[key] ~= nil
                            and self._spec.enabled
                    )
                end
            end
            self._needsEnabled = nil
        end
    end

    self._needsVisibility = true
    if SyncPartitionVisibility(self) then
        self._needsVisibility = nil
        pendingControllers[self] = nil
    end
end

function PartitionControllerMixin:ApplyHolderConfig(configure)
    assert(not self._destroyed and not self._destroyRequested,
        "aura partition controller is destroyed")
    assert(type(configure) == "function",
        "aura partition holder configuration must be a function")

    self._holderConfig = configure
    RequestMutation(self)
end

function PartitionControllerMixin:Rebuild(completeSpec)
    assert(not self._destroyed and not self._destroyRequested,
        "aura partition controller is destroyed")
    assert(not self._spec,
        "aura partition controller initial build already attempted")

    self._spec = NormalizePartitionCompleteSpec(completeSpec)
    self._variant = self._spec.variant
    self._needsRebuild = true
    self._needsTuning = nil
    self._pendingTuning = nil
    self._needsRetarget = nil
    self._needsEnabled = nil
    self._needsVisibility = nil
    RequestMutation(self)
end

function PartitionControllerMixin:ApplyTuning(tuning)
    assert(not self._destroyed and not self._destroyRequested,
        "aura partition controller is destroyed")
    assert(self._spec,
        "aura partition controller requires a complete spec")

    tuning = NormalizePartitionTuning(tuning)
    assert((self._spec.main == nil) == (tuning.main == nil),
        "aura partition main topology requires Rebuild")
    assert(
        (self._spec.complement == nil)
            == (tuning.complement == nil),
        "aura partition complement topology requires Rebuild"
    )

    self._pendingTuning = tuning
    self._needsTuning = true
    RequestMutation(self)
end

function PartitionControllerMixin:SetUnit(unit)
    assert(not self._destroyed and not self._destroyRequested,
        "aura partition controller is destroyed")
    assert(self._spec,
        "aura partition controller requires a complete spec")
    assert(IsNonEmptyString(unit),
        "aura partition unit must be a non-empty string")
    if self._spec.unit == unit then return end

    self._spec.unit = unit
    if not self._needsRebuild then
        self._needsRetarget = true
    end
    RequestMutation(self)
end

function PartitionControllerMixin:SetEnabled(enabled)
    assert(not self._destroyed and not self._destroyRequested,
        "aura partition controller is destroyed")
    assert(self._spec,
        "aura partition controller requires a complete spec")
    assert(type(enabled) == "boolean",
        "aura partition enabled must be a boolean")
    if self._spec.enabled == enabled then return end

    self._spec.enabled = enabled
    if not self._needsRebuild then
        self._needsEnabled = true
    end
    self._needsVisibility = true
    RequestMutation(self)
end

function PartitionControllerMixin:SetShown(shown)
    assert(not self._destroyed and not self._destroyRequested,
        "aura partition controller is destroyed")
    assert(self._spec,
        "aura partition controller requires a complete spec")
    assert(type(shown) == "boolean",
        "aura partition shown must be a boolean")
    if self._spec.shown == shown then return end

    self._spec.shown = shown
    self._needsVisibility = true
    RequestMutation(self)
end

function PartitionControllerMixin:SetVariant(variant)
    assert(not self._destroyed and not self._destroyRequested,
        "aura partition controller is destroyed")
    variant = NormalizePartitionVariant(variant)
    if self._variant == variant then return end

    self._variant = variant
    if self._spec then
        self._spec.variant = variant
        self._needsVisibility = true
        RequestMutation(self)
    end
end

function PartitionControllerMixin:Refresh()
    assert(not self._destroyed and not self._destroyRequested,
        "aura partition controller is destroyed")
    assert(self._spec,
        "aura partition controller requires a complete spec")

    for _, key in ipairs(PARTITION_VARIANTS) do
        local child = self[key]
        if self._spec[key] and PartitionChildBuilt(child) then
            child:Refresh()
        end
    end
end

function PartitionControllerMixin:Destroy()
    if self._destroyed or self._destroyRequested then return end

    self._destroyRequested = true
    self._holderConfig = nil
    self._needsRebuild = nil
    self._needsTuning = nil
    self._pendingTuning = nil
    self._needsRetarget = nil
    self._needsEnabled = nil
    self._needsVisibility = nil
    RequestMutation(self)
end

function UF.CreateNativeAuraPartitionController(parent, name)
    if not UF.HasNativeAuraContainerBackend() then
        return nil
    end

    local controller = setmetatable({}, PartitionControllerMixin)
    controller.frame = CreateFrame("Frame", name, parent)
    controller.frame:SetAlpha(0)
    controller._holderAlpha = 0
    if not InCombatLockdown() then
        controller.frame:Hide()
        controller._holderShown = false
    else
        controller._needsVisibility = true
        QueueController(controller)
    end
    controller.friendly = UF.CreateNativeAuraContainerController(
        controller.frame,
        name .. "_Friendly"
    )
    controller.main = UF.CreateNativeAuraContainerController(
        controller.frame,
        name .. "_HostileMain"
    )
    controller.complement = UF.CreateNativeAuraContainerController(
        controller.frame,
        name .. "_HostileComplement",
        nil,
        "DisableUntrustedLayoutScriptsTemplate"
    )
    return controller
end
