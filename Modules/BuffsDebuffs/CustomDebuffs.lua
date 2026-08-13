---@type BFI
local BFI = select(2, ...)
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs

-- Retail 12.1.0.69273 (wow-ui-source
-- eb941aad028d73ddc69e3e8ef4da709f4d3cd744) lets a native HARMFUL group
-- describe ordinary and private presentation without exposing AuraData. The
-- SetUnit(nil) deregisters each of DebuffFrame's exact six private anchors;
-- Blizzard's watcher releases and hides the pooled renderers. The finite
-- PublicAndPrivate cap remains behind a separate, explicit saved opt-in.
if type(BD.HasCustomHarmfulAuraDescriptorCapability) ~= "function"
    or BD.HasCustomHarmfulAuraDescriptorCapability() ~= true
    or type(BD.GetDefaults) ~= "function"
    or type(BD.RegisterCustomAuraContainerPane) ~= "function"
then
    return
end

local floor = math.floor
local max = math.max
local tonumber = tonumber
local type = type

local flowAxis = _G.AnchorUtil.FlowLayoutAxis
local flowDirection = _G.AnchorUtil.FlowDirection
local sortMethod = _G.AuraContainerSortMethod
local sortDirection = _G.AuraContainerSortDirection
local processingPolicy = _G.CustomAuraContainerAuraProcessingPolicy

local defaults = BD.GetDefaults().debuffs
local CONSTRUCTION_SCHEMA = 1

local SORT_METHODS = {
    INDEX = sortMethod.AuraInstanceIDOnly,
    NAME = sortMethod.NameOnly,
    TIME = sortMethod.ExpirationOnly,
}

local SORT_DIRECTIONS = {
    ["+"] = sortDirection.Normal,
    ["-"] = sortDirection.Reverse,
}

local VALID_ANCHORS = {
    BOTTOM = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
    CENTER = true,
    LEFT = true,
    RIGHT = true,
    TOP = true,
    TOPLEFT = true,
    TOPRIGHT = true,
}

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function NormalizeNumber(value, fallback, minimum, maximum, integer)
    value = tonumber(value)
    if not IsFiniteNumber(value) then
        value = fallback
    end
    if value < minimum then
        value = minimum
    elseif value > maximum then
        value = maximum
    end
    if integer then
        value = floor(value + 0.5)
    end
    return value
end

local function NormalizeBoolean(value, fallback)
    if type(value) == "boolean" then return value end
    return fallback == true
end

local function NormalizeAnchor(value, fallback)
    if type(value) == "string" and VALID_ANCHORS[value] then
        return value
    end
    return fallback
end

local function NormalizeColor(value, fallback)
    if type(value) ~= "table" then value = {} end
    return {
        NormalizeNumber(value[1], fallback[1] or 1, 0, 1, false),
        NormalizeNumber(value[2], fallback[2] or 1, 0, 1, false),
        NormalizeNumber(value[3], fallback[3] or 1, 0, 1, false),
        NormalizeNumber(value[4], fallback[4] or 1, 0, 1, false),
    }
end

local function NormalizeFont(value, fallback)
    if type(value) ~= "table" then value = {} end
    local font = value[1]
    if type(font) ~= "string" or font == "" then
        font = fallback[1]
    end
    local outline = value[3]
    if type(outline) ~= "string" or outline == "" then
        outline = fallback[3]
    end
    return {
        font,
        NormalizeNumber(value[2], fallback[2], 5, 50, true),
        outline,
        NormalizeBoolean(value[4], fallback[4]),
    }
end

local function NormalizeTextPosition(value, fallback)
    if type(value) ~= "table" then value = {} end
    return {
        NormalizeAnchor(value[1], fallback[1]),
        NormalizeAnchor(value[2], fallback[2]),
        NormalizeNumber(value[3], fallback[3], -100, 100, false),
        NormalizeNumber(value[4], fallback[4], -100, 100, false),
    }
end

local function NormalizeStackText(config)
    if type(config) ~= "table" then config = {} end
    return {
        enabled = NormalizeBoolean(config.enabled, defaults.stack.enabled),
        font = NormalizeFont(config.font, defaults.stack.font),
        position = NormalizeTextPosition(
            config.position,
            defaults.stack.position
        ),
        color = NormalizeColor(config.color, defaults.stack.color),
    }
end

