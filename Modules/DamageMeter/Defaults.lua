---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

local CURRENT_SIZE_DEFAULTS_VERSION = 3
local CURRENT_DOCK_DEFAULTS_VERSION = 2
local MIN_WINDOW_HEIGHT = 84
local MIN_ROW_TEXT_SIZE = 8
local MAX_ROW_TEXT_SIZE = 14
local ROW_TEXT_VERTICAL_PADDING = 4
local LEGACY_DEFAULT_WIDTH = 300
local LEGACY_DEFAULT_HEIGHT = 220
local LEGACY_DEFAULT_WINDOW_HEIGHTS = {
    220,
    220,
    220,
}
local PREVIOUS_DEFAULT_WINDOW_HEIGHTS = {
    147,
    134,
    134,
}
local VERSION_ONE_DEFAULT_WIDTH = 260
local VERSION_ONE_DEFAULT_WINDOW_HEIGHTS = {
    138,
    120,
    120,
}
local VERSION_ONE_DEFAULT_HEADER_HEIGHT = 22
local VERSION_ONE_DEFAULT_BAR_HEIGHT = 20
local VERSION_ONE_DEFAULT_SPACING = 2
local VERSION_ONE_DEFAULT_PADDING = 4
local VERSION_TWO_DEFAULT_WIDTH = 240
local VERSION_TWO_DEFAULT_WINDOW_HEIGHTS = {
    124,
    104,
    104,
}
local VERSION_TWO_DEFAULT_HEADER_HEIGHT = 20
local VERSION_TWO_DEFAULT_BAR_HEIGHT = 18
local VERSION_TWO_DEFAULT_SPACING = 2
local VERSION_TWO_DEFAULT_PADDING = 3
local defaults = {
    enabled = true,
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
        124,
        84,
        84,
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
    dockToObjectiveTracker = false,
    dockDefaultsVersion = CURRENT_DOCK_DEFAULTS_VERSION,
    locked = false,
    width = 240,
    sizeDefaultsVersion = CURRENT_SIZE_DEFAULTS_VERSION,
    headerHeight = 20,
    barHeight = 18,
    rowTextSize = 11,
    spacing = 2,
    padding = 3,
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

local function WindowHeightsMatch(values, expected)
    if type(values) ~= "table" then return false end

    for index = 1, 3 do
        if values[index] ~= expected[index] then
            return false
        end
    end
    return true
end

local function DensityMatches(config, headerHeight, barHeight, spacing, padding)
    local function FieldMatches(key, expected)
        return config[key] == nil or config[key] == expected
    end

    return FieldMatches("headerHeight", headerHeight)
        and FieldMatches("barHeight", barHeight)
        and FieldMatches("spacing", spacing)
        and FieldMatches("padding", padding)
end

local function VersionOneDefaultDensityMatches(config)
    return DensityMatches(
        config,
        VERSION_ONE_DEFAULT_HEADER_HEIGHT,
        VERSION_ONE_DEFAULT_BAR_HEIGHT,
        VERSION_ONE_DEFAULT_SPACING,
        VERSION_ONE_DEFAULT_PADDING
    )
end

local function VersionTwoDefaultDensityMatches(config)
    return DensityMatches(
        config,
        VERSION_TWO_DEFAULT_HEADER_HEIGHT,
        VERSION_TWO_DEFAULT_BAR_HEIGHT,
        VERSION_TWO_DEFAULT_SPACING,
        VERSION_TWO_DEFAULT_PADDING
    )
end

local function UsesVersionOneDefaultSizes(config)
    return config.width == VERSION_ONE_DEFAULT_WIDTH
        and WindowHeightsMatch(
            config.windowHeights,
            VERSION_ONE_DEFAULT_WINDOW_HEIGHTS
        )
        and config.height == nil
        and VersionOneDefaultDensityMatches(config)
end

local function UsesVersionTwoDefaultSizes(config)
    return config.width == VERSION_TWO_DEFAULT_WIDTH
        and WindowHeightsMatch(
            config.windowHeights,
            VERSION_TWO_DEFAULT_WINDOW_HEIGHTS
        )
        and config.height == nil
        and VersionTwoDefaultDensityMatches(config)
end

local function UsesUnversionedHistoricalDefaultSizes(config)
    if type(config.sizeDefaultsVersion) == "number"
        or config.width ~= LEGACY_DEFAULT_WIDTH
        or not VersionOneDefaultDensityMatches(config)
    then
        return false
    end

    if config.height == nil then
        return WindowHeightsMatch(
            config.windowHeights,
            PREVIOUS_DEFAULT_WINDOW_HEIGHTS
        ) or WindowHeightsMatch(
            config.windowHeights,
            LEGACY_DEFAULT_WINDOW_HEIGHTS
        )
    end

    return config.height == LEGACY_DEFAULT_HEIGHT
        and config.windowHeights == nil
end

local function MigrateDefaultSizes(config)
    local version = config.sizeDefaultsVersion
    if type(version) == "number"
        and version >= CURRENT_SIZE_DEFAULTS_VERSION
    then
        return
    end

    -- Only compact an exact default tuple. If any dimension or density differs,
    -- the complete saved layout remains user-owned.
    if UsesVersionOneDefaultSizes(config)
        or UsesVersionTwoDefaultSizes(config)
        or UsesUnversionedHistoricalDefaultSizes(config)
    then
        config.width = defaults.width
        config.height = nil
        config.windowHeights = CopyWindowHeights(defaults.windowHeights)
        config.headerHeight = defaults.headerHeight
        config.barHeight = defaults.barHeight
        config.spacing = defaults.spacing
        config.padding = defaults.padding
    end
    config.sizeDefaultsVersion = CURRENT_SIZE_DEFAULTS_VERSION
end

local function GetMinimumWindowHeight(config)
    return math.max(
        MIN_WINDOW_HEIGHT,
        config.headerHeight + (config.padding * 2) + config.barHeight
    )
end

local function GetMaximumRowTextSize(config)
    return math.max(
        MIN_ROW_TEXT_SIZE,
        math.min(
            MAX_ROW_TEXT_SIZE,
            config.barHeight - ROW_TEXT_VERTICAL_PADDING
        )
    )
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

local function MigrateDefaultDock(config)
    local version = config.dockDefaultsVersion
    if type(version) == "number"
        and version >= CURRENT_DOCK_DEFAULTS_VERSION
    then
        return
    end

    -- Version one made tracker docking the default. Keep every existing
    -- anchor chain and explicit docking choice intact; the independent
    -- bottom-right stack is a new-install/reset default only.
    config.dockDefaultsVersion = CURRENT_DOCK_DEFAULTS_VERSION
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

    MigrateDefaultSizes(config)

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
    config.rowTextSize = NormalizeNumber(
        config.rowTextSize,
        defaults.rowTextSize,
        MIN_ROW_TEXT_SIZE,
        GetMaximumRowTextSize(config),
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
    local minimumWindowHeight = GetMinimumWindowHeight(config)

    local legacyHeight
    if type(config.height) == "number" and config.height == config.height then
        legacyHeight = NormalizeNumber(
            config.height,
            defaults.windowHeights[1],
            minimumWindowHeight,
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
            minimumWindowHeight,
            520,
            true
        )
    end
    MigrateDefaultDock(config)
    local hadTrackerDockSetting =
        type(config.dockToObjectiveTracker) == "boolean"
    NormalizeWindowAnchors(config)
    if not hadTrackerDockSetting then
        -- Profiles created before this setting had only screen-relative
        -- anchors, so retain that behavior rather than assuming docking.
        config.dockToObjectiveTracker = defaults.dockToObjectiveTracker
    end
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
