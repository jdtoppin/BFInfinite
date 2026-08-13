---@type BFI
local BFI = select(2, ...)
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs
local IsValueNonSecret = BFI.funcs.isValueNonSecret

local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local hasRestrictedAuraButtons = _G.C_AuraContainerUtil ~= nil

local suppressedStates = {}
local suppressedRoots = {}
local hookedRoots = {}
local harmfulSuppressedState
local harmfulRecoveryState

local function HasExpectedParent(object, expected)
    if not object or type(object.GetParent) ~= "function" then return false end
    local parent = object:GetParent()
    return IsValueNonSecret(parent) and parent == expected
end

local function IsAuraContainer(frame)
    return frame
        and type(frame.SetShown) == "function"
        and type(frame.GetParent) == "function"
end

local function IsVisualControl(frame)
    return frame
        and type(frame.SetAlpha) == "function"
        and type(frame.EnableMouse) == "function"
        and type(frame.GetParent) == "function"
end

local function HasRootPrivateAuraAnchors(frame)
    local anchors = frame.PrivateAuraAnchors
    if type(anchors) ~= "table" or #anchors == 0 then return false end

    for _, anchor in ipairs(anchors) do
        if not HasExpectedParent(anchor, frame) then
            return false
        end
    end
    return true
end

local function ResolveNativePublicAuraFrame(which)
    if type(hooksecurefunc) ~= "function" then return end

    if which == "buffs" then
        local frame = _G.BuffFrame
        local container = frame and frame.AuraContainer
        local collapseButton = frame and frame.CollapseAndExpandButton
        local consolidatedBuffs = frame and frame.ConsolidatedBuffs
        local consolidatedTooltip = consolidatedBuffs and consolidatedBuffs.Tooltip
        local consolidatedAuras = consolidatedTooltip and consolidatedTooltip.Auras

        if not frame
            or type(frame.UpdateAuraButtons) ~= "function"
            or type(frame.auraFrames) ~= "table"
            or not IsAuraContainer(container)
            or not HasExpectedParent(container, frame)
            or not IsVisualControl(collapseButton)
            or not HasExpectedParent(collapseButton, frame)
            or not IsVisualControl(consolidatedBuffs)
            or not HasExpectedParent(consolidatedBuffs, frame)
            or not consolidatedTooltip
            or type(consolidatedTooltip.Hide) ~= "function"
            or type(consolidatedTooltip.GetParent) ~= "function"
            or not HasExpectedParent(consolidatedTooltip, consolidatedBuffs)
            or not consolidatedAuras
            or type(consolidatedAuras.auraFrames) ~= "table"
            or type(consolidatedAuras.GetParent) ~= "function"
            or not IsAuraContainer(consolidatedAuras.AuraContainer)
            or not HasExpectedParent(consolidatedAuras, consolidatedTooltip)
            or not HasExpectedParent(
                consolidatedAuras.AuraContainer,
                consolidatedAuras
            )
        then
            return
        end

        return {
            frame = frame,
            container = container,
            controls = {collapseButton, consolidatedBuffs},
            consolidatedTooltip = consolidatedTooltip,
            consolidatedAuras = consolidatedAuras,
        }
    elseif which == "debuffs" then
        local frame = _G.DebuffFrame
        local container = frame and frame.AuraContainer
        if not frame
            or type(frame.UpdateAuraButtons) ~= "function"
            or type(frame.auraFrames) ~= "table"
            or not IsAuraContainer(container)
            or not HasExpectedParent(container, frame)
            or not HasRootPrivateAuraAnchors(frame)
        then
            return
        end

        return {
            frame = frame,
            container = container,
            controls = {},
        }
    end
end

local function HidePublicAuraOverlays(frame, publicParent)
    -- Retail 12.1.0.69273 AuraButtons can deny addon access while aura data is
    -- secret. C_AuraContainerUtil identifies that native path: never enumerate
    -- intrinsic children or install the update hook that would revisit them.
    -- BlizzardDebuffs.lua separately validates only the pinned, fixed ordinary
    -- DebuffFrame pool; it does not weaken this generic restricted-child rule.
    if hasRestrictedAuraButtons then return end

    local auraFrames = frame.auraFrames
    if type(auraFrames) ~= "table" then return end

    local gameTooltip = _G.GameTooltip
    local helpTip = _G.HelpTip
    for _, button in ipairs(auraFrames) do
        if HasExpectedParent(button, publicParent) then
            if gameTooltip and gameTooltip:IsOwned(button) then
                gameTooltip:Hide()
            end
            if helpTip and type(helpTip.HideAll) == "function" then
                helpTip:HideAll(button)
            end
        end
    end
end

local function HideTargetOverlays(target)
    HidePublicAuraOverlays(target.frame, target.container)
    if target.consolidatedAuras then
        HidePublicAuraOverlays(target.consolidatedAuras, target.consolidatedAuras.AuraContainer)
        target.consolidatedTooltip:Hide()
    end
end

local function InstallOverlayCleanupHook(target)
    if hasRestrictedAuraButtons then return end

    local frame = target.frame
    if hookedRoots[frame] then return end

    hooksecurefunc(frame, "UpdateAuraButtons", function(updatedFrame)
        local state = suppressedRoots[updatedFrame]
        if state then
            HideTargetOverlays(state.target)
        end
    end)
    hookedRoots[frame] = true
end

function BD.CanSuppressNativePublicAuras(which)
    return ResolveNativePublicAuraFrame(which) ~= nil
end

