---@type BFI
local BFI = select(2, ...)
---@class BuffsDebuffs
local BD = BFI.modules.BuffsDebuffs
---@type AbstractFramework
local AF = _G.AbstractFramework

local defaults = {
    buffs = {
        enabled = false,
        position = {"TOPRIGHT", -4, -4},
        width = 26,
        height = 26,
        orientation = "right_to_left_then_down",
        spacingX = 4,
        spacingY = 6,
        separateOwn = 0,
        sortMethod = "TIME",
        sortDirection = "-",
        maxWraps = 1, -- rows
        wrapAfter = 25, -- buttons per row
        stack = {
            enabled = true,
            position = {"TOPRIGHT", "TOPRIGHT", 0, 3},
            font = {"Expressway", 11, "outline", false},
            color = AF.GetColorTable("white"),
        },
        duration = {
            enabled = true,
            position = {"BOTTOM", "BOTTOM", 1, -3},
            font = {"Expressway", 10, "outline", false},
            color = {
                normal = AF.GetColorTable("white"),
            },
        },

    },
    debuffs = {
        enabled = false,
        position = {"TOPRIGHT", -4, -40},
        width = 26,
        height = 26,
        orientation = "right_to_left_then_down",
        spacingX = 4,
        spacingY = 6,
        separateOwn = 0,
        sortMethod = "TIME",
        sortDirection = "-",
        maxWraps = 1, -- rows
        wrapAfter = 25, -- buttons per row
        stack = {
            enabled = true,
            position = {"TOPRIGHT", "TOPRIGHT", 0, 3},
            font = {"Expressway", 11, "outline", false},
            color = AF.GetColorTable("white"),
        },
        duration = {
            enabled = true,
            position = {"BOTTOM", "BOTTOM", 1, -3},
            font = {"Expressway", 10, "outline", false},
            color = {
                normal = AF.GetColorTable("white"),
            },
        },
    },
}

local floor = math.floor
local tonumber = tonumber
local type = type

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

local VALID_ORIENTATIONS = {
    bottom_to_top_then_left = true,
    bottom_to_top_then_right = true,
    left_to_right_then_down = true,
    left_to_right_then_up = true,
    right_to_left_then_down = true,
    right_to_left_then_up = true,
    top_to_bottom_then_left = true,
    top_to_bottom_then_right = true,
}

local VALID_SORT_METHODS = {
    INDEX = true,
    NAME = true,
    TIME = true,
}

