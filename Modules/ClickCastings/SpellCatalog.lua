---@type BFI
local BFI = select(2, ...)
---@class ClickCastings
local CC = BFI.modules.ClickCastings
---@type AbstractFramework
local AF = _G.AbstractFramework

-- API contract pin: Retail 12.1.0.68914, Blizzard UI source
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9. The catalog is rebuilt from
-- live player data and is never persisted in a BFI profile.

local C_Spell = _G.C_Spell
local C_SpellBook = _G.C_SpellBook
local C_ClassTalents = _G.C_ClassTalents
local C_Traits = _G.C_Traits
local C_SpecializationInfo = _G.C_SpecializationInfo
local C_ClickBindings = _G.C_ClickBindings
local C_PetInfo = _G.C_PetInfo

local spellBookBank = _G.Enum
    and _G.Enum.SpellBookSpellBank
    and _G.Enum.SpellBookSpellBank.Player
    or 0
local petSpellBookBank = _G.Enum
    and _G.Enum.SpellBookSpellBank
    and _G.Enum.SpellBookSpellBank.Pet
    or 1
local spellBookItemType = _G.Enum
    and _G.Enum.SpellBookItemType
    and _G.Enum.SpellBookItemType.Spell
    or 1
local petActionItemType = _G.Enum
    and _G.Enum.SpellBookItemType
    and _G.Enum.SpellBookItemType.PetAction
    or 3
local skillLineClass = _G.Enum
    and _G.Enum.SpellBookSkillLineIndex
    and _G.Enum.SpellBookSkillLineIndex.Class
    or 2
local skillLineMainSpec = _G.Enum
    and _G.Enum.SpellBookSkillLineIndex
    and _G.Enum.SpellBookSkillLineIndex.MainSpec
    or 3

local categoryOrder = {
    class = 1,
    spec = 2,
    pet = 3,
    talent = 4,
    hero = 5,
    pvp = 6,
    resurrection = 7,
}

-- Sorting and provenance are separate concerns. A spell can appear in the
-- active spellbook and in its semantic source (Talent, Hero, or PvP). Keep
-- the more descriptive source while retaining a stable menu order.
local categorySpecificity = {
    class = 1,
    spec = 2,
    pet = 3,
    talent = 4,
    hero = 5,
    pvp = 6,
    resurrection = 7,
}

-- Blizzard does not expose resurrection semantics. Keep this deliberately
-- small; everything else in the picker comes from the active player APIs.
local resurrectionFacts = {
    DEATHKNIGHT = {combat = 61999}, -- Raise Ally
    DRUID = {
        normal = 50769, -- Revive
        massBySpec = {[105] = 212040}, -- Revitalize
        combat = 20484, -- Rebirth
    },
    EVOKER = {
        normal = 361227, -- Return
        massBySpec = {[1468] = 361178}, -- Mass Return
    },
    MONK = {
        normal = 115178, -- Resuscitate
        massBySpec = {[270] = 212051}, -- Reawaken
    },
    PALADIN = {
        normal = 7328, -- Redemption
        massBySpec = {[65] = 212056}, -- Absolution
        combat = 391054, -- Intercession
    },
    PRIEST = {
        normal = 2006, -- Resurrection
        massBySpec = {
            [256] = 212036, -- Mass Resurrection
            [257] = 212036,
        },
    },
    SHAMAN = {
        normal = 2008, -- Ancestral Spirit
        massBySpec = {[264] = 212048}, -- Ancestral Vision
    },
    WARLOCK = {combat = 20707}, -- Soulstone
}

local resurrectionSpellIDs = {}
for _, facts in pairs(resurrectionFacts) do
    if facts.normal then resurrectionSpellIDs[facts.normal] = true end
    if facts.combat then resurrectionSpellIDs[facts.combat] = true end
    for _, spellID in pairs(facts.massBySpec or {}) do
        resurrectionSpellIDs[spellID] = true
    end
end

function CC.IsResurrectionSpell(spellID)
    return resurrectionSpellIDs[tonumber(spellID)] == true
end

