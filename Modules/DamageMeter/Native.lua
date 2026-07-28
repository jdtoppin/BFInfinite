---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter

DM.Native = DM.Native or {}
local Native = DM.Native

-- FrameXML evidence: Retail PTR 12.1.0.68914, Gethe/wow-ui-source commit
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9. Setting enums, ranges, and
-- conversions are defined by Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua;
-- persistence and live updates use Blizzard_EditMode/Shared/EditModeManager.lua
-- and EditModeSystemTemplates.lua; window management uses the public methods on
-- Blizzard_DamageMeter/DamageMeter.lua.

local CVAR_ENABLED = "damageMeterEnabled"
local CVAR_RESET_ON_NEW_INSTANCE = "damageMeterResetOnNewInstance"
local MAX_SUPPORTED_WINDOWS = 3

local SETTING_DEFINITIONS = {
    visibility = {
        setting = _G.Enum.EditModeDamageMeterSetting.Visibility,
        values = {
            [_G.Enum.DamageMeterVisibility.Always] = true,
            [_G.Enum.DamageMeterVisibility.InCombat] = true,
            [_G.Enum.DamageMeterVisibility.Hidden] = true,
            [_G.Enum.DamageMeterVisibility.InGroup] = true,
        },
    },
    style = {
        setting = _G.Enum.EditModeDamageMeterSetting.Style,
        values = {
            [_G.Enum.DamageMeterStyle.Default] = true,
            [_G.Enum.DamageMeterStyle.Thin] = true,
            [_G.Enum.DamageMeterStyle.Bordered] = true,
        },
    },
    numbers = {
        setting = _G.Enum.EditModeDamageMeterSetting.Numbers,
        values = {
            [_G.Enum.DamageMeterNumbers.Minimal] = true,
            [_G.Enum.DamageMeterNumbers.Compact] = true,
            [_G.Enum.DamageMeterNumbers.Complete] = true,
        },
    },
    frameWidth = {
        setting = _G.Enum.EditModeDamageMeterSetting.FrameWidth,
        min = 200,
        max = 600,
        step = 1,
    },
    frameHeight = {
        setting = _G.Enum.EditModeDamageMeterSetting.FrameHeight,
        min = 120,
        max = 400,
        step = 1,
    },
    padding = {
        setting = _G.Enum.EditModeDamageMeterSetting.Padding,
        min = 2,
        max = 10,
        step = 1,
    },
    transparency = {
        setting = _G.Enum.EditModeDamageMeterSetting.Transparency,
        min = 50,
        max = 100,
        step = 1,
    },
    showSpecIcon = {
        setting = _G.Enum.EditModeDamageMeterSetting.ShowSpecIcon,
        boolean = true,
    },
    showClassColor = {
        setting = _G.Enum.EditModeDamageMeterSetting.ShowClassColor,
        boolean = true,
    },
    barHeight = {
        setting = _G.Enum.EditModeDamageMeterSetting.BarHeight,
        min = 15,
        max = 40,
        step = 1,
    },
    textSize = {
        setting = _G.Enum.EditModeDamageMeterSetting.TextSize,
        min = 50,
        max = 150,
        step = 10,
    },
    backgroundTransparency = {
        setting = _G.Enum.EditModeDamageMeterSetting.BackgroundTransparency,
        min = 0,
        max = 100,
        step = 1,
    },
}

local DAMAGE_METER_TYPE_DEFINITIONS = {
    {
        key = "damageDone",
        value = _G.Enum.DamageMeterType.DamageDone,
        labelGlobal = "DAMAGE_METER_TYPE_DAMAGE_DONE",
    },
    {
        key = "dps",
        value = _G.Enum.DamageMeterType.Dps,
        labelGlobal = "DAMAGE_METER_TYPE_DPS",
    },
    {
        key = "healingDone",
        value = _G.Enum.DamageMeterType.HealingDone,
        labelGlobal = "DAMAGE_METER_TYPE_HEALING_DONE",
    },
    {
        key = "hps",
        value = _G.Enum.DamageMeterType.Hps,
        labelGlobal = "DAMAGE_METER_TYPE_HPS",
    },
    {
        key = "absorbs",
        value = _G.Enum.DamageMeterType.Absorbs,
        labelGlobal = "DAMAGE_METER_TYPE_ABSORBS",
    },
    {
        key = "interrupts",
        value = _G.Enum.DamageMeterType.Interrupts,
        labelGlobal = "DAMAGE_METER_TYPE_INTERRUPTS",
    },
    {
        key = "dispels",
        value = _G.Enum.DamageMeterType.Dispels,
        labelGlobal = "DAMAGE_METER_TYPE_DISPELS",
    },
    {
        key = "damageTaken",
        value = _G.Enum.DamageMeterType.DamageTaken,
        labelGlobal = "DAMAGE_METER_TYPE_DAMAGE_TAKEN",
    },
    {
        key = "avoidableDamageTaken",
        value = _G.Enum.DamageMeterType.AvoidableDamageTaken,
        labelGlobal = "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN",
    },
    {
        key = "deaths",
        value = _G.Enum.DamageMeterType.Deaths,
        labelGlobal = "DAMAGE_METER_TYPE_DEATHS",
    },
    {
        key = "enemyDamageTaken",
        value = _G.Enum.DamageMeterType.EnemyDamageTaken,
        labelGlobal = "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN",
    },
}

