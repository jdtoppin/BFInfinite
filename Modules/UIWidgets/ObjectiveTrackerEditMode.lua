---@type BFI
local BFI = select(2, ...)
---@class UIWidgets
local W = BFI.modules.UIWidgets
---@type AbstractFramework
local AF = _G.AbstractFramework

-- Retail 12.1.0.68914, wow-ui-source d3915c78aba77a7a9be76acbfa35c674bbb6abe9:
-- C_EditMode.GetLayouts and SaveLayouts provide the persistent layout
-- snapshot. Objective Tracker Height is stored as a raw 0-60 value and
-- displayed as 400-1000 pixels in 10-pixel steps. Blizzard applies it only
-- after the tracker leaves its default/right-managed position; required
-- objective content may still expand past the requested height.
-- GetLayouts contains saved layouts only, but activeLayout keeps its global
-- index after Blizzard's preset layouts. Convert it to a saved-layout index
-- before reading or changing the active custom layout.
-- Temporary Blizzard override layouts are intentionally not inspected here:
-- the public API exposes saved layouts only, so this adapter persists an
-- eligible custom layout without depending on private Edit Mode state.
local NATIVE_HEIGHT_MIN = 400
local NATIVE_HEIGHT_MAX = 1000
local NATIVE_HEIGHT_STEP = 10
local NATIVE_HEIGHT_DEFAULT_RAW = 40
local BFI_TRACKER_DEFAULT_HEIGHT = 640
local BFI_FRESH_LAYOUT_NAME = "BFI"
local BFI_RIGHT_STACK_ANCHOR = {
    point = "TOPRIGHT",
    relativeTo = "UIParent",
    relativePoint = "TOPRIGHT",
    -- The styled BFI surface extends six pixels beyond Blizzard's header.
    -- Keep its outer edge four pixels inside the screen instead of retaining
    -- Blizzard's much larger preset inset.
    offsetX = -10,
    -- Blizzard's preset is -275. Keep the native tracker clear of the
    -- minimap while placing the BFI right-side stack 75 pixels higher.
    offsetY = -200,
}

local nativeLayoutSaveInProgress

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

local function GetObjectiveTrackerEditModeContext(
    requireCustomPosition,
    requireHeightSetting
)
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
        or type(layoutTypes) ~= "table"
        or type(presetLayouts) ~= "table"
        or systems.ObjectiveTracker == nil
        or layoutTypes.Account == nil
        or layoutTypes.Character == nil
        or type(presetLayouts.NumValues) ~= "number"
        or (requireHeightSetting and (
            type(settings) ~= "table"
            or settings.Height == nil
        ))
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
            if requireHeightSetting and type(systemInfo.settings) ~= "table" then
                return nil, "unavailable"
            end
            if requireCustomPosition
                and systemInfo.isInDefaultPosition ~= false
            then
                return nil, "customPosition"
            end

            return {
                activeLayoutIndex = activeLayoutIndex,
                editMode = editMode,
                heightSetting = requireHeightSetting and settings.Height,
                layouts = layouts,
                systemIndex = index,
            }
        end
    end

    return nil, "unavailable"
end

local function FindPresetLayout(presetLayouts, layoutIndex)
    if type(presetLayouts) ~= "table" then return end

    for _, presetLayout in ipairs(presetLayouts) do
        if type(presetLayout) == "table"
            and presetLayout.layoutIndex == layoutIndex
        then
            return presetLayout
        end
    end
end

