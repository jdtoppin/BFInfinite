---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework
local IsValueNonSecret = BFI.funcs.isValueNonSecret

local C_Timer = C_Timer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local rawget = rawget

-- Retail 12.1.0.69189 (wow-ui-source a520b6c2) makes aura groups and
-- item-enchantment sources add-only. Their buttons receive conditional access
-- restrictions after AF's initializer returns and deny tainted access whenever
-- aura data is secret. This controller owns configuration state, plain holders,
-- and native container shells; it never reads aura data, restricted buttons,
-- or native container geometry.
local NATIVE_GROUP_INITIAL_RESERVATIONS = 10
local ALLOWED_NATIVE_FOLLOWER_GLOBALS = {
    DebuffFrame = true,
}
local ALLOWED_HOLDER_ANCHOR_GLOBALS = {
    DebuffFrame = true,
}
local VALID_ANCHOR_POINTS = {
    BOTTOM = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
    CENTER = true,
    LEFT = true,
    RIGHT = true,
    TOP = true,
    TOPLEFT = true,
    TOPRIGHT = true,
}

local registrations = {}
local pendingControllers = {}
local regenRegistered
local unitEventsRegistered
local nativeFollowerLifecycleRegistered
local nativeFollowerEditModeActive
local nativeFollowerRefreshQueued
local nativeFollowerRefreshPending

local function NotifyControllerState(controller)
    local signature = table.concat({
        controller.state or "",
        (
            pendingControllers[controller]
            or (
                nativeFollowerRefreshPending
                and controller.active
                and controller.descriptor
                and controller.descriptor.nativeFollower
            )
        ) and "1" or "0",
        controller.reloadRequired and "1" or "0",
        controller.nativeFollowerActive and "1" or "0",
        controller.editModeSuspended and "1" or "0",
        controller.diagnostic or "",
    }, "\031")
    if controller.optionsStateSignature == signature then return end

    controller.optionsStateSignature = signature
    AF.Fire("BFI_RefreshOptions", "buffsDebuffs")
end

local constructionStats = {
    controllersCreated = 0,
    buildAttempts = 0,
    buildCompletions = 0,
    expectedGroups = 0,
    expectedItemEnchantments = 0,
    expectedInitialReservations = 0,
    retiredNativeShells = 0,
    retiredInitialReservations = 0,
    strandedNativeShells = 0,
    strandedInitialReservations = 0,
    reloadRequiredTransitions = 0,
}

local AF_CONSTRUCTION_TOTAL_FIELDS = {
    containerCreateAttempts = "afContainerCreateAttempts",
    containerAllocations = "afContainerAllocations",
    containerCreateCompletions = "afContainerCreateCompletions",
    trackedContainers = "afTrackedContainers",
    externalContainersObserved = "afExternalContainersObserved",
    groupAddAttempts = "afGroupAddAttempts",
    groupsAdded = "afGroupsAdded",
    itemEnchantmentAddAttempts = "afItemEnchantmentAddAttempts",
    itemEnchantmentsAdded = "afItemEnchantmentsAdded",
    initialFrameReservationsAttempted = "afInitialFrameReservationsAttempted",
    initialFrameReservationsCompleted = "afInitialFrameReservationsCompleted",
}

local function Copy(value)
    if type(value) == "table" then
        return AF.Copy(value)
    end
    return value
end

local function TablesEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return false end

    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right

    for key, value in pairs(left) do
        if not TablesEqual(value, right[key], seen) then
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

local function IsPane(which)
    return which == "buffs" or which == "debuffs"
end

local function ResolvePlayerUnit()
    local playerFrame = _G.PlayerFrame
    if playerFrame and type(playerFrame.unit) == "string"
        and playerFrame.unit ~= ""
    then
        return playerFrame.unit
    end
    return "player"
end

local function HasPendingControllers()
    return next(pendingControllers) ~= nil
end

local function UnregisterRegenIfIdle()
    if regenRegistered and not HasPendingControllers() then
        BD:UnregisterEvent("PLAYER_REGEN_ENABLED", BD.FlushCustomAuraContainerUpdates)
        regenRegistered = nil
    end
end

local function QueueController(controller)
    local wasPending = pendingControllers[controller] == true
    pendingControllers[controller] = true
    if not regenRegistered then
        BD:RegisterEvent("PLAYER_REGEN_ENABLED", BD.FlushCustomAuraContainerUpdates)
        regenRegistered = true
    end
    if not wasPending then
        NotifyControllerState(controller)
    end
end

local function UsesHolderAnchor(controller)
    local pendingDescriptor = controller.pendingDescriptor
    local descriptor = controller.descriptor
    return (pendingDescriptor and pendingDescriptor.holderAnchor ~= nil)
        or (descriptor and descriptor.holderAnchor ~= nil)