local function IsSpellAvailable(spellID)
    if not spellID then return false end
    if C_SpellBook
        and type(C_SpellBook.IsSpellKnown) == "function"
    then
        return C_SpellBook.IsSpellKnown(spellID, spellBookBank)
    end
    if C_SpellBook
        and type(C_SpellBook.IsSpellKnownOrInSpellBook) == "function"
    then
        return C_SpellBook.IsSpellKnownOrInSpellBook(
            spellID,
            spellBookBank,
            true
        )
    end
    return AF.GetSpellInfo(spellID) ~= nil
end

---@param class string?
---@param specID number?
---@return table capabilities
function CC.GetSmartResurrectionCapabilities(class, specID)
    local facts = resurrectionFacts[class or AF.player.class]
    local mass = facts and facts.massBySpec
        and facts.massBySpec[specID or AF.player.specID]
    local hasNormal = facts and IsSpellAvailable(facts.normal) or false
    local hasMass = IsSpellAvailable(mass)
    return {
        normal = hasNormal or hasMass,
        mass = hasMass,
        combat = facts and IsSpellAvailable(facts.combat) or false,
    }
end

local function FirstAvailable(...)
    for index = 1, select("#", ...) do
        local spellID = select(index, ...)
        if IsSpellAvailable(spellID) then return spellID end
    end
end

---@param config table
---@param class string?
---@param specID number?
---@return number? normalSpellID
---@return number? combatSpellID
function CC.ResolveSmartResurrection(config, class, specID)
    if type(config) ~= "table"
        or config.smartResurrection == "disabled"
    then
        return
    end

    class = class or AF.player.class
    specID = specID or AF.player.specID
    local facts = resurrectionFacts[class]
    if not facts then return end

    local normal
    if config.smartResurrection == "normal"
        or config.smartResurrection == "normal+combat"
    then
        local mass = facts.massBySpec and facts.massBySpec[specID]
        if config.preferMassResurrection then
            normal = FirstAvailable(mass, facts.normal)
        else
            normal = FirstAvailable(facts.normal, mass)
        end
    end

    local combat
    if config.smartResurrection == "normal+combat" then
        combat = FirstAvailable(facts.combat)
    end
    return normal, combat
end

---@param spellID number|string
---@param config table
---@return table? action
function CC.GetSmartResurrectionAction(spellID, config)
    spellID = tonumber(spellID)
    if not spellID or CC.IsResurrectionSpell(spellID) then return end

    local normal, combat = CC.ResolveSmartResurrection(config)
    if not normal and not combat then return end
    return {
        original = spellID,
        normal = normal,
        combat = combat,
    }
end

local function AddCandidate(snapshot, spellID, category, values)
    if type(spellID) ~= "number" or spellID <= 0 then return end
    values = values or {}
    local name, iconID = AF.GetSpellInfo(spellID)
    local effectiveSpellID = values.effectiveSpellID or spellID
    local effectiveName, effectiveIcon = AF.GetSpellInfo(effectiveSpellID)
    local displayName = values.name or effectiveName or name
    if not displayName then
        if C_Spell
            and type(C_Spell.RequestLoadSpellData) == "function"
        then
            C_Spell.RequestLoadSpellData(spellID)
        end
        return
    end

    snapshot.candidates[#snapshot.candidates + 1] = {
        spellID = spellID,
        effectiveSpellID = effectiveSpellID,
        name = displayName,
        iconID = values.iconID or effectiveIcon or iconID,
        category = category,
        selected = values.selected,
        isPet = values.isPet,
        isPassive = values.isPassive,
        isOffSpec = values.isOffSpec,
        forceInclude = values.forceInclude,
        isSpellBook = values.isSpellBook,
        canClickBind = values.canClickBind,
    }
end

local function CanSpellBeClickBound(spellID)
    if C_ClickBindings
        and type(C_ClickBindings.CanSpellBeClickBound) == "function"
    then
        return C_ClickBindings.CanSpellBeClickBound(spellID)
    end
end