function BD.AreNativePublicAurasSuppressed(which)
    return suppressedStates[which] ~= nil
end

function BD.SetNativePublicAurasSuppressed(which, suppressed)
    if which ~= "buffs" and which ~= "debuffs" then return false end
    suppressed = suppressed == true
    if which == "debuffs"
        and suppressed
        and (harmfulSuppressedState or harmfulRecoveryState)
    then
        return false
    end
    local state = suppressedStates[which]
    if (state ~= nil) == suppressed then return true end
    if InCombatLockdown() then return false end

    if state then
        HideTargetOverlays(state.target)
        state.target.container:SetShown(true)
        for _, control in ipairs(state.target.controls) do
            control:SetAlpha(1)
            control:EnableMouse(true)
        end

        suppressedStates[which] = nil
        suppressedRoots[state.target.frame] = nil
        return true
    end

    local target = ResolveNativePublicAuraFrame(which)
    if not target then return false end

    -- Retail 12.1.0.69273 (wow-ui-source
    -- eb941aad028d73ddc69e3e8ef4da709f4d3cd744) creates the supported public
    -- AuraContainerTemplate shown, with these ordinary controls at alpha 1 and
    -- mouse enabled. Keep only a BFI-owned suppression ledger and restore those
    -- known constants; observing visibility, alpha, or mouse state can return
    -- secret values. Private anchors are direct root children and
    -- DeadlyDebuffFrame is separate; neither is touched here.
    state = {target = target}

    InstallOverlayCleanupHook(target)
    HideTargetOverlays(target)
    target.container:SetShown(false)
    for _, control in ipairs(target.controls) do
        control:SetAlpha(0)
        control:EnableMouse(false)
    end

    suppressedStates[which] = state
    suppressedRoots[target.frame] = state
    return true
end

local EXPECTED_PRIVATE_ANCHOR_COUNT = 6

local function IsOrdinaryValue(value)
    return type(IsValueNonSecret) == "function"
        and IsValueNonSecret(value) == true
end

local function IsOrdinaryFunction(value)
    return IsOrdinaryValue(value) and type(value) == "function"
end

local function IsOrdinaryTable(value)
    return IsOrdinaryValue(value) and type(value) == "table"
end

local function IsOrdinaryNumber(value)
    return IsOrdinaryValue(value)
        and type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function AddDistinctObject(seen, object)
    if not IsOrdinaryTable(seen) or not IsOrdinaryValue(object) then
        return false
    end
    if seen[object] then return false end
    seen[object] = true
    return true
end

local function IsOutOfCombat()
    local locked = InCombatLockdown()
    return IsOrdinaryValue(locked)
        and type(locked) == "boolean"
        and locked == false
end

local function CanAccessScriptObject(object)
    if not IsOrdinaryValue(object) then return end
    local objectType = type(object)
    if objectType ~= "table" and objectType ~= "userdata" then return end

    local canAccessMethod = object.CanBeAccessedInContext
    if not IsOrdinaryFunction(canAccessMethod) then return end
    local canAccess = canAccessMethod(object)
    if not IsOrdinaryValue(canAccess)
        or type(canAccess) ~= "boolean"
        or canAccess ~= true
    then
        return
    end
    return canAccessMethod
end

local function CaptureExactArray(array, count)
    if not IsOrdinaryTable(array) then return end
    local captured = {}
    for key in next, array do
        if not IsOrdinaryValue(key)
            or type(key) ~= "number"
            or key ~= math.floor(key)
            or key < 1
            or key > count
        then
            return
        end
    end
    for index = 1, count do
        local value = rawget(array, index)
        if not IsOrdinaryValue(value) or value == nil then
            return
        end
        captured[index] = value
    end
    return captured
end