end

local function DeferControllerForEditMode(controller)
    local wasPending = pendingControllers[controller] == true
    pendingControllers[controller] = true
    if not wasPending then
        NotifyControllerState(controller)
    end
end

local function AssertDescriptor(descriptor)
    assert(type(descriptor) == "table",
        "custom aura pane compiler must return a descriptor")
    assert(type(descriptor.enabled) == "boolean",
        "custom aura descriptor enabled must be a boolean")
    assert(type(descriptor.constructionKey) == "table",
        "custom aura descriptor requires a construction key")
    assert(type(descriptor.holder) == "table"
        and type(descriptor.holder.width) == "number"
        and descriptor.holder.width > 0
        and type(descriptor.holder.height) == "number"
        and descriptor.holder.height > 0,
        "custom aura descriptor requires positive holder dimensions")
    assert(type(descriptor.containerPoint) == "table"
        and type(descriptor.containerPoint.point) == "string"
        and type(descriptor.containerPoint.relativePoint) == "string",
        "custom aura descriptor requires a container point")
    assert(type(descriptor.flowLayout) == "table",
        "custom aura descriptor requires a flow layout")
    assert(type(descriptor.processing) == "table"
        and descriptor.processing.policy ~= nil,
        "custom aura descriptor requires a processing policy")
    assert(type(descriptor.groups) == "table",
        "custom aura descriptor groups must be a table")
    assert(type(descriptor.itemEnchantments) == "table",
        "custom aura descriptor itemEnchantments must be a table")
    assert(descriptor.position == nil or type(descriptor.position) == "table",
        "custom aura descriptor position must be a table or nil")
    assert(descriptor.positionSave == nil
        or type(descriptor.positionSave) == "table"
        or type(descriptor.positionSave) == "function",
        "custom aura descriptor positionSave must be a table, function, or nil")
    assert(descriptor.nativeFollower == nil
        or (
            type(descriptor.nativeFollower) == "table"
            and type(descriptor.nativeFollower.globalName) == "string"
            and ALLOWED_NATIVE_FOLLOWER_GLOBALS[
                descriptor.nativeFollower.globalName
            ] == true
            and VALID_ANCHOR_POINTS[descriptor.nativeFollower.point] == true
            and VALID_ANCHOR_POINTS[
                descriptor.nativeFollower.relativePoint
            ] == true
            and type(descriptor.nativeFollower.x) == "number"
            and type(descriptor.nativeFollower.y) == "number"
        ),
        "custom aura descriptor requires an allowed native follower")
    assert(descriptor.holderRolesets == nil
        or type(descriptor.holderRolesets) == "string",
        "custom aura descriptor holderRolesets must be a string or nil")
    assert(descriptor.holderAnchor == nil
        or (
            type(descriptor.holderAnchor) == "table"
            and type(descriptor.holderAnchor.globalName) == "string"
            and ALLOWED_HOLDER_ANCHOR_GLOBALS[
                descriptor.holderAnchor.globalName
            ] == true
            and VALID_ANCHOR_POINTS[
                descriptor.holderAnchor.point
            ] == true
            and VALID_ANCHOR_POINTS[
                descriptor.holderAnchor.relativePoint
            ] == true
            and type(descriptor.holderAnchor.x) == "number"
            and type(descriptor.holderAnchor.y) == "number"
        ),
        "custom aura descriptor requires an allowed holder anchor")
    assert((descriptor.position ~= nil)
        ~= (descriptor.holderAnchor ~= nil),
        "custom aura descriptor requires one holder position source")
    assert(descriptor.position ~= nil or descriptor.positionSave == nil,
        "custom aura descriptor cannot save a missing holder position")
end

local function CopyDescriptor(descriptor)
    AssertDescriptor(descriptor)
    local copy = Copy(descriptor)
    -- Mover saves must retain their profile-owned table identity or closure.
    -- All native construction/tuning inputs remain isolated copies.
    copy.positionSave = descriptor.positionSave
    return copy
end

local function IsOrdinaryNumber(value)
    return type(IsValueNonSecret) == "function"
        and IsValueNonSecret(value)
        and type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function IsOrdinaryString(value)
    return type(IsValueNonSecret) == "function"
        and IsValueNonSecret(value)
        and type(value) == "string"
        and value ~= ""
end

local function CanAccessNativeFollower(target)
    if not target
        or type(IsValueNonSecret) ~= "function"
        or type(target.CanBeAccessedInContext) ~= "function"
    then
        return false
    end

    local canAccess = target:CanBeAccessedInContext()
    return IsValueNonSecret(canAccess) and canAccess == true
end

