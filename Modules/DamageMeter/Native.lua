---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter

DM.Native = DM.Native or {}
local Native = DM.Native

-- API evidence: Retail PTR 12.1.0.68914, Gethe/wow-ui-source commit
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9. BFI only uses Blizzard's
-- sanctioned Damage Meter CVars here. The custom renderer never loads,
-- hooks, reads, or mutates Blizzard Damage Meter or Edit Mode frames.

local CVAR_ENABLED = "damageMeterEnabled"
local CVAR_RESET_ON_NEW_INSTANCE = "damageMeterResetOnNewInstance"

local function SetBooleanCVar(name, enabled)
    if type(enabled) ~= "boolean" then
        return false, "invalid_value"
    end

    if _G.C_CVar.SetCVar(name, enabled and "1" or "0") == false then
        return false, "cvar_write_failed"
    end
    return true
end

function Native.GetEnabled()
    return _G.C_CVar.GetCVarBool(CVAR_ENABLED)
end

function Native.SetEnabled(enabled)
    return SetBooleanCVar(CVAR_ENABLED, enabled)
end

function Native.GetResetOnNewInstance()
    return _G.C_CVar.GetCVarBool(CVAR_RESET_ON_NEW_INSTANCE)
end

function Native.SetResetOnNewInstance(enabled)
    return SetBooleanCVar(CVAR_RESET_ON_NEW_INSTANCE, enabled)
end