local function CollectSpellBook(snapshot)
    if not C_SpellBook
        or type(C_SpellBook.GetSpellBookSkillLineInfo) ~= "function"
        or type(C_SpellBook.GetSpellBookItemInfo) ~= "function"
    then
        return
    end

    for _, descriptor in ipairs({
        {index = skillLineClass, category = "class"},
        {index = skillLineMainSpec, category = "spec"},
    }) do
        local skillLine = C_SpellBook.GetSpellBookSkillLineInfo(
            descriptor.index
        )
        if skillLine
            and not skillLine.shouldHide
            and not skillLine.offSpecID
            and (descriptor.category ~= "spec"
                or not skillLine.specID
                or skillLine.specID == snapshot.specID)
        then
            local first = (skillLine.itemIndexOffset or 0) + 1
            local last = first + (skillLine.numSpellBookItems or 0) - 1
            for slot = first, last do
                local item = C_SpellBook.GetSpellBookItemInfo(
                    slot,
                    spellBookBank
                )
                if item
                    and item.itemType == spellBookItemType
                    and not item.isPassive
                    and not item.isOffSpec
                then
                    AddCandidate(
                        snapshot,
                        item.actionID or item.spellID,
                        descriptor.category,
                        {
                            effectiveSpellID = item.spellID,
                            name = item.name,
                            iconID = item.iconID,
                            isSpellBook = true,
                            canClickBind = CanSpellBeClickBound(
                                item.actionID or item.spellID
                            ),
                        }
                    )
                end
            end
        end
    end
end

local function CollectPetSpellBook(snapshot)
    if not C_SpellBook
        or type(C_SpellBook.HasPetSpells) ~= "function"
        or type(C_SpellBook.GetSpellBookItemInfo) ~= "function"
    then
        return
    end

    local count = C_SpellBook.HasPetSpells()
    for slot = 1, tonumber(count) or 0 do
        local item = C_SpellBook.GetSpellBookItemInfo(
            slot,
            petSpellBookBank
        )
        if item
            and (item.itemType == spellBookItemType
                or item.itemType == petActionItemType)
            and not item.isPassive
            and not item.isOffSpec
        then
            local spellID = item.spellID
            -- PetAction actionID is not a pet-bar slot or necessarily a spell
            -- ID. Resolve it through the generated Retail API before storing
            -- BFI's numeric Spell action.
            if not spellID
                and item.itemType == petActionItemType
                and C_PetInfo
                and type(C_PetInfo.GetSpellForPetAction) == "function"
            then
                spellID = C_PetInfo.GetSpellForPetAction(item.actionID)
            end
            if spellID then
                AddCandidate(snapshot, spellID, "pet", {
                    effectiveSpellID = spellID,
                    name = item.name,
                    iconID = item.iconID,
                    isSpellBook = true,
                    isPet = true,
                    canClickBind = CanSpellBeClickBound(spellID),
                })
            end
        end
    end
end

local function CollectTalents(snapshot)
    if not C_ClassTalents
        or not C_Traits
        or type(C_ClassTalents.GetActiveConfigID) ~= "function"
        or type(C_Traits.GetConfigInfo) ~= "function"
        or type(C_Traits.GetTreeNodes) ~= "function"
        or type(C_Traits.GetNodeInfo) ~= "function"
        or type(C_Traits.GetEntryInfo) ~= "function"
        or type(C_Traits.GetDefinitionInfo) ~= "function"
    then
        return
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    local configInfo = configID and C_Traits.GetConfigInfo(configID)
    if not configInfo then return end

    local allowedHero = {}
    if type(C_ClassTalents.GetHeroTalentSpecsForClassSpec) == "function" then
        local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(
            configID,
            snapshot.specID
        )
        for _, subTreeID in ipairs(subTreeIDs or {}) do
            allowedHero[subTreeID] = true
        end
    end

    for _, treeID in ipairs(configInfo.treeIDs or {}) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local node = C_Traits.GetNodeInfo(configID, nodeID)
            local heroAllowed = node and node.subTreeID
                and allowedHero[node.subTreeID]
            if node
                and node.isVisible
                and (not node.subTreeID or heroAllowed)
            then
                for _, entryID in ipairs(node.entryIDs or {}) do
                    local entry = C_Traits.GetEntryInfo(configID, entryID)
                    local definition = entry
                        and entry.isAvailable
                        and entry.definitionID
                        and C_Traits.GetDefinitionInfo(entry.definitionID)
                    if definition and definition.spellID then
                        AddCandidate(
                            snapshot,
                            definition.spellID,
                            node.subTreeID and "hero" or "talent",
                            {
                                selected = node.activeEntry
                                    and node.activeEntry.entryID == entryID,
                            }
                        )
                    end
                end
            end
        end
    end
end

