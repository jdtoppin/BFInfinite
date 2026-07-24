---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames

local ceil, floor, huge, min = math.ceil, math.floor, math.huge, math.min
local ipairs, next, pairs, rawget, type = ipairs, next, pairs, rawget, type
local sub = string.sub

-- Retail 12.1.0.68914 (wow-ui-source d3915c78) creates restricted
-- CustomAuraContainer buttons in batches of ten. Keep the constant here as
-- audit metadata only; this compiler never creates a frame.
local NATIVE_BUTTON_BATCH_SIZE = 10

local ANCHOR_POINTS = {
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
    bottom_to_top = true,
    left_to_right = true,
    right_to_left = true,
    top_to_bottom = true,
}

local COOLDOWN_STYLES = {
    block_clock = true,
    block_clock_with_leading_edge = true,
    block_vertical = true,
    clock = true,
    clock_with_leading_edge = true,
    none = true,
    vertical = true,
}

local TOOLTIP_ANCHOR_TARGETS = {
    default = true,
    parent = true,
    root = true,
    self = true,
    self_adaptive = true,
}

-- GameTooltip:SetPoint(point, button, relativePoint) can only be represented
-- by the native button's SetOwner-style anchor for these opposing pairs.
local SELF_TOOLTIP_ANCHORS = {
    ["BOTTOM|TOP"] = "ANCHOR_TOP",
    ["BOTTOMLEFT|TOPRIGHT"] = "ANCHOR_TOPRIGHT",
    ["BOTTOMRIGHT|TOPLEFT"] = "ANCHOR_TOPLEFT",
    ["LEFT|RIGHT"] = "ANCHOR_RIGHT",
    ["RIGHT|LEFT"] = "ANCHOR_LEFT",
    ["TOP|BOTTOM"] = "ANCHOR_BOTTOM",
    ["TOPLEFT|BOTTOMRIGHT"] = "ANCHOR_BOTTOMRIGHT",
    ["TOPRIGHT|BOTTOMLEFT"] = "ANCHOR_BOTTOMLEFT",
}

local NATIVE_TOOLTIP_ANCHORS = {
    BOTTOM = "ANCHOR_BOTTOM",
    BOTTOMLEFT = "ANCHOR_BOTTOMLEFT",
    BOTTOMRIGHT = "ANCHOR_BOTTOMRIGHT",
    LEFT = "ANCHOR_LEFT",
    RIGHT = "ANCHOR_RIGHT",
    TOP = "ANCHOR_TOP",
    TOPLEFT = "ANCHOR_TOPLEFT",
    TOPRIGHT = "ANCHOR_TOPRIGHT",
}

local function IsNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -huge
        and value < huge
end

local function IsPositiveInteger(value)
    return IsFiniteNumber(value) and value > 0 and value == floor(value)
end

local function IsNonNegativeInteger(value)
    return IsFiniteNumber(value) and value >= 0 and value == floor(value)
end

local function Copy(value)
    if type(value) ~= "table" then return value end

    local copied = {}
    for key, child in pairs(value) do
        copied[Copy(key)] = Copy(child)
    end
    return copied
end

local function IsPosition(position)
    return type(position) == "table"
        and #position == 4
        and ANCHOR_POINTS[position[1]] == true
        and ANCHOR_POINTS[position[2]] == true
        and IsFiniteNumber(position[3])
        and IsFiniteNumber(position[4])
end

local function IsFont(font)
    return type(font) == "table"
        and IsNonEmptyString(font[1])
        and IsFiniteNumber(font[2])
        and font[2] > 0
        and (font[3] == nil or type(font[3]) == "string")
        and (font[4] == nil or type(font[4]) == "boolean")
end

local function IsColor(color)
    return type(color) == "table"
        and IsFiniteNumber(color[1])
        and IsFiniteNumber(color[2])
        and IsFiniteNumber(color[3])
        and (color[4] == nil or IsFiniteNumber(color[4]))
end

local function CopyFont(font)
    return {font[1], font[2], font[3], font[4]}
end