local function CopySystemAnchor(anchorInfo, scale)
    if type(anchorInfo) ~= "table" then return end

    local point = anchorInfo.point
    local relativeTo = anchorInfo.relativeTo
    local relativePoint = anchorInfo.relativePoint
    local offsetX = anchorInfo.offsetX
    local offsetY = anchorInfo.offsetY
    if not IsOrdinaryString(point)
        or not VALID_ANCHOR_POINTS[point]
        or not IsOrdinaryString(relativeTo)
        or not IsOrdinaryString(relativePoint)
        or not VALID_ANCHOR_POINTS[relativePoint]
        or not IsOrdinaryNumber(offsetX)
        or not IsOrdinaryNumber(offsetY)
    then
        return
    end

    return {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = offsetX / scale,
        y = offsetY / scale,
    }
end

local function CaptureNativeFollowerRestore(target)
    if not CanAccessNativeFollower(target)
        or type(target.GetScale) ~= "function"
        or type(target.ClearAllPointsBase) ~= "function"
        or type(target.SetPointBase) ~= "function"
        or type(target.systemInfo) ~= "table"
    then
        return
    end

    local scale = target:GetScale()
    if not IsOrdinaryNumber(scale) or scale <= 0 then return end

    local anchorInfo = CopySystemAnchor(
        target.systemInfo.anchorInfo,
        scale
    )
    if not anchorInfo then return end

    local points = {anchorInfo}
    if target.systemInfo.anchorInfo2 ~= nil then
        local anchorInfo2 = CopySystemAnchor(
            target.systemInfo.anchorInfo2,
            scale
        )
        if not anchorInfo2 then return end
        points[2] = anchorInfo2
    end
    return points
end

local function ClearNativeFollowerState(controller)
    controller.nativeFollowerActive = nil
    controller.nativeFollowerTarget = nil
    controller.nativeFollowerRestorePoints = nil
    controller.nativeFollowerSpec = nil
end

local function RestoreNativeFollower(controller)
    if not controller.nativeFollowerActive then
        ClearNativeFollowerState(controller)
        return true
    end
    if InCombatLockdown() then return false end

    local target = controller.nativeFollowerTarget
    local restorePoints = controller.nativeFollowerRestorePoints
    if not CanAccessNativeFollower(target)
        or type(restorePoints) ~= "table"
        or #restorePoints == 0
    then
        return false
    end

    target:ClearAllPointsBase()
    for _, point in ipairs(restorePoints) do
        target:SetPointBase(
            point.point,
            point.relativeTo,
            point.relativePoint,
            point.x,
            point.y
        )
    end
    ClearNativeFollowerState(controller)
    return true
end

local function ApplyNativeFollower(controller, descriptor, refreshRestore)
    local follower = descriptor.nativeFollower
    if not follower then
        return RestoreNativeFollower(controller)
    end
    if InCombatLockdown()
        or nativeFollowerEditModeActive
        or not nativeFollowerLifecycleRegistered
    then
        return false
    end

    if controller.nativeFollowerActive
        and TablesEqual(controller.nativeFollowerSpec, follower)
    then
        if not refreshRestore then return true end

        local refreshed = CaptureNativeFollowerRestore(
            controller.nativeFollowerTarget
        )
        if not refreshed then return false end
        controller.nativeFollowerRestorePoints = refreshed
    elseif controller.nativeFollowerActive then
        if not RestoreNativeFollower(controller) then return false end
    end

    local target = controller.nativeFollowerTarget
    local restorePoints = controller.nativeFollowerRestorePoints
    if not controller.nativeFollowerActive then
        if not ALLOWED_NATIVE_FOLLOWER_GLOBALS[follower.globalName] then
            return false
        end
        target = rawget(_G, follower.globalName)
        restorePoints = CaptureNativeFollowerRestore(target)
        if not restorePoints then return false end
    elseif not CanAccessNativeFollower(target) then
        return false
    end

    target:ClearAllPointsBase()
    target:SetPointBase(
        follower.point,
        controller.holder,
        follower.relativePoint,
        follower.x,
        follower.y
    )
    controller.nativeFollowerTarget = target
    controller.nativeFollowerRestorePoints = restorePoints
    controller.nativeFollowerSpec = Copy(follower)
    controller.nativeFollowerActive = true
    return true
end

local function ApplyHolder(controller, descriptor)
    local holder = controller.holder
    AF.SetSize(holder, descriptor.holder.width, descriptor.holder.height)

    if descriptor.holderAnchor then
        local anchor = descriptor.holderAnchor
        local relativeTo = rawget(_G, anchor.globalName)
        if not relativeTo then return false end

        -- The relative frame is a static positioning seam only. Never read
        -- its geometry or visibility: #127 may move DebuffFrame under the BFI
        -- Buff holder, while Blizzard Edit Mode may restore its native point.
        holder:ClearAllPoints()
        holder:SetPoint(
            anchor.point,
            relativeTo,
            anchor.relativePoint,
            anchor.x,
            anchor.y
        )
    else
        if holder.mover then
            AF.UpdateMoverSave(
                holder,
                descriptor.positionSave or descriptor.position
            )
        end
        BFI.funcs.LoadPosition(holder, descriptor.position)
    end

    holder.enabled = descriptor.enabled
    return true
