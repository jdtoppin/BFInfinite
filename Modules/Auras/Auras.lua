---@type BFI
local BFI = select(2, ...)
---@class Auras
local A = BFI.modules.Auras
---@type AbstractFramework
local AF = _G.AbstractFramework

local blacklist = {}
local auraPriorities = {}
local auraColors = {}

---------------------------------------------------------------------
-- get
---------------------------------------------------------------------
function A.GetAuraPriority(spellId)
    return auraPriorities[spellId] or 9999
end

function A.GetAuraColor(spellId)
    if auraColors[spellId] then
        return AF.UnpackColor(auraColors[spellId])
    end
end

function A.IsBlacklisted(spellId)
    return blacklist[spellId] == true
end

---------------------------------------------------------------------
-- secret-safe filters
---------------------------------------------------------------------
local function AddMatchFilter(filters, seen, baseFilter, suffix)
    local filter = baseFilter .. "|" .. suffix
    if not seen[filter] then
        seen[filter] = true
        filters[#filters + 1] = filter
    end
end

function A.GetSecretSafeMatchFilters(baseFilter, config)
    if not config then return nil end

    local filters = {}
    local seen = {}

    if config.castByMe then
        AddMatchFilter(filters, seen, baseFilter, "PLAYER")
    end

    -- RAID_IN_COMBAT is Blizzard's curated replacement for encounter auras
    -- whose spell IDs or boss-aura flags cannot be inspected in Lua.
    if config.isBossAura or config.castByNPC then
        AddMatchFilter(filters, seen, baseFilter, "RAID_IN_COMBAT")
    end

    if config.dispellable or config.canBeDispelled then
        AddMatchFilter(filters, seen, baseFilter, "RAID_PLAYER_DISPELLABLE")
    end

    -- External/source-specific spell matching is unavailable for restricted
    -- auras. Blizzard's curated defensive filters retain the combat-useful
    -- subset without reading spell or source fields.
    if baseFilter == "HELPFUL" and (config.castByOthers or config.castByUnit or config.castByNPC) then
        AddMatchFilter(filters, seen, baseFilter, "BIG_DEFENSIVE")
        AddMatchFilter(filters, seen, baseFilter, "EXTERNAL_DEFENSIVE")
    end

    return filters
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateAuras(_, module, which)
    if module and module ~= "auras" then return end

    local config = A.config

    if not which then
        blacklist = config.blacklist
        auraPriorities = config.priorities
        auraColors = config.colors
        return
    end
end
AF.RegisterCallback("BFI_UpdateConfig", UpdateAuras)