local function CopyPosition(position)
    return {position[1], position[2], position[3], position[4]}
end

local function CopyColor(color)
    return {color[1], color[2], color[3], color[4]}
end

local function ValidateDurationText(config)
    return type(config) == "table"
        and type(config.enabled) == "boolean"
        and IsFont(config.font)
        and IsPosition(config.position)
        and type(config.color) == "table"
        and IsColor(config.color.normal)
end

local function ValidateStackText(config)
    return type(config) == "table"
        and type(config.enabled) == "boolean"
        and IsFont(config.font)
        and IsPosition(config.position)
        and IsColor(config.color)
end

local function NormalizeDurationText(config)
    return {
        enabled = config.enabled,
        font = CopyFont(config.font),
        position = CopyPosition(config.position),
        color = {
            normal = CopyColor(config.color.normal),
        },
    }
end

local function NormalizeStackText(config)
    return {
        enabled = config.enabled,
        font = CopyFont(config.font),
        position = CopyPosition(config.position),
        color = CopyColor(config.color),
    }
end

local function NormalizeTooltip(config)
    if type(config) ~= "table" or type(config.enabled) ~= "boolean" then
        return nil, nil, "INVALID_TOOLTIP"
    end

    local tooltip = {
        enabled = config.enabled,
        hideInCombat = false,
    }
    if not config.enabled then
        return tooltip, false
    end
    if not TOOLTIP_ANCHOR_TARGETS[config.anchorTo]
        or not IsPosition(config.position)
    then
        return nil, nil, "INVALID_TOOLTIP"
    end

    if config.anchorTo == "self" then
        local key = config.position[1] .. "|" .. config.position[2]
        tooltip.anchorPoint = NATIVE_TOOLTIP_ANCHORS[config.position[2]]
        if tooltip.anchorPoint then
            tooltip.offsetX = config.position[3]
            tooltip.offsetY = config.position[4]
        end
        return tooltip, SELF_TOOLTIP_ANCHORS[key] == nil
    end

    -- Legacy root/parent/default placement is adaptive. Native restricted aura
    -- buttons expose only SetOwner-style anchors, so retain their default and
    -- report the approximation instead of rejecting a valid saved profile.
    return tooltip, true
end

local function NormalizePartition(subFrame)
    if subFrame == nil then return nil end
    if type(subFrame) ~= "table"
        or (subFrame.enabled ~= nil and type(subFrame.enabled) ~= "boolean")
    then
        return nil, "INVALID_SUBFRAME"
    end

    -- The legacy path treats every other filter as disabled.
    if not subFrame.enabled or subFrame.filter ~= "notCastByMe" then
        return nil
    end

    if type(subFrame.desaturated) ~= "boolean"
        or not IsFiniteNumber(subFrame.width)
        or subFrame.width <= 0
        or not IsFiniteNumber(subFrame.height)
        or subFrame.height <= 0
    then
        return nil, "INVALID_SUBFRAME"
    end

    return {
        filter = "notCastByMe",
        desaturated = subFrame.desaturated,
        width = subFrame.width,
        height = subFrame.height,
    }
end

local function GetNativeSchema()
    local anchorUtil = rawget(_G, "AnchorUtil")
    local sortMethod = rawget(_G, "AuraContainerSortMethod")
    local sortDirection = rawget(_G, "AuraContainerSortDirection")
    local processing = rawget(_G, "CustomAuraContainerAuraProcessingPolicy")

    local axis = anchorUtil and anchorUtil.FlowLayoutAxis
    local direction = anchorUtil and anchorUtil.FlowDirection
    if type(axis) ~= "table"
        or axis.Horizontal == nil
        or axis.Vertical == nil
        or type(direction) ~= "table"
        or direction.Left == nil
        or direction.Right == nil
        or direction.Up == nil
        or direction.Down == nil
        or type(sortMethod) ~= "table"
        or sortMethod.Default == nil
        or type(sortDirection) ~= "table"
        or sortDirection.Normal == nil
        or type(processing) ~= "table"
        or processing.None == nil
    then
        return nil
    end

    return {
        horizontalAxis = axis.Horizontal,
        verticalAxis = axis.Vertical,
        left = direction.Left,
        right = direction.Right,
        up = direction.Up,
        down = direction.Down,
        defaultSort = sortMethod.Default,
        normalSort = sortDirection.Normal,
        noProcessing = processing.None,
    }
