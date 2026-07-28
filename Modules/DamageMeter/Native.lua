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
-- Blizzard_DamageMeter/DamageMeter.lua. BFI only reads native Edit Mode
-- settings and window counts here. Blizzard's own controls remain the sole
-- mutation path for row-affecting settings, session windows, meter types, and
-- secret-bearing combat data.

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

function Native.GetSettingDefinition(key)
    return CopyDefinition(SETTING_DEFINITIONS[key])
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
