---@type BFI
local BFI = select(2, ...)
---@class ActionBars
local AB = BFI.modules.ActionBars
---@type AbstractFramework
local AF = _G.AbstractFramework

local MOUSEOVER_CVAR = "enableMouseoverCast"
local MOUSEOVER_MODIFIED_CLICK = "MOUSEOVERCAST"

local GetCVarBool = GetCVarBool
local GetModifiedClick = GetModifiedClick
local InCombatLockdown = InCombatLockdown
local SetCVar = SetCVar
local SetModifiedClick = SetModifiedClick
local applyingProfile

local function GetConfig()
    local shared = AB.config and AB.config.sharedButtonConfig
    local cast = shared and shared.cast
    return cast and cast.mouseover
end

local function RefreshOptions()
    AF.Fire("BFI_MouseoverCastChanged")
end

function AB.GetMouseoverCast()
    local config = GetConfig()
    if not config then
        return false, "NONE"
    end
    return config[1] == true, config[2] or "NONE"
end

local RetryApply

local function SetNativeSetting(variable, value)
    if Settings
        and type(Settings.GetSetting) == "function"
        and type(Settings.SetValue) == "function"
        and Settings.GetSetting(variable)
    then
        Settings.SetValue(variable, value, true)
        return
    end

    if variable == MOUSEOVER_MODIFIED_CLICK then
        SetModifiedClick(variable, value)
        if Settings and type(Settings.NotifyUpdate) == "function" then
            Settings.NotifyUpdate(variable)
        end
    else
        SetCVar(variable, value and 1 or 0)
    end
end

function AB.ApplyMouseoverCastProfile()
    local config = GetConfig()
    if not config then return end

    local enabled = config[1] == true
    local modifier = config[2] or "NONE"
    local enabledChanged = GetCVarBool(MOUSEOVER_CVAR) ~= enabled
    local modifierChanged = GetModifiedClick(MOUSEOVER_MODIFIED_CLICK) ~= modifier
    if not enabledChanged and not modifierChanged then return end

    if InCombatLockdown() then
        AB:RegisterEvent("PLAYER_REGEN_ENABLED", RetryApply)
        return
    end

    -- Apply the pair atomically from BFI's perspective. Both Settings
    -- callbacks and CVAR_UPDATE can run synchronously.
    applyingProfile = true
    if modifierChanged then
        SetNativeSetting(MOUSEOVER_MODIFIED_CLICK, modifier)
    end
    if enabledChanged then
        SetNativeSetting(MOUSEOVER_CVAR, enabled)
    end
    applyingProfile = nil
end

RetryApply = function()
    AB:UnregisterEvent("PLAYER_REGEN_ENABLED", RetryApply)
    AB.ApplyMouseoverCastProfile()
end

function AB.SetMouseoverCast(enabled, modifier)
    local config = GetConfig()
    if not config then return false end

    if enabled == nil then
        enabled = config[1] == true
    else
        enabled = not not enabled
    end
    modifier = modifier or config[2] or "NONE"

    local changed = config[1] ~= enabled or config[2] ~= modifier
    config[1] = enabled
    config[2] = modifier
    AB.ApplyMouseoverCastProfile()

    if changed then
        RefreshOptions()
    end
    return changed
end

local function SyncProfileFromNative()
    if applyingProfile then return end

    local config = GetConfig()
    if not config then return end

    local enabled = GetCVarBool(MOUSEOVER_CVAR)
    local modifier = GetModifiedClick(MOUSEOVER_MODIFIED_CLICK) or "NONE"
    if config[1] == enabled and config[2] == modifier then return end

    config[1] = enabled
    config[2] = modifier
    RefreshOptions()
end

local function CVarUpdated(_, _, cvar)
    if cvar == MOUSEOVER_CVAR then
        SyncProfileFromNative()
    end
end

local function ProfileUpdated()
    AB.ApplyMouseoverCastProfile()
    RefreshOptions()
end

local function UpdateModule(_, module)
    if module and module ~= "actionBars" then return end
    AB.ApplyMouseoverCastProfile()
end

-- Retail 12.1.0.68914, Gethe/wow-ui-source d3915c78aba7:
-- Blizzard_SettingsDefinitions_Frame/Combat.lua registers these exact native
-- settings. The Settings callbacks cover Blizzard's panel, while the events
-- also adopt changes made through console commands and binding APIs.
AB:RegisterEvent("CVAR_UPDATE", CVarUpdated)
AB:RegisterEvent("UPDATE_BINDINGS", SyncProfileFromNative)
if Settings and type(Settings.SetOnValueChangedCallback) == "function" then
    Settings.SetOnValueChangedCallback(MOUSEOVER_CVAR, SyncProfileFromNative, AB)
    Settings.SetOnValueChangedCallback(MOUSEOVER_MODIFIED_CLICK, SyncProfileFromNative, AB)
end

AF.RegisterCallback("BFI_UpdateProfile", ProfileUpdated, "low")
AF.RegisterCallback("BFI_UpdateModule", UpdateModule, "high")