local DAMAGE_METER_TYPE_SET = {}
for _, definition in ipairs(DAMAGE_METER_TYPE_DEFINITIONS) do
    DAMAGE_METER_TYPE_SET[definition.value] = true
end

local TRIPLE_WINDOW_PRESET = {
    _G.Enum.DamageMeterType.DamageDone,
    _G.Enum.DamageMeterType.HealingDone,
    _G.Enum.DamageMeterType.DamageTaken,
}

local function CopyArray(source)
    local copy = {}
    for i, value in ipairs(source) do
        copy[i] = value
    end
    return copy
end

local function CopyTypeDefinitions()
    local copy = {}
    for i, definition in ipairs(DAMAGE_METER_TYPE_DEFINITIONS) do
        copy[i] = {
            key = definition.key,
            value = definition.value,
            labelGlobal = definition.labelGlobal,
        }
    end
    return copy
end

local function CopyDefinition(definition)
    if not definition then return nil end

    local copy = {
        setting = definition.setting,
        min = definition.min,
        max = definition.max,
        step = definition.step,
        boolean = definition.boolean,
    }
    if definition.values then
        copy.values = {}
        for value in next, definition.values do
            copy.values[value] = true
        end
    end
    return copy
end

local function GetDamageMeter()
    local damageMeter = _G.DamageMeter
    if not damageMeter then return nil end
    return damageMeter
end

local function GetEditModeManager()
    local manager = _G.EditModeManagerFrame
    if not manager then return nil end
    return manager
end

local function IsSettingReady(damageMeter, definition)
    return damageMeter
        and type(damageMeter.IsInitialized) == "function"
        and type(damageMeter.HasSetting) == "function"
        and damageMeter:IsInitialized()
        and damageMeter:HasSetting(definition.setting)
end

local function IsValidSettingValue(definition, value)
    if definition.boolean then
        return type(value) == "boolean"
    end
    if type(value) ~= "number" then
        return false
    end
    if definition.values then
        return definition.values[value] == true
    end
    if value < definition.min or value > definition.max then
        return false
    end
    return (value - definition.min) % definition.step == 0
end

local function IsValidWindowType(damageMeterType)
    return type(damageMeterType) == "number"
        and DAMAGE_METER_TYPE_SET[damageMeterType] == true
end

function Native.GetSettingDefinition(key)
    return CopyDefinition(SETTING_DEFINITIONS[key])
end

function Native.GetDamageMeterTypes()
    return CopyTypeDefinitions()
end

function Native.GetTripleWindowPreset()
    return CopyArray(TRIPLE_WINDOW_PRESET)
end

function Native.GetEnabled()
    return _G.C_CVar.GetCVarBool(CVAR_ENABLED)
end

function Native.SetEnabled(enabled)
    if type(enabled) ~= "boolean" then
        return false, "invalid_value"
    end

    if _G.C_CVar.SetCVar(
        CVAR_ENABLED,
        enabled and "1" or "0"
    ) == false then
        return false, "cvar_write_failed"
    end
    return true
end

function Native.GetResetOnNewInstance()
    return _G.C_CVar.GetCVarBool(CVAR_RESET_ON_NEW_INSTANCE)
end

function Native.SetResetOnNewInstance(enabled)
    if type(enabled) ~= "boolean" then
        return false, "invalid_value"
    end

    if _G.C_CVar.SetCVar(
        CVAR_RESET_ON_NEW_INSTANCE,
        enabled and "1" or "0"
    ) == false then
        return false, "cvar_write_failed"
    end
    return true
end

function Native.GetSetting(key)
    local definition = SETTING_DEFINITIONS[key]
    if not definition then
        return nil, "unknown_setting"
    end

    local damageMeter = GetDamageMeter()
    if not IsSettingReady(damageMeter, definition)
        or type(damageMeter.GetSettingValue) ~= "function" then
        return nil, "unavailable"
    end

    local value = damageMeter:GetSettingValue(definition.setting)
    if value == nil then
        return nil, "unavailable"
    end
    if definition.boolean then
        return value == 1
    end
    return value
end