end

local function GetFlow(config, schema)
    local orientation = config.orientation
    local anchor = config.position[1]
    local flowAnchor
    local horizontalDirection
    local verticalDirection
    local horizontal

    if orientation == "left_to_right" then
        horizontal = true
        horizontalDirection = schema.right
        if sub(anchor, 1, 6) == "BOTTOM" then
            flowAnchor = "BOTTOMLEFT"
            verticalDirection = schema.up
        else
            flowAnchor = "TOPLEFT"
            verticalDirection = schema.down
        end
    elseif orientation == "right_to_left" then
        horizontal = true
        horizontalDirection = schema.left
        if sub(anchor, 1, 6) == "BOTTOM" then
            flowAnchor = "BOTTOMRIGHT"
            verticalDirection = schema.up
        else
            flowAnchor = "TOPRIGHT"
            verticalDirection = schema.down
        end
    elseif orientation == "top_to_bottom" then
        horizontal = false
        verticalDirection = schema.down
        if sub(anchor, -5) == "RIGHT" then
            flowAnchor = "TOPRIGHT"
            horizontalDirection = schema.left
        else
            flowAnchor = "TOPLEFT"
            horizontalDirection = schema.right
        end
    else
        horizontal = false
        verticalDirection = schema.up
        if sub(anchor, -5) == "RIGHT" then
            flowAnchor = "BOTTOMRIGHT"
            horizontalDirection = schema.left
        else
            flowAnchor = "BOTTOMLEFT"
            horizontalDirection = schema.right
        end
    end

    return {
        horizontal = horizontal,
        anchor = flowAnchor,
        horizontalDirection = horizontalDirection,
        verticalDirection = verticalDirection,
    }
end

local function NewLayout(index, config, primarySpacing, crossSpacing)
    return {
        elementSpacing = primarySpacing,
        lineSpacing = crossSpacing,
        groupSpacing = 0,
        groupLineSpacing = crossSpacing,
        forceNewLine = false,
        elementWidth = config.width,
        elementHeight = config.height,
        layoutIndex = index,
    }
end

local function NewButtonStyle(baseFilter, config, tooltip)
    return {
        noBorder = true,
        width = config.width,
        height = config.height,
        desaturated = false,
        cooldownStyle = config.cooldownStyle,
        durationText = NormalizeDurationText(config.durationText),
        stackText = NormalizeStackText(config.stackText),
        dispelColor = baseFilter == "HARMFUL"
            and config.auraTypeColor ~= nil
            and config.auraTypeColor.debuffType == true,
        tooltip = Copy(tooltip),
    }
end

