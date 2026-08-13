local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local names = setmetatable({
    [1126] = "Mark of the Wild",
    [8936] = "Regrowth",
    [2782] = "Remove Corruption",
    [102342] = "Ironbark",
    [474750] = "Symbiotic Relationship",
    [305497] = "Thorns",
    [50769] = "Revive",
    [212040] = "Revitalize",
    [20484] = "Rebirth",
    [2061] = "Flash Heal",
    [2006] = "Resurrection",
    [212036] = "Mass Resurrection",
    [61999] = "Raise Ally",
    [90361] = "Spirit Mend",
}, {
    __index = function(_, spellID) return "Spell " .. tostring(spellID) end,
})
local known = {}
local passive = {[900001] = true}
local selfBuff = {[900002] = true}
local harmfulOnly = {[900003] = true}

local AF = {
    player = {
        class = "DRUID",
        specID = 105,
    },
}
function AF.GetSpellInfo(spellID)
    if not spellID then return end
    return names[spellID], spellID + 100000
end

local spellBookItems = {
    [1] = {itemType = 1, actionID = 1126, spellID = 1126},
    [2] = {
        itemType = 1,
        actionID = 900001,
        spellID = 900001,
        isPassive = true,
    },
    [3] = {itemType = 1, actionID = 900002, spellID = 900002},
    [4] = {itemType = 1, actionID = 900003, spellID = 900003},
    [5] = {itemType = 1, actionID = 8936, spellID = 8936},
    [6] = {itemType = 1, actionID = 102342, spellID = 102342},
    [7] = {
        itemType = 1,
        actionID = 999999,
        spellID = 999999,
        isOffSpec = true,
    },
}

local C_SpellBook = {}
function C_SpellBook.GetSpellBookSkillLineInfo(index)
    if index == 2 then
        return {itemIndexOffset = 0, numSpellBookItems = 4}
    elseif index == 3 then
        return {
            itemIndexOffset = 4,
            numSpellBookItems = 3,
            specID = AF.player.specID,
        }
    end
end
function C_SpellBook.GetSpellBookItemInfo(slot, bank)
    if bank == 1 then
        return {
            itemType = 3,
            actionID = 777777,
            name = names[90361],
            iconID = 190361,
        }
    end
    if slot == 5 and AF.player.specID == 104 then
        return {itemType = 1, actionID = 2782, spellID = 2782}
    end
    if AF.player.specID == 104 and slot == 6 then return end
    return spellBookItems[slot]
end
function C_SpellBook.HasPetSpells()
    return 1, "PET"
end
function C_SpellBook.IsSpellKnownOrInSpellBook(spellID)
    return known[spellID] ~= false
end

local C_Spell = {}
function C_Spell.IsSpellHelpful(spellID)
    return not harmfulOnly[spellID]
end
function C_Spell.IsSpellPassive(spellID)
    return passive[spellID] or false
end
function C_Spell.IsSelfBuff(spellID)
    return selfBuff[spellID] or false
end
function C_Spell.SpellHasRange()
    return true
end

local clickBoundCalls = {}
local C_ClickBindings = {}
function C_ClickBindings.CanSpellBeClickBound(spellID)
    clickBoundCalls[spellID] = true
    return spellID ~= 900002 and spellID ~= 900003
end

local C_ClassTalents = {}
function C_ClassTalents.GetActiveConfigID()
    return 77
end
function C_ClassTalents.GetHeroTalentSpecsForClassSpec()
    return {500}
end

local C_Traits = {}
function C_Traits.GetConfigInfo()
    return {treeIDs = {10}}
end
function C_Traits.GetTreeNodes()
    return {100, 101, 102}
end
function C_Traits.GetNodeInfo(_, nodeID)
    if nodeID == 100 then
        return {
            isVisible = AF.player.specID == 105,
            entryIDs = {1},
            activeEntry = {entryID = 1},
        }
    elseif nodeID == 101 then
        return {
            isVisible = true,
            subTreeID = 500,
            entryIDs = {2},
        }
    end
    return {isVisible = false, entryIDs = {3}}
end
function C_Traits.GetEntryInfo(_, entryID)
    return {isAvailable = true, definitionID = entryID + 1000}
end
function C_Traits.GetDefinitionInfo(definitionID)
    local spells = {
        [1001] = 102342,
        [1002] = 474750,
        [1003] = 999998,
    }
    return {spellID = spells[definitionID]}
end

local C_SpecializationInfo = {}
function C_SpecializationInfo.GetPvpTalentSlotInfo(slot)
    if slot == 1 then
        return {enabled = true, availableTalentIDs = {20}}
    elseif slot == 2 then
        return {enabled = false, availableTalentIDs = {21}}
    end
end
function C_SpecializationInfo.GetPvpTalentInfo(talentID)
    if talentID == 20 then
        return {
            spellID = 305497,
            name = names[305497],
            icon = 405497,
            selected = true,
            unlocked = true,
            dependenciesUnmet = false,
        }
    elseif talentID == 21 then
        error("disabled PvP slots are not enumerated")
    end
end

