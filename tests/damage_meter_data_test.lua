local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertCall(calls, index, name, ...)
    local call = calls[index]
    assertEqual(type(call), "table", name .. " call")
    assertEqual(call.name, name, name .. " method")
    assertEqual(call.count, select("#", ...), name .. " argument count")

    for i = 1, call.count do
        assertEqual(call.args[i], select(i, ...), name .. " argument " .. i)
    end
end

local function loadAdapter(api, enums)
    local damageMeter = {}
    local BFI = {
        modules = {
            DamageMeter = damageMeter,
        },
    }
    local environment = {
        C_DamageMeter = api,
        Enum = enums,
        error = error,
        select = select,
        type = type,
    }
    environment._G = environment

    local chunk, loadError = loadfile("Modules/DamageMeter/Data.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return damageMeter.Data
end

local function record(calls, name, ...)
    calls[#calls + 1] = {
        args = {...},
        count = select("#", ...),
        name = name,
    }
end

local calls = {}
local currentType = {}
local overallType = {}
local customType = {}
local meterType = {}
local sessionID = {}
local sourceGUID = {}
local sourceCreatureID = {}
local sessionResult = {
    opaqueField = {},
}
local historicalSessionResult = {
    opaqueField = {},
}
local sourceResult = {
    opaqueField = {},
}
local historicalSourceResult = {
    opaqueField = {},
}
local durationResult = {}
local availableSessionsResult = {
    {
        opaqueField = {},
    },
}
local resetCalls = 0

local api = {
    GetAvailableCombatSessions = function()
        record(calls, "GetAvailableCombatSessions")
        return availableSessionsResult
    end,
    GetCombatSessionFromID = function(...)
        record(calls, "GetCombatSessionFromID", ...)
        return historicalSessionResult
    end,
    GetCombatSessionFromType = function(...)
        record(calls, "GetCombatSessionFromType", ...)
        return sessionResult
    end,
    GetCombatSessionSourceFromID = function(...)
        record(calls, "GetCombatSessionSourceFromID", ...)
        return historicalSourceResult
    end,
    GetCombatSessionSourceFromType = function(...)
        record(calls, "GetCombatSessionSourceFromType", ...)
        return sourceResult
    end,
    GetSessionDurationSeconds = function(...)
        record(calls, "GetSessionDurationSeconds", ...)
        return durationResult
    end,
    IsDamageMeterAvailable = function()
        record(calls, "IsDamageMeterAvailable")
        return true, ""
    end,
    ResetAllCombatSessions = function()
        record(calls, "ResetAllCombatSessions")
        resetCalls = resetCalls + 1
    end,
}
local enums = {
    DamageMeterSessionType = {
        Current = currentType,
        Overall = overallType,
    },
}
local Data = loadAdapter(api, enums)

local available, failureReason = Data.IsAvailable()
assertEqual(available, true, "native availability")
assertEqual(failureReason, "", "native availability reason")
assertCall(calls, 1, "IsDamageMeterAvailable")

assertEqual(Data.GetCurrentSession(meterType), sessionResult, "current session identity")
assertCall(calls, 2, "GetCombatSessionFromType", currentType, meterType)

assertEqual(Data.GetOverallSession(meterType), sessionResult, "overall session identity")
assertCall(calls, 3, "GetCombatSessionFromType", overallType, meterType)

assertEqual(Data.GetSession(customType, meterType), sessionResult, "typed session identity")
assertCall(calls, 4, "GetCombatSessionFromType", customType, meterType)

assertEqual(
    Data.GetHistoricalSession(sessionID, meterType),
    historicalSessionResult,
    "historical session identity"
)
assertCall(calls, 5, "GetCombatSessionFromID", sessionID, meterType)

assertEqual(
    Data.GetCurrentSource(meterType, sourceGUID, sourceCreatureID),
    sourceResult,
    "current source identity"
)
assertCall(
    calls,
    6,
    "GetCombatSessionSourceFromType",
    currentType,
    meterType,
    sourceGUID,
    sourceCreatureID
)

assertEqual(
    Data.GetOverallSource(meterType, sourceGUID, sourceCreatureID),
    sourceResult,
    "overall source identity"
)
assertCall(
    calls,
    7,
    "GetCombatSessionSourceFromType",
    overallType,
    meterType,
    sourceGUID,
    sourceCreatureID
)

assertEqual(
    Data.GetSource(customType, meterType, sourceGUID, sourceCreatureID),
    sourceResult,
    "typed source identity"
)
assertCall(
    calls,
    8,
    "GetCombatSessionSourceFromType",
    customType,
    meterType,
    sourceGUID,
    sourceCreatureID
)

assertEqual(
    Data.GetHistoricalSource(sessionID, meterType, sourceGUID, sourceCreatureID),
    historicalSourceResult,
    "historical source identity"
)
assertCall(
    calls,
    9,
    "GetCombatSessionSourceFromID",
    sessionID,
    meterType,
    sourceGUID,
    sourceCreatureID
)

assertEqual(Data.GetDuration(customType), durationResult, "typed duration identity")
assertCall(calls, 10, "GetSessionDurationSeconds", customType)

assertEqual(Data.GetCurrentDuration(), durationResult, "current duration identity")
assertCall(calls, 11, "GetSessionDurationSeconds", currentType)

assertEqual(Data.GetOverallDuration(), durationResult, "overall duration identity")
assertCall(calls, 12, "GetSessionDurationSeconds", overallType)

assertEqual(
    Data.GetAvailableSessions(),
    availableSessionsResult,
    "available sessions identity"
)
assertCall(calls, 13, "GetAvailableCombatSessions")

assertEqual(Data.Reset(), true, "reset dispatch result")
assertEqual(resetCalls, 1, "reset dispatch count")
assertCall(calls, 14, "ResetAllCombatSessions")

local unavailableData = loadAdapter(nil, nil)
local unavailable, unavailableReason = unavailableData.IsAvailable()
assertEqual(unavailable, false, "missing API availability")
assertEqual(unavailableReason, nil, "missing API availability reason")
assertEqual(unavailableData.GetCurrentSession(meterType), nil, "missing current session")
assertEqual(unavailableData.GetOverallSession(meterType), nil, "missing overall session")
assertEqual(unavailableData.GetSession(customType, meterType), nil, "missing typed session")
assertEqual(
    unavailableData.GetHistoricalSession(sessionID, meterType),
    nil,
    "missing historical session"
)
assertEqual(
    unavailableData.GetCurrentSource(meterType, sourceGUID, sourceCreatureID),
    nil,
    "missing current source"
)
assertEqual(
    unavailableData.GetOverallSource(meterType, sourceGUID, sourceCreatureID),
    nil,
    "missing overall source"
)
assertEqual(
    unavailableData.GetSource(customType, meterType, sourceGUID, sourceCreatureID),
    nil,
    "missing typed source"
)
assertEqual(
    unavailableData.GetHistoricalSource(
        sessionID,
        meterType,
        sourceGUID,
        sourceCreatureID
    ),
    nil,
    "missing historical source"
)
assertEqual(unavailableData.GetDuration(customType), nil, "missing typed duration")
assertEqual(unavailableData.GetCurrentDuration(), nil, "missing current duration")
assertEqual(unavailableData.GetOverallDuration(), nil, "missing overall duration")
assertEqual(unavailableData.GetAvailableSessions(), nil, "missing available sessions")
assertEqual(unavailableData.Reset(), false, "missing reset")

local missingEnumCalls = 0
local missingEnumData = loadAdapter({
    GetCombatSessionFromType = function()
        missingEnumCalls = missingEnumCalls + 1
    end,
    GetCombatSessionSourceFromType = function()
        missingEnumCalls = missingEnumCalls + 1
    end,
    GetSessionDurationSeconds = function()
        missingEnumCalls = missingEnumCalls + 1
    end,
}, {})
assertEqual(missingEnumData.GetCurrentSession(meterType), nil, "missing Current enum")
assertEqual(missingEnumData.GetOverallSession(meterType), nil, "missing Overall enum")
assertEqual(
    missingEnumData.GetCurrentSource(meterType, sourceGUID, sourceCreatureID),
    nil,
    "missing Current source enum"
)
assertEqual(
    missingEnumData.GetOverallSource(meterType, sourceGUID, sourceCreatureID),
    nil,
    "missing Overall source enum"
)
assertEqual(missingEnumData.GetCurrentDuration(), nil, "missing Current duration enum")
assertEqual(missingEnumData.GetOverallDuration(), nil, "missing Overall duration enum")
assertEqual(missingEnumCalls, 0, "missing enums do not dispatch")

local nativeFailureData = loadAdapter({
    IsDamageMeterAvailable = function()
        return false, "restricted"
    end,
}, enums)
local nativeAvailable, nativeReason = nativeFailureData.IsAvailable()
assertEqual(nativeAvailable, false, "native unavailable result")
assertEqual(nativeReason, "restricted", "native unavailable reason")

local nonFunctionData = loadAdapter({
    GetAvailableCombatSessions = true,
    IsDamageMeterAvailable = true,
    ResetAllCombatSessions = true,
}, enums)
assertEqual(nonFunctionData.IsAvailable(), false, "non-function availability")
assertEqual(nonFunctionData.GetAvailableSessions(), nil, "non-function sessions")
assertEqual(nonFunctionData.Reset(), false, "non-function reset")

print("damage_meter_data_test.lua: ok")
