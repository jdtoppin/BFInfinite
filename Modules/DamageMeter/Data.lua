---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter

DM.Data = DM.Data or {}
local Data = DM.Data

-- API evidence: Retail PTR 12.1.0.68914, Gethe/wow-ui-source commit
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9,
-- Interface/AddOns/Blizzard_APIDocumentationGenerated/DamageMeterDocumentation.lua.
--
-- Session and source results can contain secret fields. This adapter returns
-- Blizzard's values unchanged: it does not inspect, copy, cache, or normalize
-- any result or source identifier.

local function GetMethod(name)
    local api = _G.C_DamageMeter
    if type(api) ~= "table" then return end

    local method = api[name]
    if type(method) ~= "function" then return end

    return method
end

local function GetSessionType(name)
    local enums = _G.Enum
    if type(enums) ~= "table" then return end

    local sessionTypes = enums.DamageMeterSessionType
    if type(sessionTypes) ~= "table" then return end

    return sessionTypes[name]
end

function Data.IsAvailable()
    local method = GetMethod("IsDamageMeterAvailable")
    if not method then return false end

    return method()
end

function Data.GetSession(sessionType, meterType)
    local method = GetMethod("GetCombatSessionFromType")
    if not method then return end

    return method(sessionType, meterType)
end

function Data.GetCurrentSession(meterType)
    local sessionType = GetSessionType("Current")
    if sessionType == nil then return end

    return Data.GetSession(sessionType, meterType)
end

function Data.GetOverallSession(meterType)
    local sessionType = GetSessionType("Overall")
    if sessionType == nil then return end

    return Data.GetSession(sessionType, meterType)
end

function Data.GetHistoricalSession(sessionID, meterType)
    local method = GetMethod("GetCombatSessionFromID")
    if not method then return end

    return method(sessionID, meterType)
end

function Data.GetSource(sessionType, meterType, sourceGUID, sourceCreatureID)
    local method = GetMethod("GetCombatSessionSourceFromType")
    if not method then return end

    return method(sessionType, meterType, sourceGUID, sourceCreatureID)
end

function Data.GetCurrentSource(meterType, sourceGUID, sourceCreatureID)
    local sessionType = GetSessionType("Current")
    if sessionType == nil then return end

    return Data.GetSource(sessionType, meterType, sourceGUID, sourceCreatureID)
end

function Data.GetOverallSource(meterType, sourceGUID, sourceCreatureID)
    local sessionType = GetSessionType("Overall")
    if sessionType == nil then return end

    return Data.GetSource(sessionType, meterType, sourceGUID, sourceCreatureID)
end

function Data.GetHistoricalSource(sessionID, meterType, sourceGUID, sourceCreatureID)
    local method = GetMethod("GetCombatSessionSourceFromID")
    if not method then return end

    return method(sessionID, meterType, sourceGUID, sourceCreatureID)
end

function Data.GetDuration(sessionType)
    local method = GetMethod("GetSessionDurationSeconds")
    if not method then return end

    return method(sessionType)
end

function Data.GetCurrentDuration()
    local sessionType = GetSessionType("Current")
    if sessionType == nil then return end

    return Data.GetDuration(sessionType)
end

function Data.GetOverallDuration()
    local sessionType = GetSessionType("Overall")
    if sessionType == nil then return end

    return Data.GetDuration(sessionType)
end

function Data.GetAvailableSessions()
    local method = GetMethod("GetAvailableCombatSessions")
    if not method then return end

    return method()
end

function Data.Reset()
    local method = GetMethod("ResetAllCombatSessions")
    if not method then return false end

    method()
    return true
end