local function GetFreshInstallPresetContext()
    local editMode = _G.C_EditMode
    local enums = _G.Enum
    local systems = enums and enums.EditModeSystem
    local layoutTypes = enums and enums.EditModeLayoutType
    local presetLayoutsMeta = enums and enums.EditModePresetLayoutsMeta
    local presetLayoutManager = _G.EditModePresetLayoutManager
    if type(editMode) ~= "table"
        or type(editMode.GetLayouts) ~= "function"
        or type(editMode.SaveLayouts) ~= "function"
        or type(editMode.OnLayoutAdded) ~= "function"
        or type(editMode.IsValidLayoutName) ~= "function"
        or type(systems) ~= "table"
        or type(layoutTypes) ~= "table"
        or type(presetLayoutsMeta) ~= "table"
        or systems.ObjectiveTracker == nil
        or layoutTypes.Preset == nil
        or layoutTypes.Account == nil
        or type(presetLayoutsMeta.NumValues) ~= "number"
        or type(presetLayoutManager) ~= "table"
        or type(presetLayoutManager.GetCopyOfPresetLayouts) ~= "function"
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

    local presetLayoutCount = presetLayoutsMeta.NumValues
    if layouts.activeLayout < 1
        or layouts.activeLayout > presetLayoutCount
    then
        return nil, "customLayout"
    end

    -- A fresh BFI install may seed one BFI-owned Account layout, but never
    -- adds a layout beside an existing Blizzard user layout.
    if next(layouts.layouts) ~= nil then return nil, "customLayout" end

    -- Retail 12.1.0.68914, wow-ui-source d3915c78aba77a7a9be76acbfa35c674bbb6abe9:
    -- Blizzard's EditModeManagerFrameMixin:MakeNewLayout starts from this
    -- read-only preset copy, saves the new Account layout, then calls the
    -- documented C_EditMode.OnLayoutAdded. Do the same only for the narrow
    -- empty-layout first-install case above.
    local presetLayouts = presetLayoutManager:GetCopyOfPresetLayouts()
    local presetLayout = FindPresetLayout(
        presetLayouts,
        layouts.activeLayout
    )
    if type(presetLayout) ~= "table"
        or presetLayout.layoutType ~= layoutTypes.Preset
        or type(presetLayout.systems) ~= "table"
    then
        return nil, "unavailable"
    end

    return {
        accountLayoutType = layoutTypes.Account,
        editMode = editMode,
        layouts = layouts,
        presetLayout = presetLayout,
        presetLayoutCount = presetLayoutCount,
        trackerSystem = systems.ObjectiveTracker,
    }
end

local function GetHeightSettingInfo(settings, heightSetting)
    if type(settings) ~= "table" then return end

    for index, settingInfo in ipairs(settings) do
        if type(settingInfo) == "table"
            and settingInfo.setting == heightSetting
        then
            return settingInfo, index
        end
    end
end

local function GetNativeHeightSetting()
    local enums = _G.Enum
    local settings = enums and enums.EditModeObjectiveTrackerSetting
    if type(settings) ~= "table" then return nil end
    return settings.Height
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

local function SetHeightSettingValue(systemInfo, heightSetting, height)
    if heightSetting == nil or type(systemInfo.settings) ~= "table" then
        return false
    end

    local settingInfo = GetHeightSettingInfo(
        systemInfo.settings,
        heightSetting
    )
    local rawValue = GetRawValueFromHeight(height)
    if settingInfo and settingInfo.value == rawValue then return false end

    if settingInfo then
        settingInfo.value = rawValue
    else
        table.insert(systemInfo.settings, {
            setting = heightSetting,
            value = rawValue,
        })
    end
    return true
end

local function ApplyBFIRightStackPlacement(systemInfo, heightSetting)
    systemInfo.isInDefaultPosition = false
    systemInfo.anchorInfo = AF.Copy(BFI_RIGHT_STACK_ANCHOR)
    systemInfo.anchorInfo2 = nil
    SetHeightSettingValue(
        systemInfo,
        heightSetting,
        BFI_TRACKER_DEFAULT_HEIGHT
    )
end

local function FindSystemInfo(systems, system)
    if type(systems) ~= "table" then return end

    for _, systemInfo in ipairs(systems) do
        if type(systemInfo) == "table" and systemInfo.system == system then
            return systemInfo
        end
    end
end

function W.GetObjectiveTrackerNativeHeight()
    local context, reason = GetObjectiveTrackerEditModeContext(true, true)
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
    if nativeLayoutSaveInProgress then return height, "busy" end
    return height
end

function W.SetObjectiveTrackerNativeHeight(height)
    if type(height) ~= "number" then return false, "invalid" end
    if nativeLayoutSaveInProgress then return false, "busy" end

    local context, reason = GetObjectiveTrackerEditModeContext(true, true)
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

    nativeLayoutSaveInProgress = true
    context.editMode.SaveLayouts(layouts)
    nativeLayoutSaveInProgress = nil
    return true
