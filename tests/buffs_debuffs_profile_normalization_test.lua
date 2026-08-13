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

local function assertFalse(value, message)
    assertEqual(value == false, true, message)
end

local function assertNil(value, message)
    assertEqual(value, nil, message)
end

local function assertColor(actual, expected, message)
    for index = 1, 4 do
        assertEqual(actual[index], expected[index],
            message .. " channel " .. index)
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

local profileCallback
local environment = setmetatable({}, {__index = _G})
environment._G = environment
environment.wipe = function(value)
    for key in pairs(value) do
        value[key] = nil
    end
end

local shippedColors = {
    white = {1, 1, 1, 1},
    aura_seconds = {0.9, 0.1, 0.2, 0.8},
    aura_percent = {0.2, 0.8, 0.3, 0.7},
}

local AF = {}
function AF.GetColorTable(name)
    return deepCopy(assert(shippedColors[name], "unknown color " .. tostring(name)))
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

local function newProfileWith(duration)
    return {
        buffsDebuffs = {
            buffs = {duration = duration or {}},
            debuffs = {},
        },
    }
end

do
    local profile = {}
    profileCallback(nil, profile)
    local config = profile.buffsDebuffs
    assertEqual(config.buffs.separateOwn, 0, "new Buffs Separate Own default")
    assertEqual(config.debuffs.separateOwn, 0,
        "new Debuffs Separate Own default")
    for _, pane in ipairs({config.buffs, config.debuffs}) do
        assertNil(pane.duration.showSecondsUnit,
            "new profiles omit unsupported seconds unit")
        assertTrue(pane.duration.color.seconds.enabled,
            "new profile defaults to Seconds mode")
        assertFalse(pane.duration.color.percent.enabled,
            "new profile disables Percent mode")
        assertEqual(pane.duration.color.seconds.value, 5,
            "new profile keeps seconds threshold")
        assertEqual(pane.duration.color.percent.value, 0.5,
            "new profile keeps percent threshold")
        assertColor(pane.duration.color.seconds.rgb,
            shippedColors.aura_seconds, "new seconds color")
        assertColor(pane.duration.color.percent.rgb,
            shippedColors.aura_percent, "new percent color")
        assertEqual(BD.GetDurationColorMode(pane.duration), "seconds",
            "new profile reports one Seconds mode")
    end
    assertTrue(config.buffs.duration.color.seconds.rgb
            ~= config.debuffs.duration.color.seconds.rgb,
        "pane seconds colors are not aliased")
    assertTrue(config.buffs.duration.color.percent.rgb
            ~= config.debuffs.duration.color.percent.rgb,
        "pane percent colors are not aliased")
    assertEqual(BD.config, config, "module receives new profile config")
end

do
    local importedPercent = {
        enabled = true,
        value = "0.37",
        rgb = {"0.25", 2, -1, "0.6"},
        importedRuleKey = "preserve",
    }
    local profile = newProfileWith({
        showSecondsUnit = true,
        importedDurationKey = "preserve",
        color = {
            percent = importedPercent,
            importedColorKey = "preserve",
        },
    })
    profile.buffsDebuffs.customModuleKey = "preserve"
    profile.buffsDebuffs.buffs.customPaneKey = "preserve"
    profileCallback(nil, profile)

    local duration = profile.buffsDebuffs.buffs.duration
    assertFalse(duration.color.seconds.enabled,
        "percent-only profile does not acquire default Seconds mode")
    assertTrue(duration.color.percent.enabled,
        "percent-only profile preserves Percent mode")
    assertEqual(duration.color.percent, importedPercent,
        "imported percent table identity is preserved")
    assertEqual(duration.color.percent.value, 0.37,
        "arbitrary percent numeric string normalizes")
    assertColor(duration.color.percent.rgb, {0.25, 1, 0, 0.6},
        "active imported percent color normalizes")
    assertEqual(duration.color.percent.importedRuleKey, "preserve",
        "unknown threshold key is preserved")
    assertEqual(duration.color.seconds.value, 5,
        "missing inactive seconds payload is filled")
    assertColor(duration.color.seconds.rgb, shippedColors.aura_seconds,
        "missing inactive seconds color is copied")
    assertEqual(duration.showSecondsUnit, true,
        "imported seconds-unit key is preserved")
    assertEqual(duration.importedDurationKey, "preserve",
        "unknown duration key is preserved")
    assertEqual(duration.color.importedColorKey, "preserve",
        "unknown color key is preserved")
    assertEqual(profile.buffsDebuffs.buffs.customPaneKey, "preserve",
        "unknown pane key is preserved")
    assertEqual(profile.buffsDebuffs.customModuleKey, "preserve",
        "unknown module key is preserved")
    assertEqual(BD.GetDurationColorMode(duration), "percent",
        "percent-only import reports Percent mode")
end