local function AddDiagnostic(diagnostics, code)
    diagnostics[#diagnostics + 1] = code
end

local function HasEntries(value)
    return type(value) == "table" and next(value) ~= nil
end

local function EmptyMetrics()
    return {
        groupCount = 0,
        legacyMaxFrameCount = 0,
        nativeVisibleCapacity = 0,
        nativeBatchSize = 0,
        initialRestrictedButtonCount = 0,
        freshContainerRestrictedButtonCountCeiling = 0,
    }
end

-- Compile only configuration-derived data. In particular, this function does
-- not read units, auras, frames, native buttons, combat state, or secrets.
function UF.CompileNativeAuraSpec(unit, baseFilter, config)
    if not IsNonEmptyString(unit) then
        return nil, "INVALID_UNIT"
    end
    if type(config) ~= "table" or type(config.enabled) ~= "boolean" then
        return nil, "INVALID_AURA_CONFIG"
    end

    local policy, policyError = UF.CompileNativeAuraPolicy(baseFilter, config.filters)
    if not policy then
        return nil, policyError
    end

    if not IsPosition(config.position) or not IsNonEmptyString(config.anchorTo) then
        return nil, "INVALID_PLACEMENT"
    end
    if not IsNonNegativeInteger(config.frameLevel) then
        return nil, "INVALID_FRAME_LEVEL"
    end
    if not ORIENTATIONS[config.orientation] then
        return nil, "INVALID_ORIENTATION"
    end
    if not IsFiniteNumber(config.width)
        or config.width <= 0
        or not IsFiniteNumber(config.height)
        or config.height <= 0
        or not IsFiniteNumber(config.spacingX)
        or not IsFiniteNumber(config.spacingY)
        or config.width + config.spacingX <= 0
        or config.height + config.spacingY <= 0
    then
        return nil, "INVALID_GEOMETRY"
    end
    if not IsPositiveInteger(config.numPerLine)
        or not IsPositiveInteger(config.numTotal)
    then
        return nil, "INVALID_COUNTS"
    end
    if not COOLDOWN_STYLES[config.cooldownStyle] then
        return nil, "INVALID_COOLDOWN_STYLE"
    end
    if not ValidateDurationText(config.durationText) then
        return nil, "INVALID_DURATION_TEXT"
    end
    if not ValidateStackText(config.stackText) then
        return nil, "INVALID_STACK_TEXT"
    end
    if config.auraTypeColor ~= nil
        and (type(config.auraTypeColor) ~= "table"
            or (config.auraTypeColor.debuffType ~= nil
                and type(config.auraTypeColor.debuffType) ~= "boolean"))
    then
        return nil, "INVALID_AURA_TYPE_COLOR"
    end

    local tooltip, tooltipApproximate, tooltipError = NormalizeTooltip(config.tooltip)
    if not tooltip then
        return nil, tooltipError
    end

    local partition, partitionError = NormalizePartition(config.subFrame)
    if partitionError then
        return nil, partitionError
    end

    local schema = GetNativeSchema()
    if not schema then
        return nil, "NATIVE_AURA_SCHEMA_UNAVAILABLE"
    end

    local empty = policy.empty
    local spellListsIgnored = not empty
        and (HasEntries(config.blacklist) or HasEntries(config.whitelist))
    local sourceColorsIgnored = not empty
        and config.auraTypeColor ~= nil
        and (config.auraTypeColor.castByMe == true
            or config.auraTypeColor.dispellable == true)
    local partitionDeferred = not empty and partition ~= nil
    local degradations = Copy(policy.degradations)
    degradations.defaultSortPriority = not empty
    degradations.fixedHolderExtent = not empty
    degradations.spellIDListsIgnored = spellListsIgnored
    degradations.auraTypeColorSourceRulesIgnored = sourceColorsIgnored
    degradations.tooltipPlacementApproximate = not empty and tooltipApproximate
    degradations.partitionDeferred = partitionDeferred

    local descriptor = {
        completeSpec = nil,
        tuningSpec = nil,
        constructionKey = {
            groups = {},
            slots = {},
        },
        placement = {
            position = CopyPosition(config.position),
            anchorTo = config.anchorTo,
            frameLevel = config.frameLevel,
        },
        visibility = {
            requiresVisible = policy.requiresVisible,
            requiresAssist = policy.requiresAssist,
        },
        partition = Copy(partition),
        migrationReady = not empty and not partitionDeferred,
        empty = empty,
        diagnostics = {},
        degradations = degradations,
        metrics = EmptyMetrics(),
    }

    if empty then
        return descriptor
    end

    AddDiagnostic(descriptor.diagnostics, "NATIVE_DEFAULT_SORT_ADDS_PRIORITY")
    AddDiagnostic(descriptor.diagnostics, "NATIVE_HOLDER_USES_MAXIMUM_EXTENT")
    if spellListsIgnored then
        AddDiagnostic(descriptor.diagnostics, "SPELL_ID_LISTS_IGNORED")
    end
    if sourceColorsIgnored then
        AddDiagnostic(
            descriptor.diagnostics,
            "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED"
        )
    end
    if tooltipApproximate then
        AddDiagnostic(descriptor.diagnostics, "TOOLTIP_PLACEMENT_APPROXIMATED")
    end
    if partitionDeferred then
        AddDiagnostic(descriptor.diagnostics, "TARGET_PARTITION_DEFERRED")
    end

    local groupCount = #policy.groups
    local capacity = groupCount * config.numTotal
    local perLine = min(config.numPerLine, config.numTotal)
    local lineSlots = min(capacity, perLine)
    local lines = ceil(capacity / perLine)
    local flow = GetFlow(config, schema)
    local primarySize = flow.horizontal and config.width or config.height
    local primarySpacing = flow.horizontal and config.spacingX or config.spacingY
    local crossSpacing = flow.horizontal and config.spacingY or config.spacingX
    local maximumLineSize = perLine * primarySize
        + (perLine - 1) * primarySpacing
    local primaryExtent = lineSlots * primarySize
        + (lineSlots - 1) * primarySpacing
    local crossSize = flow.horizontal and config.height or config.width
    local crossExtent = lines * crossSize + (lines - 1) * crossSpacing
    local holder = {
        width = flow.horizontal and primaryExtent or crossExtent,
        height = flow.horizontal and crossExtent or primaryExtent,
    }
    local containerPoint = {
        point = flow.anchor,
        relativePoint = flow.anchor,
        x = 0,
        y = 0,
    }
    local flowLayout = {
        axis = flow.horizontal and schema.horizontalAxis or schema.verticalAxis,
        anchorPoint = flow.anchor,
        horizontalGrowthDirection = flow.horizontalDirection,
        verticalGrowthDirection = flow.verticalDirection,
        paddingLeft = 0,
        paddingRight = 0,
        paddingTop = 0,
        paddingBottom = 0,
        maximumLineSize = maximumLineSize,
    }

    local completeGroups = {}
    local tuningGroups = {}
    for index, policyGroup in ipairs(policy.groups) do
        local layout = NewLayout(index, config, primarySpacing, crossSpacing)
        local style = NewButtonStyle(baseFilter, config, tooltip)
        completeGroups[index] = {
            key = policyGroup.key,
            filterString = policyGroup.filterString,
            maxFrameCount = config.numTotal,
            sortMethod = schema.defaultSort,
            sortDirection = schema.normalSort,
            layout = layout,
            buttonStyle = style,
        }
        tuningGroups[index] = {
            key = policyGroup.key,
            filterString = policyGroup.filterString,
            maxFrameCount = config.numTotal,
            sortMethod = schema.defaultSort,
            sortDirection = schema.normalSort,
            layout = Copy(layout),
        }
        descriptor.constructionKey.groups[index] = {
            key = policyGroup.key,
            buttonStyle = Copy(style),
        }
    end

    descriptor.completeSpec = {
        unit = unit,
        enabled = config.enabled,
        shown = false,
        holder = Copy(holder),
        containerPoint = Copy(containerPoint),
        flowLayout = Copy(flowLayout),
        processing = {
            policy = schema.noProcessing,
        },
        groups = completeGroups,
        slots = {},
    }
    descriptor.tuningSpec = {
        holder = Copy(holder),
        containerPoint = Copy(containerPoint),
        flowLayout = Copy(flowLayout),
        processing = {
            policy = schema.noProcessing,
        },
        groups = tuningGroups,
        slots = {},
    }
    descriptor.metrics = {
        groupCount = groupCount,
        legacyMaxFrameCount = config.numTotal,
        nativeVisibleCapacity = capacity,
        nativeBatchSize = NATIVE_BUTTON_BATCH_SIZE,
        initialRestrictedButtonCount = groupCount * NATIVE_BUTTON_BATCH_SIZE,
        -- Fresh containers can grow only as far as each group's configured
        -- maximum. Native frame pools do not shrink after later tuning.
        freshContainerRestrictedButtonCountCeiling = groupCount
            * ceil(config.numTotal / NATIVE_BUTTON_BATCH_SIZE)
            * NATIVE_BUTTON_BATCH_SIZE,
    }

    return descriptor
end