function Native.CanPersistLayout()
    if type(_G.InCombatLockdown) == "function"
        and _G.InCombatLockdown() then
        return false, "combat"
    end

    local manager = GetEditModeManager()
    if not manager or type(manager.GetActiveLayoutInfo) ~= "function" then
        return false, "unavailable"
    end
    if type(manager.IsShown) == "function" and manager:IsShown() then
        return false, "edit_mode_active"
    end
    if type(manager.HasActiveChanges) == "function"
        and manager:HasActiveChanges() then
        return false, "pending_changes"
    end

    local layoutInfo = manager:GetActiveLayoutInfo()
    if not layoutInfo then
        return false, "unavailable"
    end

    local layoutType = layoutInfo.layoutType
    if layoutType == _G.Enum.EditModeLayoutType.Account
        or layoutType == _G.Enum.EditModeLayoutType.Character then
        return true
    end
    return false, "preset"
end

function Native.SetSetting(key, value)
    local definition = SETTING_DEFINITIONS[key]
    if not definition then
        return false, "unknown_setting"
    end
    if not IsValidSettingValue(definition, value) then
        return false, "invalid_value"
    end

    local damageMeter = GetDamageMeter()
    local manager = GetEditModeManager()
    if not IsSettingReady(damageMeter, definition)
        or not manager
        or type(manager.OnSystemSettingChange) ~= "function"
        or type(manager.SaveLayouts) ~= "function" then
        return false, "unavailable"
    end
    local canPersist, reason = Native.CanPersistLayout()
    if not canPersist then
        return false, reason
    end

    local displayValue = definition.boolean and (value and 1 or 0) or value
    manager:OnSystemSettingChange(
        damageMeter,
        definition.setting,
        displayValue
    )
    manager:SaveLayouts()
    return true
end

function Native.GetMaxWindowCount()
    local damageMeter = GetDamageMeter()
    if not damageMeter
        or type(damageMeter.GetMaxSessionWindowCount) ~= "function" then
        return nil, "unavailable"
    end

    return math.min(
        damageMeter:GetMaxSessionWindowCount(),
        MAX_SUPPORTED_WINDOWS
    )
end

function Native.GetWindowCount()
    local damageMeter = GetDamageMeter()
    if not damageMeter
        or type(damageMeter.GetCurrentSessionWindowCount) ~= "function" then
        return nil, "unavailable"
    end

    return damageMeter:GetCurrentSessionWindowCount()
end

function Native.GetWindowTypes()
    local damageMeter = GetDamageMeter()
    if not damageMeter
        or type(damageMeter.GetMaxSessionWindowCount) ~= "function"
        or type(damageMeter.GetSessionWindow) ~= "function"
        or type(damageMeter.GetSessionWindowDamageMeterType) ~= "function" then
        return nil, "unavailable"
    end

    local types = {}
    local maxWindows = math.min(
        damageMeter:GetMaxSessionWindowCount(),
        MAX_SUPPORTED_WINDOWS
    )
    for i = 1, maxWindows do
        local window = damageMeter:GetSessionWindow(i)
        if window and window:IsShown() then
            types[#types + 1] =
                damageMeter:GetSessionWindowDamageMeterType(window)
        end
    end
    return types
end

function Native.ConfigureWindows(types)
    if type(types) ~= "table" then
        return false, "invalid_value"
    end

    local count = #types
    if count < 1 or count > MAX_SUPPORTED_WINDOWS then
        return false, "window_count"
    end
    for key in next, types do
        if type(key) ~= "number"
            or key < 1
            or key > count
            or key % 1 ~= 0 then
            return false, "invalid_value"
        end
    end
    for i = 1, count do
        if not IsValidWindowType(types[i]) then
            return false, "invalid_value"
        end
    end
    if type(_G.InCombatLockdown) == "function"
        and _G.InCombatLockdown() then
        return false, "combat"
    end

    local damageMeter = GetDamageMeter()
    if not damageMeter
        or type(damageMeter.GetMaxSessionWindowCount) ~= "function"
        or type(damageMeter.GetSessionWindow) ~= "function"
        or type(damageMeter.ShowNewSecondarySessionWindow) ~= "function"
        or type(damageMeter.HideSessionWindow) ~= "function"
        or type(damageMeter.SetSessionWindowDamageMeterType) ~= "function" then
        return false, "unavailable"
    end

    local maxWindows = math.min(
        damageMeter:GetMaxSessionWindowCount(),
        MAX_SUPPORTED_WINDOWS
    )
    if count > maxWindows then
        return false, "window_count"
    end

    for i = 1, count do
        local window = damageMeter:GetSessionWindow(i)
        if not window or not window:IsShown() then
            damageMeter:ShowNewSecondarySessionWindow()
            window = damageMeter:GetSessionWindow(i)
        end
        if not window or not window:IsShown() then
            return false, "window_unavailable"
        end
        damageMeter:SetSessionWindowDamageMeterType(window, types[i])
    end

    for i = count + 1, maxWindows do
        local window = damageMeter:GetSessionWindow(i)
        if window and window:IsShown() then
            damageMeter:HideSessionWindow(window)
        end
    end

    return true
end

function Native.ApplyTripleWindowPreset()
    return Native.ConfigureWindows(TRIPLE_WINDOW_PRESET)
end
