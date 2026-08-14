---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class Funcs
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- cvar
---------------------------------------------------------------------
local GetCVar = GetCVar
function F.GetCVarNumber(name)
    return tonumber(GetCVar(name)) or 0
end

---------------------------------------------------------------------
-- module
---------------------------------------------------------------------
local moduleNames = {
    -- common
    general = {localized = L["General"]},
    enhancements = {localized = L["Enhancements"], class = "Enhancements"},
    colors = {localized = L["Colors"], class = "Colors"},
    auras = {localized = L["Auras"], class = "Auras"},
    -- profile
    actionBars = {localized = L["Action Bars"], class = "ActionBars"},
    bags = {localized = L["Bags"], class = "Bags"},
    buffsDebuffs = {localized = L["Buffs & Debuffs"], class = "BuffsDebuffs"},
    chat = {localized = L["Chat"], class = "Chat"},
    cooldownManager = {localized = L["Cooldown Manager"], class = "CooldownManager"},
    dataBars = {localized = L["Data Bars"], class = "DataBars"},
    damageMeter = {localized = L["Damage Meter"], class = "DamageMeter"},
    maps = {localized = L["Maps"], class = "Maps"},
    nameplates = {localized = L["Nameplates"], class = "Nameplates"},
    tooltip = {localized = L["Tooltip"], class = "Tooltip"},
    uiWidgets = {localized = L["UI Widgets"], class = "UIWidgets"},
    unitFrames = {localized = L["Unit Frames"], class = "UnitFrames"},
    disableBlizzard = {localized = L["Disable Blizzard"], class = "DisableBlizzard"},
    -- special
    profiles = {localized = L["Profiles"]},
    about = {localized = L["About"]},
}

local moduleClassMap = {}
for key, info in next, moduleNames do
    if info.class then
        moduleClassMap[info.class] = key
    end
end

function F.GetModuleLocalizedName(moduleKey)
    return moduleNames[moduleKey] and moduleNames[moduleKey].localized or moduleKey
end

function F.GetModuleClassName(moduleKey)
    return moduleNames[moduleKey] and moduleNames[moduleKey].class or AF.UpperFirst(moduleKey)
end

function F.GetModuleKey(moduleClassName)
    return moduleClassMap[moduleClassName] or AF.LowerFirst(moduleClassName)
end

function F.GetProfileModuleClassNames()
    return {
        "ActionBars",
        "Bags",
        "BuffsDebuffs",
        "Chat",
        "CooldownManager",
        "DataBars",
        "DamageMeter",
        "Maps",
        "Nameplates",
        "Tooltip",
        "UIWidgets",
        "UnitFrames",
        "DisableBlizzard",
    }
end

function F.GetModuleDefaults(moduleClassName)
    local module = moduleClassName and BFI.modules[moduleClassName]
    if module and module.GetDefaults then
        return module.GetDefaults()
    end
end

function F.MergeMissingDefaults(config, defaults)
    assert(type(defaults) == "table", "MergeMissingDefaults: defaults must be a table")

    if type(config) ~= "table" then
        config = {}
    end

    for key, defaultValue in next, defaults do
        if type(defaultValue) == "table" then
            config[key] = F.MergeMissingDefaults(config[key], defaultValue)
        elseif config[key] == nil then
            config[key] = defaultValue
        end
    end

    return config
end

function F.FixModule(profileTbl, moduleKey)
    assert(not AF.IsBlank(moduleKey), "Fix: module is required")
    local M = BFI.modules[F.GetModuleClassName(moduleKey)]
    assert(M, "Fix: module not found: " .. moduleKey)
    if not M.GetDefaults then return false end

    profileTbl[moduleKey] = F.MergeMissingDefaults(profileTbl[moduleKey], M.GetDefaults())
    return true
end

---------------------------------------------------------------------
-- aura filters
---------------------------------------------------------------------
local unitFrameAuraFilterFields = {
    "all",
    "player",
    "notPlayer",
    "raidInCombat",
    "raidPlayerDispellable",
    "bigDefensive",
    "externalDefensive",
    "important",
    "anyDispellable",
}

