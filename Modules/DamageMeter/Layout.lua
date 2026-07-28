---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter

local DEFAULT_X = -20
local DEFAULT_Y = 20
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

local function ArrangeShownSecondaryWindows(damageMeter, firstIndex)
    firstIndex = firstIndex or 2
    local previous = firstIndex == 2
        and damageMeter
        or damageMeter:GetSessionWindow(firstIndex - 1)
    if not previous
        or (firstIndex > 2 and not previous:IsShown()) then
        return false, "window_unavailable"
    end

    local width, height = damageMeter:GetSize()
    local maxWindows = math.min(
        damageMeter:GetMaxSessionWindowCount(),
        3
    )

    for i = firstIndex, maxWindows do
        local window = damageMeter:GetSessionWindow(i)
        if window and window:IsShown() then
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
    if type(damageMeter.OnSystemPositionChange) ~= "function"
        or type(manager.SaveLayouts) ~= "function" then
        return false, "unavailable"
    end

    local canChange, reason = CanChangeLayout(manager)
    if not canChange then
        return false, reason
    end

    SetBottomRight(damageMeter)
    damageMeter:OnSystemPositionChange()
    manager:SaveLayouts()
    ArrangeShownSecondaryWindows(damageMeter, 2)
    return true
end

function DM.ArrangeSecondaryWindows(firstIndex)
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

    firstIndex = firstIndex or 2
    if type(firstIndex) ~= "number"
        or firstIndex < 2
        or firstIndex % 1 ~= 0 then
        return false, "invalid_value"
    end

    return ArrangeShownSecondaryWindows(damageMeter, firstIndex)
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
        SetBottomRight(damageMeter)
        damageMeter:OnSystemPositionChange()
        manager:SaveLayouts()
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
