---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework

local C_Timer = C_Timer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

-- Retail 12.1.0.68914 (wow-ui-source d3915c78) makes aura groups and
-- item-enchantment sources add-only and restricts their buttons immediately
-- after AF's initializer returns. This controller owns configuration state,
-- plain holders, and native container shells; it never reads aura data,
-- restricted buttons, or native container geometry.
local NATIVE_GROUP_INITIAL_RESERVATIONS = 10
local HOVER_RETRY_SECONDS = 0.25

local registrations = {}
local pendingControllers = {}
local regenRegistered
local unitEventsRegistered

local function NotifyControllerState(controller)
    local signature = table.concat({
        controller.state or "",
        pendingControllers[controller] and "1" or "0",
        controller.reloadRequired and "1" or "0",
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

local function IsControllerHovered(controller)
    if controller.holder
        and type(controller.holder.IsMouseOver) == "function"
        and controller.holder:IsMouseOver()
    then
        return true
    end

    return type(BD.IsNativePublicAuraFrameHovered) == "function"
        and BD.IsNativePublicAuraFrameHovered(controller.which) == true
end

local function QueueHoverRetry(controller)
    QueueController(controller)
    if controller.hoverRetryScheduled then return end

    controller.hoverRetryScheduled = true
    C_Timer.After(HOVER_RETRY_SECONDS, function()
        controller.hoverRetryScheduled = nil
        if pendingControllers[controller] then
            controller:_ApplyPending()
        end
    end)
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
        or type(descriptor.positionSave) == "table",
        "custom aura descriptor positionSave must be a table or nil")
end

local function CopyDescriptor(descriptor)
    AssertDescriptor(descriptor)
    local copy = Copy(descriptor)
    -- Mover saves must retain the profile-owned table identity. All native
    -- construction/tuning inputs remain isolated copies.
    copy.positionSave = descriptor.positionSave
    return copy
end

local function ApplyHolder(controller, descriptor)
    local holder = controller.holder
    AF.SetSize(holder, descriptor.holder.width, descriptor.holder.height)

    if descriptor.position then
        if holder.mover then
            AF.UpdateMoverSave(
                holder,
                descriptor.positionSave or descriptor.position
            )
        end
        AF.LoadPosition(holder, descriptor.position)
    end

    holder.enabled = descriptor.enabled
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
    ApplyHolder(controller, descriptor)
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
end

local function RestoreNative(controller)
    return BD.SetNativePublicAurasSuppressed(controller.which, false) == true
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
    if not RestoreNative(controller) then
        return false
    end

    HideCustom(controller)
    controller.state = state or (controller.buildCompleted and "INACTIVE" or "NEW")
    return true
end

local function Activate(controller)
    local container = controller.container
    AF.SetCustomAuraContainerEnabled(container, true)

    -- Fail native: do not hide Blizzard until the replacement has completed
    -- its one-shot construction and final enable transition.
    if not BD.SetNativePublicAurasSuppressed(controller.which, true) then
        AF.SetCustomAuraContainerEnabled(container, false)
        container:Hide()
        controller.holder:Hide()
        controller.active = nil
        controller.state = "SUPPRESSION_FAILED"
        controller.diagnostic = "NATIVE_SUPPRESSION_FAILED"
        return false
    end

    container:Show()
    controller.holder.enabled = true
    controller.holder:Show()
    controller.active = true
    controller.state = "ACTIVE"
    controller.diagnostic = nil
    return true
end

local function CreateHolder(controller, descriptor)
    if controller.holder then return end

    local holder = CreateFrame("Frame", nil, AF.UIParent)
    controller.holder = holder
    holder:Hide()
    AF.SetSize(holder, descriptor.holder.width, descriptor.holder.height)

    if descriptor.moverText then
        AF.CreateMover(
            holder,
            "BFI: " .. L["UI Widgets"],
            descriptor.moverText,
            descriptor.positionSave or descriptor.position
        )
    end
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

    controller.buildAttempted = true
    controller.state = "BUILDING"
    constructionStats.buildAttempts = constructionStats.buildAttempts + 1
    local expectedReservations = RecordExpectedConstruction(descriptor)
    controller.expectedInitialReservations = expectedReservations

    CreateHolder(controller, descriptor)
    ApplyHolder(controller, descriptor)

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
    if IsControllerHovered(self) then
        QueueHoverRetry(self)
        return false
    end

    AF.SetCustomAuraContainerUnit(self.container, self.pendingUnit)
    AF.UpdateCustomAuraContainer(self.container)
    self.unit = self.pendingUnit
    self.pendingUnit = nil
    return true
end

function ControllerMixin:_ApplyPending()
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
    if IsControllerHovered(self) then
        QueueHoverRetry(self)
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
        ApplyNativeTuning(self, descriptor)
        Activate(self)
    end

    if self.pendingUnit then
        self:_ApplyRetarget()
    end
    UnregisterRegenIfIdle()
    NotifyControllerState(self)
end

function ControllerMixin:Update(config)
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
        pending = pendingControllers[self] == true,
        hoverRetryScheduled = self.hoverRetryScheduled == true,
        buildAttempted = self.buildAttempted == true,
        buildCompleted = self.buildCompleted == true,
        reloadRequired = self.reloadRequired == true,
        diagnostic = self.diagnostic,
        unit = self.unit,
        expectedInitialReservations =
            self.expectedInitialReservations or 0,
    }
end

function BD.RegisterCustomAuraContainerPane(which, compiler)
    assert(IsPane(which), "custom aura pane must be buffs or debuffs")
    assert(type(compiler) == "function",
        "custom aura pane compiler must be a function")
    assert(registrations[which] == nil,
        "custom aura pane is already registered: " .. which)

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
        and BD.HasCustomAuraContainerCapability() == true
        and BD.CanSuppressNativePublicAuras(which) == true
end

function BD.UpdateCustomAuraContainer(which, config)
    local controller = registrations[which]
    if not controller or not BD.HasCustomAuraContainerCapability() then
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