do
    local seconds = {
        enabled = true,
        value = "7.5",
        rgb = {"0.1", "0.2", "0.3", "0.4"},
    }
    local percent = {
        enabled = true,
        value = "0.27",
        rgb = {"0.4", "0.5", "0.6", "0.7"},
    }
    local profile = newProfileWith({
        color = {seconds = seconds, percent = percent},
    })
    profileCallback(nil, profile)
    local duration = profile.buffsDebuffs.buffs.duration

    assertTrue(duration.color.seconds.enabled,
        "both enabled canonicalizes to Seconds")
    assertFalse(duration.color.percent.enabled,
        "both enabled disables Percent")
    assertEqual(duration.color.seconds, seconds,
        "seconds table identity is retained")
    assertEqual(duration.color.percent, percent,
        "inactive percent table identity is retained")
    assertEqual(duration.color.seconds.value, 7.5,
        "active seconds numeric string normalizes")
    assertEqual(duration.color.percent.value, 0.27,
        "inactive percent numeric string also normalizes")
    assertColor(duration.color.seconds.rgb, {0.1, 0.2, 0.3, 0.4},
        "active seconds RGBA normalizes")
    assertColor(duration.color.percent.rgb, {0.4, 0.5, 0.6, 0.7},
        "inactive percent RGBA normalizes")
end

do
    local offProfile = newProfileWith({
        color = {
            seconds = {
                enabled = false,
                value = -2,
                rgb = {math.huge, -1, "bad", 2},
            },
            percent = {
                enabled = false,
                value = 1,
                rgb = {-1, 2, "bad", -2},
            },
        },
    })
    profileCallback(nil, offProfile)
    local off = offProfile.buffsDebuffs.buffs.duration
    assertFalse(off.color.seconds.enabled, "both false stays Off")
    assertFalse(off.color.percent.enabled, "Off has no Percent rule")
    assertEqual(off.color.seconds.value, 5,
        "invalid inactive seconds value uses default")
    assertEqual(off.color.percent.value, 0.5,
        "out-of-range inactive percent uses default")
    assertColor(off.color.seconds.rgb, {0.9, 0, 0.2, 1},
        "inactive seconds color normalizes")
    assertColor(off.color.percent.rgb, {0, 1, 0.3, 0},
        "inactive percent color normalizes")
    assertEqual(BD.GetDurationColorMode(off), "off",
        "both false reports Off")

    local explicitFalse = newProfileWith({
        color = {seconds = {enabled = false}},
    })
    profileCallback(nil, explicitFalse)
    assertEqual(BD.GetDurationColorMode(
        explicitFalse.buffsDebuffs.buffs.duration), "off",
        "one explicit false with missing peer infers Off before fill")

    local absent = newProfileWith({color = {normal = {1, 1, 1, 1}}})
    profileCallback(nil, absent)
    local absentDuration = absent.buffsDebuffs.buffs.duration
    assertTrue(absentDuration.color.seconds.enabled,
        "missing duration mode defaults to Seconds")
    assertFalse(absentDuration.color.percent.enabled,
        "missing duration mode keeps Percent inactive")
end

do
    local profile = newProfileWith({
        color = {
            seconds = {
                enabled = true,
                value = 8,
                rgb = {0.8, 0.1, 0.2, 1},
                secondsKey = "keep",
            },
            percent = {
                enabled = false,
                value = 0.41,
                rgb = {0.1, 0.8, 0.2, 1},
                percentKey = "keep",
            },
        },
    })
    profileCallback(nil, profile)
    local duration = profile.buffsDebuffs.buffs.duration
    local seconds = duration.color.seconds
    local percent = duration.color.percent

    assertTrue(BD.SetDurationColorMode(duration, "percent"),
        "mode helper accepts Percent")
    assertFalse(seconds.enabled, "Percent disables Seconds")
    assertTrue(percent.enabled, "Percent enables Percent")
    assertEqual(seconds.value, 8,
        "mode helper preserves inactive seconds value")
    assertEqual(percent.value, 0.41,
        "mode helper preserves active percent value")
    assertEqual(seconds.secondsKey, "keep",
        "mode helper preserves seconds unknowns")
    assertEqual(percent.percentKey, "keep",
        "mode helper preserves percent unknowns")

    assertTrue(BD.SetDurationColorMode(duration, "off"),
        "mode helper accepts Off")
    assertFalse(seconds.enabled, "Off disables Seconds")
    assertFalse(percent.enabled, "Off disables Percent")
    assertFalse(BD.SetDurationColorMode(duration, "unknown"),
        "mode helper rejects unknown mode")
    assertEqual(BD.GetDurationColorMode(duration), "off",
        "rejected mode leaves Off unchanged")
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
            buffs = {separateOwn = "1"},
            debuffs = {separateOwn = "-1"},
        },
    }
    profileCallback(nil, profile)
    assertEqual(profile.buffsDebuffs.buffs.separateOwn, 1,
        "numeric Before string normalizes without erasure")
    assertEqual(profile.buffsDebuffs.debuffs.separateOwn, -1,
        "numeric After string normalizes without erasure")
end

