---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames

local ceil, floor, huge, max, min =
    math.ceil, math.floor, math.huge, math.max, math.min
local ipairs, next, pairs, rawget, sort, type =
    ipairs, next, pairs, rawget, table.sort, type
local format, sub = string.format, string.sub

-- Retail 12.1.0.68914 (wow-ui-source d3915c78) creates restricted
-- CustomAuraContainer buttons in batches of ten. Keep the constant here as
-- audit metadata only; this compiler never creates a frame.
local NATIVE_BUTTON_BATCH_SIZE = 10
-- Cap only the extra groups requested by spell-colour expansion. A baseline
-- policy may already require more than eight active groups after a relation
-- partition duplicates any-scope categories; that exact gray policy remains
-- intact. Colour expansion falls back as a whole and never drops categories.
local MAX_NATIVE_COLOR_EXPANDED_GROUPS = 8

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

local function IsBlockCooldownStyle(style)
    return sub(style, 1, 5) == "block"
end

local function IsDurationThresholdOption(option, mode)
    if type(option) ~= "table"
        or type(option.enabled) ~= "boolean"
    then
        return false
    end
    if not option.enabled then return true end
    if not IsFiniteNumber(option.value) or not IsColor(option.rgb) then
        return false
    end

    if mode == "seconds" then
        return option.value > 0
    end
    return option.value > 0 and option.value < 1
end

local function ValidateDurationText(config)
    return type(config) == "table"
        and type(config.enabled) == "boolean"
        and IsFont(config.font)
        and IsPosition(config.position)
        and type(config.color) == "table"
        and IsColor(config.color.normal)
        and IsDurationThresholdOption(config.color.percent, "percent")
        and IsDurationThresholdOption(config.color.seconds, "seconds")
end

local function ValidateStackText(config)
    return type(config) == "table"
        and type(config.enabled) == "boolean"
        and IsFont(config.font)
        and IsPosition(config.position)
        and IsColor(config.color)
end

local function NormalizeDurationText(config)
    local normalized = {
        enabled = config.enabled,
        font = CopyFont(config.font),
        position = CopyPosition(config.position),
        color = {
            normal = CopyColor(config.color.normal),
        },
    }

    -- The native duration binding accepts one color curve against one
    -- remaining-time property. Legacy BFI allowed both rules at once and
    -- evaluated seconds first, so retain that priority when loading an
    -- existing profile with both flags enabled.
    local threshold
    if config.color.seconds.enabled then
        threshold = {
            mode = "seconds",
            value = config.color.seconds.value,
            rgb = CopyColor(config.color.seconds.rgb),
        }
    elseif config.color.percent.enabled then
        threshold = {
            mode = "percent",
            value = config.color.percent.value,
            rgb = CopyColor(config.color.percent.rgb),
        }
    end
    normalized.color.threshold = threshold

    return normalized
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

local function NormalizeSpellIDCandidateFilters(config)
    local mode = config.mode
    if mode ~= "blacklist" and mode ~= "whitelist" then
        return nil, nil, "INVALID_SPELL_ID_FILTER_MODE"
    end

    local list = config[mode]
    local invalidListError = mode == "blacklist"
        and "INVALID_SPELL_ID_BLACKLIST"
        or "INVALID_SPELL_ID_WHITELIST"
    if type(list) ~= "table" then
        return nil, nil, invalidListError
    end

    local count = 0
    for index, spellID in pairs(list) do
        if not IsPositiveInteger(index) or not IsPositiveInteger(spellID) then
            return nil, nil, invalidListError
        end
        count = count + 1
    end

    local spellIDs = {}
    for index = 1, count do
        local spellID = rawget(list, index)
        if not IsPositiveInteger(spellID) then
            return nil, nil, invalidListError
        end
        spellIDs[spellID] = true
    end

    if mode == "whitelist" then
        -- An empty include map is intentional: whitelist mode with no entries
        -- must include no aura identities rather than disable filtering.
        return {
            includeSpellIDs = spellIDs,
        }, true
    end
    if count > 0 then
        return {
            excludeSpellIDs = spellIDs,
        }, true
    end
    return nil, false
end

local function GetColorKey(color)
    return format(
        "%.17g|%.17g|%.17g|%.17g",
        color[1],
        color[2],
        color[3],
        color[4]
    )
end