local environment = setmetatable({
    _G = false,
    AbstractFramework = AF,
    C_Spell = C_Spell,
    C_SpellBook = C_SpellBook,
    C_ClassTalents = C_ClassTalents,
    C_Traits = C_Traits,
    C_SpecializationInfo = C_SpecializationInfo,
    C_ClickBindings = C_ClickBindings,
    C_PetInfo = {
        GetSpellForPetAction = function(actionID)
            assertEqual(actionID, 777777, "pet action ID lookup")
            return 90361
        end,
    },
    Enum = {
        SpellBookSpellBank = {Player = 0, Pet = 1},
        SpellBookItemType = {Spell = 1, PetAction = 3},
        SpellBookSkillLineIndex = {Class = 2, MainSpec = 3},
    },
}, {__index = _G})
environment._G = environment

local CC = {}
local BFI = {modules = {ClickCastings = CC}}
local chunk = assert(loadfile("Modules/ClickCastings/SpellCatalog.lua"))
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local function Find(entries, spellID)
    for _, entry in ipairs(entries) do
        if entry.spellID == spellID then return entry end
    end
end

local resto = CC.GetSuggestedSpells()
assertEqual(Find(resto, 1126).category, "class", "class spell category")
assertEqual(Find(resto, 8936).category, "spec", "restoration spell")
assertEqual(Find(resto, 102342).category, "talent", "visible talent")
assertEqual(Find(resto, 474750).category, "hero", "current hero tree")
assertEqual(Find(resto, 305497).category, "pvp", "current PvP talent")
assertEqual(Find(resto, 212040).category, "resurrection",
    "restoration mass resurrection")
assertEqual(Find(resto, 900001), nil, "passive excluded")
assertEqual(Find(resto, 900002), nil, "self-only spell excluded")
assertEqual(Find(resto, 900003), nil, "harmful-only spell excluded")
assertEqual(Find(resto, 999999), nil, "off-spec spell excluded")
assertEqual(Find(resto, 90361).category, "pet", "active pet spell")
assert(clickBoundCalls[1126] and clickBoundCalls[90361],
    "learned player and pet spells use Blizzard's click-binding predicate")

AF.player.specID = 104
local guardian = CC.GetSuggestedSpells()
assert(Find(guardian, 2782), "guardian spellbook replaces restoration list")
assertEqual(Find(guardian, 8936), nil, "restoration spell is no longer suggested")
assertEqual(Find(guardian, 102342), nil, "restoration talent is no longer suggested")
assertEqual(Find(guardian, 212040), nil,
    "restoration mass resurrection is no longer suggested")

local config = {
    smartResurrection = "normal+combat",
    preferMassResurrection = true,
}
AF.player.specID = 105
local normal, combat = CC.ResolveSmartResurrection(config)
assertEqual(normal, 212040, "restoration prefers mass resurrection")
assertEqual(combat, 20484, "druid combat resurrection")

AF.player.specID = 104
normal, combat = CC.ResolveSmartResurrection(config)
assertEqual(normal, 50769, "guardian uses normal resurrection")
assertEqual(combat, 20484, "guardian retains combat resurrection")

config.preferMassResurrection = false
AF.player.specID = 105
normal = CC.ResolveSmartResurrection(config)
assertEqual(normal, 50769, "single-target preference overrides mass res")

config.preferMassResurrection = true
known[212040] = false
normal = CC.ResolveSmartResurrection(config)
assertEqual(normal, 50769, "unavailable mass res falls back to normal res")
known[212040] = nil

AF.player.specID = 105
local action = CC.GetSmartResurrectionAction(2061, config)
assertEqual(action.original, 2061,
    "smart action preserves the original numeric spell ID")
assertEqual(action.normal, 212040,
    "smart action includes the spec-derived normal resurrection")
assertEqual(action.combat, 20484,
    "smart action includes the combat resurrection")
assertEqual(CC.GetSmartResurrectionAction(20484, config), nil,
    "explicit resurrection is not recursively rewritten")

local capabilities = CC.GetSmartResurrectionCapabilities("DRUID", 105)
assertEqual(capabilities.normal, true, "druid has normal resurrection")
assertEqual(capabilities.mass, true, "restoration has mass resurrection")
assertEqual(capabilities.combat, true, "druid has combat resurrection")
capabilities = CC.GetSmartResurrectionCapabilities("MAGE", 62)
assertEqual(capabilities.normal, false, "mage has no resurrection mode")
assertEqual(capabilities.combat, false, "mage has no combat resurrection")
known[212040] = false
known[50769] = false
known[20484] = false
capabilities = CC.GetSmartResurrectionCapabilities("DRUID", 105)
assertEqual(capabilities.normal, false,
    "unlearned resurrection does not advertise a usable normal mode")
assertEqual(capabilities.mass, false,
    "unlearned mass resurrection disables its preference")
assertEqual(capabilities.combat, false,
    "unlearned combat resurrection does not advertise capability")
known[212040], known[50769], known[20484] = nil, nil, nil

normal = CC.ResolveSmartResurrection(config, "PRIEST", 256)
assertEqual(normal, 212036, "discipline priest mass resurrection")
normal = CC.ResolveSmartResurrection(config, "PRIEST", 258)
assertEqual(normal, 2006, "shadow priest normal resurrection")
normal, combat = CC.ResolveSmartResurrection(config, "DEATHKNIGHT", 250)
assertEqual(normal, nil, "death knight has no normal resurrection")
assertEqual(combat, 61999, "death knight combat resurrection")

print("click_casting_spell_catalog_test: ok")
