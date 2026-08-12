---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames

local concat = table.concat
local ipairs, type = ipairs, type

-- Retail 12.1.0.69273 (wow-ui-source eb941aad) supports negated native
-- filter tokens, but each CustomAuraContainer group owns its own limit and
-- sort. The container also has no selector that separates public from private
-- aura sources. This compiler records those limitations without reading any
-- unit, aura, frame, or native-container state.
local FILTER_FIELDS = {
    "castByMe",
    "castByOthers",
    "castByUnit",
    "castByNPC",
    "isBossAura",
    "dispellable",
}

local RULES = {
    {key = "player", token = "PLAYER"},
    {key = "raidInCombat", token = "RAID_IN_COMBAT"},
    {key = "raidPlayerDispellable", token = "RAID_PLAYER_DISPELLABLE"},
    {key = "bigDefensive", token = "BIG_DEFENSIVE"},
    {key = "externalDefensive", token = "EXTERNAL_DEFENSIVE"},
}

local function HasValidSchema(filters)
    if type(filters) ~= "table" then return false end

    for _, field in ipairs(FILTER_FIELDS) do
        local value = filters[field]
        if value ~= nil and type(value) ~= "boolean" then
            return false
        end
    end
    return true
end

function UF.CompileNativeAuraPolicy(baseFilter, filters)
    if baseFilter ~= "HELPFUL" and baseFilter ~= "HARMFUL" then
        return nil, "INVALID_BASE_FILTER"
    end
    if not HasValidSchema(filters) then
        return nil, "INVALID_FILTER_SCHEMA"
    end

    local defensive = baseFilter == "HELPFUL"
        and (filters.castByOthers or filters.castByUnit or filters.castByNPC)
        or false
    local enabled = {
        player = filters.castByMe == true,
        raidInCombat = filters.isBossAura == true or filters.castByNPC == true,
        raidPlayerDispellable = filters.dispellable == true,
        bigDefensive = defensive,
        externalDefensive = defensive,
    }

    local groups = {}
    local precedingTokens = {}

    -- The legacy filters are an OR-union. Negating every earlier enabled token
    -- makes the native groups disjoint while preserving that union and avoids
    -- inspecting restricted aura identity or counts.
    for _, rule in ipairs(RULES) do
        if enabled[rule.key] then
            local parts = {baseFilter, rule.token}
            for _, token in ipairs(precedingTokens) do
                parts[#parts + 1] = "!" .. token
            end

            groups[#groups + 1] = {
                key = rule.key,
                filterString = concat(parts, "|"),
                -- Keep source partitioning as compiler metadata instead of
                -- reparsing filter strings later. When PLAYER is enabled it
                -- is the first disjoint group and every later group excludes
                -- it; otherwise the group spans both player relationships.
                playerScope = rule.key == "player" and "player"
                    or enabled.player and "notPlayer"
                    or "any",
            }
            precedingTokens[#precedingTokens + 1] = rule.token
        end
    end

    local groupCount = #groups
    return {
        groups = groups,
        empty = groupCount == 0,
        requiresVisible = enabled.player,
        requiresAssist = enabled.bigDefensive or enabled.externalDefensive,
        degradations = {
            perGroupLimit = groupCount > 1,
            perGroupSort = groupCount > 1,
            privateAuraSourceUnseparable = groupCount > 0,
        },
    }
end
