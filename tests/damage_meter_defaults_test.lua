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

local function assertAnchor(actual, expected, message)
    assertEqual(actual.relativeTo, expected.relativeTo, message .. " target")
    assertEqual(actual.point, expected.point, message .. " point")
    assertEqual(
        actual.relativePoint,
        expected.relativePoint,
        message .. " relative point"
    )
    assertEqual(actual.x, expected.x, message .. " x")
    assertEqual(actual.y, expected.y, message .. " y")
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
    for index = 1, 3 do
        assertEqual(
            config.windowHeights[index],
            220,
            message .. " window " .. index .. " height"
        )
    end
    assertAnchor(config.windowAnchors[1], {
        relativeTo = 0,
        point = "BOTTOMRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = -4,
        y = 4,
    }, message .. " first anchor")
    assertAnchor(config.windowAnchors[2], {
        relativeTo = 1,
        point = "BOTTOMRIGHT",
        relativePoint = "TOPRIGHT",
        x = 0,
        y = 4,
    }, message .. " second anchor")
    assertAnchor(config.windowAnchors[3], {
        relativeTo = 2,
        point = "BOTTOMRIGHT",
        relativePoint = "TOPRIGHT",
        x = 0,
        y = 4,
    }, message .. " third anchor")
    assertEqual(config.locked, false, message .. " locked")
    assertEqual(config.width, 300, message .. " width")
    assertEqual(config.height, nil, message .. " legacy height removed")
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
defaultsCopy.windowHeights[1] = 500
defaultsCopy.windowAnchors[1].x = 500
assertDefaults(DM.GetDefaults(), "independent defaults copy")

