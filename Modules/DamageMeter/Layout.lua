---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter

local DEFAULT_X = 0
local DEFAULT_Y = 0
local WINDOW_SPACING = 8

-- FrameXML evidence: Retail PTR 12.1.0.68914, Gethe/wow-ui-source commit
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9. The primary window is
-- anchored through Edit Mode; secondary windows are native user-placed
-- DamageMeterSessionWindow2/3 frames persisted by SavedFramePositionCache.

local function GetNativeFrames()
    local damageMeter = _G.DamageMeter
    local manager = _G.EditModeManagerFrame
    if not damageMeter or not manager then
        return nil, nil, "unavailable"
    end
    return damageMeter, manager
end

local function CanChangeLayout(manager)
    if type(manager.IsShown) == "function" and manager:IsShown() then
        return false, "edit_mode_active"
    end
    if type(manager.HasActiveChanges) == "function"
        and manager:HasActiveChanges() then
        return false, "pending_changes"
    end
    return DM.Native.CanPersistLayout()
end

local function GetExactTargetSet(damageMeter, indices)
    if indices == nil then
        return nil
    end

    if type(indices) ~= "table" then
        return nil, "invalid_value"
    end

    local maxWindows = math.min(
        damageMeter:GetMaxSessionWindowCount(),
        3
    )
    local targets = {}
    local count = 0
    local highestKey = 0

    for key, index in next, indices do
        if type(key) ~= "number"
            or key < 1
            or key % 1 ~= 0
            or type(index) ~= "number"
            or index < 2
            or index > maxWindows
            or index % 1 ~= 0
            or targets[index] then
            return nil, "invalid_value"
        end

        targets[index] = true
        count = count + 1
        highestKey = math.max(highestKey, key)
    end

    if highestKey ~= count then
        return nil, "invalid_value"
    end

    for index in next, targets do
        local window = damageMeter:GetSessionWindow(index)
        if not window or not window:IsShown() then
            return nil, "window_unavailable"
        end
    end

    return targets
end

local function ArrangeShownSecondaryWindows(damageMeter, indices)
    local targets, targetError = GetExactTargetSet(damageMeter, indices)
    if targetError then
        return false, targetError
    end

    local width, height = damageMeter:GetSize()
    local maxWindows = math.min(
        damageMeter:GetMaxSessionWindowCount(),
        3
    )
    local previous = damageMeter

    for i = 2, maxWindows do
        local window = damageMeter:GetSessionWindow(i)
        if window and window:IsShown() then
            local isUserPlaced =
                type(window.IsUserPlaced) == "function"
                and window:IsUserPlaced()
            -- An exact index list marks automatic placement. Normalize every
            -- visible native fallback in that mode so a pre-existing unplaced
            -- window cannot strand the new one at the top-left. A nil list is
            -- the explicit arrange-all action and may replace user positions.
            if targets == nil or not isUserPlaced then
                window:ClearAllPoints()
                window:SetPoint(
                    "BOTTOMRIGHT",
                    previous,
                    "BOTTOMLEFT",
                    -WINDOW_SPACING,
                    0
                )
                window:SetSize(width, height)
                window:SetUserPlaced(true)
            end
            previous = window
        end
    end

    return true
end

local function SetBottomRight(damageMeter)
    damageMeter:ClearAllPoints()
    damageMeter:SetPoint(
        "BOTTOMRIGHT",
        _G.UIParent,
        "BOTTOMRIGHT",
        DEFAULT_X,
        DEFAULT_Y
    )
end

function DM.ApplyBottomRightLayout()
    if _G.InCombatLockdown() then
        return false, "combat"
    end

    local damageMeter, manager, errorReason = GetNativeFrames()
    if not damageMeter then
        return false, errorReason
    end
    if type(_G.securecallfunction) ~= "function"
        or type(damageMeter.OnSystemPositionChange) ~= "function"
        or type(manager.SaveLayouts) ~= "function" then
        return false, "unavailable"
    end

    local canChange, reason = CanChangeLayout(manager)
    if not canChange then
        return false, reason
    end

    SetBottomRight(damageMeter)
    _G.securecallfunction(
        damageMeter.OnSystemPositionChange,
        damageMeter
    )
    _G.securecallfunction(manager.SaveLayouts, manager)
    ArrangeShownSecondaryWindows(damageMeter)
    return true
end

function DM.ArrangeSecondaryWindows(indices)
    if _G.InCombatLockdown() then
        return false, "combat"
    end

    local damageMeter = _G.DamageMeter
    if not damageMeter
        or type(damageMeter.GetMaxSessionWindowCount) ~= "function"
        or type(damageMeter.GetSessionWindow) ~= "function"
        or type(damageMeter.GetSize) ~= "function" then
        return false, "unavailable"
    end

    return ArrangeShownSecondaryWindows(damageMeter, indices)
end

function DM.ApplyDefaultPositionIfNeeded()
    if _G.InCombatLockdown() then
        return false, "combat"
    end

    local damageMeter, manager, errorReason = GetNativeFrames()
    if not damageMeter then
        return false, errorReason
    end
    if type(damageMeter.IsInDefaultPosition) ~= "function"
        or not damageMeter:IsInDefaultPosition() then
        return false, "custom_position"
    end

    local canChange, reason = CanChangeLayout(manager)
    if canChange then
        if type(_G.securecallfunction) ~= "function"
            or type(damageMeter.OnSystemPositionChange) ~= "function"
            or type(manager.SaveLayouts) ~= "function" then
            return false, "unavailable"
        end

        SetBottomRight(damageMeter)
        _G.securecallfunction(
            damageMeter.OnSystemPositionChange,
            damageMeter
        )
        _G.securecallfunction(manager.SaveLayouts, manager)
        return true
    end
    if reason ~= "preset" then
        return false, reason
    end

    -- Blizzard preset layouts are immutable. Keep the BFI default visually
    -- useful for this session without mutating or silently cloning a preset.
    SetBottomRight(damageMeter)
    return true, "runtime"
end
