---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework
local type = type
local afVersion = type(AF) == "table" and AF.versionNum or nil

-- AF r40 added the native duration-color binding used by this pane. Keep the
-- local registration gate ahead of capability, defaults, and schema reads so
-- r36-r39 cannot activate a container that silently drops legacy thresholds.
if type(afVersion) ~= "number"
    or afVersion ~= afVersion
    or afVersion == math.huge
    or afVersion == -math.huge
    or afVersion < 40
then
    return
end

-- Retail 12.1.0.69273 (wow-ui-source
-- eb941aad028d73ddc69e3e8ef4da709f4d3cd744) ManagedAuraContainer supplies
-- every CustomAuraContainer the native PublicAndPrivate source list. This
-- pane's HELPFUL group therefore consumes the combined ordinary/private
-- authorized Buffs source; HARMFUL remains Blizzard-owned to avoid duplicating
-- DebuffFrame's private anchors.
if type(BD.RegisterCustomAuraContainerPane) ~= "function"
    or type(BD.HasCustomAuraContainerCapability) ~= "function"
    or BD.HasCustomAuraContainerCapability() ~= true
then
    return
end

local ceil = math.ceil
local floor = math.floor
local max = math.max
local tonumber = tonumber

local flowAxis = _G.AnchorUtil.FlowLayoutAxis
local flowDirection = _G.AnchorUtil.FlowDirection
local sortMethod = _G.AuraContainerSortMethod
local sortDirection = _G.AuraContainerSortDirection
local enchantmentSlot = _G.AuraContainerItemEnchantmentSlot
local enchantmentSortMethod = _G.AuraContainerItemEnchantmentSortMethod
local processingPolicy = _G.CustomAuraContainerAuraProcessingPolicy
local enchantmentPlacement =
    _G.CustomAuraContainerItemEnchantmentPlacement

local defaults = BD.GetDefaults().buffs
local CONSTRUCTION_SCHEMA = 1
local MAX_POSITION_OFFSET = 10000

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

local ORIENTATIONS = {
    left_to_right_then_down = {
        axis = flowAxis.Horizontal,
        anchorPoint = "TOPLEFT",
        horizontalGrowthDirection = flowDirection.Right,
        verticalGrowthDirection = flowDirection.Down,
    },
    left_to_right_then_up = {
        axis = flowAxis.Horizontal,
        anchorPoint = "BOTTOMLEFT",
        horizontalGrowthDirection = flowDirection.Right,
        verticalGrowthDirection = flowDirection.Up,
    },
    right_to_left_then_down = {
        axis = flowAxis.Horizontal,
        anchorPoint = "TOPRIGHT",
        horizontalGrowthDirection = flowDirection.Left,
        verticalGrowthDirection = flowDirection.Down,
    },
    right_to_left_then_up = {
        axis = flowAxis.Horizontal,
        anchorPoint = "BOTTOMRIGHT",
        horizontalGrowthDirection = flowDirection.Left,
        verticalGrowthDirection = flowDirection.Up,
    },
    top_to_bottom_then_left = {
        axis = flowAxis.Vertical,
        anchorPoint = "TOPRIGHT",
        horizontalGrowthDirection = flowDirection.Left,
        verticalGrowthDirection = flowDirection.Down,
    },
    top_to_bottom_then_right = {
        axis = flowAxis.Vertical,
        anchorPoint = "TOPLEFT",
        horizontalGrowthDirection = flowDirection.Right,
        verticalGrowthDirection = flowDirection.Down,
    },
    bottom_to_top_then_left = {
        axis = flowAxis.Vertical,
        anchorPoint = "BOTTOMRIGHT",
        horizontalGrowthDirection = flowDirection.Left,
        verticalGrowthDirection = flowDirection.Up,
    },
    bottom_to_top_then_right = {
        axis = flowAxis.Vertical,
        anchorPoint = "BOTTOMLEFT",
        horizontalGrowthDirection = flowDirection.Right,
        verticalGrowthDirection = flowDirection.Up,
    },
}

local SORT_METHODS = {
    INDEX = sortMethod.AuraInstanceIDOnly,
    NAME = sortMethod.NameOnly,
    TIME = sortMethod.ExpirationOnly,
}