local function CaptureNativeHarmfulAuraFrame()
    local frame = _G.DebuffFrame
    local debuffMixin = _G.DebuffFrameMixin
    local anchorMixin = _G.BuffFramePrivateAuraAnchorMixin
    local unitAuras = _G.C_UnitAuras
    local frameAccessMethod = CanAccessScriptObject(frame)
    if not frameAccessMethod
        or not IsOrdinaryTable(debuffMixin)
        or not IsOrdinaryTable(anchorMixin)
        or not IsOrdinaryTable(unitAuras)
    then
        return
    end

    local updatePrivateAuraAnchors = frame.UpdatePrivateAuraAnchors
    local maxPrivateAuras = frame.maxPrivateAuras
    local expectedUpdatePrivateAuraAnchors =
        rawget(debuffMixin, "UpdatePrivateAuraAnchors")
    local expectedSetUnit = rawget(anchorMixin, "SetUnit")
    local addPrivateAuraAnchor = rawget(unitAuras, "AddPrivateAuraAnchor")
    local removePrivateAuraAnchor = rawget(unitAuras, "RemovePrivateAuraAnchor")
    local container = frame.AuraContainer
    local anchors = frame.PrivateAuraAnchors
    local containerAccessMethod = CanAccessScriptObject(container)
    if not containerAccessMethod then return end
    local setShown = container.SetShown
    local getContainerParent = container.GetParent
    local showDispelType = container.showDispelType
    local anchorObjects = CaptureExactArray(
        anchors,
        EXPECTED_PRIVATE_ANCHOR_COUNT
    )
    if not IsOrdinaryFunction(updatePrivateAuraAnchors)
        or not IsOrdinaryNumber(maxPrivateAuras)
        or maxPrivateAuras ~= EXPECTED_PRIVATE_ANCHOR_COUNT
        or not IsOrdinaryFunction(expectedUpdatePrivateAuraAnchors)
        or not rawequal(
            updatePrivateAuraAnchors,
            expectedUpdatePrivateAuraAnchors
        )
        or not IsOrdinaryFunction(expectedSetUnit)
        or not IsOrdinaryFunction(addPrivateAuraAnchor)
        or not IsOrdinaryFunction(removePrivateAuraAnchor)
        or not IsOrdinaryFunction(setShown)
        or not IsOrdinaryFunction(getContainerParent)
        or not IsOrdinaryValue(showDispelType)
        or type(showDispelType) ~= "boolean"
        or not anchorObjects
    then
        return
    end

    local containerParent = getContainerParent(container)
    if not IsOrdinaryValue(containerParent)
        or not rawequal(containerParent, frame)
    then
        return
    end

    local snapshot = {
        frame = frame,
        frameAccessMethod = frameAccessMethod,
        debuffMixin = debuffMixin,
        anchorMixin = anchorMixin,
        unitAuras = unitAuras,
        addPrivateAuraAnchor = addPrivateAuraAnchor,
        removePrivateAuraAnchor = removePrivateAuraAnchor,
        updatePrivateAuraAnchors = updatePrivateAuraAnchors,
        maxPrivateAuras = maxPrivateAuras,
        expectedSetUnit = expectedSetUnit,
        container = container,
        containerAccessMethod = containerAccessMethod,
        containerGetParent = getContainerParent,
        containerSetShown = setShown,
        showDispelType = showDispelType,
        anchors = anchors,
        anchorObjects = anchorObjects,
        anchorAccessMethods = {},
        anchorGetParents = {},
        anchorSetUnits = {},
        anchorAuraIndexes = {},
        anchorIsAuraAnchors = {},
        anchorIcons = {},
        anchorIconAccessMethods = {},
        anchorIconGetParents = {},
        anchorIconGetWidths = {},
        anchorIconWidths = {},
        anchorIconGetHeights = {},
        anchorIconHeights = {},
        anchorDurations = {},
        anchorDurationAccessMethods = {},
        anchorDurationGetParents = {},
        anchorDurationGetWidths = {},
        anchorDurationWidths = {},
        anchorDurationGetHeights = {},
        anchorDurationHeights = {},
    }

    local seenObjects = {}
    if not AddDistinctObject(seenObjects, frame)
        or not AddDistinctObject(seenObjects, container)
    then
        return
    end

    for index = 1, EXPECTED_PRIVATE_ANCHOR_COUNT do
        local anchor = anchorObjects[index]
        local parentKey = frame["privateAuraAnchor" .. index]
        local accessMethod = CanAccessScriptObject(anchor)
        if not accessMethod then return end
        local getParent = anchor.GetParent
        local setUnit = anchor.SetUnit
        local auraIndex = anchor.auraIndex
        local isAuraAnchor = anchor.isAuraAnchor
        local icon = anchor.Icon
        local duration = anchor.Duration
        if not AddDistinctObject(seenObjects, anchor)
            or not AddDistinctObject(seenObjects, icon)
            or not AddDistinctObject(seenObjects, duration)
        then
            return
        end
        local iconAccessMethod = CanAccessScriptObject(icon)
        local durationAccessMethod = CanAccessScriptObject(duration)
        if not iconAccessMethod or not durationAccessMethod then return end
        local iconGetParent = icon.GetParent
        local durationGetParent = duration.GetParent
        local durationGetWidth = duration.GetWidth
        local durationGetHeight = duration.GetHeight
        local iconGetWidth = icon.GetWidth
        local iconGetHeight = icon.GetHeight
        if not IsOrdinaryValue(parentKey)
            or not rawequal(parentKey, anchor)
            or not IsOrdinaryFunction(getParent)
            or not IsOrdinaryFunction(setUnit)
            or not rawequal(setUnit, expectedSetUnit)
            or not IsOrdinaryNumber(auraIndex)
            or auraIndex ~= index
            or not IsOrdinaryValue(isAuraAnchor)
            or type(isAuraAnchor) ~= "boolean"
            or isAuraAnchor ~= true
            or not iconAccessMethod
            or not durationAccessMethod
            or not IsOrdinaryFunction(iconGetParent)
            or not IsOrdinaryFunction(durationGetParent)
            or not IsOrdinaryFunction(durationGetWidth)
            or not IsOrdinaryFunction(durationGetHeight)
            or not IsOrdinaryFunction(iconGetWidth)
            or not IsOrdinaryFunction(iconGetHeight)
        then
            return
        end
        local parent = getParent(anchor)
        if not IsOrdinaryValue(parent) or not rawequal(parent, frame) then
            return
        end
        local iconParent = iconGetParent(icon)
        local durationParent = durationGetParent(duration)
        local iconWidth = iconGetWidth(icon)
        local iconHeight = iconGetHeight(icon)
        local durationWidth = durationGetWidth(duration)
        local durationHeight = durationGetHeight(duration)
        if not IsOrdinaryValue(iconParent)
            or not rawequal(iconParent, anchor)
            or not IsOrdinaryValue(durationParent)
            or not rawequal(durationParent, anchor)
            or not IsOrdinaryNumber(iconWidth)
            or iconWidth <= 0
            or not IsOrdinaryNumber(iconHeight)
            or iconHeight <= 0
            or not IsOrdinaryNumber(durationWidth)
            or durationWidth <= 0
            or not IsOrdinaryNumber(durationHeight)
            or durationHeight <= 0
        then
            return
        end
        snapshot.anchorObjects[index] = anchor
        snapshot.anchorAccessMethods[index] = accessMethod
        snapshot.anchorGetParents[index] = getParent
        snapshot.anchorSetUnits[index] = setUnit
        snapshot.anchorAuraIndexes[index] = auraIndex
        snapshot.anchorIsAuraAnchors[index] = isAuraAnchor
        snapshot.anchorIcons[index] = icon
        snapshot.anchorIconAccessMethods[index] = iconAccessMethod
        snapshot.anchorIconGetParents[index] = iconGetParent
        snapshot.anchorIconGetWidths[index] = iconGetWidth
        snapshot.anchorIconWidths[index] = iconWidth
        snapshot.anchorIconGetHeights[index] = iconGetHeight
        snapshot.anchorIconHeights[index] = iconHeight
        snapshot.anchorDurations[index] = duration
        snapshot.anchorDurationAccessMethods[index] = durationAccessMethod
        snapshot.anchorDurationGetParents[index] = durationGetParent
        snapshot.anchorDurationGetWidths[index] = durationGetWidth
        snapshot.anchorDurationWidths[index] = durationWidth
        snapshot.anchorDurationGetHeights[index] = durationGetHeight
        snapshot.anchorDurationHeights[index] = durationHeight
    end
    return snapshot