end

local function PositionContainer(controller, descriptor)
    local point = descriptor.containerPoint
    controller.container:ClearAllPoints()
    controller.container:SetPoint(
        point.point,
        controller.holder,
        point.relativePoint,
        point.x or 0,
        point.y or 0
    )
end

local function ApplyNativeTuning(controller, descriptor)
    local container = controller.container
    if not ApplyHolder(controller, descriptor) then return false end
    PositionContainer(controller, descriptor)
    AF.SetCustomAuraContainerFlowLayout(container, descriptor.flowLayout)
    AF.SetCustomAuraContainerProcessingPolicy(
        container,
        descriptor.processing.policy,
        descriptor.processing.options
    )

    for _, group in ipairs(descriptor.groups) do
        AF.SetCustomAuraGroupFilterString(
            container,
            group.key,
            group.filterString
        )
        AF.SetCustomAuraGroupMaxFrameCount(
            container,
            group.key,
            group.maxFrameCount
        )
        AF.SetCustomAuraGroupCandidateFilters(
            container,
            group.key,
            group.candidateFilters
        )
        AF.SetCustomAuraGroupSortMethod(
            container,
            group.key,
            group.sortMethod,
            group.sortDirection
        )
        AF.SetCustomAuraGroupLayout(container, group.key, group.layout)
    end

    if descriptor.itemEnchantmentSort then
        AF.SetCustomItemEnchantmentSortMethod(
            container,
            descriptor.itemEnchantmentSort.method,
            descriptor.itemEnchantmentSort.direction
        )
    end
    if descriptor.itemEnchantmentLayout then
        AF.SetCustomItemEnchantmentLayout(
            container,
            descriptor.itemEnchantmentLayout
        )
    end

    local unit = ResolvePlayerUnit()
    if controller.unit ~= unit then
        AF.SetCustomAuraContainerUnit(container, unit)
        controller.unit = unit
    end
    AF.UpdateCustomAuraContainer(container)
    return true
end

local function RestoreNative(controller)
    return BD.SetNativePublicAurasSuppressed(controller.which, false) == true
end

local function SuspendNativeForEditMode(controller)
    return type(BD.SuspendNativePublicAuraSuppressionForEditMode) == "function"
        and BD.SuspendNativePublicAuraSuppressionForEditMode(
            controller.which
        ) == true
end

local function HideCustom(controller)
    if controller.container then
        AF.SetCustomAuraContainerEnabled(controller.container, false)
        controller.container:Hide()
    end
    if controller.holder then
        controller.holder.enabled = false
        controller.holder:Hide()
    end
    controller.active = nil
end

local function Deactivate(controller, state)
    if not RestoreNativeFollower(controller) then
        return false
    end
    if not RestoreNative(controller) then
        return false
    end

    HideCustom(controller)
    controller.editModeSuspended = nil
    controller.state = state or (controller.buildCompleted and "INACTIVE" or "NEW")
    return true
end

local function Activate(controller)
    local container = controller.container
    if not ApplyNativeFollower(controller, controller.descriptor) then
        -- A temporarily unavailable follower (most notably while Blizzard
        -- Edit Mode owns DebuffFrame) must also release the public Buff
        -- fallback. Otherwise an update could hide the custom container while
        -- Blizzard Buffs remain suppressed, leaving no Buff display at all.
        RestoreNative(controller)
        AF.SetCustomAuraContainerEnabled(container, false)
        container:Hide()
        controller.holder:Hide()
        controller.active = nil
        controller.state = "NATIVE_UNAVAILABLE"
        controller.diagnostic = "NATIVE_FOLLOWER_UNAVAILABLE"
        return false
    end

    AF.SetCustomAuraContainerEnabled(container, true)

    -- Fail native: do not hide Blizzard until the replacement has completed
    -- its one-shot construction and final enable transition.
    if not BD.SetNativePublicAurasSuppressed(controller.which, true) then
        AF.SetCustomAuraContainerEnabled(container, false)
        container:Hide()
        controller.holder:Hide()
        RestoreNativeFollower(controller)
        controller.active = nil
        controller.state = "SUPPRESSION_FAILED"
        controller.diagnostic = "NATIVE_SUPPRESSION_FAILED"
        return false
    end

    container:Show()
    controller.holder.enabled = true
    controller.holder:Show()
    controller.active = true
    controller.editModeSuspended = nil
    controller.state = "ACTIVE"
    controller.diagnostic = nil
    return true
