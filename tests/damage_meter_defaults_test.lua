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
    local state = {
        runtimeClearCalls = 0,
    }
    local damageMeter = {
        Renderer = {
            ClearRuntimeSessions = function()
                state.runtimeClearCalls = state.runtimeClearCalls + 1
            end,
        },
    }
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

    return damageMeter, callbacks, state
end

local function assertDefaults(config, message)
    local expectedWindowHeights = {138, 120, 120}
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
            config.windowSessions[index].mode,
            "current",
            message .. " window " .. index .. " session mode"
        )
        assertEqual(
            config.windowSessions[index].sessionID,
            nil,
            message .. " window " .. index .. " session id"
        )
        assertEqual(
            config.windowSyncSessions[index],
            true,
            message .. " window " .. index .. " session sync"
        )
        assertEqual(
            config.windowAutoCurrentOnCombat[index],
            true,
            message .. " window " .. index .. " combat automation"
        )
        assertEqual(
            config.windowAutoCurrentOnMythicPlusStart[index],
            false,
            message .. " window " .. index .. " key-start session"
        )
        assertEqual(
            config.windowAutoOverallOnMythicPlusComplete[index],
            false,
            message .. " window " .. index .. " key-complete session"
        )
        assertEqual(
            config.mythicPlusWindowTypes[index],
            false,
            message .. " window " .. index .. " key-start type"
        )
        assertEqual(
            config.windowHeights[index],
            expectedWindowHeights[index],
            message .. " window " .. index .. " height"
        )
    end
    assertEqual(
        config.resetOnMythicPlusStart,
        false,
        message .. " reset on key start"
    )
    assertEqual(config.alwaysShowPlayer, true, message .. " always show player")
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
    assertEqual(
        config.dockToObjectiveTracker,
        true,
        message .. " Objective Tracker docking"
    )
    assertEqual(config.locked, false, message .. " locked")
    assertEqual(config.width, 260, message .. " width")
    assertEqual(config.sizeDefaultsVersion, 1, message .. " size defaults version")
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
end

local DM, callbacks, state = loadDefaults()
local updateProfile = callbacks.BFI_UpdateProfile
assertEqual(type(updateProfile), "function", "profile callback registration")

local defaultsCopy = DM.GetDefaults()
assertDefaults(defaultsCopy, "defaults copy")
defaultsCopy.enabled = true
defaultsCopy.extra = true
defaultsCopy.windowTypes[1] = "DamageTaken"
defaultsCopy.windowSessions[1].mode = "overall"
defaultsCopy.windowSyncSessions[1] = false
defaultsCopy.windowAutoCurrentOnCombat[1] = false
defaultsCopy.windowAutoCurrentOnMythicPlusStart[1] = true
defaultsCopy.windowAutoOverallOnMythicPlusComplete[1] = true
defaultsCopy.mythicPlusWindowTypes[1] = "Deaths"
defaultsCopy.windowHeights[1] = 500
defaultsCopy.windowAnchors[1].x = 500
assertDefaults(DM.GetDefaults(), "independent defaults copy")