end

local function HasExactHarmfulSnapshotIdentity(
    original,
    current,
    includeMutablePresentation
)
    if not IsOrdinaryTable(original) or not IsOrdinaryTable(current) then
        return false
    end
    if not rawequal(original.frame, current.frame)
        or not rawequal(original.frameAccessMethod, current.frameAccessMethod)
        or not rawequal(original.debuffMixin, current.debuffMixin)
        or not rawequal(original.anchorMixin, current.anchorMixin)
        or not rawequal(original.unitAuras, current.unitAuras)
        or not rawequal(
            original.addPrivateAuraAnchor,
            current.addPrivateAuraAnchor
        )
        or not rawequal(
            original.removePrivateAuraAnchor,
            current.removePrivateAuraAnchor
        )
        or not rawequal(
            original.updatePrivateAuraAnchors,
            current.updatePrivateAuraAnchors
        )
        or original.maxPrivateAuras ~= current.maxPrivateAuras
        or not rawequal(original.expectedSetUnit, current.expectedSetUnit)
        or not rawequal(original.container, current.container)
        or not rawequal(
            original.containerAccessMethod,
            current.containerAccessMethod
        )
        or not rawequal(
            original.containerGetParent,
            current.containerGetParent
        )
        or not rawequal(
            original.containerSetShown,
            current.containerSetShown
        )
        or not rawequal(original.anchors, current.anchors)
    then
        return false
    end
    for index = 1, EXPECTED_PRIVATE_ANCHOR_COUNT do
        if not rawequal(
            original.anchorObjects[index],
            current.anchorObjects[index]
        ) or not rawequal(
            original.anchorAccessMethods[index],
            current.anchorAccessMethods[index]
        ) or not rawequal(
            original.anchorGetParents[index],
            current.anchorGetParents[index]
        ) or not rawequal(
            original.anchorSetUnits[index],
            current.anchorSetUnits[index]
        ) or original.anchorAuraIndexes[index]
            ~= current.anchorAuraIndexes[index]
        or original.anchorIsAuraAnchors[index]
            ~= current.anchorIsAuraAnchors[index]
        or not rawequal(
            original.anchorIcons[index],
            current.anchorIcons[index]
        ) or not rawequal(
            original.anchorIconAccessMethods[index],
            current.anchorIconAccessMethods[index]
        ) or not rawequal(
            original.anchorIconGetParents[index],
            current.anchorIconGetParents[index]
        ) or not rawequal(
            original.anchorIconGetWidths[index],
            current.anchorIconGetWidths[index]
        )
        or not rawequal(
            original.anchorIconGetHeights[index],
            current.anchorIconGetHeights[index]
        )
        or not rawequal(
            original.anchorDurations[index],
            current.anchorDurations[index]
        ) or not rawequal(
            original.anchorDurationAccessMethods[index],
            current.anchorDurationAccessMethods[index]
        ) or not rawequal(
            original.anchorDurationGetParents[index],
            current.anchorDurationGetParents[index]
        ) or not rawequal(
            original.anchorDurationGetWidths[index],
            current.anchorDurationGetWidths[index]
        )
        or not rawequal(
            original.anchorDurationGetHeights[index],
            current.anchorDurationGetHeights[index]
        )
        then
            return false
        end
        if includeMutablePresentation
            and (
                original.anchorIconWidths[index]
                    ~= current.anchorIconWidths[index]
                or original.anchorIconHeights[index]
                    ~= current.anchorIconHeights[index]
                or original.anchorDurationWidths[index]
                    ~= current.anchorDurationWidths[index]
                or original.anchorDurationHeights[index]
                    ~= current.anchorDurationHeights[index]
            )
        then
            return false
        end
    end
    return not includeMutablePresentation
        or original.showDispelType == current.showDispelType
end

local function HasExactOrdinaryArray(array)
    if not IsOrdinaryTable(array) then return false end
    for key in next, array do
        if not IsOrdinaryValue(key)
            or type(key) ~= "number"
            or key ~= math.floor(key)
            or key < 1
            or key > EXPECTED_PRIVATE_ANCHOR_COUNT
        then
            return false
        end
    end
    for index = 1, EXPECTED_PRIVATE_ANCHOR_COUNT do
        local value = rawget(array, index)
        if value == nil or not IsOrdinaryValue(value) then return false end
    end
    return true
