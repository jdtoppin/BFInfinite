---@type BFI
local BFI = select(2, ...)
---@class UIWidgets
local W = BFI.modules.UIWidgets
---@type AbstractFramework
local AF = _G.AbstractFramework

-- Retail 12.1.0.68914, wow-ui-source d3915c78aba77a7a9be76acbfa35c674bbb6abe9:
-- Blizzard exposes only C_EditMode.GetLayouts and SaveLayouts for persistent
-- system settings. Objective Tracker Height is stored as a raw 0-60 value and
-- displayed as 400-1000 pixels in 10-pixel steps. Blizzard applies it only
-- after the tracker leaves its default/right-managed position; required
-- objective content may still expand past the requested height.
-- GetLayouts contains saved layouts only, but activeLayout keeps its global
-- index after Blizzard's preset layouts. Convert it to a saved-layout index
-- before reading or changing the active custom layout.
local NATIVE_HEIGHT_MIN = 400
local NATIVE_HEIGHT_MAX = 1000
local NATIVE_HEIGHT_STEP = 10
local NATIVE_HEIGHT_DEFAULT_RAW = 40

local nativeHeightSaveInProgress

local function IsInCombat()
    return type(_G.InCombatLockdown) == "function"
        and _G.InCombatLockdown()
end

local function IsEditModeActive()
    local manager = _G.EditModeManagerFrame
    return manager
        and type(manager.IsEditModeActive) == "function"
        and manager:IsEditModeActive()
end

local function GetObjectiveTrackerEditModeContext()
    local editMode = _G.C_EditMode
    local enums = _G.Enum
    local systems = enums and enums.EditModeSystem
    local settings = enums and enums.EditModeObjectiveTrackerSetting
    local layoutTypes = enums and enums.EditModeLayoutType
    local presetLayouts = enums and enums.EditModePresetLayoutsMeta
    if type(editMode) ~= "table"
        or type(editMode.GetLayouts) ~= "function"
        or type(editMode.SaveLayouts) ~= "function"
        or type(systems) ~= "table"
        or type(settings) ~= "table"
        or type(layoutTypes) ~= "table"
        or type(presetLayouts) ~= "table"
        or systems.ObjectiveTracker == nil
        or settings.Height == nil
        or layoutTypes.Account == nil
        or layoutTypes.Character == nil
        or type(presetLayouts.NumValues) ~= "number"
    then
        return nil, "unavailable"
    end

    local layouts = editMode.GetLayouts()
    if type(layouts) ~= "table"
        or type(layouts.layouts) ~= "table"
        or type(layouts.activeLayout) ~= "number"
    then
        return nil, "unavailable"
    end

    local presetLayoutCount = presetLayouts.NumValues
    if layouts.activeLayout <= presetLayoutCount then
        return nil, "customLayout"
    end

    local activeLayoutIndex = layouts.activeLayout - presetLayoutCount
    local activeLayout = layouts.layouts[activeLayoutIndex]
    if type(activeLayout) ~= "table"
        or type(activeLayout.systems) ~= "table"
    then
        return nil, "unavailable"
    end

    local layoutType = activeLayout.layoutType
    if layoutType ~= layoutTypes.Account
        and layoutType ~= layoutTypes.Character
    then
        return nil, "customLayout"
    end

    for index, systemInfo in ipairs(activeLayout.systems) do
        if type(systemInfo) == "table"
            and systemInfo.system == systems.ObjectiveTracker
        then
            if type(systemInfo.settings) ~= "table" then
                return nil, "unavailable"
            end
            if systemInfo.isInDefaultPosition ~= false then
                return nil, "customPosition"
            end

            return {
                activeLayoutIndex = activeLayoutIndex,
                editMode = editMode,
                heightSetting = settings.Height,
                layouts = layouts,
                systemIndex = index,
            }
        end
    end

    return nil, "unavailable"
end

local function GetHeightSettingInfo(settings, heightSetting)
    for index, settingInfo in ipairs(settings) do
        if type(settingInfo) == "table"
            and settingInfo.setting == heightSetting
        then
            return settingInfo, index
        end
    end
end

local function GetHeightFromRawValue(rawValue)
    if type(rawValue) ~= "number" then
        rawValue = NATIVE_HEIGHT_DEFAULT_RAW
    end

    rawValue = math.max(
        0,
        math.min(
            (NATIVE_HEIGHT_MAX - NATIVE_HEIGHT_MIN) / NATIVE_HEIGHT_STEP,
            math.floor(rawValue + 0.5)
        )
    )
    return NATIVE_HEIGHT_MIN + (rawValue * NATIVE_HEIGHT_STEP)
end

local function GetRawValueFromHeight(height)
    local rawValue = math.floor(
        ((height - NATIVE_HEIGHT_MIN) / NATIVE_HEIGHT_STEP) + 0.5
    )
    return math.max(
        0,
        math.min(
            (NATIVE_HEIGHT_MAX - NATIVE_HEIGHT_MIN) / NATIVE_HEIGHT_STEP,
            rawValue
        )
    )
end

function W.GetObjectiveTrackerNativeHeight()
    local context, reason = GetObjectiveTrackerEditModeContext()
    if not context then return nil, reason end

    local activeLayout = context.layouts.layouts[
        context.activeLayoutIndex
    ]
    local systemInfo = activeLayout.systems[context.systemIndex]
    local settingInfo = GetHeightSettingInfo(
        systemInfo.settings,
        context.heightSetting
    )
    local height = GetHeightFromRawValue(settingInfo and settingInfo.value)

    if IsInCombat() then return height, "combat" end
    if IsEditModeActive() then return height, "editMode" end
    if nativeHeightSaveInProgress then return height, "busy" end
    return height
end

function W.SetObjectiveTrackerNativeHeight(height)
    if type(height) ~= "number" then return false, "invalid" end
    if nativeHeightSaveInProgress then return false, "busy" end

    local context, reason = GetObjectiveTrackerEditModeContext()
    if not context then return false, reason end
    if IsInCombat() then return false, "combat" end
    if IsEditModeActive() then return false, "editMode" end
    if type(AF.Copy) ~= "function" then return false, "unavailable" end

    local layouts = AF.Copy(context.layouts)
    local activeLayout = layouts.layouts[context.activeLayoutIndex]
    local systemInfo = activeLayout.systems[context.systemIndex]
    local settingInfo = GetHeightSettingInfo(
        systemInfo.settings,
        context.heightSetting
    )
    local rawValue = GetRawValueFromHeight(height)
    if settingInfo and settingInfo.value == rawValue then return true end

    if settingInfo then
        settingInfo.value = rawValue
    else
        table.insert(systemInfo.settings, {
            setting = context.heightSetting,
            value = rawValue,
        })
    end

    nativeHeightSaveInProgress = true
    context.editMode.SaveLayouts(layouts)
    nativeHeightSaveInProgress = nil
    return true
end
