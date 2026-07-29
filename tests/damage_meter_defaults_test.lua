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
    assertEqual(config.windowCount, 3, message .. " window count")
    assertEqual(
        config.windowTypes[1],
        "DamageDone",
        message .. " first window type"
    )
    assertEqual(
        config.windowTypes[2],
        "HealingDone",
        message .. " second window type"
    )
    assertEqual(
        config.windowTypes[3],
        "DamageTaken",
        message .. " third window type"
    )
    assertEqual(config.width, 300, message .. " width")
    assertEqual(config.height, 220, message .. " height")
    assertEqual(config.headerHeight, 22, message .. " header height")
    assertEqual(config.barHeight, 20, message .. " bar height")
    assertEqual(config.spacing, 2, message .. " spacing")
    assertEqual(config.padding, 4, message .. " padding")
    assertEqual(config.texture, "AF", message .. " texture")
    assertEqual(config.numberMode, "both", message .. " number mode")
    assertEqual(config.showSpecIcon, true, message .. " spec icon")
    assertEqual(config.classColor, true, message .. " class color")
    assertEqual(config.backgroundAlpha, 0.82, message .. " background alpha")
    assertEqual(config.barAlpha, 0.9, message .. " bar alpha")
    assertEqual(config.accentHeader, true, message .. " accent header")
end

local DM, callbacks = loadDefaults()
local updateProfile = callbacks.BFI_UpdateProfile
assertEqual(type(updateProfile), "function", "profile callback registration")

local defaultsCopy = DM.GetDefaults()
assertDefaults(defaultsCopy, "defaults copy")
defaultsCopy.enabled = true
defaultsCopy.extra = true
defaultsCopy.windowTypes[1] = "DamageTaken"
assertDefaults(DM.GetDefaults(), "independent defaults copy")

local missingProfile = {}
updateProfile(nil, missingProfile)
assertEqual(type(missingProfile.damageMeter), "table", "missing config replacement")
assertDefaults(missingProfile.damageMeter, "missing config")
assertEqual(DM.config, missingProfile.damageMeter, "missing config identity")
missingProfile.damageMeter.windowTypes[1] = "HealingDone"
assertEqual(
    DM.GetDefaults().windowTypes[1],
    "DamageDone",
    "profile window types independent from defaults"
)

local malformedProfile = {
    damageMeter = "invalid",
}
updateProfile(nil, malformedProfile)
assertEqual(type(malformedProfile.damageMeter), "table", "malformed config replacement")
assertDefaults(malformedProfile.damageMeter, "malformed config")
assertEqual(DM.config, malformedProfile.damageMeter, "malformed config identity")

local partialConfig = {
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
assertEqual(partialConfig.extra, "preserved", "unknown config preserved")

local invalidConfig = {
    accentHeader = 1,
    backgroundAlpha = -1,
    barAlpha = 2,
    barHeight = 100,
    classColor = "yes",
    enabled = "yes",
    headerHeight = 1,
    height = 1000,
    nativeEnabledBeforeBFI = true,
    numberMode = "verbose",
    padding = 99,
    showSpecIcon = 1,
    spacing = -10,
    texture = "",
    width = 10,
    windowCount = 20,
    windowTypes = {
        "invalid",
        "HealingDone",
    },
}
updateProfile(nil, {
    damageMeter = invalidConfig,
})
assertEqual(invalidConfig.enabled, false, "invalid enabled normalization")
assertEqual(invalidConfig.windowCount, 3, "window count clamp")
assertEqual(invalidConfig.windowTypes[1], "DamageDone", "window one type")
assertEqual(invalidConfig.windowTypes[2], "HealingDone", "window two type")
assertEqual(invalidConfig.windowTypes[3], "DamageTaken", "window three type")
assertEqual(invalidConfig.width, 220, "width clamp")
assertEqual(invalidConfig.height, 520, "height clamp")
assertEqual(
    invalidConfig.nativeEnabledBeforeBFI,
    nil,
    "legacy native restore metadata removed from profile"
)
assertEqual(invalidConfig.headerHeight, 18, "header height clamp")
assertEqual(invalidConfig.barHeight, 36, "bar height clamp")
assertEqual(invalidConfig.spacing, 0, "spacing clamp")
assertEqual(invalidConfig.padding, 12, "padding clamp")
assertEqual(invalidConfig.texture, "AF", "texture normalization")
assertEqual(invalidConfig.numberMode, "both", "number mode normalization")
assertEqual(invalidConfig.showSpecIcon, true, "spec icon normalization")
assertEqual(invalidConfig.classColor, true, "class color normalization")
assertEqual(invalidConfig.backgroundAlpha, 0, "background alpha clamp")
assertEqual(invalidConfig.barAlpha, 1, "bar alpha clamp")
assertEqual(invalidConfig.accentHeader, true, "accent normalization")

local configIdentity = DM.config
configIdentity.enabled = true
configIdentity.accentHeader = false
configIdentity.extra = "remove"
configIdentity.windowTypes[1] = "DamageTaken"
DM.ResetToDefaults()
assertEqual(DM.config, configIdentity, "reset config identity")
assertDefaults(DM.config, "reset config")
assertEqual(DM.config.extra, nil, "reset removes unknown config")

print("damage_meter_defaults_test.lua: ok")