local missingProfile = {}
updateProfile(nil, missingProfile)
assertEqual(
    state.runtimeClearCalls,
    1,
    "profile update clears runtime historical sessions"
)
assertEqual(type(missingProfile.damageMeter), "table", "missing config replacement")
assertDefaults(missingProfile.damageMeter, "missing config")
assertEqual(DM.config, missingProfile.damageMeter, "missing config identity")
missingProfile.damageMeter.windowTypes[1] = "HealingDone"
missingProfile.damageMeter.windowSessions[1].mode = "overall"
missingProfile.damageMeter.windowSyncSessions[1] = false
missingProfile.damageMeter.windowAutoCurrentOnCombat[1] = false
missingProfile.damageMeter.windowAutoCurrentOnMythicPlusStart[1] = true
missingProfile.damageMeter.windowAutoOverallOnMythicPlusComplete[1] = true
missingProfile.damageMeter.mythicPlusWindowTypes[1] = "Deaths"
missingProfile.damageMeter.windowHeights[1] = 300
missingProfile.damageMeter.windowAnchors[1].x = 300
assertEqual(
    DM.GetDefaults().windowTypes[1],
    "DamageDone",
    "profile window types independent from defaults"
)
assertEqual(
    DM.GetDefaults().windowSessions[1].mode,
    "current",
    "profile window sessions independent from defaults"
)
assertEqual(
    DM.GetDefaults().windowSyncSessions[1],
    true,
    "profile sync settings independent from defaults"
)
assertEqual(
    DM.GetDefaults().windowAutoCurrentOnCombat[1],
    true,
    "profile combat automation independent from defaults"
)
assertEqual(
    DM.GetDefaults().windowAutoCurrentOnMythicPlusStart[1],
    false,
    "profile key-start session independent from defaults"
)
assertEqual(
    DM.GetDefaults().windowAutoOverallOnMythicPlusComplete[1],
    false,
    "profile key-complete session independent from defaults"
)
assertEqual(
    DM.GetDefaults().mythicPlusWindowTypes[1],
    false,
    "profile key-start type independent from defaults"
)
assertEqual(
    DM.GetDefaults().windowHeights[1],
    138,
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
assertEqual(partialConfig.locked, false, "partial lock default")
assertEqual(
    partialConfig.resetOnMythicPlusStart,
    false,
    "partial key-start reset default"
)
assertEqual(partialConfig.alwaysShowPlayer, true, "partial player pin default")
assertEqual(
    partialConfig.dockToObjectiveTracker,
    true,
    "untouched historical anchors migrate beside the Objective Tracker"
)
assertEqual(partialConfig.width, 260, "partial width default")
assertEqual(partialConfig.windowHeights[1], 138, "partial first height default")
assertEqual(partialConfig.windowHeights[2], 120, "partial second height default")
assertEqual(partialConfig.windowHeights[3], 120, "partial third height default")
assertEqual(partialConfig.extra, "preserved", "unknown config preserved")

local partialHeightsConfig = {
    windowHeights = {
        [2] = 199,
    },
}
updateProfile(nil, {
    damageMeter = partialHeightsConfig,
})
assertEqual(partialHeightsConfig.windowHeights[1], 138, "missing first height")
assertEqual(partialHeightsConfig.windowHeights[2], 199, "saved second height")
assertEqual(partialHeightsConfig.windowHeights[3], 120, "missing third height")

local previousDefaultsConfig = {
    width = 300,
    windowHeights = {
        147,
        134,
        134,
    },
}
updateProfile(nil, {
    damageMeter = previousDefaultsConfig,
})
assertEqual(previousDefaultsConfig.width, 260,
    "previous default width migrates to compact width")
assertEqual(previousDefaultsConfig.windowHeights[1], 138,
    "previous first default height migrates")
assertEqual(previousDefaultsConfig.windowHeights[2], 120,
    "previous second default height migrates")
assertEqual(previousDefaultsConfig.windowHeights[3], 120,
    "previous third default height migrates")
assertEqual(previousDefaultsConfig.sizeDefaultsVersion, 1,
    "previous default sizes record migration")
updateProfile(nil, {
    damageMeter = previousDefaultsConfig,
})
assertEqual(previousDefaultsConfig.width, 260,
    "default size migration is idempotent")

local historicalWindowDefaultsConfig = {
    width = 300,
    windowHeights = {
        220,
        220,
        220,
    },
}
updateProfile(nil, {
    damageMeter = historicalWindowDefaultsConfig,
})
assertEqual(historicalWindowDefaultsConfig.width, 260,
    "historical default width migrates")
assertEqual(historicalWindowDefaultsConfig.windowHeights[1], 138,
    "historical window defaults migrate")

local historicalScalarDefaultConfig = {
    width = 300,
    height = 220,
}
updateProfile(nil, {
    damageMeter = historicalScalarDefaultConfig,
})
assertEqual(historicalScalarDefaultConfig.width, 260,
    "historical scalar default width migrates")
assertEqual(historicalScalarDefaultConfig.height, nil,
    "historical scalar default is removed")
assertEqual(historicalScalarDefaultConfig.windowHeights[1], 138,
    "historical scalar default uses compact first height")
assertEqual(historicalScalarDefaultConfig.windowHeights[2], 120,
    "historical scalar default uses compact stacked height")

local customWidthConfig = {
    width = 280,
    windowHeights = {
        147,
        134,
        134,
    },
}
updateProfile(nil, {
    damageMeter = customWidthConfig,
})
assertEqual(customWidthConfig.width, 280,
    "custom width preserves the complete saved size")
assertEqual(customWidthConfig.windowHeights[1], 147,
    "custom width preserves previous saved heights")

local customHeightConfig = {
    width = 300,
    windowHeights = {
        147,
        199,
        134,
    },
}
updateProfile(nil, {
    damageMeter = customHeightConfig,
})
assertEqual(customHeightConfig.width, 300,
    "custom height preserves the saved width")
assertEqual(customHeightConfig.windowHeights[1], 147,
    "custom height preserves the first saved height")
assertEqual(customHeightConfig.windowHeights[2], 199,
    "custom height remains unchanged")
assertEqual(customHeightConfig.windowHeights[3], 134,
    "custom height preserves the third saved height")

local versionedPreviousDefaultsConfig = {
    sizeDefaultsVersion = 1,
    width = 300,
    windowHeights = {
        147,
        134,
        134,
    },
}
updateProfile(nil, {
    damageMeter = versionedPreviousDefaultsConfig,
})
assertEqual(versionedPreviousDefaultsConfig.width, 300,
    "versioned user-selected width is preserved")
assertEqual(versionedPreviousDefaultsConfig.windowHeights[1], 147,
    "versioned user-selected heights are preserved")

local customAnchorConfig = {
    windowAnchors = {
        {
            relativeTo = 0,
            point = "BOTTOMLEFT",
            relativePoint = "BOTTOMLEFT",
            x = 111,
            y = 222,
        },
        {
            relativeTo = 1,
            point = "BOTTOMRIGHT",
            relativePoint = "TOPRIGHT",
            x = 0,
            y = 4,
        },
        {
            relativeTo = 2,
            point = "BOTTOMRIGHT",
            relativePoint = "TOPRIGHT",
            x = 0,
            y = 4,
        },
    },
}
updateProfile(nil, {
    damageMeter = customAnchorConfig,
})
assertEqual(
    customAnchorConfig.dockToObjectiveTracker,
    false,
    "saved custom anchors do not migrate"
)
assertAnchor(customAnchorConfig.windowAnchors[1], {
    relativeTo = 0,
    point = "BOTTOMLEFT",
    relativePoint = "BOTTOMLEFT",
    x = 111,
    y = 222,
}, "saved custom root anchor")

local explicitOptOutConfig = {
    dockToObjectiveTracker = false,
}
updateProfile(nil, {
    damageMeter = explicitOptOutConfig,
})
assertEqual(
    explicitOptOutConfig.dockToObjectiveTracker,
    false,
    "explicit tracker docking opt-out survives normalization"
)
assertAnchor(
    explicitOptOutConfig.windowAnchors[1],
    DM.GetDefaults().windowAnchors[1],
    "explicit opt-out keeps the historical root anchor"
)

local invalidConfig = {
    alwaysShowPlayer = "yes",
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
    resetOnMythicPlusStart = "yes",
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
    windowSessions = {
        {
            mode = "history",
            sessionID = 0,
            name = "must not persist",
        },
        {
            mode = "history",
            sessionID = 12.9,
            durationSeconds = 60,
        },
        {
            mode = "overall",
            sessionID = 99,
        },
    },
    windowSyncSessions = {
        "yes",
        false,
        true,
    },
    windowAutoCurrentOnCombat = {
        false,
        "yes",
        true,
    },
    windowAutoCurrentOnMythicPlusStart = {
        true,
        "yes",
        false,
    },
    windowAutoOverallOnMythicPlusComplete = {
        true,
        false,
        "yes",
    },
    mythicPlusWindowTypes = {
        "invalid",
        "Absorbs",
        false,
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
assertEqual(invalidConfig.windowSessions[1].mode, "current", "invalid history")
assertEqual(invalidConfig.windowSessions[1].sessionID, nil, "invalid history id")
assertEqual(invalidConfig.windowSessions[1].name, nil, "session name discarded")
assertEqual(
    invalidConfig.windowSessions[2].mode,
    "current",
    "stored history migrates to current"
)
assertEqual(
    invalidConfig.windowSessions[2].sessionID,
    nil,
    "stored history id discarded"
)
assertEqual(
    invalidConfig.windowSessions[2].durationSeconds,
    nil,
    "session duration discarded"
)
assertEqual(
    invalidConfig.windowSessions[3].mode,
    "overall",
    "overall mode preserved"
)
assertEqual(
    invalidConfig.windowSessions[3].sessionID,
    nil,
    "overall session id discarded"
)
assertEqual(invalidConfig.windowSyncSessions[1], true, "invalid sync default")
assertEqual(invalidConfig.windowSyncSessions[2], false, "valid sync preserved")
assertEqual(
    invalidConfig.windowAutoCurrentOnCombat[1],
    false,
    "valid combat automation preserved"
)
assertEqual(
    invalidConfig.windowAutoCurrentOnCombat[2],
    true,
    "invalid combat automation default"
)
assertEqual(
    invalidConfig.windowAutoCurrentOnMythicPlusStart[1],
    true,
    "valid key-start session preserved"
)
assertEqual(
    invalidConfig.windowAutoCurrentOnMythicPlusStart[2],
    false,
    "invalid key-start session default"
)
assertEqual(
    invalidConfig.windowAutoOverallOnMythicPlusComplete[1],
    true,
    "valid key-complete session preserved"
)
assertEqual(
    invalidConfig.windowAutoOverallOnMythicPlusComplete[3],
    false,
    "invalid key-complete session default"
)
assertEqual(
    invalidConfig.mythicPlusWindowTypes[1],
    false,
    "invalid key-start type default"
)
assertEqual(
    invalidConfig.mythicPlusWindowTypes[2],
    "Absorbs",
    "valid key-start type preserved"
)
assertEqual(
    invalidConfig.resetOnMythicPlusStart,
    false,
    "invalid key-start reset default"
)
assertEqual(
    invalidConfig.alwaysShowPlayer,
    true,
    "invalid player pin default"
)
assertEqual(
    invalidConfig.dockToObjectiveTracker,
    false,
    "non-default normalized anchors remain screen-relative"
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
assertEqual(
    cyclicAnchorsConfig.dockToObjectiveTracker,
    true,
    "repaired default stack docks beside the Objective Tracker"
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
configIdentity.extra = "remove"
configIdentity.windowTypes[1] = "DamageTaken"
configIdentity.windowSessions[1].mode = "overall"
configIdentity.windowSyncSessions[1] = false
configIdentity.windowAutoCurrentOnCombat[1] = false
configIdentity.windowAutoCurrentOnMythicPlusStart[1] = true
configIdentity.windowAutoOverallOnMythicPlusComplete[1] = true
configIdentity.mythicPlusWindowTypes[1] = "Deaths"
configIdentity.windowHeights[1] = 500
configIdentity.windowAnchors[1].x = 500
local runtimeClearsBeforeReset = state.runtimeClearCalls
DM.ResetToDefaults()
assertEqual(
    state.runtimeClearCalls,
    runtimeClearsBeforeReset + 1,
    "defaults reset clears runtime historical sessions"
)
assertEqual(DM.config, configIdentity, "reset config identity")
assertDefaults(DM.config, "reset config")
assertEqual(DM.config.extra, nil, "reset removes unknown config")

print("damage_meter_defaults_test.lua: ok")