local function CollectPvPTalents(snapshot)
    if not C_SpecializationInfo
        or type(C_SpecializationInfo.GetPvpTalentSlotInfo) ~= "function"
        or type(C_SpecializationInfo.GetPvpTalentInfo) ~= "function"
    then
        return
    end

    local seen = {}
    for slot = 1, 3 do
        local slotInfo = C_SpecializationInfo.GetPvpTalentSlotInfo(slot)
        for _, talentID in ipairs(
            slotInfo and slotInfo.enabled
                and slotInfo.availableTalentIDs or {}
        ) do
            if not seen[talentID] then
                seen[talentID] = true
                local talent = C_SpecializationInfo.GetPvpTalentInfo(talentID)
                if talent
                    and talent.spellID
                    and talent.unlocked
                    and not talent.dependenciesUnmet
                then
                    AddCandidate(snapshot, talent.spellID, "pvp", {
                        name = talent.name,
                        iconID = talent.icon,
                        selected = talent.selected,
                    })
                end
            end
        end
    end
end

local function CollectResurrections(snapshot)
    local facts = resurrectionFacts[snapshot.class]
    if not facts then return end

    local function AddIfAvailable(spellID)
        if IsSpellAvailable(spellID) then
            AddCandidate(snapshot, spellID, "resurrection", {
                forceInclude = true,
            })
        end
    end

    AddIfAvailable(facts.normal)
    AddIfAvailable(facts.massBySpec and facts.massBySpec[snapshot.specID])
    AddIfAvailable(facts.combat)
end

local function CollectSnapshot()
    local snapshot = {
        class = AF.player.class,
        specID = AF.player.specID,
        candidates = {},
    }
    CollectSpellBook(snapshot)
    CollectPetSpellBook(snapshot)
    CollectTalents(snapshot)
    CollectPvPTalents(snapshot)
    CollectResurrections(snapshot)
    return snapshot
end

local function IsCandidateUseful(candidate)
    if candidate.forceInclude then return true end
    if candidate.isPassive or candidate.isOffSpec then return false end
    if candidate.isPet and not candidate.canClickBind then return false end
    if candidate.isSpellBook and candidate.canClickBind ~= nil then
        return candidate.canClickBind
    end

    local spellID = candidate.effectiveSpellID or candidate.spellID
    if C_Spell then
        if type(C_Spell.IsSpellHelpful) == "function"
            and not C_Spell.IsSpellHelpful(spellID)
        then
            return false
        end
        if type(C_Spell.IsSpellPassive) == "function"
            and C_Spell.IsSpellPassive(spellID)
        then
            return false
        end
        if type(C_Spell.IsSelfBuff) == "function"
            and C_Spell.IsSelfBuff(spellID)
        then
            return false
        end
        if type(C_Spell.SpellHasRange) == "function"
            and not C_Spell.SpellHasRange(spellID)
        then
            return false
        end
    end
    return true
end

---@param snapshot table?
---@return table entries
function CC.BuildSpellCatalog(snapshot)
    snapshot = snapshot or CollectSnapshot()
    local entries = {}
    local bySpellID = {}

    for _, candidate in ipairs(snapshot.candidates or {}) do
        if IsCandidateUseful(candidate) then
            local spellID = candidate.spellID
            local existing = bySpellID[spellID]
            if not existing then
                existing = {
                    spellID = spellID,
                    effectiveSpellID = candidate.effectiveSpellID,
                    name = candidate.name,
                    iconID = candidate.iconID,
                    category = candidate.category or "talent",
                    selected = candidate.selected and true or false,
                }
                entries[#entries + 1] = existing
                bySpellID[spellID] = existing
            else
                existing.selected = existing.selected or candidate.selected
                local oldSpecificity = categorySpecificity[
                    existing.category
                ] or 0
                local newSpecificity = categorySpecificity[
                    candidate.category
                ] or 0
                if newSpecificity > oldSpecificity then
                    existing.category = candidate.category
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        local aOrder = categoryOrder[a.category] or 99
        local bOrder = categoryOrder[b.category] or 99
        if aOrder ~= bOrder then return aOrder < bOrder end
        if a.selected ~= b.selected then return a.selected end
        if a.name ~= b.name then return a.name < b.name end
        return a.spellID < b.spellID
    end)
    return entries
end

function CC.GetSuggestedSpells()
    return CC.BuildSpellCatalog()
end
