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

-- Retail 12.1.0.69273 (wow-ui-source eb941aad) makes native aura
-- groups/slots add-only and restricts their buttons after initialization.
-- This controller owns only configuration-derived state and never reads aura
-- data, live buttons, native container geometry, or native visibility.
local REQUIRED_AF_VERSION = 33
local REQUIRED_AF_METHODS = {
    "AddCustomAuraGroup",
    "AddCustomAuraSlot",
    "CreateCustomAuraContainer",
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
    if controller._holderShown == shown then
        return true
    end

    -- Retail 12.1.0.69273 can make visibility and hover accessors secret when
    -- a holder is anchored to a native aura container. Keep an ordinary
    -- write-only ledger instead of inspecting frame state.
    controller.frame:SetShown(shown)
    controller._holderShown = shown
    return true
end

local function RestoreHolderVisibility(controller)
    local spec = controller._spec
    return SetHolderShownSafe(
        controller,
        spec ~= nil and spec.enabled and spec.shown
    )
end

local function PositionContainer(container, holder, point)
    container:ClearAllPoints()
    container:SetPoint(point.point, holder, point.relativePoint, point.x, point.y)
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

function ControllerMixin:_Build()
    local spec = self._spec
    local holder = self.frame

    AF.SetSize(holder, spec.holder.width, spec.holder.height)

    -- Build a complete hidden replacement before touching the old container.
    -- The public holder is already hidden by the hover-safe lifecycle gate.
    local container = AF.CreateCustomAuraContainer(holder)
    container:Hide()
    AF.SetCustomAuraContainerEnabled(container, false)
    PositionContainer(container, holder, spec.containerPoint)
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
    end

    for _, slot in ipairs(spec.slots) do
        local button = AF.AddCustomAuraSlot(container, slot.key, slot.filterString, {
            candidateFilters = slot.candidateFilters,
            sortMethod = slot.sortMethod,
            sortDirection = slot.sortDirection,
        }, slot.buttonStyle)
        button:ClearAllPoints()
        button:SetPoint(
            slot.point.point,
            holder,
            slot.point.relativePoint,
            slot.point.x,
            slot.point.y
        )
    end

    -- Unit is assigned only after every source and construction-time slot
    -- anchor exists. Enabling remains the final native lifecycle transition.
    AF.SetCustomAuraContainerUnit(container, spec.unit)
    AF.UpdateCustomAuraContainer(container)
    AF.SetCustomAuraContainerEnabled(container, spec.enabled)

    local oldContainer = self._container
    if oldContainer then
        AF.SetCustomAuraContainerEnabled(oldContainer, false)
        oldContainer:Hide()
    end

    self._container = container
    container:Show()
end

function ControllerMixin:_ApplyPending()
    if not HasPendingMutation(self) then
        pendingControllers[self] = nil
        return
    end

    -- A pure public-holder visibility change is render-side only and may run
    -- in combat. Holder state is tracked only through BFI-owned writes.
    if not HasNativeMutation(self) then
        if RestoreHolderVisibility(self) then
            self._needsVisibility = nil
            pendingControllers[self] = nil
        end
        return
    end

    -- Native configuration and replacement work is OOC-only. Hide the holder
    -- before applying the complete requested presentation.
    local holderHidden = SetHolderShownSafe(self, false)
    if InCombatLockdown() then
        QueueController(self)
        return
    end
    if not holderHidden then
        return
    end

    if self._destroyRequested then
        if self._container then
            AF.SetCustomAuraContainerEnabled(self._container, false)
            self._container:Hide()
            self._container = nil
        end
        self._spec = nil
        self._holderShown = nil
        self._destroyed = true
        pendingControllers[self] = nil
        return
    end

    if self._holderConfig then
        local configure = self._holderConfig
        self._holderConfig = nil
        configure(self.frame)
    end

    -- Holder-only placement/configuration is allowed before the first
    -- complete native spec. When it is the only pending work, restore the
    -- configured visibility of an existing spec and stop here.
    if not HasNativeMutation(self) then
        if self._spec then
            self._needsVisibility = true
            if RestoreHolderVisibility(self) then
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
        if RestoreHolderVisibility(self) then
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
    if RestoreHolderVisibility(self) then
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

-- Expose only the native frame reference needed for forbidden-aspect-safe
-- dependent anchoring. Callers must never inspect its size, visibility,
-- children, aura data, or other restricted state.
function ControllerMixin:GetNativeFrame()
    return self._container
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

    self._spec = NormalizeCompleteSpec(completeSpec)
    self._needsRebuild = true
    self._needsTuning = nil
    self._needsRetarget = nil
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
    if not self._needsRebuild then
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

    -- 69273's inbound UpdateAllAuras only marks a full native dirty rebuild.
    -- It does not expose aura values and is safe for stable-token refreshes.
    AF.UpdateCustomAuraContainer(self._container)
end

function ControllerMixin:Destroy()
    if self._destroyed or self._destroyRequested then return end

    self._destroyRequested = true
    self._holderConfig = nil
    self._needsRebuild = nil
    self._needsTuning = nil
    self._needsRetarget = nil
    self._needsEnabled = nil
    self._needsVisibility = nil
    self._needsRefresh = nil
    RequestMutation(self)
end

function UF.CreateNativeAuraContainerController(
    parent,
    name,
    completeSpec,
    frameTemplate
)
    if not UF.HasNativeAuraContainerBackend() then
        return nil
    end

    local controller = setmetatable({}, ControllerMixin)
    controller.frame = CreateFrame("Frame", name, parent, frameTemplate)
    controller.frame:Hide()
    controller._holderShown = false

    if completeSpec then
        controller:Rebuild(completeSpec)
    end
    return controller
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

    if not shown then
        if not SetHolderShownSafe(controller, false) then
            return false
        end
        for _, key in ipairs(PARTITION_VARIANTS) do
            SetPartitionChildShown(controller[key], false)
        end
        controller._shownVariant = nil
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
        end
        return
    end

    local holderHidden = SetHolderShownSafe(self, false)
    if InCombatLockdown() then
        QueueController(self)
        return
    end
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
    controller.frame:Hide()
    controller._holderShown = false
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