local function NormalizeDurationText(config)
    if type(config) ~= "table" then config = {} end
    local color = type(config.color) == "table" and config.color or {}
    local defaultColor = defaults.duration.color
    local seconds = type(color.seconds) == "table" and color.seconds or {}
    local percent = type(color.percent) == "table" and color.percent or {}

    local threshold
    if NormalizeBoolean(seconds.enabled, defaultColor.seconds.enabled) then
        local value = tonumber(seconds.value)
        if not IsFiniteNumber(value) or value <= 0 then
            value = defaultColor.seconds.value
        end
        threshold = {
            mode = "seconds",
            value = value,
            rgb = NormalizeColor(seconds.rgb, defaultColor.seconds.rgb),
        }
    elseif NormalizeBoolean(percent.enabled, defaultColor.percent.enabled) then
        local value = tonumber(percent.value)
        if not IsFiniteNumber(value) or value <= 0 or value >= 1 then
            value = defaultColor.percent.value
        end
        threshold = {
            mode = "percent",
            value = value,
            rgb = NormalizeColor(percent.rgb, defaultColor.percent.rgb),
        }
    end

    return {
        enabled = NormalizeBoolean(config.enabled, defaults.duration.enabled),
        font = NormalizeFont(config.font, defaults.duration.font),
        position = NormalizeTextPosition(
            config.position,
            defaults.duration.position
        ),
        color = {
            normal = NormalizeColor(
                color.normal,
                defaultColor.normal
            ),
            threshold = threshold,
        },
    }
end

local function CompileDebuffs(config)
    if type(config) ~= "table" then config = {} end

    local separateOwn = tonumber(config.separateOwn)
    if IsFiniteNumber(separateOwn) and separateOwn ~= 0 then
        return nil, "UNSUPPORTED_SEPARATE_OWN"
    end

    local width = NormalizeNumber(config.width, defaults.width, 10, 100, true)
    local height = NormalizeNumber(
        config.height,
        defaults.height,
        10,
        100,
        true
    )
    local spacingX = NormalizeNumber(
        config.spacingX,
        defaults.spacingX,
        -1,
        50,
        false
    )
    local spacingY = NormalizeNumber(
        config.spacingY,
        defaults.spacingY,
        -1,
        50,
        false
    )
    local wrapAfter = NormalizeNumber(
        config.wrapAfter,
        defaults.wrapAfter,
        1,
        50,
        true
    )
    local maxWraps = NormalizeNumber(
        config.maxWraps,
        defaults.maxWraps,
        1,
        50,
        true
    )
    local nativeSortMethod = SORT_METHODS[config.sortMethod]
        or SORT_METHODS[defaults.sortMethod]
    local nativeSortDirection = SORT_DIRECTIONS[config.sortDirection]
        or SORT_DIRECTIONS[defaults.sortDirection]
    local maximumLineSize = max(
        1,
        wrapAfter * width + (wrapAfter - 1) * spacingX
    )
    local layout = {
        elementSpacing = spacingX,
        lineSpacing = spacingY,
        groupSpacing = 0,
        groupLineSpacing = spacingY,
        forceNewLine = false,
        elementWidth = width,
        elementHeight = height,
    }
    local buttonStyle = {
        noBorder = false,
        width = width,
        height = height,
        iconInset = 1,
        desaturated = false,
        cooldownStyle = "clock",
        durationText = NormalizeDurationText(config.duration),
        stackText = NormalizeStackText(config.stack),
        tooltip = {
            enabled = true,
            anchorPoint = "ANCHOR_BOTTOMLEFT",
            offsetX = 0,
            offsetY = 0,
            hideInCombat = false,
        },
        nativeDispelColor = true,
    }

    local descriptor = {
        enabled = config.enabled == true
            and config.customHarmfulEnabled == true,
        constructionKey = {
            schema = CONSTRUCTION_SCHEMA,
            buttonStyle = buttonStyle,
        },
        holder = {
            width = maximumLineSize,
            height = height,
        },
        holderRolesets = "buffs",
        holderAnchor = {
            globalName = "DebuffFrame",
            point = "TOPRIGHT",
            relativePoint = "TOPRIGHT",
            x = 0,
            y = 0,
        },
        nativeSuppression = "harmful",
        containerPoint = {
            point = "TOPRIGHT",
            relativePoint = "TOPRIGHT",
            x = 0,
            y = 0,
        },
        flowLayout = {
            axis = flowAxis.Horizontal,
            anchorPoint = "TOPRIGHT",
            horizontalGrowthDirection = flowDirection.Left,
            verticalGrowthDirection = flowDirection.Down,
            paddingLeft = 0,
            paddingRight = 0,
            paddingTop = 0,
            paddingBottom = 0,
            maximumLineSize = maximumLineSize,
        },
        processing = {
            policy = processingPolicy.None,
        },
        groups = {
            {
                key = "harmful",
                filterString = "HARMFUL",
                maxFrameCount = wrapAfter * maxWraps,
                candidateFilters = {},
                sortMethod = nativeSortMethod,
                sortDirection = nativeSortDirection,
                layout = layout,
                buttonStyle = buttonStyle,
            },
        },
        itemEnchantments = {},
    }
    return descriptor
end

BD.RegisterCustomAuraContainerPane("debuffs", CompileDebuffs)
