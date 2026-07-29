---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local C_Timer = C_Timer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local floor, huge = math.floor, math.huge
local ipairs, next, pairs, pcall, type = ipairs, next, pairs, pcall, type

-- Retail 12.1.0.68914 (wow-ui-source d3915c78) makes native aura
-- groups/slots add-only and restricts their buttons after initialization.
-- This controller owns only configuration-derived state and never reads aura
-- data, live buttons, native container geometry, or native visibility.
local REQUIRED_AF_VERSION = 30
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
    container:Hide()
    AF.SetCustomAuraContainerEnabled(container, false)
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

function ControllerMixin:_QueueHoverRetry()
    if self._hoverRetryScheduled or self._destroyed then return end

    self._hoverRetryScheduled = true
    C_Timer.After(0.25, function()
        self._hoverRetryScheduled = nil
        if self._destroyed or not HasPendingMutation(self) then return end

        self:_ApplyPending()
        UnregisterRegenIfIdle()
    end)
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

local function SetHolderShownSafe(controller, shown)
    local holder = controller.frame
    if holder:IsShown() == shown then
        return true
    end

    -- IsShown/IsMouseOver are read only from BFI's plain, config-sized
    -- holder. Native containers, restricted buttons, and aura state remain
    -- opaque. A visibility flip while a native aura tooltip is hovered can
    -- synchronously enter protected tooltip code, so retry after hover ends.
    if holder:IsMouseOver() then
        controller:_QueueHoverRetry()
        return false
    end

    -- pcall only contains a non-secret write to BFI's own holder. It is not
    -- an API/secret probe or a security boundary; hover avoidance above is
    -- the defense. Verification keeps a raced or aborted write from letting
    -- native mutations proceed while the holder is still visible.
    local wrote = pcall(holder.SetShown, holder, shown)
    if not wrote or holder:IsShown() ~= shown then
        controller:_QueueHoverRetry()
        return false
    end
    return true
end

local function SetExternalContainerShownSafe(controller, shown)
    if not controller._containerIsExternal
        or not controller._container
        or controller._containerShown == shown
    then
        return true
    end

    if controller.frame:IsMouseOver() then
        controller:_QueueHoverRetry()
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

local function SetControllerShownSafe(controller, shown)
    -- A header-born/seeded container is parented to the secure unit button,
    -- not to BFI's plain holder. Hide it explicitly before hiding the holder;
    -- show it only after the holder is restored. No native visibility is
    -- read: _containerShown tracks only BFI's own successful writes.
    if not shown and not SetExternalContainerShownSafe(controller, false) then
        return false
    end
    if not SetHolderShownSafe(controller, shown) then
        return false
    end
    if shown and not SetExternalContainerShownSafe(controller, true) then
        return false
    end
    return true
end

local function RestoreControllerVisibility(controller)
    local spec = controller._spec
    return SetControllerShownSafe(
        controller,
        spec ~= nil and spec.enabled and spec.shown
    )
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
    -- hover-safe lifecycle gate. Native groups/slots are add-only, so this
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
        MarkBuildShellStranded(self)
    end
    container:Hide()
    AF.SetCustomAuraContainerEnabled(container, false)
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
    AF.SetCustomAuraContainerEnabled(container, spec.enabled)

    if not containerIsExternal then
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

    -- A pure public-holder visibility change is render-side only. It may run
    -- in combat, but still waits for hover to end before firing tooltip
    -- intrinsics through a native child.
    if not HasNativeMutation(self) then
        if RestoreControllerVisibility(self) then
            self._needsVisibility = nil
            pendingControllers[self] = nil
        end
        return
    end

    -- Native configuration and initial-build work is OOC-only. Hide the
    -- plain holder first so no hovered restricted child participates.
    local holderHidden = SetControllerShownSafe(self, false)
    if InCombatLockdown() then
        if holderHidden then
            ApplyLiveUnitRetarget(self)
        end
        if HasNativeMutation(self) then
            QueueController(self)
        else
            self._needsVisibility = true
            if RestoreControllerVisibility(self) then
                self._needsVisibility = nil
                pendingControllers[self] = nil
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
        self._nativeShellStranded = nil
        self._knownInitialReservations = nil
        self._spec = nil
        self._destroyed = true
        constructionStats.destroyCompletions =
            constructionStats.destroyCompletions + 1
        pendingControllers[self] = nil
        return
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
    -- An ordinary out-of-combat update or hover retry may beat the queued
    -- regen event.
    UnregisterRegenIfIdle()
end

function ControllerMixin:GetFrame()
    return self.frame
end

-- Queue the latest configuration-only holder mutation behind the same
-- combat and hover gate as native work. This is intentionally a callback:
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
    controller.frame = CreateFrame("Frame", name, parent)
    controller.frame:Hide()
    controller._seedContainer = options.seedContainer
    controller._liveUnitChanges = options.liveUnitChanges == true
    constructionStats.controllersCreated = constructionStats.controllersCreated + 1

    if controller._seedContainer then
        claimedGroupAuraContainers[controller._seedContainer] = true
        constructionStats.seedsClaimed = constructionStats.seedsClaimed + 1
        controller._seedContainer:Hide()
        AF.SetCustomAuraContainerEnabled(controller._seedContainer, false)
    end

    if completeSpec then
        controller:Rebuild(completeSpec)
    end
    return controller
end

function UF.CreateNativeAuraContainerController(parent, name, completeSpec)
    return CreateController(parent, name, completeSpec)
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