end

local function HarmfulSnapshotRemainsOrdinary(snapshot)
    if not IsOrdinaryTable(snapshot)
        or not IsOrdinaryValue(snapshot.frame)
        or not IsOrdinaryFunction(snapshot.frameAccessMethod)
        or not IsOrdinaryTable(snapshot.debuffMixin)
        or not IsOrdinaryTable(snapshot.anchorMixin)
        or not IsOrdinaryTable(snapshot.unitAuras)
        or not IsOrdinaryFunction(snapshot.updatePrivateAuraAnchors)
        or not IsOrdinaryFunction(snapshot.expectedSetUnit)
        or not IsOrdinaryFunction(snapshot.addPrivateAuraAnchor)
        or not IsOrdinaryFunction(snapshot.removePrivateAuraAnchor)
        or not IsOrdinaryNumber(snapshot.maxPrivateAuras)
        or snapshot.maxPrivateAuras ~= EXPECTED_PRIVATE_ANCHOR_COUNT
        or not IsOrdinaryValue(snapshot.container)
        or not IsOrdinaryFunction(snapshot.containerAccessMethod)
        or not IsOrdinaryFunction(snapshot.containerGetParent)
        or not IsOrdinaryFunction(snapshot.containerSetShown)
        or not IsOrdinaryValue(snapshot.showDispelType)
        or type(snapshot.showDispelType) ~= "boolean"
        or not HasExactOrdinaryArray(snapshot.anchors)
        or not HasExactOrdinaryArray(snapshot.anchorObjects)
        or not HasExactOrdinaryArray(snapshot.anchorAccessMethods)
        or not HasExactOrdinaryArray(snapshot.anchorGetParents)
        or not HasExactOrdinaryArray(snapshot.anchorSetUnits)
        or not HasExactOrdinaryArray(snapshot.anchorAuraIndexes)
        or not HasExactOrdinaryArray(snapshot.anchorIsAuraAnchors)
        or not HasExactOrdinaryArray(snapshot.anchorIcons)
        or not HasExactOrdinaryArray(snapshot.anchorIconAccessMethods)
        or not HasExactOrdinaryArray(snapshot.anchorIconGetParents)
        or not HasExactOrdinaryArray(snapshot.anchorIconGetWidths)
        or not HasExactOrdinaryArray(snapshot.anchorIconWidths)
        or not HasExactOrdinaryArray(snapshot.anchorIconGetHeights)
        or not HasExactOrdinaryArray(snapshot.anchorIconHeights)
        or not HasExactOrdinaryArray(snapshot.anchorDurations)
        or not HasExactOrdinaryArray(
            snapshot.anchorDurationAccessMethods
        )
        or not HasExactOrdinaryArray(snapshot.anchorDurationGetParents)
        or not HasExactOrdinaryArray(snapshot.anchorDurationGetWidths)
        or not HasExactOrdinaryArray(snapshot.anchorDurationWidths)
        or not HasExactOrdinaryArray(snapshot.anchorDurationGetHeights)
        or not HasExactOrdinaryArray(snapshot.anchorDurationHeights)
    then
        return false
    end

    for index = 1, EXPECTED_PRIVATE_ANCHOR_COUNT do
        local arrayAnchor = rawget(snapshot.anchors, index)
        local anchor = rawget(snapshot.anchorObjects, index)
        local anchorAccessMethod = rawget(
            snapshot.anchorAccessMethods,
            index
        )
        local anchorGetParent = rawget(snapshot.anchorGetParents, index)
        local anchorSetUnit = rawget(snapshot.anchorSetUnits, index)
        local auraIndex = rawget(snapshot.anchorAuraIndexes, index)
        local isAuraAnchor = rawget(snapshot.anchorIsAuraAnchors, index)
        local icon = rawget(snapshot.anchorIcons, index)
        local iconAccessMethod = rawget(
            snapshot.anchorIconAccessMethods,
            index
        )
        local iconGetParent = rawget(snapshot.anchorIconGetParents, index)
        local iconGetWidth = rawget(snapshot.anchorIconGetWidths, index)
        local iconWidth = rawget(snapshot.anchorIconWidths, index)
        local iconGetHeight = rawget(snapshot.anchorIconGetHeights, index)
        local iconHeight = rawget(snapshot.anchorIconHeights, index)
        local duration = rawget(snapshot.anchorDurations, index)
        local durationAccessMethod = rawget(
            snapshot.anchorDurationAccessMethods,
            index
        )
        local durationGetParent = rawget(
            snapshot.anchorDurationGetParents,
            index
        )
        local durationGetWidth = rawget(
            snapshot.anchorDurationGetWidths,
            index
        )
        local durationWidth = rawget(snapshot.anchorDurationWidths, index)
        local durationGetHeight = rawget(
            snapshot.anchorDurationGetHeights,
            index
        )
        local durationHeight = rawget(snapshot.anchorDurationHeights, index)
        if not IsOrdinaryValue(arrayAnchor)
            or not IsOrdinaryValue(anchor)
            or not rawequal(arrayAnchor, anchor)
            or not IsOrdinaryFunction(anchorAccessMethod)
            or not IsOrdinaryFunction(anchorGetParent)
            or not IsOrdinaryFunction(anchorSetUnit)
            or not IsOrdinaryNumber(auraIndex)
            or auraIndex ~= index
            or not IsOrdinaryValue(isAuraAnchor)
            or type(isAuraAnchor) ~= "boolean"
            or isAuraAnchor ~= true
            or not IsOrdinaryValue(icon)
            or not IsOrdinaryFunction(iconAccessMethod)
            or not IsOrdinaryFunction(iconGetParent)
            or not IsOrdinaryFunction(iconGetWidth)
            or not IsOrdinaryNumber(iconWidth)
            or iconWidth <= 0
            or not IsOrdinaryFunction(iconGetHeight)
            or not IsOrdinaryNumber(iconHeight)
            or iconHeight <= 0
            or not IsOrdinaryValue(duration)
            or not IsOrdinaryFunction(durationAccessMethod)
            or not IsOrdinaryFunction(durationGetParent)
            or not IsOrdinaryFunction(durationGetWidth)
            or not IsOrdinaryNumber(durationWidth)
            or durationWidth <= 0
            or not IsOrdinaryFunction(durationGetHeight)
            or not IsOrdinaryNumber(durationHeight)
            or durationHeight <= 0
        then
            return false
        end
    end
    return true
