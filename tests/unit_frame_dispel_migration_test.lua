local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local function copyInto(result, value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    seen[value] = result
    for key, child in pairs(value) do
        if type(child) == "table" then
            local target = type(result[key]) == "table"
                and result[key]
                or {}
            result[key] = copyInto(target, child, seen)
        else
            result[key] = child
        end
    end
    return result
end

local function copy(...)
    local result = {}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "table" then
            copyInto(result, value)
        end
    end
    return result
end

local function readFile(path)
    local file, openError = io.open(path, "rb")
    assertTrue(file, openError)
    local contents = file:read("*a")
    file:close()
    return contents
end

local function countPlain(haystack, needle)
    local count = 0
    local start = 1
    while true do
        local found = haystack:find(needle, start, true)
        if not found then return count end
        count = count + 1
        start = found + #needle
    end
end

local function loadPresets()
    local UF = {}
    local AF = {}

    function AF.Copy(...)
        return copy(...)
    end

    function AF.GetColorTable(name, alpha)
        return {
            name = name,
            alpha = alpha,
        }
    end

    function AF.Merge(target, source)
        return copyInto(target, source)
    end

    function AF.RegisterCallback()
    end

    local BFI = {
        L = setmetatable({}, {
            __index = function(_, key)
                return key
            end,
        }),
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        assert = assert,
        error = error,
        next = next,
        pairs = pairs,
        select = select,
        type = type,
        wipe = function(value)
            for key in pairs(value) do
                value[key] = nil
            end
        end,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected preset global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError =
        loadfile("Modules/UnitFrames/Presets.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
    return UF
end

local function testMigrationDefaultsAndLegacyMapping()
    local UF = loadPresets()
    assertEqual(UF.MigrateConfig(nil), nil,
        "missing module table remains a new profile")

    local existing = {}
    UF.MigrateConfig(existing)
    assertEqual(existing.party.indicators.dispels.enabled, false,
        "existing profile does not silently enable dispels")
    assertEqual(existing.raid.indicators.dispels.enabled, false,
        "existing profile does not silently enable Raid dispels")

    local legacy = {
        party = {
            indicators = {
                healthBar = {
                    dispelHighlight = {
                        enabled = true,
                        dispellable = false,
                        alpha = 0.7,
                        blendMode = "BLEND",
                    },
                },
            },
        },
    }
    UF.MigrateConfig(legacy)
    local migrated = legacy.party.indicators.dispels
    assertEqual(migrated.enabled, false,
        "legacy unrestricted mode is conservatively disabled")
    assertEqual(migrated.scope, "any",
        "legacy broad mode retains the nearest selectable scope")
    assertEqual(migrated.appearance, "full_solid",
        "legacy appearance maps to solid")
    assertEqual(migrated.alpha, 0.7, "legacy alpha migrates")
    assertEqual(migrated.blendMode, "BLEND",
        "legacy blend mode migrates")
    assertEqual(
        legacy.party.indicators.healthBar.dispelHighlight,
        nil,
        "legacy nested setting is retired"
    )

    local playerDispellable = {
        party = {
            indicators = {
                healthBar = {
                    dispelHighlight = {
                        enabled = true,
                        dispellable = true,
                        blendMode = "ADD",
                    },
                },
            },
        },
    }
    UF.MigrateConfig(playerDispellable)
    assertEqual(playerDispellable.party.indicators.dispels.enabled,
        true, "legacy player-dispellable mode stays enabled")
    assertEqual(playerDispellable.party.indicators.dispels.scope,
        "player", "legacy player-dispellable scope migrates")

    local raidLegacy = {
        raid = {
            indicators = {
                healthBar = {
                    dispelHighlight = {
                        enabled = true,
                        dispellable = true,
                        alpha = 0.65,
                        blendMode = "MOD",
                    },
                },
            },
        },
    }
    UF.MigrateConfig(raidLegacy)
    local migratedRaid = raidLegacy.raid.indicators.dispels
    assertEqual(migratedRaid.enabled, true,
        "legacy Raid player-dispellable mode stays enabled")
    assertEqual(migratedRaid.scope, "player",
        "legacy Raid player-dispellable scope migrates")
    assertEqual(migratedRaid.appearance, "full_solid",
        "legacy Raid appearance maps to solid")
    assertEqual(migratedRaid.alpha, 0.65,
        "legacy Raid alpha migrates")
    assertEqual(migratedRaid.blendMode, "MOD",
        "legacy Raid blend mode migrates")
    assertEqual(
        raidLegacy.raid.indicators.healthBar.dispelHighlight,
        nil,
        "legacy Raid nested setting is retired"
    )

    local preserved = {
        party = {
            indicators = {
                dispels = {
                    enabled = false,
                    scope = "group",
                    appearance = "full_gradient",
                },
                healthBar = {
                    dispelHighlight = {
                        enabled = true,
                    },
                },
            },
        },
    }
    UF.MigrateConfig(preserved)
    assertEqual(preserved.party.indicators.dispels.scope, "group",
        "new dispel settings win over legacy data")
    assertEqual(preserved.party.indicators.dispels.enabled, false,
        "new explicit disabled state is preserved")

    local hiddenBlend = {
        party = {
            indicators = {
                dispels = {
                    enabled = true,
                    blendMode = "DISABLE",
                },
            },
        },
    }
    UF.MigrateConfig(hiddenBlend)
    assertEqual(hiddenBlend.party.indicators.dispels.blendMode,
        "BLEND", "hidden legacy blend mode is normalized")

    local defaults = UF.GetDefaults()
    local defaultDispels = defaults.party.indicators.dispels
    assertEqual(defaultDispels.enabled, true,
        "new-profile Party dispel default")
    assertEqual(defaultDispels.scope, "player",
        "new-profile dispel scope")
    assertEqual(defaultDispels.appearance, "bottom_gradient",
        "new-profile dispel appearance")
    local defaultRaidDispels = defaults.raid.indicators.dispels
    assertEqual(defaultRaidDispels.enabled, true,
        "new-profile Raid dispel default")
    assertEqual(defaultRaidDispels.scope, "player",
        "new-profile Raid dispel scope")
    assertEqual(defaultRaidDispels.appearance, "bottom_gradient",
        "new-profile Raid dispel appearance")
end

local function testMigrationAndOptionsContracts()
    local revise = readFile("Revise.lua")
    local migrateIndex = assert(revise:find(
        "unitFrames%.MigrateConfig", 1, false
    ), "pre-hydration unit-frame migration")
    local hydrateIndex = assert(revise:find(
        "HydrateProfile", migrateIndex, true
    ), "profile hydration")
    assertTrue(migrateIndex < hydrateIndex,
        "dispel migration must run before default hydration")

    local unitFrameOptions = readFile("Options/UnitFrames.lua")
    assertTrue(unitFrameOptions:find(
        '"buffs", "debuffs", "dispels"',
        1,
        true
    ), "Party Dispels follows Buffs and Debuffs")
    assertEqual(countPlain(
        unitFrameOptions,
        '"buffs", "debuffs", "dispels"'
    ), 2, "Party and Raid each expose Dispels after aura rows")

    local optionBuilders = readFile("Options/UnitFrames_Options.lua")
    assertTrue(optionBuilders:find(
        'dispels = {\n        "enabled",\n        "dispelScope",',
        1,
        true
    ), "dedicated Party dispel settings")
    assertEqual(optionBuilders:find(
        'builder["dispelHighlight"]',
        1,
        true
    ), nil, "old nested dispel option is retired")
    assertTrue(optionBuilders:find(
        't.owner == "party" or t.owner == "raid"',
        1,
        true
    ), "health-bar mutations reevaluate Party and Raid dispels")

    local healthBar = readFile(
        "Modules/UnitFrames/Indicators/HealthBar.lua"
    )
    assertEqual(healthBar:find(
        "EnableDispelHighlight",
        1,
        true
    ), nil, "dormant nested health-bar dispel call is removed")
    assertTrue(healthBar:find(
        "self._configuredFrameLevel = config.frameLevel",
        1,
        true
    ), "Health Bar records the construction-owned frame level")
end

testMigrationDefaultsAndLegacyMapping()
testMigrationAndOptionsContracts()

print("unit_frame_dispel_migration_test.lua: ok")