local unitFrameAuraFilterFieldSet = {}
for _, field in ipairs(unitFrameAuraFilterFields) do
    unitFrameAuraFilterFieldSet[field] = true
end

local legacyUnitFrameAuraFilterFields = {
    "castByMe",
    "castByOthers",
    "castByUnit",
    "castByNPC",
    "isBossAura",
    "dispellable",
    "canBeDispelled",
}

local function HasValidAuraFilterFields(config, fields)
    for _, field in ipairs(fields) do
        local value = config[field]
        if value ~= nil and type(value) ~= "boolean" then
            return false
        end
    end
    return true
end

local function NewUnitFrameAuraFilterMigration()
    return {
        legacy = false,
        legacySourceFilterUsesSuperset = false,
        bossAuraUsesCuratedRaidInCombat = false,
        legacyDispellableUsesRaidPlayerDispellable = false,
    }
end

-- Retail 12.1 can express the base aura set, PLAYER, the C-side complement of
-- PLAYER, and the original curated categories. It also provides IMPORTANT
-- and DISPELLABLE; their settings are exposed only when the
-- client advertises those exact AuraUtil tokens. Legacy source-oriented saved
-- keys are accepted only as a compatibility input; once a Retail control is
-- changed, the full canonical state is materialized so retired aliases cannot
-- silently affect the result.
function F.ResolveUnitFrameAuraFilters(baseFilter, config)
    if baseFilter ~= "HELPFUL" and baseFilter ~= "HARMFUL" then return nil end
    if type(config) ~= "table" then return nil end
    if not HasValidAuraFilterFields(config, unitFrameAuraFilterFields)
        or not HasValidAuraFilterFields(
            config,
            legacyUnitFrameAuraFilterFields
        )
    then
        return nil
    end

    local hasCanonicalField = false
    for _, field in ipairs(unitFrameAuraFilterFields) do
        if config[field] ~= nil then
            hasCanonicalField = true
            break
        end
    end

    if hasCanonicalField then
        local all = config.all == true
        local player = config.player == true
        local notPlayer = config.notPlayer == true
        if player and notPlayer then
            all = true
        end

        return {
            all = all,
            player = not all and player,
            notPlayer = not all and notPlayer,
            raidInCombat =
                not all and config.raidInCombat == true,
            raidPlayerDispellable =
                not all
                and config.raidPlayerDispellable == true,
            bigDefensive =
                not all
                and baseFilter == "HELPFUL"
                and config.bigDefensive == true,
            externalDefensive =
                not all
                and baseFilter == "HELPFUL"
                and config.externalDefensive == true,
            important =
                not all
                and baseFilter == "HELPFUL"
                and config.important == true,
            anyDispellable =
                not all
                and config.anyDispellable == true,
        }, NewUnitFrameAuraFilterMigration()
    end

    local castByMe = config.castByMe == true
    local castByOthers = config.castByOthers == true
    local castByUnit = config.castByUnit == true
    local castByNPC = config.castByNPC == true
    local exactNotPlayer = castByOthers and castByNPC
    local notPlayer = castByOthers or castByNPC
    local exactAll = castByMe and exactNotPlayer
    local all = castByUnit or (castByMe and notPlayer)
    local migration = {
        legacy = true,
        legacySourceFilterUsesSuperset =
            (notPlayer and not exactNotPlayer)
            or (all and not exactAll),
        bossAuraUsesCuratedRaidInCombat =
            not all and config.isBossAura == true,
        legacyDispellableUsesRaidPlayerDispellable =
            not all
            and (
                config.dispellable == true
                or config.canBeDispelled == true
            ),
    }

    if all then
        return {
            all = true,
            player = false,
            notPlayer = false,
            raidInCombat = false,
            raidPlayerDispellable = false,
            bigDefensive = false,
            externalDefensive = false,
            important = false,
            anyDispellable = false,
        }, migration
    end

    return {
        all = false,
        player = castByMe,
        notPlayer = notPlayer,
        raidInCombat = config.isBossAura == true,
        raidPlayerDispellable =
            config.dispellable == true
            or config.canBeDispelled == true,
        bigDefensive = false,
        externalDefensive = false,
        important = false,
        anyDispellable = false,
    }, migration