local VALID_SORT_DIRECTIONS = {
    ["+"] = true,
    ["-"] = true,
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

local function FillMissing(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = type(value) == "table" and AF.Copy(value) or value
        elseif type(value) == "table" and type(target[key]) == "table" then
            FillMissing(target[key], value)
        end
    end
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
    value[1] = NormalizeNumber(value[1], fallback[1] or 1, 0, 1, false)
    value[2] = NormalizeNumber(value[2], fallback[2] or 1, 0, 1, false)
    value[3] = NormalizeNumber(value[3], fallback[3] or 1, 0, 1, false)
    value[4] = NormalizeNumber(value[4], fallback[4] or 1, 0, 1, false)
    return value
end

local function NormalizeFont(value, fallback)
    if type(value) ~= "table" then value = {} end
    if type(value[1]) ~= "string" or value[1] == "" then
        value[1] = fallback[1]
    end
    value[2] = NormalizeNumber(value[2], fallback[2], 5, 50, true)
    if type(value[3]) ~= "string" or value[3] == "" then
        value[3] = fallback[3]
    end
    value[4] = NormalizeBoolean(value[4], fallback[4])
    return value
end

local function NormalizeTextPosition(value, fallback)
    if type(value) ~= "table" then value = {} end
    value[1] = NormalizeAnchor(value[1], fallback[1])
    value[2] = NormalizeAnchor(value[2], fallback[2])
    value[3] = NormalizeNumber(value[3], fallback[3], -100, 100, false)
    value[4] = NormalizeNumber(value[4], fallback[4], -100, 100, false)
    return value
end

local function NormalizeHolderPosition(value, fallback)
    if type(value) ~= "table" then value = {} end
    local point = NormalizeAnchor(value[1], fallback[1])
    if type(value[2]) == "string" then
        return {
            point,
            NormalizeAnchor(value[2], point),
            NormalizeNumber(value[3], fallback[2], -10000, 10000, false),
            NormalizeNumber(value[4], fallback[3], -10000, 10000, false),
        }
    end
    return {
        point,
        NormalizeNumber(value[2], fallback[2], -10000, 10000, false),
        NormalizeNumber(value[3], fallback[3], -10000, 10000, false),
    }
end

local function NormalizeTextConfig(config, fallback, isDuration)
    if type(config) ~= "table" then config = {} end
    FillMissing(config, fallback)
    config.enabled = NormalizeBoolean(config.enabled, fallback.enabled)
    config.font = NormalizeFont(config.font, fallback.font)
    config.position = NormalizeTextPosition(config.position, fallback.position)
    if isDuration then
        if type(config.color) ~= "table" then config.color = {} end
        config.color.normal = NormalizeColor(
            config.color.normal,
            fallback.color.normal
        )
    else
        config.color = NormalizeColor(config.color, fallback.color)
    end
    return config
end

local function NormalizePane(config, fallback)
    if type(config) ~= "table" then config = {} end
    FillMissing(config, fallback)

    config.enabled = NormalizeBoolean(config.enabled, fallback.enabled)
    config.position = NormalizeHolderPosition(config.position, fallback.position)
    config.width = NormalizeNumber(config.width, fallback.width, 10, 100, true)
    config.height = NormalizeNumber(
        config.height,
        fallback.height,
        10,
        100,
        true
    )
    config.spacingX = NormalizeNumber(
        config.spacingX,
        fallback.spacingX,
        -1,
        50,
        false
    )
    config.spacingY = NormalizeNumber(
        config.spacingY,
        fallback.spacingY,
        -1,
        50,
        false
    )
    if not VALID_ORIENTATIONS[config.orientation] then
        config.orientation = fallback.orientation
    end

    local separateOwn = tonumber(config.separateOwn)
    if separateOwn ~= -1 and separateOwn ~= 0 and separateOwn ~= 1 then
        separateOwn = fallback.separateOwn
    end
    config.separateOwn = separateOwn

    if not VALID_SORT_METHODS[config.sortMethod] then
        config.sortMethod = fallback.sortMethod
    end
    if not VALID_SORT_DIRECTIONS[config.sortDirection] then
        config.sortDirection = fallback.sortDirection
    end
    config.maxWraps = NormalizeNumber(
        config.maxWraps,
        fallback.maxWraps,
        1,
        50,
        true
    )
    config.wrapAfter = NormalizeNumber(
        config.wrapAfter,
        fallback.wrapAfter,
        1,
        50,
        true
    )
    config.stack = NormalizeTextConfig(config.stack, fallback.stack, false)
    config.duration = NormalizeTextConfig(
        config.duration,
        fallback.duration,
        true
    )
    return config
end

AF.RegisterCallback("BFI_UpdateProfile", function(_, t)
    if type(t["buffsDebuffs"]) ~= "table" then
        t["buffsDebuffs"] = AF.Copy(defaults)
    else
        local config = t["buffsDebuffs"]
        config.buffs = NormalizePane(config.buffs, defaults.buffs)
        config.debuffs = NormalizePane(config.debuffs, defaults.debuffs)
    end
    BD.config = t["buffsDebuffs"]
end)

function BD.GetDefaults()
    return AF.Copy(defaults)
end

function BD.ResetToDefaults(which)
    if not which then
        for k, v in next, defaults do
            wipe(BD.config[k])
            AF.Merge(BD.config[k], v)
        end
    else
        wipe(BD.config[which])
        AF.Merge(BD.config[which], defaults[which])
    end
end
