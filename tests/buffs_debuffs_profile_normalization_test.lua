local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    assertEqual(value == true, true, message)
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[deepCopy(key)] = deepCopy(child)
    end
    return copy
end

local profileCallback
local environment = setmetatable({}, {__index = _G})
environment._G = environment
environment.wipe = function(value)
    for key in pairs(value) do
        value[key] = nil
    end
end

local AF = {}
function AF.GetColorTable()
    return {1, 1, 1, 1}
end
function AF.Copy(...)
    local copy = {}
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        for key, value in pairs(source) do
            copy[key] = deepCopy(value)
        end
    end
    return copy
end
function AF.Merge(target, source)
    for key, value in pairs(source) do
        target[key] = deepCopy(value)
    end
end
function AF.RegisterCallback(event, callback)
    assertEqual(event, "BFI_UpdateProfile", "profile callback event")
    profileCallback = callback
end
environment.AbstractFramework = AF

local BD = {}
local BFI = {
    modules = {
        BuffsDebuffs = BD,
    },
}

local chunk = assert(loadfile("Modules/BuffsDebuffs/Defaults.lua"))
setfenv(chunk, environment)
chunk("BFInfinite", BFI)
assertTrue(type(profileCallback) == "function", "profile callback registered")

do
    local profile = {}
    profileCallback(nil, profile)
    local config = profile.buffsDebuffs
    assertEqual(config.buffs.separateOwn, 0, "new Buffs Separate Own default")
    assertEqual(config.debuffs.separateOwn, 0,
        "new Debuffs Separate Own default")
    assertEqual(config.buffs.duration.showSecondsUnit, nil,
        "new profiles omit retired seconds unit")
    assertEqual(config.buffs.duration.color.percent, nil,
        "new profiles omit retired percent color")
    assertEqual(config.buffs.duration.color.seconds, nil,
        "new profiles omit retired seconds color")
    assertEqual(BD.config, config, "module receives new profile config")
end

do
    local retiredPercent = {
        enabled = true,
        value = 0.7,
        rgb = {0.1, 0.2, 0.3, 1},
    }
    local profile = {
        buffsDebuffs = {
            customModuleKey = "preserve",
            buffs = {
                separateOwn = 1,
                showUnknown = "preserve",
                duration = {
                    showSecondsUnit = false,
                    color = {
                        percent = retiredPercent,
                        seconds = {
                            enabled = true,
                            value = 9,
                            rgb = {1, 0, 0, 1},
                        },
                    },
                },
            },
            debuffs = {
                separateOwn = -1,
            },
        },
    }
    profileCallback(nil, profile)

    local config = profile.buffsDebuffs
    assertEqual(config.buffs.separateOwn, 1,
        "valid Before value is preserved")
    assertEqual(config.debuffs.separateOwn, -1,
        "valid After value is preserved")
    assertEqual(config.buffs.showUnknown, "preserve",
        "unknown pane key is preserved")
    assertEqual(config.customModuleKey, "preserve",
        "unknown module key is preserved")
    assertEqual(config.buffs.duration.showSecondsUnit, false,
        "retired seconds-unit value is preserved")
    assertEqual(config.buffs.duration.color.percent, retiredPercent,
        "retired percent table identity is preserved")
    assertEqual(config.buffs.duration.color.seconds.value, 9,
        "retired seconds threshold is preserved")
    assertEqual(config.buffs.width, 26, "missing active field is filled")
    assertEqual(config.debuffs.duration.enabled, true,
        "missing nested active field is filled")
    assertTrue(type(config.buffs.duration.color.normal) == "table",
        "active normal color is filled beside retired fields")
end

do
    local profile = {
        buffsDebuffs = {
            buffs = {
                enabled = "yes",
                position = {"INVALID", math.huge, {}},
                width = math.huge,
                height = -50,
                orientation = "INVALID",
                spacingX = -50,
                spacingY = math.huge,
                separateOwn = "invalid",
                sortMethod = "INVALID",
                sortDirection = "INVALID",
                maxWraps = 500,
                wrapAfter = 0,
                stack = {
                    enabled = "yes",
                    font = {false, math.huge, false, "yes"},
                    position = {"INVALID", "INVALID", math.huge, {}},
                    color = {2, -1, "bad", math.huge},
                },
                duration = {
                    color = {
                        normal = {2, -1, "bad", math.huge},
                    },
                },
            },
            debuffs = "invalid",
        },
    }
    profileCallback(nil, profile)

    local buffs = profile.buffsDebuffs.buffs
    assertEqual(buffs.enabled, false, "malformed enabled normalizes")
    assertEqual(buffs.width, 26, "infinite width uses default")
    assertEqual(buffs.height, 10, "height clamps")
    assertEqual(buffs.orientation, "right_to_left_then_down",
        "orientation falls back")
    assertEqual(buffs.spacingX, -1, "X spacing clamps")
    assertEqual(buffs.spacingY, 6, "infinite Y spacing uses default")
    assertEqual(buffs.separateOwn, 0, "malformed Separate Own falls back")
    assertEqual(buffs.sortMethod, "TIME", "sort method falls back")
    assertEqual(buffs.sortDirection, "-", "sort direction falls back")
    assertEqual(buffs.maxWraps, 50, "line count clamps")
    assertEqual(buffs.wrapAfter, 1, "icons-per-line clamps")
    assertEqual(buffs.stack.font[1], "Expressway", "font name normalizes")
    assertEqual(buffs.stack.font[2], 11, "font size normalizes")
    assertEqual(buffs.stack.position[1], "TOPRIGHT",
        "text anchor normalizes")
    assertEqual(buffs.stack.color[1], 1, "color high channel clamps")
    assertEqual(buffs.stack.color[2], 0, "color low channel clamps")
    assertEqual(buffs.stack.color[3], 1, "invalid color uses fallback")
    assertTrue(type(profile.buffsDebuffs.debuffs) == "table",
        "malformed Debuffs pane is rebuilt")
end

do
    local profile = {
        buffsDebuffs = {
            buffs = {
                separateOwn = "1",
            },
            debuffs = {
                separateOwn = "-1",
            },
        },
    }
    profileCallback(nil, profile)
    assertEqual(profile.buffsDebuffs.buffs.separateOwn, 1,
        "numeric Before string normalizes without erasure")
    assertEqual(profile.buffsDebuffs.debuffs.separateOwn, -1,
        "numeric After string normalizes without erasure")
end

print("buffs/debuffs profile normalization tests passed")