end

function F.SetUnitFrameAuraFilter(baseFilter, config, field, value)
    if not unitFrameAuraFilterFieldSet[field] then return false end
    if type(value) ~= "boolean" then return false end
    if baseFilter ~= "HELPFUL"
        and (
            field == "bigDefensive"
            or field == "externalDefensive"
            or field == "important"
        )
    then
        return false
    end

    local resolved = F.ResolveUnitFrameAuraFilters(baseFilter, config)
    if not resolved then return false end
    resolved[field] = value
    if field == "all" and value then
        for _, canonicalField in ipairs(unitFrameAuraFilterFields) do
            if canonicalField ~= "all" then
                resolved[canonicalField] = false
            end
        end
    elseif field ~= "all" and value then
        resolved.all = false
        if resolved.player and resolved.notPlayer then
            resolved.all = true
            resolved.player = false
            resolved.notPlayer = false
        end
    end

    for _, canonicalField in ipairs(unitFrameAuraFilterFields) do
        config[canonicalField] = resolved[canonicalField]
    end
    for _, legacyField in ipairs(legacyUnitFrameAuraFilterFields) do
        config[legacyField] = nil
    end
    return true
end

local function AddAuraMatchFilter(filters, seen, baseFilter, suffix)
    local filter = baseFilter .. "|" .. suffix
    if not seen[filter] then
        seen[filter] = true
        filters[#filters + 1] = filter
    end
end

-- Nameplates retain their existing compatibility projection. Unit frames use
-- the explicit cross-version policy below so step #6 does not silently change
-- nameplate presets or imports.
function F.GetSecretSafeAuraMatchFilters(baseFilter, config)
    if not config then return nil end
    local filters = {}
    local seen = {}

    if config.castByMe then
        AddAuraMatchFilter(filters, seen, baseFilter, "PLAYER")
    end

    if config.isBossAura or config.castByNPC then
        AddAuraMatchFilter(filters, seen, baseFilter, "RAID_IN_COMBAT")
    end

    if config.dispellable or config.canBeDispelled then
        AddAuraMatchFilter(filters, seen, baseFilter, "RAID_PLAYER_DISPELLABLE")
    end

    if baseFilter == "HELPFUL"
        and (
            config.castByOthers
            or config.castByUnit
            or config.castByNPC
        )
    then
        AddAuraMatchFilter(filters, seen, baseFilter, "BIG_DEFENSIVE")
        AddAuraMatchFilter(filters, seen, baseFilter, "EXTERNAL_DEFENSIVE")
    end

    return filters
end

function F.GetSecretSafeUnitFrameAuraMatchFilters(baseFilter, config)
    local resolved = F.ResolveUnitFrameAuraFilters(baseFilter, config)
    if not resolved then return nil end

    if resolved.all then
        return {baseFilter}
    end

    -- IMPORTANT and DISPELLABLE are native-container choices. A legacy
    -- unit-frame row cannot represent them faithfully, so widen to the base
    -- aura type instead of passing an
    -- unknown token or silently dropping every requested aura.
    if resolved.important or resolved.anyDispellable then
        return {baseFilter}
    end

    local filters = {}
    local seen = {}

    if resolved.player then
        AddAuraMatchFilter(filters, seen, baseFilter, "PLAYER")
    end

    if resolved.notPlayer then
        local filterString = baseFilter .. "|PLAYER"
        local seenKey = "FILTERED_OUT:" .. filterString
        if not seen[seenKey] then
            seen[seenKey] = true
            filters[#filters + 1] = {
                filterString = filterString,
                matchWhenFilteredOut = true,
            }
        end
    end

    if resolved.raidInCombat then
        AddAuraMatchFilter(filters, seen, baseFilter, "RAID_IN_COMBAT")
    end

    if resolved.raidPlayerDispellable then
        AddAuraMatchFilter(filters, seen, baseFilter, "RAID_PLAYER_DISPELLABLE")
    end

    if resolved.bigDefensive then
        AddAuraMatchFilter(filters, seen, baseFilter, "BIG_DEFENSIVE")
    end

    if resolved.externalDefensive then
        AddAuraMatchFilter(filters, seen, baseFilter, "EXTERNAL_DEFENSIVE")
    end

    return filters
end

---------------------------------------------------------------------
-- hide frame
---------------------------------------------------------------------
function F.Hide(region)
    if not region then return end
    if region.UnregisterAllEvents then
        region:UnregisterAllEvents()
        region:SetParent(AF.hiddenParent)
    else
        -- region.Show = region.Hide -- TAINT!
        -- region.SetShown = region.Hide -- TAINT!
        hooksecurefunc(region, "Show", region.Hide)
        hooksecurefunc(region, "SetShown", region.Hide)
    end
    region:Hide()
end

---------------------------------------------------------------------
-- disable frame (forked from ElvUI)
---------------------------------------------------------------------
local hookedFrames = {}

local function Reparent(self, parent)
    if parent ~= AF.hiddenParent then
        self:SetParent(AF.hiddenParent)
    end
end

function F.DisableFrame(frame, doNotReparent)
    if not frame then return end

    frame:UnregisterAllEvents()
    pcall(frame.Hide, frame)

    if not doNotReparent then
        frame:SetParent(AF.hiddenParent)
        if not hookedFrames[frame] then
            hookedFrames[frame] = true
            hooksecurefunc(frame, "SetParent", Reparent)
        end
    end
end

---------------------------------------------------------------------
-- disable edit mode
---------------------------------------------------------------------
function F.DisableEditMode(region)
    -- region.HighlightSystem = AF.noop -- TAINT!
    -- region.ClearHighlight = AF.noop -- TAINT!
    if not (region.HighlightSystem or region.ClearHighlight) then return end
    hooksecurefunc(region, "HighlightSystem", region.ClearHighlight)
end

---------------------------------------------------------------------
-- AbstractFramework position compatibility
---------------------------------------------------------------------
function F.LoadPosition(region, position, relativeTo)
    if type(position) == "table"
        and type(position[2]) == "number"
        and type(position[3]) == "number"
    then
        -- AF movers persist {point, x, y}. Affected AF releases pass
        -- an explicit nil fourth table field and misread x as relativePoint.
        -- Expand only the transient value, leaving the saved table canonical.
        AF.LoadPosition(
            region,
            {position[1], position[1], position[2], position[3]},
            relativeTo
        )
    else
        AF.LoadPosition(region, position, relativeTo)
    end
end

function F.PrepareEditModePositions()
    if InCombatLockdown() then return end

    -- AFPopupParent is the framework's only production mover owner. It uses
    -- the same affected three-field table path, so repair that known owner
    -- before showing the global registry. BFI-owned movers already use
    -- F.LoadPosition at setup time.
    local popupParent = _G.AFPopupParent
    local mover = popupParent and popupParent.mover
    local position = mover and mover.save
    if mover and position == nil then
        local config = _G.AFConfig
        position = config and config.popups and config.popups.position
        if type(position) == "table" then
            AF.UpdateMoverSave(popupParent, position)
        end
    end
    if type(position) == "table"
        and type(position[2]) == "number"
        and type(position[3]) == "number"
    then
        F.LoadPosition(popupParent, position, AF.UIParent)
    end

    AF.Fire("BFI_PrepareEditModePositions")
end

---------------------------------------------------------------------
-- loot spec
---------------------------------------------------------------------
function F.GetLootSpecInfo()
    local id = GetLootSpecialization()
    if id == 0 then
        -- current spec
        id = AF.player.specID
    end
    local _, name, _, icon = GetSpecializationInfoByID(id)
    return id, name, icon
end