end

local function StoredHarmfulSnapshotRemainsAccessible(snapshot)
    if not HarmfulSnapshotRemainsOrdinary(snapshot) then return false end

    local frameAccessMethod = CanAccessScriptObject(snapshot.frame)
    local containerAccessMethod = CanAccessScriptObject(snapshot.container)
    if not frameAccessMethod
        or not containerAccessMethod
        or not rawequal(frameAccessMethod, snapshot.frameAccessMethod)
        or not rawequal(
            containerAccessMethod,
            snapshot.containerAccessMethod
        )
    then
        return false
    end

    for index = 1, EXPECTED_PRIVATE_ANCHOR_COUNT do
        local anchorAccessMethod = CanAccessScriptObject(
            rawget(snapshot.anchorObjects, index)
        )
        local iconAccessMethod = CanAccessScriptObject(
            rawget(snapshot.anchorIcons, index)
        )
        local durationAccessMethod = CanAccessScriptObject(
            rawget(snapshot.anchorDurations, index)
        )
        if not anchorAccessMethod
            or not iconAccessMethod
            or not durationAccessMethod
            or not rawequal(
                anchorAccessMethod,
                rawget(snapshot.anchorAccessMethods, index)
            )
            or not rawequal(
                iconAccessMethod,
                rawget(snapshot.anchorIconAccessMethods, index)
            )
            or not rawequal(
                durationAccessMethod,
                rawget(snapshot.anchorDurationAccessMethods, index)
            )
        then
            return false
        end
    end
    return true
end

