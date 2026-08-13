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

-- Retail 12.1.0.69273 (wow-ui-source
-- eb941aad028d73ddc69e3e8ef4da709f4d3cd744) makes aura groups and
-- item-enchantment sources add-only, then conditionally denies tainted button
-- access whenever aura data is secret after AF's initializer returns. This
-- controller owns configuration state, plain holders, native container shells,
-- and one validated Edit Mode root anchor; it never reads aura data,
-- restricted buttons, private anchors, DeadlyDebuffFrame, or aura geometry.
-- The follower transaction reads only validated DebuffFrame Edit Mode root
-- anchor metadata documented by the pinned build above.
local NATIVE_GROUP_INITIAL_RESERVATIONS = 10
local ALLOWED_NATIVE_FOLLOWER_GLOBALS = {
    DebuffFrame = true,
}
local ALLOWED_HOLDER_ANCHOR_GLOBALS = {
    DebuffFrame = true,
}
local ALLOWED_RESTORE_RELATIVE_GLOBALS = {
    BuffFrame = true,
    UIParent = true,
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

local function SetNativeFollowerRefreshPending(controller, pending)
    controller.nativeFollowerRefreshPending = pending and true or nil
end

local function NotifyControllerState(controller)
    local signature = table.concat({
        controller.state or "",
        (
            pendingControllers[controller]
            or (
                controller.nativeFollowerRefreshPending
                and controller.active
                and controller.descriptor
                and controller.descriptor.nativeFollower
            )
        ) and "1" or "0",
        controller.reloadRequired and "1" or "0",
        controller.nativeFollowerActive and "1" or "0",
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
    if not IsValueNonSecret(playerFrame)
        or (type(playerFrame) ~= "table" and type(playerFrame) ~= "userdata")
    then
        return "player"
    end
    local unit = playerFrame.unit
    if IsValueNonSecret(unit)
        and type(unit) == "string"
        and (unit == "player" or unit == "vehicle")
    then
        return unit
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
            and descriptor.nativeFollower.globalName == "DebuffFrame"
            and descriptor.nativeFollower.point == "TOPRIGHT"
            and descriptor.nativeFollower.relativePoint == "BOTTOMRIGHT"
            and descriptor.nativeFollower.x == 0
            and descriptor.nativeFollower.y == -5
        ),
        "custom aura descriptor requires an allowed native follower")
    assert(descriptor.holderAnchor == nil
        or (
            type(descriptor.holderAnchor) == "table"
            and descriptor.holderAnchor.globalName == "DebuffFrame"
            and descriptor.holderAnchor.point == "TOPRIGHT"
            and descriptor.holderAnchor.relativePoint == "TOPRIGHT"
            and descriptor.holderAnchor.x == 0
            and descriptor.holderAnchor.y == 0
        ),
        "custom aura descriptor requires an allowed holder anchor")
    assert(descriptor.nativeSuppression == nil
        or descriptor.nativeSuppression == "harmful",
        "custom aura descriptor requires an allowed native suppression")
    assert(descriptor.holderRolesets == nil
        or descriptor.holderRolesets == "buffs",
        "custom aura descriptor holderRolesets must be literal buffs or nil")
    assert(descriptor.nativeFollower == nil or descriptor.position ~= nil,
        "custom aura native follower requires a holder position")
    assert((descriptor.position ~= nil)
        ~= (descriptor.holderAnchor ~= nil),
        "custom aura descriptor requires one holder position source")
    assert(descriptor.nativeSuppression ~= "harmful"
        or (
            descriptor.holderAnchor ~= nil
            and descriptor.nativeFollower == nil
        ),
        "harmful native suppression requires the DebuffFrame holder anchor")
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

local function IsOrdinaryPositiveNumber(value)
    return IsOrdinaryNumber(value) and value > 0
end

local function IsOrdinaryValue(value)
    return type(IsValueNonSecret) == "function"
        and IsValueNonSecret(value)
end

local function IsOrdinaryTable(value)
    return IsOrdinaryValue(value) and type(value) == "table"
end

local function IsOrdinaryFunction(value)
    return IsOrdinaryValue(value) and type(value) == "function"
end

local function IsOrdinaryString(value)
    return type(IsValueNonSecret) == "function"
        and IsValueNonSecret(value)
        and type(value) == "string"
        and value ~= ""
end

local function IsOutOfCombat()
    local locked = InCombatLockdown()
    return IsOrdinaryValue(locked)
        and type(locked) == "boolean"
        and locked == false
end

local function CanAccessScriptObject(target)
    if not IsOrdinaryValue(target) then return false end
    local targetType = type(target)
    if targetType ~= "table" and targetType ~= "userdata" then
        return false
    end

    local canAccessMethod = target.CanBeAccessedInContext
    if not IsOrdinaryFunction(canAccessMethod) then return false end
    local canAccess = canAccessMethod(target)
    if not IsOrdinaryValue(canAccess)
        or type(canAccess) ~= "boolean"
        or canAccess ~= true
    then
        return
    end
    return canAccessMethod
end

local function ResolveAccessibleGlobal(globalName, allowedGlobals)
    if not IsOrdinaryString(globalName) or allowedGlobals[globalName] ~= true then
        return
    end
    local target = rawget(_G, globalName)
    local canAccessMethod = CanAccessScriptObject(target)
    if not canAccessMethod then return end
    return target, canAccessMethod
end

local function CaptureSystemAnchor(anchorInfo, scale)
    if not IsOrdinaryTable(anchorInfo)
        or not IsOrdinaryPositiveNumber(scale)
    then
        return
    end

    local point = anchorInfo.point
    local relativeTo = anchorInfo.relativeTo
    local relativePoint = anchorInfo.relativePoint
    local offsetX = anchorInfo.offsetX
    local offsetY = anchorInfo.offsetY
    if not IsOrdinaryString(point)
        or VALID_ANCHOR_POINTS[point] ~= true
        or not IsOrdinaryString(relativeTo)
        or not IsOrdinaryString(relativePoint)
        or VALID_ANCHOR_POINTS[relativePoint] ~= true
        or not IsOrdinaryNumber(offsetX)
        or not IsOrdinaryNumber(offsetY)
    then
        return
    end

    local relativeObject, relativeAccessMethod = ResolveAccessibleGlobal(
        relativeTo,
        ALLOWED_RESTORE_RELATIVE_GLOBALS
    )
    if not relativeObject then return end
    local x = offsetX / scale
    local y = offsetY / scale
    if not IsOrdinaryNumber(x) or not IsOrdinaryNumber(y) then return end
    return {
        source = anchorInfo,
        point = point,
        relativeName = relativeTo,
        relativeObject = relativeObject,
        relativeAccessMethod = relativeAccessMethod,
        relativePoint = relativePoint,
        offsetX = offsetX,
        offsetY = offsetY,
        x = x,
        y = y,
    }
end

local function CaptureNativeFollowerSnapshot()
    local target, canAccessMethod = ResolveAccessibleGlobal(
        "DebuffFrame",
        ALLOWED_NATIVE_FOLLOWER_GLOBALS
    )
    if not target then return end
    local getScale = target.GetScale
    local clearPoints = target.ClearAllPointsBase
    local setPoint = target.SetPointBase
    local systemInfo = target.systemInfo
    if not IsOrdinaryFunction(getScale)
        or not IsOrdinaryFunction(clearPoints)
        or not IsOrdinaryFunction(setPoint)
        or not IsOrdinaryTable(systemInfo)
    then
        return
    end

    local scale = getScale(target)
    if not IsOrdinaryPositiveNumber(scale) then return end

    local anchorInfo = systemInfo.anchorInfo
    local anchorInfo2 = systemInfo.anchorInfo2
    if not IsOrdinaryTable(anchorInfo)
        or not IsOrdinaryValue(anchorInfo2)
    then
        return
    end
    if anchorInfo2 ~= nil then
        if not IsOrdinaryTable(anchorInfo2)
            or rawequal(anchorInfo, anchorInfo2)
        then
            return
        end
    end

    local first = CaptureSystemAnchor(anchorInfo, scale)
    if not first then return end
    local points = {first}
    if anchorInfo2 ~= nil then
        local second = CaptureSystemAnchor(anchorInfo2, scale)
        if not second then return end
        points[2] = second
    end
    return {
        target = target,
        canAccessMethod = canAccessMethod,
        getScale = getScale,
        clearPoints = clearPoints,
        setPoint = setPoint,
        systemInfo = systemInfo,
        anchorInfo = anchorInfo,
        anchorInfo2 = anchorInfo2,
        scale = scale,
        points = points,
    }
end

local function RevalidateSystemAnchor(point, source, scale)
    if not IsOrdinaryTable(point) or not rawequal(point.source, source) then
        return false
    end
    local current = CaptureSystemAnchor(source, scale)
    return current ~= nil
        and current.point == point.point
        and current.relativeName == point.relativeName
        and rawequal(current.relativeObject, point.relativeObject)
        and rawequal(
            current.relativeAccessMethod,
            point.relativeAccessMethod
        )
        and current.relativePoint == point.relativePoint
        and current.offsetX == point.offsetX
        and current.offsetY == point.offsetY
        and current.x == point.x
        and current.y == point.y
end

local function HasExactSystemAnchorIdentity(original, current, source)
    if not IsOrdinaryTable(original)
        or not IsOrdinaryTable(current)
        or not IsOrdinaryTable(source)
    then
        return false
    end
    if not rawequal(original.source, source)
        or not rawequal(current.source, source)
    then
        return false
    end
    local point = source.point
    if not IsOrdinaryString(point) then return false end
    local relativeName = source.relativeTo
    if not IsOrdinaryString(relativeName) then return false end
    local relativePoint = source.relativePoint
    if not IsOrdinaryString(relativePoint) then return false end
    local offsetX = source.offsetX
    if not IsOrdinaryNumber(offsetX) then return false end
    local offsetY = source.offsetY
    if not IsOrdinaryNumber(offsetY) then return false end
    if ALLOWED_RESTORE_RELATIVE_GLOBALS[relativeName] ~= true
        or point ~= original.point
        or point ~= current.point
        or relativeName ~= original.relativeName
        or relativeName ~= current.relativeName
        or relativePoint ~= original.relativePoint
        or relativePoint ~= current.relativePoint
        or offsetX ~= original.offsetX
        or offsetX ~= current.offsetX
        or offsetY ~= original.offsetY
        or offsetY ~= current.offsetY
    then
        return false
    end
    local relativeObject = rawget(_G, relativeName)
    if not IsOrdinaryValue(relativeObject) then return false end
    local relativeType = type(relativeObject)
    if relativeType ~= "table" and relativeType ~= "userdata"
    then
        return false
    end
    local relativeAccessMethod = relativeObject.CanBeAccessedInContext
    if not IsOrdinaryFunction(relativeAccessMethod) then return false end
    return original.x == current.x
        and original.y == current.y
        and rawequal(relativeObject, original.relativeObject)
        and rawequal(relativeObject, current.relativeObject)
        and rawequal(
            relativeAccessMethod,
            original.relativeAccessMethod
        )
        and rawequal(
            relativeAccessMethod,
            current.relativeAccessMethod
        )
end

local function HasExactNativeFollowerIdentity(original, current)
    if not IsOrdinaryTable(original) or not IsOrdinaryTable(current) then
        return false
    end
    local target = rawget(_G, "DebuffFrame")
    if not IsOrdinaryValue(target) then return false end
    local targetType = type(target)
    if targetType ~= "table" and targetType ~= "userdata"
    then
        return false
    end
    local canAccessMethod = target.CanBeAccessedInContext
    if not IsOrdinaryFunction(canAccessMethod) then return false end
    local getScale = target.GetScale
    if not IsOrdinaryFunction(getScale) then return false end
    local clearPoints = target.ClearAllPointsBase
    if not IsOrdinaryFunction(clearPoints) then return false end
    local setPoint = target.SetPointBase
    if not IsOrdinaryFunction(setPoint) then return false end
    local systemInfo = target.systemInfo
    if not IsOrdinaryTable(systemInfo) then return false end
    local anchorInfo = systemInfo.anchorInfo
    if not IsOrdinaryTable(anchorInfo) then return false end
    local anchorInfo2 = systemInfo.anchorInfo2
    if not IsOrdinaryValue(anchorInfo2) then return false end
    if anchorInfo2 ~= nil and not IsOrdinaryTable(anchorInfo2) then
        return false
    end
    if not rawequal(target, original.target)
        or not rawequal(target, current.target)
        or not rawequal(canAccessMethod, original.canAccessMethod)
        or not rawequal(canAccessMethod, current.canAccessMethod)
        or not rawequal(getScale, original.getScale)
        or not rawequal(getScale, current.getScale)
        or not rawequal(clearPoints, original.clearPoints)
        or not rawequal(clearPoints, current.clearPoints)
        or not rawequal(setPoint, original.setPoint)
        or not rawequal(setPoint, current.setPoint)
        or not rawequal(systemInfo, original.systemInfo)
        or not rawequal(systemInfo, current.systemInfo)
        or not rawequal(anchorInfo, original.anchorInfo)
        or not rawequal(anchorInfo, current.anchorInfo)
        or not rawequal(anchorInfo2, original.anchorInfo2)
        or not rawequal(anchorInfo2, current.anchorInfo2)
        or original.scale ~= current.scale
    then
        return false
    end
    return HasExactSystemAnchorIdentity(
        original.points[1],
        current.points[1],
        original.anchorInfo
    ) and (
        original.anchorInfo2 == nil
        or HasExactSystemAnchorIdentity(
            original.points[2],
            current.points[2],
            original.anchorInfo2
        )
    )
end

local function RevalidateNativeFollowerSnapshot(snapshot)
    if not IsOrdinaryTable(snapshot) then return false end
    local current = CaptureNativeFollowerSnapshot()
    if not current
        or not rawequal(current.target, snapshot.target)
        or not rawequal(current.canAccessMethod, snapshot.canAccessMethod)
        or not rawequal(current.getScale, snapshot.getScale)
        or not rawequal(current.clearPoints, snapshot.clearPoints)
        or not rawequal(current.setPoint, snapshot.setPoint)
        or not rawequal(current.systemInfo, snapshot.systemInfo)
        or not rawequal(current.anchorInfo, snapshot.anchorInfo)
        or not rawequal(current.anchorInfo2, snapshot.anchorInfo2)
        or current.scale ~= snapshot.scale
        or not RevalidateSystemAnchor(
            snapshot.points[1],
            snapshot.anchorInfo,
            current.scale
        )
    then
        return false
    end
    if current.anchorInfo2 == nil then
        return current.points[2] == nil
            and snapshot.points[2] == nil
            and snapshot.points[3] == nil
            and HasExactNativeFollowerIdentity(snapshot, current)
    end
    return current.points[3] == nil
        and snapshot.points[3] == nil
        and RevalidateSystemAnchor(
            snapshot.points[2],
            snapshot.anchorInfo2,
            current.scale
        )
        and HasExactNativeFollowerIdentity(snapshot, current)
end

local function CaptureNativeFollowerEditModeState()
    local manager, canAccessMethod = ResolveAccessibleGlobal(
        "EditModeManagerFrame",
        {EditModeManagerFrame = true}
    )
    if not manager or not canAccessMethod then return end
    local active = manager.editModeActive
    if not IsOrdinaryValue(active)
        or (active ~= nil and active ~= false)
    then
        return
    end
    return {
        manager = manager,
        canAccessMethod = canAccessMethod,
        active = active,
    }
end

local function IsNativeFollowerEditModeInactive()
    return CaptureNativeFollowerEditModeState() ~= nil
end

local function ClearNativeFollowerState(controller)
    controller.nativeFollowerActive = nil
    controller.nativeFollowerTarget = nil
    controller.nativeFollowerRestoreSnapshot = nil
    controller.nativeFollowerSpec = nil
end

local function MarkNativeFollowerRefreshPending(controller)
    SetNativeFollowerRefreshPending(controller, true)
    if controller.active then
        controller.state = "ACTIVE_REFRESH_FAILED"
        controller.diagnostic = "NATIVE_FOLLOWER_REFRESH_FAILED"
    else
        controller.state = "NATIVE_UNAVAILABLE"
        controller.diagnostic = "NATIVE_FOLLOWER_UNAVAILABLE"
    end
end

local function IsExactNativeFollowerPayload(descriptor, follower)
    return IsOrdinaryTable(descriptor)
        and rawequal(descriptor.nativeFollower, follower)
        and IsOrdinaryTable(follower)
        and IsOrdinaryString(follower.globalName)
        and follower.globalName == "DebuffFrame"
        and IsOrdinaryString(follower.point)
        and follower.point == "TOPRIGHT"
        and IsOrdinaryString(follower.relativePoint)
        and follower.relativePoint == "BOTTOMRIGHT"
        and IsOrdinaryNumber(follower.x)
        and follower.x == 0
        and IsOrdinaryNumber(follower.y)
        and follower.y == -5
end

local function CaptureExactNativeFollowerPayload(descriptor, follower)
    if not IsExactNativeFollowerPayload(descriptor, follower) then return end
    return {
        globalName = follower.globalName,
        point = follower.point,
        relativePoint = follower.relativePoint,
        x = follower.x,
        y = follower.y,
    }
end

local function HasExactApplyTransactionIdentity(
    controller,
    descriptor,
    follower,
    payload,
    original,
    current,
    holder,
    holderAccessMethod,
    editMode
)
    local manager = rawget(_G, "EditModeManagerFrame")
    if not IsOrdinaryValue(manager) then return false end
    local managerType = type(manager)
    if managerType ~= "table" and managerType ~= "userdata"
    then
        return false
    end
    local managerAccessMethod = manager.CanBeAccessedInContext
    if not IsOrdinaryFunction(managerAccessMethod) then return false end
    local editModeActive = manager.editModeActive
    if not IsOrdinaryValue(editModeActive) then return false end

    if not IsOrdinaryValue(holder) then return false end
    local holderType = type(holder)
    if holderType ~= "table" and holderType ~= "userdata" then return false end
    if not rawequal(controller.holder, holder) then return false end
    local liveHolderAccessMethod = holder.CanBeAccessedInContext
    if not IsOrdinaryFunction(liveHolderAccessMethod) then return false end

    if not IsOrdinaryTable(descriptor) then return false end
    local liveFollower = descriptor.nativeFollower
    if not IsOrdinaryTable(liveFollower)
        or not rawequal(liveFollower, follower)
    then
        return false
    end
    local globalName = follower.globalName
    if not IsOrdinaryString(globalName) then return false end
    local point = follower.point
    if not IsOrdinaryString(point) then return false end
    local relativePoint = follower.relativePoint
    if not IsOrdinaryString(relativePoint) then return false end
    local x = follower.x
    if not IsOrdinaryNumber(x) then return false end
    local y = follower.y
    if not IsOrdinaryNumber(y) then return false end
    return rawequal(liveHolderAccessMethod, holderAccessMethod)
        and rawequal(manager, editMode.manager)
        and rawequal(managerAccessMethod, editMode.canAccessMethod)
        and editModeActive == editMode.active
        and globalName == payload.globalName
        and point == payload.point
        and relativePoint == payload.relativePoint
        and x == payload.x
        and y == payload.y
        and HasExactNativeFollowerIdentity(original, current)
end

local function RestoreNativeFollower(controller)
    if not controller.nativeFollowerActive then
        ClearNativeFollowerState(controller)
        return true
    end
    local snapshot = controller.nativeFollowerRestoreSnapshot
    if not RevalidateNativeFollowerSnapshot(snapshot) then return false end
    -- Revalidation above can call target/relative access methods. Capture the
    -- complete boundary once more, then finish with trusted secret-predicate
    -- and identity checks (no object methods/getters) before the final combat
    -- gate and first protected write.
    local current = CaptureNativeFollowerSnapshot()
    if not current
        or not HasExactNativeFollowerIdentity(snapshot, current)
    then
        return false
    end
    if not IsOutOfCombat() then return false end
    snapshot.clearPoints(snapshot.target)
    for index = 1, snapshot.points[2] == nil and 1 or 2 do
        local point = snapshot.points[index]
        snapshot.setPoint(
            snapshot.target,
            point.point,
            point.relativeObject,
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
    local payload = CaptureExactNativeFollowerPayload(descriptor, follower)
    if not payload
        or not nativeFollowerLifecycleRegistered
    then
        return false
    end

    if controller.nativeFollowerActive
        and TablesEqual(controller.nativeFollowerSpec, follower)
    then
        if not refreshRestore then return true end
    elseif controller.nativeFollowerActive then
        if not RestoreNativeFollower(controller) then return false end
    end
    local original = CaptureNativeFollowerSnapshot()
    if not original then return false end
    local holder = controller.holder
    local holderAccessMethod = CanAccessScriptObject(holder)
    if not holderAccessMethod then return false end
    local firstEditMode = CaptureNativeFollowerEditModeState()
    if not firstEditMode then return false end

    -- Second complete validation pass. These checks can call access/getter
    -- methods, so a final trusted secret-predicate/identity pass with no object
    -- methods or getters follows them.
    local current = CaptureNativeFollowerSnapshot()
    local currentHolderAccessMethod = CanAccessScriptObject(holder)
    local currentEditMode = CaptureNativeFollowerEditModeState()
    local currentPayload = CaptureExactNativeFollowerPayload(
        descriptor,
        follower
    )
    if not current
        or not currentHolderAccessMethod
        or not currentEditMode
        or not currentPayload
        or not rawequal(holderAccessMethod, currentHolderAccessMethod)
        or not rawequal(firstEditMode.manager, currentEditMode.manager)
        or not rawequal(
            firstEditMode.canAccessMethod,
            currentEditMode.canAccessMethod
        )
        or firstEditMode.active ~= currentEditMode.active
        or not HasExactApplyTransactionIdentity(
            controller,
            descriptor,
            follower,
            payload,
            original,
            current,
            holder,
            holderAccessMethod,
            currentEditMode
        )
    then
        return false
    end
    if not IsOutOfCombat() then return false end
    original.clearPoints(original.target)
    original.setPoint(
        original.target,
        payload.point,
        holder,
        payload.relativePoint,
        payload.x,
        payload.y
    )
    controller.nativeFollowerTarget = original.target
    controller.nativeFollowerRestoreSnapshot = original
    controller.nativeFollowerSpec = Copy(follower)
    controller.nativeFollowerActive = true
    return true
end

local function CaptureExactHolderAnchorPayload(descriptor)
    if not IsOrdinaryTable(descriptor) then return end
    local anchor = descriptor.holderAnchor
    if not IsOrdinaryTable(anchor) then return end
    local globalName = anchor.globalName
    local point = anchor.point
    local relativePoint = anchor.relativePoint
    local x = anchor.x
    local y = anchor.y
    if not IsOrdinaryString(globalName)
        or globalName ~= "DebuffFrame"
        or not IsOrdinaryString(point)
        or point ~= "TOPRIGHT"
        or not IsOrdinaryString(relativePoint)
        or relativePoint ~= "TOPRIGHT"
        or not IsOrdinaryNumber(x)
        or x ~= 0
        or not IsOrdinaryNumber(y)
        or y ~= 0
    then
        return
    end
    return {
        source = anchor,
        globalName = globalName,
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function CaptureHolderAnchorBoundary(controller, payload)
    if not IsOrdinaryTable(payload) then return end
    local target, targetAccessMethod = ResolveAccessibleGlobal(
        payload.globalName,
        ALLOWED_HOLDER_ANCHOR_GLOBALS
    )
    local holder = controller.holder
    local holderAccessMethod = CanAccessScriptObject(holder)
    if not target or not targetAccessMethod or not holderAccessMethod then
        return
    end
    local clearAllPoints = holder.ClearAllPoints
    local setPoint = holder.SetPoint
    if not IsOrdinaryFunction(clearAllPoints)
        or not IsOrdinaryFunction(setPoint)
    then
        return
    end
    return {
        target = target,
        targetAccessMethod = targetAccessMethod,
        holder = holder,
        holderAccessMethod = holderAccessMethod,
        clearAllPoints = clearAllPoints,
        setPoint = setPoint,
    }
end

local function HasExactHolderAnchorTransaction(
    controller,
    descriptor,
    payload,
    first,
    current
)
    if not IsOrdinaryTable(descriptor)
        or not IsOrdinaryTable(payload)
        or not IsOrdinaryTable(first)
        or not IsOrdinaryTable(current)
    then
        return false
    end
    local liveAnchor = descriptor.holderAnchor
    if not IsOrdinaryTable(liveAnchor)
        or not rawequal(liveAnchor, payload.source)
    then
        return false
    end
    local globalName = liveAnchor.globalName
    local point = liveAnchor.point
    local relativePoint = liveAnchor.relativePoint
    local x = liveAnchor.x
    local y = liveAnchor.y
    if not IsOrdinaryString(globalName)
        or not IsOrdinaryString(point)
        or not IsOrdinaryString(relativePoint)
        or not IsOrdinaryNumber(x)
        or not IsOrdinaryNumber(y)
        or globalName ~= payload.globalName
        or point ~= payload.point
        or relativePoint ~= payload.relativePoint
        or x ~= payload.x
        or y ~= payload.y
    then
        return false
    end

    local holder = controller.holder
    if not IsOrdinaryValue(holder) then return false end
    local holderType = type(holder)
    if holderType ~= "table" and holderType ~= "userdata" then return false end
    local holderAccessMethod = holder.CanBeAccessedInContext
    local clearAllPoints = holder.ClearAllPoints
    local setPoint = holder.SetPoint
    if not IsOrdinaryFunction(holderAccessMethod)
        or not IsOrdinaryFunction(clearAllPoints)
        or not IsOrdinaryFunction(setPoint)
    then
        return false
    end

    local target = rawget(_G, globalName)
    if not IsOrdinaryValue(target) then return false end
    local targetType = type(target)
    if targetType ~= "table" and targetType ~= "userdata" then return false end
    local targetAccessMethod = target.CanBeAccessedInContext
    if not IsOrdinaryFunction(targetAccessMethod) then return false end

    return rawequal(holder, first.holder)
        and rawequal(holder, current.holder)
        and rawequal(holderAccessMethod, first.holderAccessMethod)
        and rawequal(holderAccessMethod, current.holderAccessMethod)
        and rawequal(clearAllPoints, first.clearAllPoints)
        and rawequal(clearAllPoints, current.clearAllPoints)
        and rawequal(setPoint, first.setPoint)
        and rawequal(setPoint, current.setPoint)
        and rawequal(target, first.target)
        and rawequal(target, current.target)
        and rawequal(targetAccessMethod, first.targetAccessMethod)
        and rawequal(targetAccessMethod, current.targetAccessMethod)
end

local function ApplyHolder(controller, descriptor)
    local holder = controller.holder

    if descriptor.holderAnchor then
        if not nativeFollowerLifecycleRegistered
            or nativeFollowerEditModeActive
        then
            return false
        end
        local payload = CaptureExactHolderAnchorPayload(descriptor)
        local first = payload
            and CaptureHolderAnchorBoundary(controller, payload)
        local currentPayload = CaptureExactHolderAnchorPayload(descriptor)
        local current = currentPayload
            and CaptureHolderAnchorBoundary(controller, currentPayload)
        if not payload
            or not first
            or not currentPayload
            or not current
            or not rawequal(payload.source, currentPayload.source)
            or payload.globalName ~= currentPayload.globalName
            or payload.point ~= currentPayload.point
            or payload.relativePoint ~= currentPayload.relativePoint
            or payload.x ~= currentPayload.x
            or payload.y ~= currentPayload.y
            or not HasExactHolderAnchorTransaction(
                controller,
                descriptor,
                payload,
                first,
                current
            )
            or nativeFollowerEditModeActive
            or not IsOutOfCombat()
        then
            return false
        end
        first.clearAllPoints(holder)
        first.setPoint(
            holder,
            payload.point,
            first.target,
            payload.relativePoint,
            payload.x,
            payload.y
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

    AF.SetSize(holder, descriptor.holder.width, descriptor.holder.height)
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

local function UsesHarmfulSuppression(controller, descriptor)
    descriptor = descriptor or controller.descriptor
    return descriptor and descriptor.nativeSuppression == "harmful"
end

local function RestoreNative(controller, descriptor)
    if UsesHarmfulSuppression(controller, descriptor) then
        return type(BD.SetNativeHarmfulAurasSuppressed) == "function"
            and BD.SetNativeHarmfulAurasSuppressed(
                false,
                ResolvePlayerUnit()
            ) == true
    end
    return BD.SetNativePublicAurasSuppressed(controller.which, false) == true
end

local function SuppressNative(controller)
    if UsesHarmfulSuppression(controller) then
        return type(BD.SetNativeHarmfulAurasSuppressed) == "function"
            and BD.SetNativeHarmfulAurasSuppressed(true) == true
    end
    return BD.SetNativePublicAurasSuppressed(controller.which, true) == true
end

local function ReassertNative(controller)
    if UsesHarmfulSuppression(controller) then
        return type(BD.ReassertNativeHarmfulAuraSuppression) == "function"
            and BD.ReassertNativeHarmfulAuraSuppression() == true
    end
    return true
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

local function ShowCustom(controller)
    AF.SetCustomAuraContainerEnabled(controller.container, true)
    controller.container:Show()
    controller.holder.enabled = true
    controller.holder:Show()
    controller.active = true
end

local function Deactivate(controller, state)
    if not RestoreNativeFollower(controller) then
        return false
    end
    if not RestoreNative(controller) then
        return false
    end

    HideCustom(controller)
    SetNativeFollowerRefreshPending(controller, false)
    controller.editModeSuspended = nil
    controller.harmfulReassertPending = nil
    controller.state = state or (controller.buildCompleted and "INACTIVE" or "NEW")
    return true
end

local function Activate(controller)
    local container = controller.container
    if not ApplyNativeFollower(
        controller,
        controller.descriptor,
        controller.nativeFollowerRefreshPending == true
    ) then
        -- A temporarily unavailable follower (most notably while Blizzard
        -- Edit Mode owns DebuffFrame) must also release the public Buff
        -- fallback. Otherwise an update could hide the custom container while
        -- Blizzard Buffs remain suppressed, leaving no Buff display at all.
        if controller.active then
            MarkNativeFollowerRefreshPending(controller)
            return false
        end
        if RestoreNative(controller) then
            HideCustom(controller)
        else
            ShowCustom(controller)
        end
        MarkNativeFollowerRefreshPending(controller)
        return false
    end

    AF.SetCustomAuraContainerEnabled(container, true)

    -- Fail native: do not hide Blizzard until the replacement has completed
    -- its one-shot construction and final enable transition.
    if not SuppressNative(controller) then
        local wasActive = controller.active == true
        local nativeRestored = RestoreNative(controller)
        local followerRestored = RestoreNativeFollower(controller)
        if UsesHarmfulSuppression(controller) then
            SetNativeFollowerRefreshPending(controller, false)
            if nativeRestored then
                HideCustom(controller)
                controller.harmfulReassertPending = nil
                controller.state = "SUPPRESSION_FAILED"
                controller.diagnostic = "NATIVE_SUPPRESSION_FAILED"
            elseif wasActive then
                -- An existing replacement remains the truthful presentation
                -- owner until a later explicit restore or reassert succeeds.
                ShowCustom(controller)
                controller.harmfulReassertPending = true
                controller.state = "ACTIVE_REFRESH_FAILED"
                controller.diagnostic = "NATIVE_HARMFUL_REASSERT_FAILED"
                QueueController(controller)
            else
                -- Initial activation has not established ownership. The
                -- pre-build restore left Blizzard visible, so never expose an
                -- unsuppressed duplicate custom row.
                HideCustom(controller)
                controller.harmfulReassertPending = nil
                controller.state = "SUPPRESSION_FAILED"
                controller.diagnostic = "NATIVE_SUPPRESSION_FAILED"
            end
        elseif nativeRestored then
            HideCustom(controller)
            if followerRestored then
                controller.state = "SUPPRESSION_FAILED"
                controller.diagnostic = "NATIVE_SUPPRESSION_FAILED"
            else
                MarkNativeFollowerRefreshPending(controller)
            end
        else
            ShowCustom(controller)
            MarkNativeFollowerRefreshPending(controller)
        end
        return false
    end

    ShowCustom(controller)
    SetNativeFollowerRefreshPending(controller, false)
    controller.editModeSuspended = nil
    controller.harmfulReassertPending = nil
    controller.state = "ACTIVE"
    controller.diagnostic = nil
    return true
end

local function CreateHolder(controller, descriptor)
    if controller.holder then return true end

    local holder = controller.pendingHolder
    if not holder then
        holder = CreateFrame("Frame", nil, AF.UIParent)
        holder:Hide()
        -- SetRolesets is protected and its final combat gate can race. Retain
        -- this unpublished frame so every retry reuses the same allocation;
        -- mover/container publication remains after roleset success.
        controller.pendingHolder = holder
    end
    if descriptor.holderRolesets then
        if controller.holderRolesetsApplied ~= descriptor.holderRolesets then
            local holderAccessMethod = CanAccessScriptObject(holder)
            if not holderAccessMethod then return false end
            local setRolesets = holder.SetRolesets
            if not IsOrdinaryFunction(setRolesets) then return false end
            local currentHolderAccessMethod = CanAccessScriptObject(holder)
            local currentSetRolesets = holder.SetRolesets
            if not currentHolderAccessMethod
                or not IsOrdinaryFunction(currentSetRolesets)
                or not rawequal(
                    holderAccessMethod,
                    currentHolderAccessMethod
                )
                or not rawequal(currentSetRolesets, setRolesets)
                or not IsOutOfCombat()
            then return false end
            setRolesets(holder, descriptor.holderRolesets)
            controller.holderRolesetsApplied = descriptor.holderRolesets
        end
    elseif controller.holderRolesetsApplied ~= nil then
        return false
    end
    if not descriptor.holderAnchor then
        AF.SetSize(holder, descriptor.holder.width, descriptor.holder.height)
    end

    if descriptor.moverText and descriptor.position then
        AF.CreateMover(
            holder,
            "BFI: " .. L["UI Widgets"],
            descriptor.moverText,
            descriptor.positionSave or descriptor.position
        )
    end
    controller.holder = holder
    controller.pendingHolder = nil
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
    if not RestoreNative(controller, descriptor) then
        controller.state = "NATIVE_UNAVAILABLE"
        controller.diagnostic = "NATIVE_RESTORE_FAILED"
        return false
    end

    if not CreateHolder(controller, descriptor) then
        controller.state = "NATIVE_UNAVAILABLE"
        controller.diagnostic = "HOLDER_ROLESET_UNAVAILABLE"
        return false
    end
    if not ApplyHolder(controller, descriptor) then
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
    if self.active
        and UsesHarmfulSuppression(self)
        and not self.editModeSuspended
    then
        self.harmfulReassertPending = true
    end
    return true
end

function ControllerMixin:_ApplyPending()
    -- Retargeting is a supported live native write in combat and while Edit
    -- Mode owns the surrounding root. Apply the sanitized player/vehicle unit
    -- before protected holder/config work is deferred.
    if self.pendingUnit then
        self:_ApplyRetarget()
    end

    if (self.pendingOperation
        or self.harmfulReassertPending)
        and nativeFollowerEditModeActive
        and UsesHolderAnchor(self)
    then
        DeferControllerForEditMode(self)
        return
    end

    if self.harmfulReassertPending and not self.pendingOperation then
        if not IsOutOfCombat() or not ReassertNative(self) then
            self.state = "ACTIVE_REFRESH_FAILED"
            self.diagnostic = "NATIVE_HARMFUL_REASSERT_FAILED"
            QueueController(self)
            return
        end
        self.harmfulReassertPending = nil
        self.state = "ACTIVE"
        self.diagnostic = nil
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
        if not ApplyNativeTuning(self, descriptor) then
            if RestoreNative(self) then
                HideCustom(self)
            end
            self.state = "NATIVE_UNAVAILABLE"
            self.diagnostic = descriptor.holderAnchor
                and "HOLDER_ANCHOR_UNAVAILABLE"
                or "NATIVE_FOLLOWER_UNAVAILABLE"
        elseif not Activate(self) then
            if descriptor.nativeFollower
                and not self.nativeFollowerRefreshPending
            then
                MarkNativeFollowerRefreshPending(self)
            end
        end
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
    return self.active ~= true
        and pendingControllers[self] ~= true
        and self.pendingOperation == nil
end

function ControllerMixin:GetState()
    return {
        which = self.which,
        state = self.state,
        active = self.active == true,
        operationPending = pendingControllers[self] == true,
        pending = pendingControllers[self] == true
            or (
                self.nativeFollowerRefreshPending == true
                and self.active == true
                and self.descriptor ~= nil
                and self.descriptor.nativeFollower ~= nil
            ),
        buildAttempted = self.buildAttempted == true,
        buildCompleted = self.buildCompleted == true,
        nativeFollowerActive = self.nativeFollowerActive == true,
        editModeSuspended = self.editModeSuspended == true,
        harmfulReassertPending = self.harmfulReassertPending == true,
        reloadRequired = self.reloadRequired == true,
        diagnostic = self.diagnostic,
        unit = self.unit,
        expectedInitialReservations =
            self.expectedInitialReservations or 0,
    }
end

local function RefreshNativeAuraFollowers()
    nativeFollowerRefreshQueued = nil
    if not IsOutOfCombat() then
        for _, controller in pairs(registrations) do
            local descriptor = controller.descriptor
            if controller.active
                and descriptor
                and descriptor.nativeFollower
            then
                SetNativeFollowerRefreshPending(controller, true)
            end
            NotifyControllerState(controller)
        end
        return
    end
    if nativeFollowerEditModeActive then return end
    for _, controller in pairs(registrations) do
        local descriptor = controller.descriptor
        if not controller.pendingOperation
            and controller.active
            and descriptor
            and descriptor.nativeFollower
        then
            if ApplyNativeFollower(controller, descriptor, true) then
                SetNativeFollowerRefreshPending(controller, false)
                controller.state = "ACTIVE"
                controller.diagnostic = nil
            else
                MarkNativeFollowerRefreshPending(controller)
            end
            NotifyControllerState(controller)
        elseif not controller.pendingOperation
            and controller.buildCompleted
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

    -- Edit Mode exit first restores #127's native DebuffFrame follower above,
    -- then drains any holder-anchored Debuffs request, then resumes a row that
    -- was explicitly restored/suspended on Edit Mode entry.
    local deferredHolderControllers = {}
    for controller in pairs(pendingControllers) do
        if UsesHolderAnchor(controller) then
            deferredHolderControllers[#deferredHolderControllers + 1] =
                controller
        end
    end
    for _, controller in ipairs(deferredHolderControllers) do
        controller:_ApplyPending()
    end

    for _, controller in pairs(registrations) do
        local descriptor = controller.descriptor
        if controller.editModeSuspended
            and not controller.active
            and not controller.pendingOperation
            and controller.buildCompleted
            and descriptor
            and descriptor.enabled
            and descriptor.holderAnchor
        then
            if ApplyNativeTuning(controller, descriptor)
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

end

local function QueueNativeAuraFollowerRefresh()
    if nativeFollowerRefreshQueued then return end
    nativeFollowerRefreshQueued = true
    C_Timer.After(0, RefreshNativeAuraFollowers)
end

local function OnNativeAuraFollowerInvalidation()
    for _, controller in pairs(registrations) do
        if controller.active and UsesHarmfulSuppression(controller) then
            controller.harmfulReassertPending = true
            QueueController(controller)
        end
    end
    QueueNativeAuraFollowerRefresh()
end

local function OnNativeAuraFollowerRegen()
    -- Regen drains work that an earlier event explicitly queued; it never
    -- invents a six-anchor reassert on its own.
    for _, controller in pairs(registrations) do
        if controller.nativeFollowerRefreshPending then
            QueueNativeAuraFollowerRefresh()
            return
        end
    end
end

local function OnEditModeEnter()
    nativeFollowerEditModeActive = true
    -- First yield the Blizzard root that #127 follows back to Edit Mode.
    for _, controller in pairs(registrations) do
        if controller.nativeFollowerActive then
            if not RestoreNativeFollower(controller) then
                MarkNativeFollowerRefreshPending(controller)
            end
            NotifyControllerState(controller)
        end
    end
    -- Then restore the complete Blizzard harmful presentation before hiding
    -- the custom row. If restore fails, keep the replacement visible.
    for _, controller in pairs(registrations) do
        local descriptor = controller.descriptor
        if controller.active
            and descriptor
            and descriptor.holderAnchor
        then
            if Deactivate(controller, "EDIT_MODE_SUSPENDED") then
                controller.editModeSuspended = true
                controller.diagnostic = nil
            else
                if UsesHarmfulSuppression(controller) then
                    controller.harmfulReassertPending = true
                    DeferControllerForEditMode(controller)
                end
                controller.diagnostic = "EDIT_MODE_SUSPEND_FAILED"
            end
            NotifyControllerState(controller)
        end
    end
end

local function OnEditModeExit()
    nativeFollowerEditModeActive = false
    QueueNativeAuraFollowerRefresh()
end

local function RegisterNativeFollowerLifecycle()
    if nativeFollowerLifecycleRegistered then return true end

    local eventRegistry = rawget(_G, "EventRegistry")
    if not IsOrdinaryTable(eventRegistry) then return false end
    local registerCallback = eventRegistry.RegisterCallback
    if not IsOrdinaryFunction(registerCallback) then return false end

    -- Blizzard leaves editModeActive nil until the first Enter; exact ordinary
    -- nil/false are inactive, while true, another value, or secrecy fail closed.
    nativeFollowerEditModeActive = not IsNativeFollowerEditModeInactive()

    registerCallback(
        eventRegistry,
        "EditMode.Enter",
        OnEditModeEnter,
        BD
    )
    registerCallback(
        eventRegistry,
        "EditMode.Exit",
        OnEditModeExit,
        BD
    )
    BD:RegisterEvent(
        "EDIT_MODE_LAYOUTS_UPDATED",
        OnNativeAuraFollowerInvalidation
    )
    BD:RegisterEvent("PLAYER_ENTERING_WORLD", OnNativeAuraFollowerInvalidation)
    BD:RegisterEvent("PLAYER_REGEN_ENABLED", OnNativeAuraFollowerRegen)
    BD:RegisterEvent(
        "PLAYER_SPECIALIZATION_CHANGED",
        OnNativeAuraFollowerInvalidation
    )
    BD:RegisterEvent(
        "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
        OnNativeAuraFollowerInvalidation
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
        and BD.HasCustomAuraContainerCapability() == true
        and (
            which ~= "debuffs"
            and BD.CanSuppressNativePublicAuras(which) == true
            or which == "debuffs"
            and type(BD.CanSuppressNativeHarmfulAuras) == "function"
            and BD.CanSuppressNativeHarmfulAuras() == true
        )
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

    return controller:Disable() == true
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

function BD.RefreshCustomAuraContainerUnits(event)
    local unit = ResolvePlayerUnit()
    for _, controller in pairs(registrations) do
        if controller.buildCompleted and controller.unit ~= unit then
            controller.pendingUnit = unit
            if event == "PLAYER_ENTERING_WORLD" then
                -- PEW also has a separate native-layout invalidation callback,
                -- and callback-table order is intentionally unspecified. Keep
                -- the sanitized custom-container retarget immediate, but drain
                -- its private-anchor reassert through the shared next-tick
                -- refresh so either callback order produces one setter batch.
                controller:_ApplyRetarget()
                if controller.harmfulReassertPending then
                    DeferControllerForEditMode(controller)
                    QueueNativeAuraFollowerRefresh()
                else
                    controller:_ApplyPending()
                end
            else
                controller:_ApplyPending()
            end
        end
    end
end
