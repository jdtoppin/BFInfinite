local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for key, child in pairs(value) do
        copy[deepCopy(key)] = deepCopy(child)
    end
    return copy
end

local function merge(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then
            merge(target[key], value)
        else
            target[key] = deepCopy(value)
        end
    end
    return target
end

local function mergeMissingDefaults(config, defaults)
    if type(config) ~= "table" then config = {} end

    for key, defaultValue in pairs(defaults) do
        if type(defaultValue) == "table" then
            config[key] = mergeMissingDefaults(config[key], defaultValue)
        elseif config[key] == nil then
            config[key] = defaultValue
        end
    end
    return config
end

local callbacks = {}
local AF = {
    ConvertHEXToRGB = function()
        return 1, 1, 1, 1
    end,
    Copy = function(...)
        local copy = {}
        for index = 1, select("#", ...) do
            merge(copy, select(index, ...))
        end
        return copy
    end,
    GetColorTable = function(_, alpha)
        return {1, 1, 1, alpha or 1}
    end,
    Merge = merge,
    RegisterCallback = function(event, callback)
        callbacks[event] = callback
    end,
}

local F = {
    GetCVarNumber = function()
        return 0
    end,
    MergeMissingDefaults = mergeMissingDefaults,
}

local NP = {}
local BFI = {
    funcs = F,
    modules = {
        Nameplates = NP,
    },
}
local environment = setmetatable({
    _G = false,
    AbstractFramework = AF,
    wipe = function(value)
        for key in pairs(value) do
            value[key] = nil
        end
    end,
}, {__index = _G})
environment._G = environment

local chunk, loadError = loadfile("Modules/Nameplates/Defaults.lua")
assertEqual(type(chunk), "function", loadError or "defaults module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local updateProfile = callbacks.BFI_UpdateProfile
assertEqual(type(updateProfile), "function", "profile callback")
assertEqual(NP.GetDefaults().enabled, true, "shipped default")

local freshProfile = {}
updateProfile(nil, freshProfile)
assertEqual(freshProfile.nameplates.enabled, true,
    "fresh profile receives enabled default")
assertEqual(freshProfile.nameplates.schemaVersion, NP.SCHEMA_VERSION,
    "fresh profile receives current schema")

local optedOutProfile = {
    nameplates = {
        enabled = false,
        schemaVersion = NP.SCHEMA_VERSION,
    },
}
updateProfile(nil, optedOutProfile)
assertEqual(optedOutProfile.nameplates.enabled, false,
    "existing opt-out is preserved")

local legacyProfile = {
    nameplates = {},
}
updateProfile(nil, legacyProfile)
assertEqual(legacyProfile.nameplates.enabled, false,
    "existing legacy profile retains the prior opt-in behavior")

local malformedProfile = {
    nameplates = "invalid",
}
updateProfile(nil, malformedProfile)
assertEqual(malformedProfile.nameplates.enabled, true,
    "malformed config receives the shipped default")

print("nameplate_defaults_test.lua: ok")
