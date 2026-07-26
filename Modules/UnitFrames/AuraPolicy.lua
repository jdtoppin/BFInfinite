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
    {
        key = "player",
        token = "PLAYER",
        exclusionToken = "!PLAYER",
        requiresVisible = true,
    },
    {
        key = "notPlayer",
        token = "!PLAYER",
        exclusionToken = "PLAYER",
        requiresVisible = true,
    },
    {
        key = "raidInCombat",
        token = "RAID_IN_COMBAT",
        exclusionToken = "!RAID_IN_COMBAT",
    },
    {
        key = "raidPlayerDispellable",
        token = "RAID_PLAYER_DISPELLABLE",
        exclusionToken = "!RAID_PLAYER_DISPELLABLE",
    },
    {
        key = "bigDefensive",
        token = "BIG_DEFENSIVE",
        exclusionToken = "!BIG_DEFENSIVE",
        requiresAssist = true,
    },
    {
        key = "externalDefensive",
        token = "EXTERNAL_DEFENSIVE",
        exclusionToken = "!EXTERNAL_DEFENSIVE",
        requiresAssist = true,
    },
}

function UF.CompileNativeAuraPolicy(baseFilter, filters)
    if baseFilter ~= "HELPFUL" and baseFilter ~= "HARMFUL" then
        return nil, "INVALID_BASE_FILTER"
    end

    local resolved, migration =
        F.ResolveUnitFrameAuraFilters(baseFilter, filters)
    if not resolved then
        return nil, "INVALID_FILTER_SCHEMA"
    end

    local enabled = {
        all = resolved.all,
        player = resolved.player,
        notPlayer = resolved.notPlayer,
        raidInCombat = resolved.raidInCombat,
        raidPlayerDispellable = resolved.raidPlayerDispellable,
        bigDefensive = resolved.bigDefensive,
        externalDefensive = resolved.externalDefensive,
    }

    local groups = {}
    local precedingExclusionTokens = {}
    local requiresVisible = false
    local requiresAssist = false

    if enabled.all then
        groups[1] = {
            key = "all",
            filterString = baseFilter,
        }
    else
        -- The selected categories are an OR-union. Adding the logical
        -- complement of every earlier category makes native groups disjoint
        -- without producing invalid double-negation tokens for !PLAYER.
        for _, rule in ipairs(RULES) do
            if enabled[rule.key] then
                local parts = {baseFilter, rule.token}
                for _, exclusionToken in ipairs(
                    precedingExclusionTokens
                ) do
                    parts[#parts + 1] = exclusionToken
                end

                groups[#groups + 1] = {
                    key = rule.key,
                    filterString = concat(parts, "|"),
                }
                precedingExclusionTokens[
                    #precedingExclusionTokens + 1
                ] = rule.exclusionToken
            end
        end
    end

    local groupCount = #groups
    if groupCount > 0 and not enabled.all then
        requiresVisible = true
        requiresAssist = true
        for _, rule in ipairs(RULES) do
            if enabled[rule.key] then
                requiresVisible =
                    requiresVisible and rule.requiresVisible == true
                requiresAssist =
                    requiresAssist and rule.requiresAssist == true
            end
        end
    end

    return {
        groups = groups,
        empty = groupCount == 0,
        requiresVisible = requiresVisible,
        requiresAssist = requiresAssist,
        degradations = {
            perGroupLimit = groupCount > 1,
            perGroupSort = groupCount > 1,
            privateAuraSourceUnseparable = groupCount > 0,
            bossAuraUsesCuratedRaidInCombat =
                migration.bossAuraUsesCuratedRaidInCombat,
            legacySourceFilterUsesSuperset =
                migration.legacySourceFilterUsesSuperset,
        },
    }
end