do
    local profile = newProfileWith({
        showSecondsUnit = false,
        retained = "unknown",
        color = {
            seconds = {
                enabled = true,
                value = 0.625,
                rgb = {0.11, 0.22, 0.33, 0.44},
                retained = "seconds",
            },
        },
    })
    profileCallback(nil, profile)
    local duration = profile.buffsDebuffs.buffs.duration
    local seconds = duration.color.seconds
    local percent = duration.color.percent
    local secondsColor = seconds.rgb
    local percentColor = percent.rgb

    assertTrue(seconds.enabled,
        "seconds-only profile retains Seconds mode")
    assertFalse(percent.enabled,
        "seconds-only profile fills Percent inactive")
    assertEqual(seconds.value, 0.625,
        "non-grid seconds value remains exact")

    profileCallback(nil, profile)
    local repeated = profile.buffsDebuffs.buffs.duration
    assertEqual(repeated.color.seconds, seconds,
        "repeated normalization retains seconds table identity")
    assertEqual(repeated.color.percent, percent,
        "repeated normalization retains percent table identity")
    assertEqual(repeated.color.seconds.rgb, secondsColor,
        "repeated normalization retains seconds color identity")
    assertEqual(repeated.color.percent.rgb, percentColor,
        "repeated normalization retains percent color identity")
    assertEqual(repeated.color.seconds.value, 0.625,
        "repeated normalization retains exact seconds value")
    assertEqual(repeated.color.seconds.retained, "seconds",
        "repeated normalization retains rule unknowns")
    assertEqual(repeated.retained, "unknown",
        "repeated normalization retains duration unknowns")
    assertEqual(repeated.showSecondsUnit, false,
        "repeated normalization retains imported unsupported key")
end

do
    local malformedIntent = newProfileWith({
        color = {
            seconds = {enabled = "yes", value = 4},
            percent = {enabled = true, value = 0.375},
        },
    })
    profileCallback(nil, malformedIntent)
    local duration = malformedIntent.buffsDebuffs.buffs.duration
    assertFalse(duration.color.seconds.enabled,
        "malformed seconds enabled does not override explicit Percent")
    assertTrue(duration.color.percent.enabled,
        "explicit Percent wins malformed peer intent")

    local noIntent = newProfileWith({
        color = {
            seconds = {enabled = "yes"},
            percent = {enabled = 1},
        },
    })
    profileCallback(nil, noIntent)
    duration = noIntent.buffsDebuffs.buffs.duration
    assertTrue(duration.color.seconds.enabled,
        "malformed enabled values fall back to default Seconds")
    assertFalse(duration.color.percent.enabled,
        "malformed enabled values canonicalize one mode")
end

do
    local profile = newProfileWith({
        color = {
            seconds = {
                enabled = true,
                value = 0 / 0,
                rgb = {1, 1, 1, 1},
            },
            percent = {
                enabled = false,
                value = math.huge,
                rgb = {1, 1, 1, 1},
            },
        },
    })
    profileCallback(nil, profile)
    local duration = profile.buffsDebuffs.buffs.duration
    assertEqual(duration.color.seconds.value, 5,
        "active NaN seconds uses default")
    assertEqual(duration.color.percent.value, 0.5,
        "inactive positive infinity percent uses default")

    profile = newProfileWith({
        color = {
            seconds = {enabled = false, value = -math.huge},
            percent = {enabled = true, value = 0 / 0},
        },
    })
    profileCallback(nil, profile)
    duration = profile.buffsDebuffs.buffs.duration
    assertEqual(duration.color.seconds.value, 5,
        "inactive negative infinity seconds uses default")
    assertEqual(duration.color.percent.value, 0.5,
        "active NaN percent uses default")
end

do
    local profile = newProfileWith({
        showSecondsUnit = true,
        imported = "remove-on-reset",
        color = {
            seconds = {enabled = false, value = 12},
            percent = {enabled = true, value = 0.375},
        },
    })
    profileCallback(nil, profile)
    BD.ResetToDefaults("buffs")
    local buffs = profile.buffsDebuffs.buffs
    assertNil(buffs.duration.showSecondsUnit,
        "pane reset removes imported unsupported seconds-unit key")
    assertNil(buffs.duration.imported,
        "pane reset intentionally removes imported unknowns")
    assertTrue(buffs.duration.color.seconds.enabled,
        "pane reset restores Seconds default")
    assertFalse(buffs.duration.color.percent.enabled,
        "pane reset disables Percent default")
    assertEqual(buffs.duration.color.seconds.value, 5,
        "pane reset restores seconds payload")
    assertEqual(buffs.duration.color.percent.value, 0.5,
        "pane reset restores percent payload")

    profile.buffsDebuffs.buffs.duration.showSecondsUnit = true
    profile.buffsDebuffs.debuffs.duration.extra = "remove-on-all-reset"
    BD.ResetToDefaults()
    assertNil(profile.buffsDebuffs.buffs.duration.showSecondsUnit,
        "all reset removes imported Buffs seconds-unit key")
    assertNil(profile.buffsDebuffs.debuffs.duration.extra,
        "all reset removes imported Debuffs unknowns")
    assertTrue(profile.buffsDebuffs.debuffs.duration.color.seconds.enabled,
        "all reset restores Debuffs Seconds default")
    assertFalse(profile.buffsDebuffs.debuffs.duration.color.percent.enabled,
        "all reset restores Debuffs Percent inactive")
end

print("buffs/debuffs profile normalization tests passed")