end

local function CreateHolder(controller, descriptor)
    if controller.holder then return true end

    local holder = CreateFrame("Frame", nil, AF.UIParent)
    holder:Hide()
    if descriptor.holderRolesets then
        holder:SetRolesets(descriptor.holderRolesets)
    end
    AF.SetSize(holder, descriptor.holder.width, descriptor.holder.height)

    if descriptor.moverText then
        AF.CreateMover(
            holder,
            "BFI: " .. L["UI Widgets"],
            descriptor.moverText,
            descriptor.positionSave or descriptor.position
        )
    end
    controller.holder = holder
    return true
end

local function RecordExpectedConstruction(descriptor)
    local groups = #descriptor.groups
    local itemEnchantments = #descriptor.itemEnchantments
    local reservations = groups * NATIVE_GROUP_INITIAL_RESERVATIONS
        + itemEnchantments

    constructionStats.expectedGroups =
        constructionStats.expectedGroups + groups
    constructionStats.expectedItemEnchantments =
        constructionStats.expectedItemEnchantments + itemEnchantments
    constructionStats.expectedInitialReservations =
        constructionStats.expectedInitialReservations + reservations

    return reservations
end

local function Build(controller, descriptor)
    assert(not controller.buildAttempted and not controller.container,
        "custom aura controller permits only one native build attempt")
    if not RestoreNative(controller) then
        controller.state = "NATIVE_UNAVAILABLE"
        controller.diagnostic = "NATIVE_RESTORE_FAILED"
        return false
    end

    CreateHolder(controller, descriptor)
    if not ApplyHolder(controller, descriptor) then
        HideCustom(controller)
        controller.state = "NATIVE_UNAVAILABLE"
        controller.diagnostic = "HOLDER_ANCHOR_UNAVAILABLE"
        return false
    end

    controller.buildAttempted = true
    controller.state = "BUILDING"
    constructionStats.buildAttempts = constructionStats.buildAttempts + 1
    local expectedReservations = RecordExpectedConstruction(descriptor)
    controller.expectedInitialReservations = expectedReservations

    local container = AF.CreateCustomAuraContainer(controller.holder)
    controller.container = container
    constructionStats.strandedNativeShells =
        constructionStats.strandedNativeShells + 1
    constructionStats.strandedInitialReservations =
        constructionStats.strandedInitialReservations + expectedReservations

    container:Hide()
    AF.SetCustomAuraContainerEnabled(container, false)
    PositionContainer(controller, descriptor)
    AF.SetCustomAuraContainerFlowLayout(container, descriptor.flowLayout)
    AF.SetCustomAuraContainerProcessingPolicy(
        container,
        descriptor.processing.policy,
        descriptor.processing.options
    )

    if descriptor.itemEnchantmentSort then
        AF.SetCustomItemEnchantmentSortMethod(
            container,
            descriptor.itemEnchantmentSort.method,
            descriptor.itemEnchantmentSort.direction
        )
    end
    if descriptor.itemEnchantmentLayout then
        AF.SetCustomItemEnchantmentLayout(
            container,
            descriptor.itemEnchantmentLayout
        )
    end
    for _, enchantment in ipairs(descriptor.itemEnchantments) do
        AF.AddCustomItemEnchantment(
            container,
            enchantment.slot,
            enchantment.options,
            enchantment.buttonStyle
        )
    end

    for _, group in ipairs(descriptor.groups) do
        AF.AddCustomAuraGroup(
            container,
            group.key,
            group.filterString,
            {
                maxFrameCount = group.maxFrameCount,
                candidateFilters = group.candidateFilters,
                sortMethod = group.sortMethod,
                sortDirection = group.sortDirection,
                layout = group.layout,
            },
            group.buttonStyle
        )
    end

    -- SetUnit must follow every add-only source so native event registration
    -- sees the complete topology. Enabling is the final native mutation.
    local unit = ResolvePlayerUnit()
    AF.SetCustomAuraContainerUnit(container, unit)
    controller.unit = unit
    AF.UpdateCustomAuraContainer(container)

    controller.buildCompleted = true
    controller.builtConstructionKey = Copy(descriptor.constructionKey)
    controller.descriptor = descriptor
    constructionStats.buildCompletions = constructionStats.buildCompletions + 1
    constructionStats.strandedNativeShells =
        constructionStats.strandedNativeShells - 1
    constructionStats.strandedInitialReservations =
        constructionStats.strandedInitialReservations - expectedReservations

    return Activate(controller)
end

local ControllerMixin = {}

