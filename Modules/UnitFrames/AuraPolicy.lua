---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames
local F = BFI.funcs

local concat = table.concat
local ipairs = ipairs

-- Retail 12.1.0.68914 (wow-ui-source d3915c78) supports negated native
-- filter tokens, but each CustomAuraContainer group owns its own limit and
-- sort. The container also has no selector that separates public from private
-- aura sources. This compiler records those limitations without reading any
-- unit, aura, frame, or native-container state.
local RULES = {
    {key = "player", token = "PLAYER"},
    {key = "raidInCombat", token = "RAID_IN_COMBAT"},
    {key = "raidPlayerDispellable", token = "RAID_PLAYER_DISPELLABLE"},
    {key = "bigDefensive", token = "BIG_DEFENSIVE"},
    {key = "externalDefensive", token = "EXTERNAL_DEFENSIVE"},
}

function UF.CompileNativeAuraPolicy(baseFilter, filters)
    if baseFilter ~= "HELPFUL" and baseFilter ~= "HARMFUL" then
        return nil, "INVALID_BASE_FILTER"
    end

    local resolved = F.ResolveUnitFrameAuraFilters(baseFilter, filters)
    if not resolved then
        return nil, "INVALID_FILTER_SCHEMA"
    end

    -- Only a legacy `isBossAura` input is an approximation. Canonical
    -- `raidInCombat` is the exact user-facing name of the C-side category.
    local hasCanonicalField =
        filters.player ~= nil
        or filters.raidInCombat ~= nil
        or filters.raidPlayerDispellable ~= nil
        or filters.bigDefensive ~= nil
        or filters.externalDefensive ~= nil
    local bossAuraUsesCuratedRaidInCombat =
        not hasCanonicalField and filters.isBossAura == true
    local enabled = {
        player = resolved.player,
        raidInCombat = resolved.raidInCombat,
        raidPlayerDispellable = resolved.raidPlayerDispellable,
        bigDefensive = resolved.bigDefensive,
        externalDefensive = resolved.externalDefensive,
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
            bossAuraUsesCuratedRaidInCombat =
                bossAuraUsesCuratedRaidInCombat,
        },
    }
end