local function NormalizeNativeSpellColorBuckets(config)
    -- Global Colors apply only to Block rows. Helpful rows require an
    -- assistable unit and harmful rows require a non-assistable unit later;
    -- otherwise Blizzard can bypass every identity map and duplicate auras
    -- across colour groups.
    if not IsBlockCooldownStyle(config.cooldownStyle)
        or config.spellColors == nil
    then
        return nil, nil, false
    end
    if type(config.spellColors) ~= "table" then
        return nil, nil, nil, "INVALID_SPELL_COLOR_MAP"
    end

    local bucketByKey = {}
    local bucketKeys = {}
    local coloredSpellIDs = {}
    for spellID, color in pairs(config.spellColors) do
        if not IsPositiveInteger(spellID)
            or not IsColor(color)
            or not IsFiniteNumber(color[4])
        then
            return nil, nil, nil, "INVALID_SPELL_COLOR_MAP"
        end

        local colorKey = GetColorKey(color)
        local bucket = bucketByKey[colorKey]
        if not bucket then
            bucket = {
                color = CopyColor(color),
                spellIDs = {},
            }
            bucketByKey[colorKey] = bucket
            bucketKeys[#bucketKeys + 1] = colorKey
        end
        bucket.spellIDs[spellID] = true
        coloredSpellIDs[spellID] = true
    end

    if not next(coloredSpellIDs) then
        return nil, nil, false
    end

    sort(bucketKeys)
    local buckets = {}
    for index, colorKey in ipairs(bucketKeys) do
        local bucket = bucketByKey[colorKey]
        buckets[index] = {
            color = CopyColor(bucket.color),
            spellIDs = Copy(bucket.spellIDs),
        }
    end
    return buckets, coloredSpellIDs, true
end

local function CopyNonIdentityCandidateFilters(candidateFilters)
    local copied = {}
    for key, value in pairs(candidateFilters or {}) do
        if key ~= "includeSpellIDs"
            and key ~= "excludeSpellIDs"
        then
            copied[key] = Copy(value)
        end
    end
    return copied
end

local function BuildColoredCandidateFilters(
    candidateFilters,
    bucketSpellIDs
)
    local baseInclude = candidateFilters
        and candidateFilters.includeSpellIDs
    local baseExclude = candidateFilters
        and candidateFilters.excludeSpellIDs
    local combined =
        CopyNonIdentityCandidateFilters(candidateFilters)

    local includeSpellIDs = {}
    for spellID in pairs(bucketSpellIDs) do
        if baseInclude == nil or baseInclude[spellID] then
            includeSpellIDs[spellID] = true
        end
    end
    combined.includeSpellIDs = includeSpellIDs
    if baseInclude == nil and baseExclude ~= nil then
        combined.excludeSpellIDs = Copy(baseExclude)
    end
    return combined
end

local function BuildDefaultCandidateFilters(
    candidateFilters,
    coloredSpellIDs
)
    local baseInclude = candidateFilters
        and candidateFilters.includeSpellIDs
    local baseExclude = candidateFilters
        and candidateFilters.excludeSpellIDs
    local combined =
        CopyNonIdentityCandidateFilters(candidateFilters)

    if baseInclude ~= nil then
        local includeSpellIDs = {}
        for spellID in pairs(baseInclude) do
            if not coloredSpellIDs[spellID]
                and (
                    baseExclude == nil
                    or not baseExclude[spellID]
                )
            then
                includeSpellIDs[spellID] = true
            end
        end
        combined.includeSpellIDs = includeSpellIDs
        return combined
    end

    local excludeSpellIDs = Copy(coloredSpellIDs)
    for spellID in pairs(baseExclude or {}) do
        excludeSpellIDs[spellID] = true
    end
    combined.excludeSpellIDs = excludeSpellIDs
    return combined
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

local function NewLayout(
    index,
    width,
    height,
    primarySpacing,
    crossSpacing,
    horizontal,
    reserveTrailingCrossSpacing
)
    local elementWidth = width
    local elementHeight = height
    local lineSpacing = crossSpacing

    if reserveTrailingCrossSpacing then
        -- CustomAuraContainer clamps its empty size to one. Give every
        -- populated line one extra cross-axis pixel and overlap lines by one;
        -- the dependent attachment then offsets one pixel back toward the
        -- origin. Empty displacement becomes zero, while N populated lines
        -- displace the complementary container by N * (size + spacing).
        lineSpacing = -1
        if horizontal then
            elementHeight = height + crossSpacing + 1
        else
            elementWidth = width + crossSpacing + 1
        end
    end

    return {
        elementSpacing = primarySpacing,
        lineSpacing = lineSpacing,
        groupSpacing = 0,
        groupLineSpacing = lineSpacing,
        forceNewLine = false,
        elementWidth = elementWidth,
        elementHeight = elementHeight,
        layoutIndex = index,
    }
end

local function NewButtonStyle(
    baseFilter,
    config,
    tooltip,
    appearance,
    blockColor
)
    local style = {
        noBorder = true,
        width = appearance.width,
        height = appearance.height,
        desaturated = appearance.desaturated,
        cooldownStyle = config.cooldownStyle,
        durationText = NormalizeDurationText(config.durationText),
        stackText = NormalizeStackText(config.stackText),
        dispelColor = baseFilter == "HARMFUL"
            and config.auraTypeColor ~= nil
            and config.auraTypeColor.debuffType == true,
        tooltip = Copy(tooltip),
    }

    -- This is ordinary saved configuration, never aura-derived data. Omit it
    -- for icon styles so an inactive setting cannot affect native construction.
    if IsBlockCooldownStyle(config.cooldownStyle)
        and blockColor ~= nil
    then
        style.blockColor = CopyColor(blockColor)
    end

    return style
end

local function AddDiagnostic(diagnostics, code)
    diagnostics[#diagnostics + 1] = code
end

local function EmptyMetrics()
    return {
        groupCount = 0,
        legacyMaxFrameCount = 0,
        nativeVisibleCapacity = 0,
        nativeBatchSize = 0,
        initialRestrictedButtonCount = 0,
        freshContainerRestrictedButtonCountCeiling = 0,
        requestedColorBucketCount = 0,
        requestedColorExpandedGroupCount = 0,
        requestedColorExpandedCapacity = 0,
        colorGroupBudgetExceeded = false,
    }
end

local function ExpandGroupDefinitions(
    policyGroups,
    candidateFilters,
    spellColorsActive,
    spellColorBuckets,
    coloredSpellIDs
)
    local definitions = {}

    for _, policyGroup in ipairs(policyGroups) do
        if spellColorsActive then
            for colorIndex, bucket in ipairs(spellColorBuckets) do
                definitions[#definitions + 1] = {
                    key = policyGroup.key
                        .. "_color_"
                        .. colorIndex,
                    filterString = policyGroup.filterString,
                    playerScope = policyGroup.playerScope,
                    candidateFilters = BuildColoredCandidateFilters(
                        candidateFilters,
                        bucket.spellIDs
                    ),
                    blockColor = CopyColor(bucket.color),
                }
            end

            definitions[#definitions + 1] = {
                key = policyGroup.key .. "_default",
                filterString = policyGroup.filterString,
                playerScope = policyGroup.playerScope,
                candidateFilters = BuildDefaultCandidateFilters(
                    candidateFilters,
                    coloredSpellIDs
                ),
            }
        else
            definitions[#definitions + 1] = {
                key = policyGroup.key,
                filterString = policyGroup.filterString,
                playerScope = policyGroup.playerScope,
                candidateFilters = Copy(candidateFilters),
            }
        end
    end

    return definitions
end

local function GetContainerGeometry(config, flow, schema, groupCount, appearance)
    local capacity = groupCount * config.numTotal
    local perLine = min(config.numPerLine, config.numTotal)
    local lineSlots = min(capacity, perLine)
    local lines = ceil(capacity / perLine)
    local primarySize = flow.horizontal
        and appearance.width
        or appearance.height
    local primarySpacing = flow.horizontal
        and config.spacingX
        or config.spacingY
    local crossSpacing = flow.horizontal
        and config.spacingY
        or config.spacingX
    local crossSize = flow.horizontal
        and appearance.height
        or appearance.width
    local maximumLineSize = perLine * primarySize
        + (perLine - 1) * primarySpacing
    local primaryExtent = lineSlots * primarySize
        + (lineSlots - 1) * primarySpacing
    local crossExtent = lines * crossSize + (lines - 1) * crossSpacing
    local holder = {
        width = flow.horizontal and primaryExtent or crossExtent,
        height = flow.horizontal and crossExtent or primaryExtent,
    }

    return {
        capacity = capacity,
        lines = lines,
        primaryExtent = primaryExtent,
        crossExtent = crossExtent,
        primarySpacing = primarySpacing,
        crossSpacing = crossSpacing,
        crossSize = crossSize,
        holder = holder,
        containerPoint = {
            point = flow.anchor,
            relativePoint = flow.anchor,
            x = 0,
            y = 0,
        },
        flowLayout = {
            axis = flow.horizontal
                and schema.horizontalAxis
                or schema.verticalAxis,
            anchorPoint = flow.anchor,
            horizontalGrowthDirection = flow.horizontalDirection,
            verticalGrowthDirection = flow.verticalDirection,
            paddingLeft = 0,
            paddingRight = 0,
            paddingTop = 0,
            paddingBottom = 0,
            maximumLineSize = maximumLineSize,
        },
    }
end

local function NewVariantMetrics(groupCount, config, geometry)
    return {
        groupCount = groupCount,
        nativeVisibleCapacity = geometry.capacity,
        initialRestrictedButtonCount =
            groupCount * NATIVE_BUTTON_BATCH_SIZE,
        freshContainerRestrictedButtonCountCeiling = groupCount
            * ceil(config.numTotal / NATIVE_BUTTON_BATCH_SIZE)
            * NATIVE_BUTTON_BATCH_SIZE,
        holder = Copy(geometry.holder),
    }
end

local function CompileContainerVariant(
    unit,
    baseFilter,
    config,
    schema,
    flow,
    tooltip,
    groups,
    appearance,
    reserveTrailingCrossSpacing
)
    local groupCount = #groups
    if groupCount == 0 then return nil end

    local geometry = GetContainerGeometry(
        config,
        flow,
        schema,
        groupCount,
        appearance
    )
    local completeGroups = {}
    local tuningGroups = {}
    local constructionKey = {
        groups = {},
        slots = {},
    }

    for index, policyGroup in ipairs(groups) do
        local layout = NewLayout(
            index,
            appearance.width,
            appearance.height,
            geometry.primarySpacing,
            geometry.crossSpacing,
            flow.horizontal,
            reserveTrailingCrossSpacing
        )
        local style = NewButtonStyle(
            baseFilter,
            config,
            tooltip,
            appearance,
            policyGroup.blockColor
        )
        completeGroups[index] = {
            key = policyGroup.key,
            filterString = policyGroup.filterString,
            maxFrameCount = config.numTotal,
            candidateFilters = Copy(policyGroup.candidateFilters),
            sortMethod = schema.defaultSort,
            sortDirection = schema.normalSort,
            layout = layout,
            buttonStyle = style,
        }
        tuningGroups[index] = {
            key = policyGroup.key,
            filterString = policyGroup.filterString,
            maxFrameCount = config.numTotal,
            candidateFilters = Copy(policyGroup.candidateFilters),
            sortMethod = schema.defaultSort,
            sortDirection = schema.normalSort,
            layout = Copy(layout),
        }
        constructionKey.groups[index] = {
            key = policyGroup.key,
            buttonStyle = Copy(style),
        }
    end

    return {
        completeSpec = {
            unit = unit,
            enabled = config.enabled,
            shown = false,
            holder = Copy(geometry.holder),
            containerPoint = Copy(geometry.containerPoint),
            flowLayout = Copy(geometry.flowLayout),
            processing = {
                policy = schema.noProcessing,
            },
            groups = completeGroups,
            slots = {},
        },
        tuningSpec = {
            holder = Copy(geometry.holder),
            containerPoint = Copy(geometry.containerPoint),
            flowLayout = Copy(geometry.flowLayout),
            processing = {
                policy = schema.noProcessing,
            },
            groups = tuningGroups,
            slots = {},
        },
        constructionKey = constructionKey,
        metrics = NewVariantMetrics(groupCount, config, geometry),
    }, geometry
end

local function SplitPartitionGroups(policyGroups)
    local mainGroups = {}
    local complementGroups = {}

    for _, group in ipairs(policyGroups) do
        if group.playerScope == "player" then
            mainGroups[#mainGroups + 1] = {
                key = group.key,
                filterString = group.filterString,
                candidateFilters = Copy(group.candidateFilters),
                blockColor = group.blockColor
                    and CopyColor(group.blockColor)
                    or nil,
            }
        elseif group.playerScope == "notPlayer" then
            complementGroups[#complementGroups + 1] = {
                key = group.key,
                filterString = group.filterString,
                candidateFilters = Copy(group.candidateFilters),
                blockColor = group.blockColor
                    and CopyColor(group.blockColor)
                    or nil,
            }
        else
            mainGroups[#mainGroups + 1] = {
                key = group.key,
                filterString = group.filterString .. "|PLAYER",
                candidateFilters = Copy(group.candidateFilters),
                blockColor = group.blockColor
                    and CopyColor(group.blockColor)
                    or nil,
            }
            complementGroups[#complementGroups + 1] = {
                key = group.key,
                filterString = group.filterString .. "|!PLAYER",
                candidateFilters = Copy(group.candidateFilters),
                blockColor = group.blockColor
                    and CopyColor(group.blockColor)
                    or nil,
            }
        end
    end

    return mainGroups, complementGroups
end

local function GetPartitionAttachment(flow)
    local point = flow.anchor
    local relativePoint
    local x, y = 0, 0

    if flow.horizontal then
        if sub(point, 1, 6) == "BOTTOM" then
            relativePoint = "TOP" .. sub(point, 7)
            y = -1
        else
            relativePoint = "BOTTOM" .. sub(point, 4)
            y = 1
        end
    elseif sub(point, -5) == "RIGHT" then
        relativePoint = sub(point, 1, -6) .. "LEFT"
        x = 1
    else
        relativePoint = sub(point, 1, -5) .. "RIGHT"
        x = -1
    end

    return {
        template = "DisableUntrustedLayoutScriptsTemplate",
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function GetHostileHolder(flow, mainGeometry, complementGeometry)
    if not mainGeometry then
        return Copy(complementGeometry.holder)
    end
    if not complementGeometry then
        return Copy(mainGeometry.holder)
    end

    local attachmentDisplacement = mainGeometry.lines
        * (mainGeometry.crossSize + mainGeometry.crossSpacing)
    local crossExtent = max(
        mainGeometry.crossExtent,
        attachmentDisplacement + complementGeometry.crossExtent
    )
    local primaryExtent = max(
        mainGeometry.primaryExtent,
        complementGeometry.primaryExtent
    )

    return {
        width = flow.horizontal and primaryExtent or crossExtent,
        height = flow.horizontal and crossExtent or primaryExtent,
    }
end

local function GetCompositeHolder(friendlyHolder, hostileHolder)
    return {
        width = max(friendlyHolder.width, hostileHolder.width),
        height = max(friendlyHolder.height, hostileHolder.height),
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

    local candidateFilters, identityFilterActive, identityFilterError =
        NormalizeSpellIDCandidateFilters(config)
    if identityFilterError then
        return nil, identityFilterError
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
    local spellColorBuckets, coloredSpellIDs, spellColorsRequested,
        spellColorError =
        NormalizeNativeSpellColorBuckets(config)
    if spellColorError then
        return nil, spellColorError
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
    if partition
        and (
            partition.width + config.spacingX <= 0
            or partition.height + config.spacingY <= 0
        )
    then
        return nil, "INVALID_SUBFRAME"
    end

    local schema = GetNativeSchema()
    if not schema then
        return nil, "NATIVE_AURA_SCHEMA_UNAVAILABLE"
    end

    local empty = policy.empty
    local partitionActive = not empty and partition ~= nil
    local requestedColorBucketCount =
        spellColorsRequested and #spellColorBuckets or 0
    local requestedColorMultiplier =
        requestedColorBucketCount + 1
    local requestedFriendlyColorGroupCount =
        spellColorsRequested
        and #policy.groups * requestedColorMultiplier
        or 0
    local requestedHostileColorGroupCount = 0
    if spellColorsRequested and partitionActive then
        local hostilePolicyGroupCount = 0
        for _, policyGroup in ipairs(policy.groups) do
            hostilePolicyGroupCount = hostilePolicyGroupCount
                + (
                    policyGroup.playerScope == "any"
                    and 2
                    or 1
                )
        end
        requestedHostileColorGroupCount =
            hostilePolicyGroupCount * requestedColorMultiplier
    end
    local requestedColorExpandedGroupCount =
        max(
            requestedFriendlyColorGroupCount,
            requestedHostileColorGroupCount
        )
    local requestedColorExpandedCapacity =
        requestedColorExpandedGroupCount * config.numTotal
    local colorGroupBudgetExceeded =
        requestedColorExpandedGroupCount
            > MAX_NATIVE_COLOR_EXPANDED_GROUPS
    local spellColorsActive = not empty
        and spellColorsRequested
        and not colorGroupBudgetExceeded
    -- 12.1 evaluates these maps inside the restricted aura container.
    -- Identity matching is reaction-gated there: helpful auras require an
    -- assistable unit and harmful auras require a non-assistable unit, except
    -- for spells Blizzard classifies NeverSecret. Keep the full map and make
    -- BFI's holder use only the direction where the map cannot be bypassed.
    local spellIDFiltersRestricted = not empty
        and (identityFilterActive or spellColorsActive)
    local sourceColorsIgnored = not empty
        and config.auraTypeColor ~= nil
        and (config.auraTypeColor.castByMe == true
            or config.auraTypeColor.dispellable == true)
    local degradations = Copy(policy.degradations)
    degradations.defaultSortPriority = not empty
    degradations.fixedHolderExtent = not empty
    degradations.spellIDListsIgnored = false
    degradations.spellIDFiltersRestrictedByUnitReaction =
        spellIDFiltersRestricted
    degradations.globalSpellColorsUseIndependentGroups =
        not empty and spellColorsActive
    degradations.globalSpellColorsBudgetExceeded =
        not empty and colorGroupBudgetExceeded
    degradations.auraTypeColorSourceRulesIgnored = sourceColorsIgnored
    degradations.tooltipPlacementApproximate = not empty and tooltipApproximate
    degradations.partitionDeferred = false
    degradations.partitionSecretFallback = partitionActive

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
            requiresAssist = policy.requiresAssist
                or (
                    baseFilter == "HELPFUL"
                    and (
                        identityFilterActive
                        or spellColorsActive
                    )
                ),
            spellIDFilterRequiresPublicAssist =
                baseFilter == "HELPFUL"
                and (
                    identityFilterActive
                    or spellColorsActive
                ),
            spellIDFilterRequiresPublicNonAssist =
                baseFilter == "HARMFUL"
                and (
                    identityFilterActive
                    or spellColorsActive
                ),
        },
        partition = Copy(partition),
        migrationReady = not empty,
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
    if spellIDFiltersRestricted then
        AddDiagnostic(
            descriptor.diagnostics,
            "SPELL_ID_FILTERS_RESTRICTED_BY_UNIT_REACTION"
        )
    end
    if spellColorsActive then
        AddDiagnostic(
            descriptor.diagnostics,
            "GLOBAL_SPELL_COLORS_USE_INDEPENDENT_GROUPS"
        )
    elseif colorGroupBudgetExceeded then
        AddDiagnostic(
            descriptor.diagnostics,
            "NATIVE_SPELL_COLORS_GROUP_BUDGET_EXCEEDED"
        )
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
    if partitionActive then
        AddDiagnostic(
            descriptor.diagnostics,
            "NATIVE_PARTITION_PREBUILDS_RELATION_VARIANTS"
        )
        AddDiagnostic(
            descriptor.diagnostics,
            "NATIVE_PARTITION_SECRET_RELATION_USES_UNPARTITIONED"
        )
    end

    local groupDefinitions = ExpandGroupDefinitions(
        policy.groups,
        candidateFilters,
        spellColorsActive,
        spellColorBuckets,
        coloredSpellIDs
    )
    local groupCount = #groupDefinitions
    descriptor.degradations.perGroupLimit = groupCount > 1
    descriptor.degradations.perGroupSort = groupCount > 1
    local flow = GetFlow(config, schema)
    local mainAppearance = {
        width = config.width,
        height = config.height,
        desaturated = false,
    }
    local friendly = CompileContainerVariant(
        unit,
        baseFilter,
        config,
        schema,
        flow,
        tooltip,
        groupDefinitions,
        mainAppearance,
        false
    )
    descriptor.completeSpec = friendly.completeSpec
    descriptor.tuningSpec = friendly.tuningSpec
    descriptor.constructionKey = friendly.constructionKey

    local capacity = friendly.metrics.nativeVisibleCapacity
    descriptor.metrics = {
        groupCount = groupCount,
        legacyMaxFrameCount = config.numTotal,
        nativeVisibleCapacity = capacity,
        nativeBatchSize = NATIVE_BUTTON_BATCH_SIZE,
        initialRestrictedButtonCount =
            friendly.metrics.initialRestrictedButtonCount,
        freshContainerRestrictedButtonCountCeiling =
            friendly.metrics.freshContainerRestrictedButtonCountCeiling,
        requestedColorBucketCount =
            requestedColorBucketCount,
        requestedColorExpandedGroupCount =
            requestedColorExpandedGroupCount,
        requestedColorExpandedCapacity =
            requestedColorExpandedCapacity,
        colorGroupBudgetExceeded =
            colorGroupBudgetExceeded,
    }

    if partitionActive then
        local mainGroups, complementGroups =
            SplitPartitionGroups(groupDefinitions)
        local hasMain = #mainGroups > 0
        local hasComplement = #complementGroups > 0
        local mainVariant, mainGeometry = CompileContainerVariant(
            unit,
            baseFilter,
            config,
            schema,
            flow,
            tooltip,
            mainGroups,
            mainAppearance,
            hasMain and hasComplement
        )
        local complementAppearance = {
            width = partition.width,
            height = partition.height,
            desaturated = partition.desaturated,
        }
        local complementVariant, complementGeometry =
            CompileContainerVariant(
                unit,
                baseFilter,
                config,
                schema,
                flow,
                tooltip,
                complementGroups,
                complementAppearance,
                false
            )
        local hostileHolder = GetHostileHolder(
            flow,
            mainGeometry,
            complementGeometry
        )
        local compositeHolder = GetCompositeHolder(
            friendly.metrics.holder,
            hostileHolder
        )
        local hostile = {
            main = mainVariant,
            complement = complementVariant,
            holder = Copy(hostileHolder),
        }
        if mainVariant and complementVariant then
            hostile.attachment = GetPartitionAttachment(flow)
        end

        descriptor.partition.selector = {
            kind = "unitCanAttack",
            actorUnit = "player",
            secretFallback = "friendly",
        }
        descriptor.partition.holder = Copy(compositeHolder)
        descriptor.partition.hostile = hostile

        local mainMetrics = mainVariant and mainVariant.metrics
        local complementMetrics =
            complementVariant and complementVariant.metrics
        local hostileGroupCount =
            (mainMetrics and mainMetrics.groupCount or 0)
            + (complementMetrics and complementMetrics.groupCount or 0)
        local prebuiltGroupCount = friendly.metrics.groupCount
            + hostileGroupCount
        local initialRestrictedButtonCount =
            friendly.metrics.initialRestrictedButtonCount
            + (
                mainMetrics
                and mainMetrics.initialRestrictedButtonCount
                or 0
            )
            + (
                complementMetrics
                and complementMetrics.initialRestrictedButtonCount
                or 0
            )
        local mainCeiling = mainMetrics
            and mainMetrics.freshContainerRestrictedButtonCountCeiling
            or 0
        local complementCeiling = complementMetrics
            and complementMetrics.freshContainerRestrictedButtonCountCeiling
            or 0
        local freshContainerRestrictedButtonCountCeiling =
            friendly.metrics.freshContainerRestrictedButtonCountCeiling
            + mainCeiling
            + complementCeiling
        local variants = {
            friendly = Copy(friendly.metrics),
        }
        if mainMetrics then
            variants.hostileMain = Copy(mainMetrics)
        end
        if complementMetrics then
            variants.hostileComplement = Copy(complementMetrics)
        end

        descriptor.metrics = {
            groupCount = groupCount,
            legacyMaxFrameCount = config.numTotal,
            nativeVisibleCapacity = max(
                friendly.metrics.nativeVisibleCapacity,
                hostileGroupCount * config.numTotal
            ),
            nativeBatchSize = NATIVE_BUTTON_BATCH_SIZE,
            initialRestrictedButtonCount = initialRestrictedButtonCount,
            freshContainerRestrictedButtonCountCeiling =
                freshContainerRestrictedButtonCountCeiling,
            prebuiltContainerCount = 1
                + (mainVariant and 1 or 0)
                + (complementVariant and 1 or 0),
            prebuiltGroupCount = prebuiltGroupCount,
            maxActiveGroupCount = max(groupCount, hostileGroupCount),
            hostileHolder = Copy(hostileHolder),
            compositeHolder = Copy(compositeHolder),
            variants = variants,
            requestedColorBucketCount =
                requestedColorBucketCount,
            requestedColorExpandedGroupCount =
                requestedColorExpandedGroupCount,
            requestedColorExpandedCapacity =
                requestedColorExpandedCapacity,
            colorGroupBudgetExceeded =
                colorGroupBudgetExceeded,
        }
    end

    return descriptor
end