local missingProfile = {}
updateProfile(nil, missingProfile)
assertEqual(type(missingProfile.damageMeter), "table", "missing config replacement")
assertDefaults(missingProfile.damageMeter, "missing config")
assertEqual(DM.config, missingProfile.damageMeter, "missing config identity")
missingProfile.damageMeter.windowTypes[1] = "HealingDone"
missingProfile.damageMeter.windowHeights[1] = 300
missingProfile.damageMeter.windowAnchors[1].x = 300
assertEqual(
    DM.GetDefaults().windowTypes[1],
    "DamageDone",
    "profile window types independent from defaults"
)
assertEqual(
    DM.GetDefaults().windowHeights[1],
    220,
    "profile window heights independent from defaults"
)
assertEqual(
    DM.GetDefaults().windowAnchors[1].x,
    -4,
    "profile window anchors independent from defaults"
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
assertEqual(partialConfig.locked, false, "partial lock default")
assertEqual(partialConfig.extra, "preserved", "unknown config preserved")

local invalidConfig = {
    accentHeader = 1,
    backgroundAlpha = -1,
    barAlpha = 2,
    barHeight = 100,
    classColor = "yes",
    enabled = "yes",
    headerHeight = 1,
    height = 410,
    locked = "yes",
    nativeEnabledBeforeBFI = true,
    numberMode = "verbose",
    padding = 99,
    showSpecIcon = 1,
    spacing = -10,
    texture = "",
    width = 10,
    windowCount = 20,
    windowAnchors = {
        {
            relativeTo = 1,
            point = "invalid",
            relativePoint = "invalid",
            x = -5000,
            y = 5000,
        },
        {
            relativeTo = 3,
            point = "TOPLEFT",
            relativePoint = "BOTTOMRIGHT",
            x = 15.5,
            y = -20,
        },
        {
            relativeTo = 0,
            point = "CENTER",
            relativePoint = "CENTER",
            x = 30,
            y = 40,
        },
    },
    windowHeights = {
        99,
        "bad",
        600,
    },
    windowTypes = {
        "invalid",
        "Absorbs",
        "EnemyDamageTaken",
    },
}
updateProfile(nil, {
    damageMeter = invalidConfig,
})
assertEqual(invalidConfig.enabled, false, "invalid enabled normalization")
assertEqual(invalidConfig.windowCount, 3, "window count clamp")
assertEqual(invalidConfig.windowTypes[1], "DamageDone", "window one type")
assertEqual(invalidConfig.windowTypes[2], "Absorbs", "window two type")
assertEqual(
    invalidConfig.windowTypes[3],
    "EnemyDamageTaken",
    "window three type"
)
assertEqual(invalidConfig.width, 220, "width clamp")
assertEqual(invalidConfig.height, nil, "legacy height removed")
assertEqual(invalidConfig.windowHeights[1], 120, "window one height clamp")
assertEqual(invalidConfig.windowHeights[2], 410, "window two legacy height")
assertEqual(invalidConfig.windowHeights[3], 520, "window three height clamp")
assertEqual(invalidConfig.locked, false, "lock normalization")
assertAnchor(invalidConfig.windowAnchors[1], {
    relativeTo = 0,
    point = "BOTTOMRIGHT",
    relativePoint = "BOTTOMRIGHT",
    x = -4096,
    y = 4096,
}, "invalid first anchor normalization")
assertAnchor(invalidConfig.windowAnchors[2], {
    relativeTo = 3,
    point = "TOPLEFT",
    relativePoint = "BOTTOMRIGHT",
    x = 15.5,
    y = -20,
}, "valid second anchor preservation")
assertAnchor(invalidConfig.windowAnchors[3], {
    relativeTo = 0,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 30,
    y = 40,
}, "valid third anchor preservation")
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

local legacyHeightConfig = {
    height = 277,
}
updateProfile(nil, {
    damageMeter = legacyHeightConfig,
})
assertEqual(legacyHeightConfig.height, nil, "legacy scalar height removed")
for index = 1, 3 do
    assertEqual(
        legacyHeightConfig.windowHeights[index],
        277,
        "legacy scalar height migrated to window " .. index
    )
end

local cyclicAnchorsConfig = {
    windowAnchors = {
        {
            relativeTo = 2,
            point = "TOP",
            relativePoint = "BOTTOM",
            x = 10,
            y = 10,
        },
        {
            relativeTo = 1,
            point = "BOTTOM",
            relativePoint = "TOP",
            x = 20,
            y = 20,
        },
        {
            relativeTo = 0,
            point = "CENTER",
            relativePoint = "CENTER",
            x = 30,
            y = 30,
        },
    },
}
updateProfile(nil, {
    damageMeter = cyclicAnchorsConfig,
})
assertAnchor(
    cyclicAnchorsConfig.windowAnchors[1],
    DM.GetDefaults().windowAnchors[1],
    "cycle fallback first anchor"
)
assertAnchor(
    cyclicAnchorsConfig.windowAnchors[2],
    DM.GetDefaults().windowAnchors[2],
    "cycle fallback second anchor"
)
assertAnchor(
    cyclicAnchorsConfig.windowAnchors[3],
    DM.GetDefaults().windowAnchors[3],
    "cycle fallback third anchor"
)

local validWindowTypes = {
    "DamageDone",
    "Dps",
    "HealingDone",
    "Hps",
    "Absorbs",
    "Interrupts",
    "Dispels",
    "DamageTaken",
    "AvoidableDamageTaken",
    "Deaths",
    "EnemyDamageTaken",
}
for _, windowType in ipairs(validWindowTypes) do
    local typeConfig = {
        windowTypes = {
            windowType,
            "HealingDone",
            "DamageTaken",
        },
    }
    updateProfile(nil, {
        damageMeter = typeConfig,
    })
    assertEqual(
        typeConfig.windowTypes[1],
        windowType,
        windowType .. " remains a valid window type"
    )
end

local configIdentity = DM.config
configIdentity.enabled = true
configIdentity.accentHeader = false
configIdentity.extra = "remove"
configIdentity.windowTypes[1] = "DamageTaken"
configIdentity.windowHeights[1] = 500
configIdentity.windowAnchors[1].x = 500
DM.ResetToDefaults()
assertEqual(DM.config, configIdentity, "reset config identity")
assertDefaults(DM.config, "reset config")
assertEqual(DM.config.extra, nil, "reset removes unknown config")

print("damage_meter_defaults_test.lua: ok")