local SORT_DIRECTIONS = {
    ["+"] = sortDirection.Normal,
    ["-"] = sortDirection.Reverse,
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

local function NormalizeHolderPosition(value)
    local fallback = defaults.position
    if type(value) ~= "table" then value = {} end

    local point = NormalizeAnchor(value[1], fallback[1])
    if type(value[2]) == "string" then
        return {
            point,
            NormalizeAnchor(value[2], point),
            NormalizeNumber(
                value[3],
                fallback[2],
                -MAX_POSITION_OFFSET,
                MAX_POSITION_OFFSET,
                false
            ),
            NormalizeNumber(
                value[4],
                fallback[3],
                -MAX_POSITION_OFFSET,
                MAX_POSITION_OFFSET,
                false
            ),
        }
    end

    return {
        point,
        NormalizeNumber(
            value[2],
            fallback[2],
            -MAX_POSITION_OFFSET,
            MAX_POSITION_OFFSET,
            false
        ),
        NormalizeNumber(
            value[3],
            fallback[3],
            -MAX_POSITION_OFFSET,
            MAX_POSITION_OFFSET,
            false
        ),
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

local function CreateGroupLayout(
    width,
    height,
    primarySpacing,
    crossSpacing
)
    return {
        elementSpacing = primarySpacing,
        lineSpacing = crossSpacing,
        groupSpacing = 0,
        groupLineSpacing = crossSpacing,
        forceNewLine = false,
        elementWidth = width,
        elementHeight = height,
    }
end

local function CompileBuffs(config)
    if type(config) ~= "table" then config = {} end

    local separateOwn = tonumber(config.separateOwn)
    if IsFiniteNumber(separateOwn) and separateOwn ~= 0 then
        return nil, "UNSUPPORTED_SEPARATE_OWN"
    end

    local width = NormalizeNumber(
        config.width,
        defaults.width,
        10,
        100,
        true
    )
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

    local orientation = ORIENTATIONS[config.orientation]
        or ORIENTATIONS[defaults.orientation]
    local nativeSortMethod = SORT_METHODS[config.sortMethod]
        or SORT_METHODS[defaults.sortMethod]
    local nativeSortDirection = SORT_DIRECTIONS[config.sortDirection]
        or SORT_DIRECTIONS[defaults.sortDirection]

    local isHorizontal = orientation.axis == flowAxis.Horizontal
    local primarySize = isHorizontal and width or height
    local crossSize = isHorizontal and height or width
    local primarySpacing = isHorizontal and spacingX or spacingY
    local crossSpacing = isHorizontal and spacingY or spacingX
    local auraCap = wrapAfter * maxWraps
    local maximumLineSize = max(
        1,
        wrapAfter * primarySize + (wrapAfter - 1) * primarySpacing
    )

    -- maxFrameCount applies to the HELPFUL group only. Main-hand and off-hand
    -- enchantments can add two more frames, so size the hover/mover holder for
    -- their worst-case extra lines without claiming a strict global cap.
    local worstLineCount = ceil((auraCap + 2) / wrapAfter)
    local crossExtent = max(
        1,
        worstLineCount * crossSize
            + (worstLineCount - 1) * crossSpacing
    )
    local holderWidth = isHorizontal and maximumLineSize or crossExtent
    local holderHeight = isHorizontal and crossExtent or maximumLineSize

    local groupLayout = CreateGroupLayout(
        width,
        height,
        primarySpacing,
        crossSpacing
    )
    local itemEnchantmentLayout = CreateGroupLayout(
        width,
        height,
        primarySpacing,
        crossSpacing
    )
    itemEnchantmentLayout.placement =
        enchantmentPlacement.BeforeAuraGroups

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
        cancelAuraButtons = "RightButtonUp",
    }

    local moverText = _G.HUD_EDIT_MODE_BUFF_FRAME_LABEL
    if type(moverText) ~= "string" or moverText == "" then
        moverText = L["Buffs"]
    end

    return {
        enabled = config.enabled == true,
        constructionKey = {
            schema = CONSTRUCTION_SCHEMA,
            buttonStyle = buttonStyle,
        },
        holder = {
            width = holderWidth,
            height = holderHeight,
        },
        containerPoint = {
            point = orientation.anchorPoint,
            relativePoint = orientation.anchorPoint,
            x = 0,
            y = 0,
        },
        flowLayout = {
            axis = orientation.axis,
            anchorPoint = orientation.anchorPoint,
            horizontalGrowthDirection =
                orientation.horizontalGrowthDirection,
            verticalGrowthDirection = orientation.verticalGrowthDirection,
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
                key = "helpful",
                filterString = "HELPFUL",
                maxFrameCount = auraCap,
                candidateFilters = {},
                sortMethod = nativeSortMethod,
                sortDirection = nativeSortDirection,
                layout = groupLayout,
                buttonStyle = buttonStyle,
            },
        },
        itemEnchantments = {
            {
                slot = enchantmentSlot.MainHand,
                options = {hidePermanent = false},
                buttonStyle = buttonStyle,
            },
            {
                slot = enchantmentSlot.OffHand,
                options = {hidePermanent = false},
                buttonStyle = buttonStyle,
            },
        },
        itemEnchantmentSort = {
            method = enchantmentSortMethod.Slot,
            direction = sortDirection.Normal,
        },
        itemEnchantmentLayout = itemEnchantmentLayout,
        position = NormalizeHolderPosition(config.position),
        positionSave = type(config.position) == "table"
            and config.position
            or nil,
        moverText = moverText,
    }
end

BD.RegisterCustomAuraContainerPane("buffs", CompileBuffs)