function ControllerMixin:_ApplyRetarget()
    if not self.container or not self.buildCompleted or not self.pendingUnit then
        return false
    end
    AF.SetCustomAuraContainerUnit(self.container, self.pendingUnit)
    AF.UpdateCustomAuraContainer(self.container)
    self.unit = self.pendingUnit
    self.pendingUnit = nil
    return true
end

function ControllerMixin:_ApplyPending()
    if (self.pendingOperation or self.pendingUnit)
        and nativeFollowerEditModeActive
        and UsesHolderAnchor(self)
    then
        -- A holder anchored to Blizzard's DebuffFrame must remain dormant while
        -- Edit Mode owns that root. Preserve only the latest requested operation;
        -- the queued Exit refresh applies it before considering normal resume.
        DeferControllerForEditMode(self)
        return
    end

    if not self.pendingOperation and self.pendingUnit then
        self:_ApplyRetarget()
        if not self.pendingUnit then
            pendingControllers[self] = nil
            UnregisterRegenIfIdle()
        end
        NotifyControllerState(self)
        return
    end

    if not self.pendingOperation then
        pendingControllers[self] = nil
        UnregisterRegenIfIdle()
        NotifyControllerState(self)
        return
    end

    if InCombatLockdown() then
        QueueController(self)
        return
    end
    local operation = self.pendingOperation
    local descriptor = self.pendingDescriptor
    local diagnostic = self.pendingDiagnostic
    self.pendingOperation = nil
    self.pendingDescriptor = nil
    self.pendingDiagnostic = nil
    pendingControllers[self] = nil

    if operation == "disable" then
        if not Deactivate(self) then
            self.pendingOperation = operation
            QueueController(self)
            return
        end
        self.reloadRequired = nil
        self.diagnostic = nil
    elseif operation == "unsupported" then
        if not Deactivate(self, "UNSUPPORTED") then
            self.pendingOperation = operation
            self.pendingDiagnostic = diagnostic
            QueueController(self)
            return
        end
        self.reloadRequired = nil
        self.diagnostic = diagnostic or "UNSUPPORTED_CONFIG"
    elseif not descriptor.enabled then
        if not Deactivate(self) then
            self.pendingOperation = operation
            self.pendingDescriptor = descriptor
            QueueController(self)
            return
        end
        self.descriptor = descriptor
        self.reloadRequired = nil
        self.diagnostic = nil
    elseif not self.buildCompleted then
        if self.buildAttempted then
            self.state = "FAILED"
            self.diagnostic = "INCOMPLETE_BUILD"
        else
            Build(self, descriptor)
        end
    elseif not TablesEqual(
        descriptor.constructionKey,
        self.builtConstructionKey
    ) then
        if not Deactivate(self, "RELOAD_REQUIRED") then
            self.pendingOperation = operation
            self.pendingDescriptor = descriptor
            QueueController(self)
            return
        end
        if not self.reloadRequired then
            constructionStats.reloadRequiredTransitions =
                constructionStats.reloadRequiredTransitions + 1
        end
        self.reloadRequired = true
        self.descriptor = descriptor
        self.diagnostic = "CONSTRUCTION_CHANGE_REQUIRES_RELOAD"
    else
        self.reloadRequired = nil
        self.descriptor = descriptor
        if ApplyNativeTuning(self, descriptor) then
            Activate(self)
        else
            RestoreNative(self)
            HideCustom(self)
            self.state = "NATIVE_UNAVAILABLE"
            self.diagnostic = "HOLDER_ANCHOR_UNAVAILABLE"
        end
    end

    if self.pendingUnit then
        self:_ApplyRetarget()
    end
    UnregisterRegenIfIdle()
    NotifyControllerState(self)
end

function ControllerMixin:Update(config)
    self.requestGeneration = (self.requestGeneration or 0) + 1
    local descriptor, diagnostic = self.compiler(config)
    if descriptor == nil then
        self.pendingOperation = "unsupported"
        self.pendingDescriptor = nil
        self.pendingDiagnostic = diagnostic
    else
        self.pendingOperation = "update"
        self.pendingDescriptor = CopyDescriptor(descriptor)
        self.pendingDiagnostic = nil
    end
    self:_ApplyPending()
end

function ControllerMixin:Disable()
    self.requestGeneration = (self.requestGeneration or 0) + 1
    self.pendingOperation = "disable"
    self.pendingDescriptor = nil
    self.pendingDiagnostic = nil
    self:_ApplyPending()
end

function ControllerMixin:GetState()
    return {
        which = self.which,
        state = self.state,
        active = self.active == true,
        pending = pendingControllers[self] == true
            or (
                nativeFollowerRefreshPending == true
                and self.active == true
                and self.descriptor ~= nil
                and self.descriptor.nativeFollower ~= nil
            ),
        buildAttempted = self.buildAttempted == true,
        buildCompleted = self.buildCompleted == true,
        nativeFollowerActive = self.nativeFollowerActive == true,
        editModeSuspended = self.editModeSuspended == true,
        reloadRequired = self.reloadRequired == true,
        diagnostic = self.diagnostic,
        unit = self.unit,
        expectedInitialReservations =
            self.expectedInitialReservations or 0,
    }