local function HasExactLiveHarmfulTransaction(snapshot)
    if not HarmfulSnapshotRemainsOrdinary(snapshot) then return false end

    local frame = rawget(_G, "DebuffFrame")
    local debuffMixin = rawget(_G, "DebuffFrameMixin")
    local anchorMixin = rawget(_G, "BuffFramePrivateAuraAnchorMixin")
    local unitAuras = rawget(_G, "C_UnitAuras")
    if not IsOrdinaryTable(frame)
        or not IsOrdinaryTable(debuffMixin)
        or not IsOrdinaryTable(anchorMixin)
        or not IsOrdinaryTable(unitAuras)
        or not rawequal(frame, snapshot.frame)
        or not rawequal(debuffMixin, snapshot.debuffMixin)
        or not rawequal(anchorMixin, snapshot.anchorMixin)
        or not rawequal(unitAuras, snapshot.unitAuras)
    then
        return false
    end

    local frameAccessMethod = rawget(frame, "CanBeAccessedInContext")
    local updatePrivateAuraAnchors = rawget(
        frame,
        "UpdatePrivateAuraAnchors"
    )
    local maxPrivateAuras = rawget(frame, "maxPrivateAuras")
    local container = rawget(frame, "AuraContainer")
    local anchors = rawget(frame, "PrivateAuraAnchors")
    local mixinUpdate = rawget(debuffMixin, "UpdatePrivateAuraAnchors")
    local mixinSetUnit = rawget(anchorMixin, "SetUnit")
    local addPrivateAuraAnchor = rawget(unitAuras, "AddPrivateAuraAnchor")
    local removePrivateAuraAnchor = rawget(
        unitAuras,
        "RemovePrivateAuraAnchor"
    )
    if not IsOrdinaryFunction(frameAccessMethod)
        or not IsOrdinaryFunction(updatePrivateAuraAnchors)
        or not IsOrdinaryNumber(maxPrivateAuras)
        or maxPrivateAuras ~= EXPECTED_PRIVATE_ANCHOR_COUNT
        or not IsOrdinaryTable(container)
        or not HasExactOrdinaryArray(anchors)
        or not IsOrdinaryFunction(mixinUpdate)
        or not IsOrdinaryFunction(mixinSetUnit)
        or not IsOrdinaryFunction(addPrivateAuraAnchor)
        or not IsOrdinaryFunction(removePrivateAuraAnchor)
        or not rawequal(frameAccessMethod, snapshot.frameAccessMethod)
        or not rawequal(
            updatePrivateAuraAnchors,
            snapshot.updatePrivateAuraAnchors
        )
        or not rawequal(mixinUpdate, snapshot.updatePrivateAuraAnchors)
        or not rawequal(mixinSetUnit, snapshot.expectedSetUnit)
        or not rawequal(addPrivateAuraAnchor, snapshot.addPrivateAuraAnchor)
        or not rawequal(
            removePrivateAuraAnchor,
            snapshot.removePrivateAuraAnchor
        )
        or not rawequal(container, snapshot.container)
        or not rawequal(anchors, snapshot.anchors)
    then
        return false
    end

    local containerAccessMethod = rawget(
        container,
        "CanBeAccessedInContext"
    )
    local containerGetParent = rawget(container, "GetParent")
    local containerSetShown = rawget(container, "SetShown")
    local showDispelType = rawget(container, "showDispelType")
    if not IsOrdinaryFunction(containerAccessMethod)
        or not IsOrdinaryFunction(containerGetParent)
        or not IsOrdinaryFunction(containerSetShown)
        or not IsOrdinaryValue(showDispelType)
        or type(showDispelType) ~= "boolean"
        or not rawequal(
            containerAccessMethod,
            snapshot.containerAccessMethod
        )
        or not rawequal(containerGetParent, snapshot.containerGetParent)
        or not rawequal(containerSetShown, snapshot.containerSetShown)
        or showDispelType ~= snapshot.showDispelType
    then
        return false
    end

    local seenObjects = {}
    if not AddDistinctObject(seenObjects, frame)
        or not AddDistinctObject(seenObjects, container)
    then
        return false
    end

    for index = 1, EXPECTED_PRIVATE_ANCHOR_COUNT do
        local anchor = rawget(anchors, index)
        local alias = rawget(frame, "privateAuraAnchor" .. index)
        local expectedAnchor = rawget(snapshot.anchorObjects, index)
        if not IsOrdinaryTable(anchor)
            or not IsOrdinaryValue(alias)
            or not IsOrdinaryValue(expectedAnchor)
            or not rawequal(anchor, alias)
            or not rawequal(anchor, expectedAnchor)
        then
            return false
        end
        if not AddDistinctObject(seenObjects, anchor) then return false end

        local anchorAccessMethod = rawget(
            anchor,
            "CanBeAccessedInContext"
        )
        local anchorGetParent = rawget(anchor, "GetParent")
        local anchorSetUnit = rawget(anchor, "SetUnit")
        local auraIndex = rawget(anchor, "auraIndex")
        local isAuraAnchor = rawget(anchor, "isAuraAnchor")
        local icon = rawget(anchor, "Icon")
        local duration = rawget(anchor, "Duration")
        if not IsOrdinaryFunction(anchorAccessMethod)
            or not IsOrdinaryFunction(anchorGetParent)
            or not IsOrdinaryFunction(anchorSetUnit)
            or not IsOrdinaryNumber(auraIndex)
            or auraIndex ~= index
            or not IsOrdinaryValue(isAuraAnchor)
            or type(isAuraAnchor) ~= "boolean"
            or isAuraAnchor ~= true
            or not IsOrdinaryTable(icon)
            or not IsOrdinaryTable(duration)
            or not rawequal(
                anchorAccessMethod,
                rawget(snapshot.anchorAccessMethods, index)
            )
            or not rawequal(
                anchorGetParent,
                rawget(snapshot.anchorGetParents, index)
            )
            or not rawequal(
                anchorSetUnit,
                rawget(snapshot.anchorSetUnits, index)
            )
            or auraIndex ~= rawget(snapshot.anchorAuraIndexes, index)
            or isAuraAnchor
                ~= rawget(snapshot.anchorIsAuraAnchors, index)
            or not rawequal(icon, rawget(snapshot.anchorIcons, index))
            or not rawequal(
                duration,
                rawget(snapshot.anchorDurations, index)
            )
        then
            return false
        end
        if not AddDistinctObject(seenObjects, icon)
            or not AddDistinctObject(seenObjects, duration)
        then
            return false
        end

        local iconAccessMethod = rawget(icon, "CanBeAccessedInContext")
        local iconGetParent = rawget(icon, "GetParent")
        local iconGetWidth = rawget(icon, "GetWidth")
        local iconGetHeight = rawget(icon, "GetHeight")
        local durationAccessMethod = rawget(
            duration,
            "CanBeAccessedInContext"
        )
        local durationGetParent = rawget(duration, "GetParent")
        local durationGetWidth = rawget(duration, "GetWidth")
        local durationGetHeight = rawget(duration, "GetHeight")
        if not IsOrdinaryFunction(iconAccessMethod)
            or not IsOrdinaryFunction(iconGetParent)
            or not IsOrdinaryFunction(iconGetWidth)
            or not IsOrdinaryFunction(iconGetHeight)
            or not IsOrdinaryFunction(durationAccessMethod)
            or not IsOrdinaryFunction(durationGetParent)
            or not IsOrdinaryFunction(durationGetWidth)
            or not IsOrdinaryFunction(durationGetHeight)
            or not rawequal(
                iconAccessMethod,
                rawget(snapshot.anchorIconAccessMethods, index)
            )
            or not rawequal(
                iconGetParent,
                rawget(snapshot.anchorIconGetParents, index)
            )
            or not rawequal(
                iconGetWidth,
                rawget(snapshot.anchorIconGetWidths, index)
            )
            or not rawequal(
                iconGetHeight,
                rawget(snapshot.anchorIconGetHeights, index)
            )
            or not rawequal(
                durationAccessMethod,
                rawget(snapshot.anchorDurationAccessMethods, index)
            )
            or not rawequal(
                durationGetParent,
                rawget(snapshot.anchorDurationGetParents, index)
            )
            or not rawequal(
                durationGetWidth,
                rawget(snapshot.anchorDurationGetWidths, index)
            )
            or not rawequal(
                durationGetHeight,
                rawget(snapshot.anchorDurationGetHeights, index)
            )
        then
            return false
        end
    end
    return true
