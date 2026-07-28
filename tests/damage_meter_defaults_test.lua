local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function copyTable(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function loadDefaults()
    local callbacks = {}
    local damageMeter = {}
    local BFI = {
        modules = {
            DamageMeter = damageMeter,
        },
    }
    local AF = {
        Copy = copyTable,
        Merge = function(target, source)
            for key, value in pairs(source) do
                target[key] = value
            end
        end,
        RegisterCallback = function(name, callback)
            callbacks[name] = callback
        end,
    }
    local environment = {
        AbstractFramework = AF,
        math = math,
        next = next,
        select = select,
        tonumber = tonumber,
        type = type,
        wipe = function(target)
            for key in pairs(target) do
                target[key] = nil
            end
        end,
    }
    environment._G = environment

    local chunk, loadError = loadfile("Modules/DamageMeter/Defaults.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return damageMeter, callbacks
end

local function assertDefaults(config, message)
    assertEqual(config.enabled, false, message .. " enabled")
    assertEqual(config.accentHeader, true, message .. " accent header")
    assertEqual(config.barTexture, "AF", message .. " bar texture")
    assertEqual(config.barBackgroundAlpha, 0.65, message .. " background alpha")
end

local DM, callbacks = loadDefaults()
local updateProfile = callbacks.BFI_UpdateProfile
assertEqual(type(updateProfile), "function", "profile callback registration")

local defaultsCopy = DM.GetDefaults()
assertDefaults(defaultsCopy, "defaults copy")
defaultsCopy.enabled = true
defaultsCopy.extra = true
assertDefaults(DM.GetDefaults(), "independent defaults copy")

local missingProfile = {}
updateProfile(nil, missingProfile)
assertEqual(type(missingProfile.damageMeter), "table", "missing config replacement")
assertDefaults(missingProfile.damageMeter, "missing config")
assertEqual(DM.config, missingProfile.damageMeter, "missing config identity")

local malformedProfile = {
    damageMeter = "invalid",
}
updateProfile(nil, malformedProfile)
assertEqual(type(malformedProfile.damageMeter), "table", "malformed config replacement")
assertDefaults(malformedProfile.damageMeter, "malformed config")
assertEqual(DM.config, malformedProfile.damageMeter, "malformed config identity")

local partialConfig = {
    barBackgroundAlpha = "0.25",
    barTexture = "Custom",
    extra = "preserved",
}
local partialProfile = {
    damageMeter = partialConfig,
}
updateProfile(nil, partialProfile)
assertEqual(partialProfile.damageMeter, partialConfig, "partial config identity")
assertEqual(DM.config, partialConfig, "active partial config identity")
assertEqual(partialConfig.enabled, false, "partial enabled default")
assertEqual(partialConfig.accentHeader, true, "partial accent default")
assertEqual(partialConfig.barTexture, "Custom", "valid texture preserved")
assertEqual(partialConfig.barBackgroundAlpha, 0.25, "numeric alpha normalized")
assertEqual(partialConfig.extra, "preserved", "unknown config preserved")

local invalidConfig = {
    accentHeader = 1,
    barBackgroundAlpha = "invalid",
    barTexture = "",
    enabled = "yes",
}
updateProfile(nil, {
    damageMeter = invalidConfig,
})
assertDefaults(invalidConfig, "invalid field normalization")

invalidConfig.barBackgroundAlpha = -0.5
updateProfile(nil, {
    damageMeter = invalidConfig,
})
assertEqual(invalidConfig.barBackgroundAlpha, 0, "alpha lower clamp")

invalidConfig.barBackgroundAlpha = 1.5
updateProfile(nil, {
    damageMeter = invalidConfig,
})
assertEqual(invalidConfig.barBackgroundAlpha, 1, "alpha upper clamp")

local configIdentity = DM.config
configIdentity.enabled = true
configIdentity.accentHeader = false
configIdentity.barTexture = "Other"
configIdentity.barBackgroundAlpha = 0
configIdentity.extra = "remove"
DM.ResetToDefaults()
assertEqual(DM.config, configIdentity, "reset config identity")
assertDefaults(DM.config, "reset config")
assertEqual(DM.config.extra, nil, "reset removes unknown config")

print("damage_meter_defaults_test.lua: ok")