end

function W.ApplyObjectiveTrackerFreshInstallLayout()
    if nativeLayoutSaveInProgress then return false, "busy" end
    if IsInCombat() then return false, "combat" end
    if IsEditModeActive() then return false, "editMode" end
    if type(AF.Copy) ~= "function" then return false, "unavailable" end

    local context, reason = GetFreshInstallPresetContext()
    if not context then return false, reason end
    if context.editMode.IsValidLayoutName(BFI_FRESH_LAYOUT_NAME) ~= true then
        return false, "layoutName"
    end

    local layouts = AF.Copy(context.layouts)
    local layout = AF.Copy(context.presetLayout)
    local systemInfo = FindSystemInfo(layout.systems, context.trackerSystem)
    if not systemInfo then return false, "unavailable" end

    layout.layoutType = context.accountLayoutType
    layout.layoutName = BFI_FRESH_LAYOUT_NAME
    ApplyBFIRightStackPlacement(systemInfo, GetNativeHeightSetting())
    table.insert(layouts.layouts, layout)

    nativeLayoutSaveInProgress = true
    context.editMode.SaveLayouts(layouts)
    context.editMode.OnLayoutAdded(
        context.presetLayoutCount + 1,
        true,
        false
    )
    nativeLayoutSaveInProgress = nil
    return true
end

local function HasBFIRightStackPlacement(systemInfo, heightSetting)
    local anchorInfo = systemInfo.anchorInfo
    local hasPosition = systemInfo.isInDefaultPosition == false
        and type(anchorInfo) == "table"
        and anchorInfo.point == BFI_RIGHT_STACK_ANCHOR.point
        and anchorInfo.relativeTo == BFI_RIGHT_STACK_ANCHOR.relativeTo
        and anchorInfo.relativePoint == BFI_RIGHT_STACK_ANCHOR.relativePoint
        and anchorInfo.offsetX == BFI_RIGHT_STACK_ANCHOR.offsetX
        and anchorInfo.offsetY == BFI_RIGHT_STACK_ANCHOR.offsetY
        and systemInfo.anchorInfo2 == nil
    if not hasPosition
        or heightSetting == nil
        or type(systemInfo.settings) ~= "table"
    then
        return hasPosition
    end

    local settingInfo = GetHeightSettingInfo(
        systemInfo.settings,
        heightSetting
    )
    return settingInfo
        and settingInfo.value == GetRawValueFromHeight(
            BFI_TRACKER_DEFAULT_HEIGHT
        )
end

function W.GetObjectiveTrackerNativePlacement()
    local context, reason = GetObjectiveTrackerEditModeContext(false, false)
    if not context then return nil, reason end

    local activeLayout = context.layouts.layouts[
        context.activeLayoutIndex
    ]
    local systemInfo = activeLayout.systems[context.systemIndex]
    local isDefaultPosition = systemInfo.isInDefaultPosition ~= false

    if IsInCombat() then return isDefaultPosition, "combat" end
    if IsEditModeActive() then return isDefaultPosition, "editMode" end
    if nativeLayoutSaveInProgress then return isDefaultPosition, "busy" end
    return isDefaultPosition
end

function W.SetObjectiveTrackerBFIRightStackPlacement()
    if nativeLayoutSaveInProgress then return false, "busy" end

    local context, reason = GetObjectiveTrackerEditModeContext(false, false)
    if not context then return false, reason end
    if IsInCombat() then return false, "combat" end
    if IsEditModeActive() then return false, "editMode" end
    if type(AF.Copy) ~= "function" then return false, "unavailable" end

    local layouts = AF.Copy(context.layouts)
    local activeLayout = layouts.layouts[context.activeLayoutIndex]
    local systemInfo = activeLayout.systems[context.systemIndex]
    local heightSetting = GetNativeHeightSetting()
    if HasBFIRightStackPlacement(systemInfo, heightSetting) then return true end

    ApplyBFIRightStackPlacement(systemInfo, heightSetting)

    nativeLayoutSaveInProgress = true
    context.editMode.SaveLayouts(layouts)
    nativeLayoutSaveInProgress = nil
    return true
end