end

local function RefreshNativeAuraFollowers()
    nativeFollowerRefreshQueued = nil
    if InCombatLockdown() then
        nativeFollowerRefreshPending = true
        for _, controller in pairs(registrations) do
            NotifyControllerState(controller)
        end
        return
    end
    if nativeFollowerEditModeActive then return end
    nativeFollowerRefreshPending = nil

    for _, controller in pairs(registrations) do
        local descriptor = controller.descriptor
        if controller.active
            and descriptor
            and descriptor.nativeFollower
        then
            if ApplyNativeFollower(controller, descriptor, true) then
                if controller.diagnostic == "NATIVE_FOLLOWER_UNAVAILABLE" then
                    controller.diagnostic = nil
                end
            else
                controller.diagnostic = "NATIVE_FOLLOWER_UNAVAILABLE"
            end
            NotifyControllerState(controller)
        elseif controller.buildCompleted
            and descriptor
            and descriptor.enabled
            and descriptor.nativeFollower
            and controller.diagnostic == "NATIVE_FOLLOWER_UNAVAILABLE"
        then
            -- The native frame can be temporarily unavailable while Blizzard
            -- Edit Mode owns it or before its systemInfo is initialized. A
            -- later lifecycle event retries the completed container without
            -- allocating another native shell.
            Activate(controller)
            NotifyControllerState(controller)
        end
    end

    -- Apply holder-anchored work accumulated during Edit Mode before the
    -- ordinary suspension-resume pass. Update/disable calls overwrite the
    -- controller's pending fields, so this drains exactly the latest request.
    local deferredHolderControllers = {}
    for controller in pairs(pendingControllers) do
        if UsesHolderAnchor(controller) then
            deferredHolderControllers[#deferredHolderControllers + 1] = controller
        end
    end
    for _, controller in ipairs(deferredHolderControllers) do
        controller:_ApplyPending()
    end

    for _, controller in pairs(registrations) do
        if controller.editModeSuspended
            and controller.buildCompleted
            and controller.descriptor
            and controller.descriptor.enabled
        then
            if ApplyNativeTuning(controller, controller.descriptor)
                and Activate(controller)
            then
                controller.editModeSuspended = nil
            else
                controller.state = "NATIVE_UNAVAILABLE"
                controller.diagnostic = "EDIT_MODE_RESUME_FAILED"
            end
            NotifyControllerState(controller)
        end
    end

    for _, controller in pairs(registrations) do
        if controller.active
            and type(BD.ReassertNativePublicAuraSuppression) == "function"
        then
            if not BD.ReassertNativePublicAuraSuppression(controller.which) then
                Deactivate(controller, "SUPPRESSION_FAILED")
                controller.diagnostic = "NATIVE_SUPPRESSION_FAILED"
            end
            NotifyControllerState(controller)
        end
    end
end

local function QueueNativeAuraFollowerRefresh()
    if nativeFollowerRefreshQueued then return end
    nativeFollowerRefreshQueued = true
    C_Timer.After(0, RefreshNativeAuraFollowers)
end

local function OnNativeAuraFollowerEvent()
    QueueNativeAuraFollowerRefresh()
end

local function OnEditModeEnter()
    nativeFollowerEditModeActive = true
    for _, controller in pairs(registrations) do
        if controller.nativeFollowerActive then
            if not RestoreNativeFollower(controller) then
                controller.diagnostic = "NATIVE_FOLLOWER_UNAVAILABLE"
            end
            NotifyControllerState(controller)
        end

        local descriptor = controller.descriptor
        if controller.active
            and descriptor
            and descriptor.holderAnchor
        then
            if SuspendNativeForEditMode(controller) then
                HideCustom(controller)
                controller.editModeSuspended = true
                controller.state = "EDIT_MODE_SUSPENDED"
                controller.diagnostic = nil
            else
                controller.diagnostic = "EDIT_MODE_SUSPEND_FAILED"
            end
            NotifyControllerState(controller)
        end
    end
end

local function OnEditModeExit()
    nativeFollowerEditModeActive = nil
    QueueNativeAuraFollowerRefresh()
end

local function RegisterNativeFollowerLifecycle()
    if nativeFollowerLifecycleRegistered then return true end

    local eventRegistry = rawget(_G, "EventRegistry")
    if not eventRegistry
        or type(eventRegistry.RegisterCallback) ~= "function"
    then
        return false
    end

    local editMode = rawget(_G, "EditModeManagerFrame")
    local editModeActive = editMode and editMode.editModeActive
    if editModeActive ~= nil then
        if type(IsValueNonSecret) == "function"
            and IsValueNonSecret(editModeActive)
            and type(editModeActive) == "boolean"
        then
            nativeFollowerEditModeActive = editModeActive or nil
        else
            -- Unknown Edit Mode state is treated as active so the protected
            -- native frame is never moved on an ambiguous execution path.
            nativeFollowerEditModeActive = true
        end
    end

    eventRegistry:RegisterCallback(
        "EditMode.Enter",
        OnEditModeEnter,
        BD
    )
    eventRegistry:RegisterCallback(
        "EditMode.Exit",
        OnEditModeExit,
        BD
    )
    BD:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", OnNativeAuraFollowerEvent)
    BD:RegisterEvent("PLAYER_ENTERING_WORLD", OnNativeAuraFollowerEvent)
    BD:RegisterEvent("PLAYER_REGEN_ENABLED", OnNativeAuraFollowerEvent)
    BD:RegisterEvent(
        "PLAYER_SPECIALIZATION_CHANGED",
        OnNativeAuraFollowerEvent
    )
    BD:RegisterEvent(
        "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
        OnNativeAuraFollowerEvent
    )
    nativeFollowerLifecycleRegistered = true
    return true
end

function BD.RegisterCustomAuraContainerPane(which, compiler)
    assert(IsPane(which), "custom aura pane must be buffs or debuffs")
    assert(type(compiler) == "function",
        "custom aura pane compiler must be a function")
    assert(registrations[which] == nil,
        "custom aura pane is already registered: " .. which)

    RegisterNativeFollowerLifecycle()

    local controller = {
        which = which,
        compiler = compiler,
        state = "NEW",
    }
    Mixin(controller, ControllerMixin)
    registrations[which] = controller
    constructionStats.controllersCreated =
        constructionStats.controllersCreated + 1

    if not unitEventsRegistered then
        BD:RegisterEvent("PLAYER_ENTERING_WORLD", BD.RefreshCustomAuraContainerUnits)
        BD:RegisterEvent("UNIT_ENTERED_VEHICLE", BD.RefreshCustomAuraContainerUnits)
        BD:RegisterEvent("UNIT_EXITED_VEHICLE", BD.RefreshCustomAuraContainerUnits)
        unitEventsRegistered = true
    end

    return controller
end

function BD.IsCustomAuraContainerAvailable(which)
    return IsPane(which)
        and registrations[which] ~= nil
        and type(BD.HasCustomAuraContainerPaneCapability) == "function"
        and BD.HasCustomAuraContainerPaneCapability(which) == true
        and BD.CanSuppressNativePublicAuras(which) == true
end

function BD.UpdateCustomAuraContainer(which, config)
    local controller = registrations[which]
    if not controller
        or type(BD.HasCustomAuraContainerPaneCapability) ~= "function"
        or not BD.HasCustomAuraContainerPaneCapability(which)
    then
        return false
    end

    controller:Update(config)
    return true
end

function BD.DisableCustomAuraContainer(which)
    local controller = registrations[which]
    if not controller then return false end

    controller:Disable()
    return true
end

function BD.GetCustomAuraContainerState(which)
    local controller = registrations[which]
    if not controller then return nil end
    return controller:GetState()
end

function BD.GetCustomAuraContainerConstructionStats()
    local snapshot = {}
    for field, value in pairs(constructionStats) do
        snapshot[field] = value
    end
    snapshot.liveControllers = constructionStats.controllersCreated
    snapshot.incompleteBuilds =
        constructionStats.buildAttempts - constructionStats.buildCompletions

    if type(AF.GetCustomAuraContainerConstructionTotals) == "function" then
        local afTotals = AF.GetCustomAuraContainerConstructionTotals()
        for sourceField, resultField in pairs(AF_CONSTRUCTION_TOTAL_FIELDS) do
            snapshot[resultField] = afTotals[sourceField] or 0
        end
    else
        for _, resultField in pairs(AF_CONSTRUCTION_TOTAL_FIELDS) do
            snapshot[resultField] = 0
        end
    end
    return snapshot
end

function BD.FlushCustomAuraContainerUpdates()
    if InCombatLockdown() then return end

    for controller in pairs(pendingControllers) do
        local pendingController = controller
        C_Timer.After(0, function()
            if pendingControllers[pendingController] then
                pendingController:_ApplyPending()
            end
        end)
    end
end

function BD.RefreshCustomAuraContainerUnits()
    local unit = ResolvePlayerUnit()
    for _, controller in pairs(registrations) do
        if controller.buildCompleted and controller.unit ~= unit then
            controller.pendingUnit = unit
            controller:_ApplyPending()
        end
    end
end
