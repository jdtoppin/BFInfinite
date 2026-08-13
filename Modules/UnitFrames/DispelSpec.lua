---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local floor, max, min = math.floor, math.max, math.min
local type = type

-- Retail 12.1.0.69273 (wow-ui-source eb941aad) evaluates the filter string,
-- candidate dispel map, private-aura eligibility, selected aura, and dispel
-- color inside AuraContainer. This compiler consumes saved settings only.
local SCOPE_FILTERS = {
    player = "HARMFUL|RAID",
    group = "HARMFUL|RAID_PLAYER_DISPELLABLE",
    any = "HARMFUL|DISPELLABLE",
}

local DISPEL_TYPES = {
    {key = "magic", nativeName = "Magic", color = "aura_magic"},
    {key = "curse", nativeName = "Curse", color = "aura_curse"},
    {key = "disease", nativeName = "Disease", color = "aura_disease"},
    {key = "poison", nativeName = "Poison", color = "aura_poison"},
    {key = "bleed", nativeName = "Bleed", color = "aura_bleed"},
}

local BLEND_MODES = {
    BLEND = true,
    ADD = true,
    MOD = true,
}

local APPEARANCES = {
    bottom_gradient = function()
        return {
            texture = AF.GetTexture("Gradient_Linear_Bottom"),
        }
    end,
    full_gradient = function()
        return {
            texture = AF.GetTexture(
                "Gradient_Linear_Vertical_CenterToEdges"
            ),
        }
    end,
    full_solid = function()
        return {
            solidColor = {1, 1, 1, 1},
        }
    end,
}

local function NormalizeAlpha(value)
    value = tonumber(value)
    if not value or value ~= value then
        return 0.5
    end
    return max(0, min(1, value))
end

local function NormalizeFrameLevel(value)
    value = tonumber(value)
    if not value or value ~= value then
        return 0
    end
    return floor(max(0, min(100, value)) + 0.5)
end

local function NormalizeConfig(config)
    config = type(config) == "table" and config or {}
    local types = type(config.types) == "table" and config.types or {}
    local normalized = {
        enabled = config.enabled == true,
        scope = SCOPE_FILTERS[config.scope] and config.scope or "player",
        appearance = APPEARANCES[config.appearance]
            and config.appearance
            or "bottom_gradient",
        alpha = NormalizeAlpha(config.alpha),
        blendMode = BLEND_MODES[config.blendMode]
            and config.blendMode
            or "ADD",
        types = {},
    }

    for _, definition in ipairs(DISPEL_TYPES) do
        normalized.types[definition.key] =
            types[definition.key] ~= false
    end
    return normalized
end

local function CompileCandidateFilters(config)
    local includeDispelTypes = {}
    for _, definition in ipairs(DISPEL_TYPES) do
        if config.types[definition.key] then
            includeDispelTypes[definition.nativeName] = true
        end
    end
    return {
        includeDispelTypes = includeDispelTypes,
    }
end

local function CompileOverlayStyle(config)
    local style = APPEARANCES[config.appearance]()
    style.alpha = config.alpha
    style.blendMode = config.blendMode
    style.drawLayer = "ARTWORK"
    style.frameLevelOffset = 0
    style.subLevel = 0
    style.dispelTypeTextureOptions = {
        showWhenHarmful = true,
        showWhenHelpful = false,
        showWithoutDispelType = false,
    }
    return style
end

local function CompileDynamicSpec(config)
    assert(AuraContainerSortMethod
            and AuraContainerSortMethod.UnitFrameDebuff ~= nil,
        "UnitFrameDebuff aura sort is unavailable")
    assert(AuraContainerSortDirection
            and AuraContainerSortDirection.Normal ~= nil,
        "normal aura sort direction is unavailable")
    return {
        holder = {width = 1, height = 1},
        containerPoint = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
        flowLayout = {},
        processing = {
            policy = CustomAuraContainerAuraProcessingPolicy.None,
        },
        groups = {},
        slots = {
            {
                key = "dispelHighlight",
                filterString = SCOPE_FILTERS[config.scope],
                candidateFilters = CompileCandidateFilters(config),
                sortMethod = AuraContainerSortMethod.UnitFrameDebuff,
                sortDirection = AuraContainerSortDirection.Normal,
            },
        },
    }
end

function UF.CompileNativeDispelHighlightSpec(
    unit,
    config,
    anchorTarget,
    anchorFrameLevel
)
    assert(type(unit) == "string" and unit ~= "",
        "native dispel highlight unit must be a non-empty string")
    assert(anchorTarget ~= nil,
        "native dispel highlight anchor target is required")

    local normalized = NormalizeConfig(config)
    local tuning = CompileDynamicSpec(normalized)
    local completeSpec = CompileDynamicSpec(normalized)
    completeSpec.unit = unit
    completeSpec.enabled = false
    completeSpec.shown = false
    completeSpec.slots[1].kind = "dispelOverlay"
    completeSpec.slots[1].anchorTarget = anchorTarget
    completeSpec.slots[1].overlayStyle =
        CompileOverlayStyle(normalized)

    return {
        completeSpec = completeSpec,
        tuning = tuning,
        constructionKey = {
            appearance = normalized.appearance,
            alpha = normalized.alpha,
            blendMode = normalized.blendMode,
            -- AF initializes the managed overlay at the health bar's live
            -- level. That button cannot be restacked later, so a saved
            -- Health Bar level change is a construction change.
            anchorFrameLevel = NormalizeFrameLevel(anchorFrameLevel),
        },
        config = normalized,
    }
end

function UF.GetNativeDispelHighlightPreviewColor(config)
    local normalized = NormalizeConfig(config)
    for _, definition in ipairs(DISPEL_TYPES) do
        if normalized.types[definition.key] then
            return definition.color
        end
    end
    return "disabled"
end
