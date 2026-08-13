---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

local defaults = {
    enabled = false,
    windowCount = 3,
    windowTypes = {
        "DamageDone",
        "HealingDone",
        "DamageTaken",
    },
    windowSessions = {
        {mode = "current"},
        {mode = "current"},
        {mode = "current"},
    },
    windowSyncSessions = {
        true,
        true,
        true,
    },
    windowAutoCurrentOnCombat = {
        true,
        true,
        true,
    },
    windowAutoCurrentOnMythicPlusStart = {
        false,
        false,
        false,
    },
    windowAutoOverallOnMythicPlusComplete = {
        false,
        false,
        false,
    },
    mythicPlusWindowTypes = {
        false,
        false,
        false,
    },
    resetOnMythicPlusStart = false,
    alwaysShowPlayer = true,
    windowHeights = {
        147,
        134,
        134,
    },
    windowAnchors = {
        {
            relativeTo = 0,
            point = "BOTTOMRIGHT",
            relativePoint = "BOTTOMRIGHT",
            x = -4,
            y = 4,
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
    locked = false,
    width = 300,
    headerHeight = 22,
    barHeight = 20,
    spacing = 2,
    padding = 4,
    texture = "AF",
    numberMode = "both",
    showSpecIcon = true,
    classColor = true,
    backgroundAlpha = 0.82,
    barAlpha = 0.9,
}

local validWindowTypes = {
    DamageDone = true,
    Dps = true,
    HealingDone = true,
    Hps = true,
    Absorbs = true,
    Interrupts = true,
    Dispels = true,
    DamageTaken = true,
    AvoidableDamageTaken = true,
    Deaths = true,
    EnemyDamageTaken = true,
}

local validNumberModes = {
    total = true,
    perSecond = true,
    both = true,
}

local validSessionModes = {
    current = true,
    overall = true,
}

local validAnchorPoints = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local function CopyWindowTypes(source)
    local copy = {}
    for index = 1, 3 do
        copy[index] = source[index]
    end
    return copy
end

local function CopyWindowSessions(source)
    local copy = {}
    for index = 1, 3 do
        copy[index] = AF.Copy(source[index])
    end
    return copy
end

local function CopyWindowValues(source)
    local copy = {}
    for index = 1, 3 do
        copy[index] = source[index]
    end
    return copy
end

local function CopyWindowHeights(source)
    local copy = {}
    for index = 1, 3 do
        copy[index] = source[index]
    end
    return copy
end

local function CopyWindowAnchors(source)
    local copy = {}
    for index = 1, 3 do
        copy[index] = AF.Copy(source[index])
    end
    return copy
end

local function CopyDefaults()
    local copy = AF.Copy(defaults)
    copy.windowTypes = CopyWindowTypes(defaults.windowTypes)
    copy.windowSessions = CopyWindowSessions(defaults.windowSessions)
    copy.windowSyncSessions = CopyWindowValues(defaults.windowSyncSessions)
    copy.windowAutoCurrentOnCombat = CopyWindowValues(
        defaults.windowAutoCurrentOnCombat
    )
    copy.windowAutoCurrentOnMythicPlusStart = CopyWindowValues(
        defaults.windowAutoCurrentOnMythicPlusStart
    )
    copy.windowAutoOverallOnMythicPlusComplete = CopyWindowValues(
        defaults.windowAutoOverallOnMythicPlusComplete
    )
    copy.mythicPlusWindowTypes = CopyWindowValues(
        defaults.mythicPlusWindowTypes
    )
    copy.windowHeights = CopyWindowHeights(defaults.windowHeights)
    copy.windowAnchors = CopyWindowAnchors(defaults.windowAnchors)
    return copy
end

local function NormalizeNumber(value, default, minimum, maximum, integer)
    if type(value) ~= "number" or value ~= value then
        return default
    end

    value = math.max(minimum, math.min(maximum, value))
    if integer then
        value = math.floor(value + 0.5)
    end
    return value
end

local function HasAnchorCycle(anchors)
    for start = 1, 3 do
        local seen = {}
        local current = start
        while current ~= 0 do
            if seen[current] then
                return true
            end
            seen[current] = true
            current = anchors[current].relativeTo
        end
    end
    return false
end

local function NormalizeWindowAnchors(config)
    if type(config.windowAnchors) ~= "table" then
        config.windowAnchors = CopyWindowAnchors(defaults.windowAnchors)
        return
    end

    for index = 1, 3 do
        local anchor = config.windowAnchors[index]
        local default = defaults.windowAnchors[index]
        if type(anchor) ~= "table" then
            anchor = AF.Copy(default)
            config.windowAnchors[index] = anchor
        end

        anchor.relativeTo = NormalizeNumber(
            anchor.relativeTo,
            default.relativeTo,
            0,
            3,
            true
        )
        if anchor.relativeTo == index then
            anchor.relativeTo = default.relativeTo
        end
        if not validAnchorPoints[anchor.point] then
            anchor.point = default.point
        end
        if not validAnchorPoints[anchor.relativePoint] then
            anchor.relativePoint = default.relativePoint
        end
        anchor.x = NormalizeNumber(anchor.x, default.x, -4096, 4096)
        anchor.y = NormalizeNumber(anchor.y, default.y, -4096, 4096)
    end

    if HasAnchorCycle(config.windowAnchors) then
        config.windowAnchors = CopyWindowAnchors(defaults.windowAnchors)
    end
end

local function NormalizeWindowSessions(config)
    if type(config.windowSessions) ~= "table" then
        config.windowSessions = CopyWindowSessions(defaults.windowSessions)
        return
    end

    for index = 1, 3 do
        local value = config.windowSessions[index]
        local mode = type(value) == "table" and value.mode or nil

        if not validSessionModes[mode] then
            mode = defaults.windowSessions[index].mode
        end

        -- Historical IDs are runtime-only because Blizzard can recycle or
        -- discard them. Profiles persist only stable Current/Overall modes.
        config.windowSessions[index] = {
            mode = mode,
        }
    end
end

local function NormalizeBooleanWindowValues(config, key)
    local values = config[key]
    if type(values) ~= "table" then
        config[key] = CopyWindowValues(defaults[key])
        return
    end

    for index = 1, 3 do
        if type(values[index]) ~= "boolean" then
            values[index] = defaults[key][index]
        end
    end
end

local function NormalizeMythicPlusWindowTypes(config)
    local values = config.mythicPlusWindowTypes
    if type(values) ~= "table" then
        config.mythicPlusWindowTypes = CopyWindowValues(
            defaults.mythicPlusWindowTypes
        )
        return
    end

    for index = 1, 3 do
        if values[index] ~= false and not validWindowTypes[values[index]] then
            values[index] = defaults.mythicPlusWindowTypes[index]
        end
    end
end

local function NormalizeConfig(config)
    -- Legacy development builds stored transient CVar state in the profile.
    -- It must never survive profile copy, import, or export.
    config.nativeEnabledBeforeBFI = nil
    if type(config.enabled) ~= "boolean" then
        config.enabled = defaults.enabled
    end
    config.windowCount = NormalizeNumber(
        config.windowCount,
        defaults.windowCount,
        1,
        3,
        true
    )
    if type(config.windowTypes) ~= "table" then
        config.windowTypes = CopyWindowTypes(defaults.windowTypes)
    end
    for index = 1, 3 do
        if not validWindowTypes[config.windowTypes[index]] then
            config.windowTypes[index] = defaults.windowTypes[index]
        end
    end
    NormalizeWindowSessions(config)
    NormalizeBooleanWindowValues(config, "windowSyncSessions")
    NormalizeBooleanWindowValues(config, "windowAutoCurrentOnCombat")
    NormalizeBooleanWindowValues(
        config,
        "windowAutoCurrentOnMythicPlusStart"
    )
    NormalizeBooleanWindowValues(
        config,
        "windowAutoOverallOnMythicPlusComplete"
    )
    NormalizeMythicPlusWindowTypes(config)
    if type(config.resetOnMythicPlusStart) ~= "boolean" then
        config.resetOnMythicPlusStart = defaults.resetOnMythicPlusStart
    end
    if type(config.alwaysShowPlayer) ~= "boolean" then
        config.alwaysShowPlayer = defaults.alwaysShowPlayer
    end

    local legacyHeight
    if type(config.height) == "number" and config.height == config.height then
        legacyHeight = NormalizeNumber(
            config.height,
            defaults.windowHeights[1],
            120,
            520,
            true
        )
    end
    config.height = nil
    if type(config.windowHeights) ~= "table" then
        config.windowHeights = {}
    end
    for index = 1, 3 do
        config.windowHeights[index] = NormalizeNumber(
            config.windowHeights[index],
            legacyHeight or defaults.windowHeights[index],
            120,
            520,
            true
        )
    end
    NormalizeWindowAnchors(config)
    if type(config.locked) ~= "boolean" then
        config.locked = defaults.locked
    end

    config.width = NormalizeNumber(
        config.width,
        defaults.width,
        220,
        520,
        true
    )
    config.headerHeight = NormalizeNumber(
        config.headerHeight,
        defaults.headerHeight,
        18,
        36,
        true
    )
    config.barHeight = NormalizeNumber(
        config.barHeight,
        defaults.barHeight,
        14,
        36,
        true
    )
    config.spacing = NormalizeNumber(
        config.spacing,
        defaults.spacing,
        0,
        8,
        true
    )
    config.padding = NormalizeNumber(
        config.padding,
        defaults.padding,
        0,
        12,
        true
    )
    if type(config.texture) ~= "string" or config.texture == "" then
        config.texture = defaults.texture
    end
    if not validNumberModes[config.numberMode] then
        config.numberMode = defaults.numberMode
    end
    if type(config.showSpecIcon) ~= "boolean" then
        config.showSpecIcon = defaults.showSpecIcon
    end
    if type(config.classColor) ~= "boolean" then
        config.classColor = defaults.classColor
    end
    config.backgroundAlpha = NormalizeNumber(
        config.backgroundAlpha,
        defaults.backgroundAlpha,
        0,
        1
    )
    config.barAlpha = NormalizeNumber(
        config.barAlpha,
        defaults.barAlpha,
        0,
        1
    )
end

AF.RegisterCallback("BFI_UpdateProfile", function(_, profile)
    if type(profile.damageMeter) ~= "table" then
        profile.damageMeter = CopyDefaults()
    end

    NormalizeConfig(profile.damageMeter)
    DM.config = profile.damageMeter
    if DM.Renderer
        and type(DM.Renderer.ClearRuntimeSessions) == "function"
    then
        DM.Renderer.ClearRuntimeSessions()
    end
end)

function DM.GetDefaults()
    return CopyDefaults()
end

function DM.ResetToDefaults()
    wipe(DM.config)
    AF.Merge(DM.config, CopyDefaults())
    if DM.Renderer
        and type(DM.Renderer.ClearRuntimeSessions) == "function"
    then
        DM.Renderer.ClearRuntimeSessions()
    end
end
