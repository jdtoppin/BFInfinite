---@type BFI
local BFI = select(2, ...)
---@class Auras
local A = BFI.modules.Auras

local floor, huge = math.floor, math.huge
local pairs, type = pairs, type

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -huge
        and value < huge
end

local function IsPositiveInteger(value)
    return IsFiniteNumber(value)
        and value > 0
        and value == floor(value)
end

local function IsColor(color)
    return type(color) == "table"
        and IsFiniteNumber(color[1])
        and IsFiniteNumber(color[2])
        and IsFiniteNumber(color[3])
        and IsFiniteNumber(color[4])
end

local function CopyColor(color)
    return {color[1], color[2], color[3], color[4]}
end

---------------------------------------------------------------------
-- get
---------------------------------------------------------------------
-- Return a fresh configuration-only map for the 12.1 native compiler.
-- A family is represented explicitly by assigning the same colour to each
-- of its aura spell IDs; the compiler combines exact-RGBA entries into one
-- native group. This function never receives or reads live aura data, and the
-- 12.0.7 legacy renderer does not call it.
function A.GetNativeSpellColorMap()
    local configured = A.config and A.config.colors
    if type(configured) ~= "table" then
        return {}
    end

    local copied = {}
    for spellID, color in pairs(configured) do
        if IsPositiveInteger(spellID) and IsColor(color) then
            copied[spellID] = CopyColor(color)
        end
    end
    return copied
end