end

local function CaptureExactHarmfulTransaction(expected)
    if expected and not StoredHarmfulSnapshotRemainsAccessible(expected) then
        return
    end
    local current = CaptureNativeHarmfulAuraFrame()
    if not current or not HarmfulSnapshotRemainsOrdinary(current) then
        return
    end
    if expected
        and (
            not StoredHarmfulSnapshotRemainsAccessible(expected)
            or not HarmfulSnapshotRemainsOrdinary(expected)
            or not HarmfulSnapshotRemainsOrdinary(current)
            or not HasExactHarmfulSnapshotIdentity(expected, current)
        )
    then
        return
    end

    -- No object-access or geometry callback may run after this final capture.
    -- The remaining write-boundary fence uses only raw field/array reads,
    -- canonical secrecy/type predicates, and identity comparisons.
    local final = CaptureNativeHarmfulAuraFrame()
    if not final
        or not HarmfulSnapshotRemainsOrdinary(current)
        or not HarmfulSnapshotRemainsOrdinary(final)
        or (expected and not HarmfulSnapshotRemainsOrdinary(expected))
        or not HasExactLiveHarmfulTransaction(final)
        or not HasExactHarmfulSnapshotIdentity(current, final, true)
        or (expected
            and not HasExactHarmfulSnapshotIdentity(expected, final))
    then
        return
    end
    return final
end

local function IsSanitizedPlayerUnit(unit)
    return IsOrdinaryValue(unit)
        and type(unit) == "string"
        and (unit == "player" or unit == "vehicle")
end

function BD.CanSuppressNativeHarmfulAuras()
    if not IsOutOfCombat() then return false end
    return CaptureExactHarmfulTransaction(
        harmfulRecoveryState or harmfulSuppressedState
    ) ~= nil
end

function BD.AreNativeHarmfulAurasSuppressed()
    return harmfulSuppressedState ~= nil
end

function BD.SetNativeHarmfulAurasSuppressed(suppressed, restoreUnit)
    if not IsOrdinaryValue(suppressed) or type(suppressed) ~= "boolean" then
        return false
    end
    if not IsOutOfCombat() then return false end

    local existing = harmfulRecoveryState or harmfulSuppressedState
    if not suppressed and not existing then return true end
    if suppressed and suppressedStates.debuffs then return false end
    if not suppressed and not IsSanitizedPlayerUnit(restoreUnit) then
        return false
    end

    local transaction = CaptureExactHarmfulTransaction(existing)
    if not transaction then return false end
    if not IsOutOfCombat() then return false end

    if suppressed then
        if harmfulRecoveryState then
            -- A prior non-transactional setter batch did not return. Require
            -- its explicit restore path before attempting another removal.
            return false
        elseif harmfulSuppressedState then
            -- Completed suppression is idempotent only after full live
            -- topology revalidation above; do not call the setters again.
            return true
        end
        -- Retail 12.1.0.69273 (wow-ui-source
        -- eb941aad028d73ddc69e3e8ef4da709f4d3cd744) implements SetUnit(nil)
        -- by calling RemovePrivateAuraAnchor. The private-aura watcher then
        -- releases and resets its pooled renderer, whose Reset hides it. This
        -- deliberately never observes or mutates anchor visibility.
        -- This recovery-only ledger is published before the non-transactional
        -- six-call batch. WoW does not offer a rollback primitive and this
        -- boundary intentionally does not pcall protected/private-aura work;
        -- a later explicit restore can still find the captured topology after
        -- an opaque client error. The completed-suppression ledger is not
        -- published until every removal and the public hide have returned.
        harmfulRecoveryState = transaction
        for index = 1, EXPECTED_PRIVATE_ANCHOR_COUNT do
            transaction.anchorSetUnits[index](
                transaction.anchorObjects[index],
                nil
            )
        end
        transaction.containerSetShown(transaction.container, false)
        harmfulSuppressedState = transaction
        harmfulRecoveryState = nil
        return true
    end

    -- Re-add all six private renderers before showing Blizzard's ordinary row.
    -- The custom controller hides its own row only after both writes return.
    transaction.updatePrivateAuraAnchors(
        transaction.frame,
        restoreUnit
    )
    transaction.containerSetShown(transaction.container, true)
    harmfulSuppressedState = nil
    harmfulRecoveryState = nil
    return true
end

function BD.ReassertNativeHarmfulAuraSuppression()
    local existing = harmfulSuppressedState
    if not existing or harmfulRecoveryState or not IsOutOfCombat() then
        return false
    end
    local transaction = CaptureExactHarmfulTransaction(existing)
    if not transaction or not IsOutOfCombat() then return false end

    -- Blizzard can re-add its private anchors when the player/vehicle unit or
    -- Edit Mode setting changes. Reassert only from a completed suppression
    -- state, after the same two-pass identity fence. As with initial removal,
    -- the setter batch has no rollback primitive; preserve recovery intent
    -- before its first direct setter boundary.
    harmfulRecoveryState = transaction
    for index = 1, EXPECTED_PRIVATE_ANCHOR_COUNT do
        transaction.anchorSetUnits[index](
            transaction.anchorObjects[index],
            nil
        )
    end
    transaction.containerSetShown(transaction.container, false)
    harmfulSuppressedState = transaction
    harmfulRecoveryState = nil
    return true
end
