---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
local L = BFI.L
---@type Style
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local ceil = math.ceil
local floor = math.floor
local sort = table.sort
local band = _G.bit.band
local GetCVarBool = _G.GetCVarBool
local GetInventoryItemTexture = _G.GetInventoryItemTexture
local SetCVar = _G.SetCVar
local GetCurrentItemLevel = _G.C_Item.GetCurrentItemLevel
local IsEquippableItem = _G.C_Item.IsEquippableItem
local ItemLocation = _G.ItemLocation

local ITEM_CLASS = _G.Enum.ItemClass
local BAG_TOP_WITH_SLOTS = 100
local BAG_TOP_WITHOUT_SLOTS = 64
local SIDEBAR_TOP = 58
local SIDEBAR_MIN_HEIGHT = 320
local SECTION_HEADER_HEIGHT = 18
local SECTION_HEADER_GAP = 4
local SECTION_SPACING = 7
local ITEM_SIZE = 37
local HORIZONTAL_PADDING = 12
local FOOTER_PADDING = 12
local MIN_FRAME_WIDTH = 320
local SCREEN_EDGE_MARGIN = 16
local SHOW_BAGS_ICON = AF.GetIcon("Layers")
local REAGENT_SPACE_ICON = "bags-icon-reagents"
local HEADER_ICON_COLOR = AF.player.class
local BACKPACK_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local EMPTY_BAG_ICON = 133633
local EMPTY_KIND_BAG = 1
local EMPTY_KIND_REAGENT = 2
local NON_EQUIPMENT_LOCATION = "INVTYPE_NON_EQUIP_IGNORE"

local equipmentSlotAliases = {
    INVTYPE_ROBE = "INVTYPE_CHEST",
    INVTYPE_SHIELD = "INVTYPE_WEAPONOFFHAND",
    INVTYPE_HOLDABLE = "INVTYPE_WEAPONOFFHAND",
    INVTYPE_RANGEDRIGHT = "INVTYPE_RANGED",
    INVTYPE_THROWN = "INVTYPE_RANGED",
}
local equipmentSlotOrder = {
    INVTYPE_HEAD = 1,
    INVTYPE_NECK = 2,
    INVTYPE_SHOULDER = 3,
    INVTYPE_CLOAK = 4,
    INVTYPE_CHEST = 5,
    INVTYPE_WRIST = 6,
    INVTYPE_HAND = 7,
    INVTYPE_WAIST = 8,
    INVTYPE_LEGS = 9,
    INVTYPE_FEET = 10,
    INVTYPE_FINGER = 11,
    INVTYPE_TRINKET = 12,
    INVTYPE_WEAPONMAINHAND = 13,
    INVTYPE_WEAPONOFFHAND = 14,
    INVTYPE_WEAPON = 15,
    INVTYPE_2HWEAPON = 16,
    INVTYPE_RANGED = 17,
    INVTYPE_BODY = 18,
    INVTYPE_TABARD = 19,
    INVTYPE_PROFESSION_TOOL = 20,
    INVTYPE_PROFESSION_GEAR = 21,
    INVTYPE_BAG = 22,
}
-- categoryIconByEquipLoc: childIcon lookups for equipment slots, keyed by
-- the post-alias INVTYPE (see equipmentSlotAliases above); aliased INVTYPEs
-- share their target slot's icon since GetCategory substitutes the alias
-- before building childKey. Nested as a nonnumeric field on the existing
-- equipmentSlotOrder local, rather than declared as its own top-level
-- local, because Modules/Bags/Bags.lua's main chunk is already at Lua
-- 5.1's 200-local ceiling (verified by scripts/lint.sh's byte-compile
-- step) with no free slot to spare; equipmentSlotOrder's own INVTYPE_*
-- keys never collide with this "categoryIconByEquipLoc" string key.
-- Populated below the do-block, not as a static literal: each entry is the
-- client's own paper-doll slot texture, resolved once via
-- GetInventorySlotInfo, so the sidebar matches the character pane exactly.
-- See the evidence comment further down for the verified INVTYPE ->
-- slot-name contract and the GetInventorySlotInfo API signature. An INVTYPE
-- that GetInventorySlotInfo can't resolve (API unavailable in this
-- environment, or a slot with no paper-doll frame at all, such as
-- profession tools/gear) is simply absent here; BuildSidebarModel's
-- child.icon or group.icon chain then falls back to the parent Equipment
-- icon, so a nil mapping still renders something.
equipmentSlotOrder.categoryIconByEquipLoc = {}
do
    -- INVTYPE -> character-pane slot-name, verified against
    -- PaperDollFrame.xml's ItemButton names ("Character" .. slotName,
    -- stripped by PaperDollItemSlotButton_GetSlotName) at both pinned
    -- commits. Neither commit defines a Ranged slot frame (only
    -- MainHandSlot/SecondaryHandSlot exist), so ranged weapons share
    -- MainHandSlot with one- and two-handed weapons, matching how the
    -- client itself renders them on the paper doll. INVTYPE_PROFESSION_TOOL,
    -- INVTYPE_PROFESSION_GEAR, and INVTYPE_BAG are intentionally omitted:
    -- neither artifact has a matching slot frame (profession tools/gear
    -- equip through the Professions UI, not PaperDollFrame; bags have no
    -- paper-doll button).
    local INV_TYPE_TO_SLOT = {
        INVTYPE_HEAD = "HeadSlot",
        INVTYPE_NECK = "NeckSlot",
        INVTYPE_SHOULDER = "ShoulderSlot",
        INVTYPE_CLOAK = "BackSlot",
        INVTYPE_CHEST = "ChestSlot",
        INVTYPE_BODY = "ShirtSlot",
        INVTYPE_TABARD = "TabardSlot",
        INVTYPE_WRIST = "WristSlot",
        INVTYPE_HAND = "HandsSlot",
        INVTYPE_WAIST = "WaistSlot",
        INVTYPE_LEGS = "LegsSlot",
        INVTYPE_FEET = "FeetSlot",
        INVTYPE_FINGER = "Finger0Slot",
        INVTYPE_TRINKET = "Trinket0Slot",
        INVTYPE_WEAPONMAINHAND = "MainHandSlot",
        INVTYPE_WEAPONOFFHAND = "SecondaryHandSlot",
        INVTYPE_WEAPON = "MainHandSlot",
        INVTYPE_2HWEAPON = "MainHandSlot",
        INVTYPE_RANGED = "MainHandSlot",
    }
    -- Retail 12.1.0.68914 moves this call behind the C_PaperDollInfo
    -- namespace; Retail 12.0.7.68887 still exposes it as a bare global.
    -- Prefer the namespaced form when present so slot-art resolution keeps
    -- working after a future client migrates. See the evidence comment for
    -- both call sites and the shared (invSlot, slotTexture, checkRelic)
    -- return contract.
    local getInventorySlotInfo = (_G.C_PaperDollInfo and _G.C_PaperDollInfo.GetInventorySlotInfo)
        or _G.GetInventorySlotInfo
    if getInventorySlotInfo then
        for invType, slotName in next, INV_TYPE_TO_SLOT do
            local _, textureName = getInventorySlotInfo(slotName)
            if textureName then
                equipmentSlotOrder.categoryIconByEquipLoc[invType] = {texture = textureName}
            end
        end
    end
end
local categoryOrderByClass = {
    [ITEM_CLASS.Consumable] = 200,
    [ITEM_CLASS.Gem] = 300,
    [ITEM_CLASS.Tradegoods] = 400,
    [ITEM_CLASS.Reagent] = 400,
    [ITEM_CLASS.ItemEnhancement] = 400,
    [ITEM_CLASS.Profession] = 400,
    [ITEM_CLASS.Recipe] = 500,
    [ITEM_CLASS.Questitem] = 800,
}
-- Parent-category icons: native ContainerFrame.lua bag-type-filter atlases
-- (BAG_FILTER_ICONS, verified identical at both pinned commits) replace the
-- Tabler Bag_* glyphs wherever a matching filter class exists. Gem,
-- Tradegoods, ItemEnhancement, and Profession keep BFI's pre-existing design
-- choice of sharing one icon (order 300/400 above); "bags-icon-profession-
-- goods" is the closest verified native equivalent for that shared bucket.
-- Recipe has no matching bag-type filter in either artifact (only
-- Equipment/Consumables/ProfessionGoods/Junk/QuestItems/Reagents exist), so
-- its parent icon (like Housing's below, and both classes' subclass icons
-- further down) is a hand-picked Interface\Icons texture instead -- an art
-- choice, not an API claim; see the evidence comment further down for the
-- chosen paths and the in-game QA note.
local categoryIconByClass = {
    [ITEM_CLASS.Consumable] = {atlas = "bags-icon-consumables"},
    [ITEM_CLASS.Gem] = {atlas = "bags-icon-profession-goods"},
    [ITEM_CLASS.Tradegoods] = {atlas = "bags-icon-profession-goods"},
    [ITEM_CLASS.Reagent] = {atlas = "bags-icon-reagents"},
    [ITEM_CLASS.ItemEnhancement] = {atlas = "bags-icon-profession-goods"},
    [ITEM_CLASS.Profession] = {atlas = "bags-icon-profession-goods"},
    [ITEM_CLASS.Recipe] = {texture = "Interface\\Icons\\INV_Misc_Book_09"},
    [ITEM_CLASS.Questitem] = {atlas = "bags-icon-questitem"},
}
-- ItemConstantsDocumentation.lua lists ItemClass.Housing (EnumValue = 20)
-- identically at both pinned commits (Retail 12.0.7.68887
-- 4383ced30106d51b27e3e86d1987f1552f0d259d and Retail 12.1.0.68914
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9) -- it is not a 12.1.0-only
-- addition. Keep the nil guard anyway for clients/environments older or
-- more minimal than either pinned artifact, where this enum member has not
-- been verified present. The icon itself is a hand-picked house-themed
-- Interface\Icons texture (art choice, not an API claim; see the evidence
-- comment further down), same as Recipe's above.
if ITEM_CLASS.Housing then
    categoryOrderByClass[ITEM_CLASS.Housing] = 600
    categoryIconByClass[ITEM_CLASS.Housing] = {texture = "Interface\\Icons\\INV_Misc_GarrisonHearthstone"}
end

-- categoryIconBySubclass: childIcon lookups for consumable and recipe
-- subclasses. Nested as a nonnumeric field on the existing
-- categoryOrderByClass local (same 200-local-ceiling reason as
-- equipmentSlotOrder.categoryIconByEquipLoc above); categoryOrderByClass's
-- own classID keys never collide with this "categoryIconBySubclass" string
-- key. The host table itself is created unconditionally (never nil), so
-- GetCategory's "categoryOrderByClass.categoryIconBySubclass and
-- categoryOrderByClass.categoryIconBySubclass[classID]" guard always finds
-- a table to index (possibly with no entry for a given classID); each
-- classID's own entry is populated only behind its own enum-presence guard,
-- independently, matching the ITEM_CLASS.Housing guard above.
categoryOrderByClass.categoryIconBySubclass = {}

-- Consumable: see the API evidence comment below for the pinned artifacts:
-- Retail 12.0.7.68887 and PTR 12.1.0.68914 both list the same 13
-- Enum.ItemConsumableSubclass members, including the five used here
-- (Potion = 1, Elixir = 2, Flasksphials = 3, Fooddrink = 5, Bandage = 7).
-- Guarded because Enum.ItemConsumableSubclass itself is absent on some
-- minimal test/client environments even though every member used here is
-- present on both pinned Retail artifacts. The five texture paths below are
-- an art choice, not an API claim (no per-subclass atlas exists in either
-- artifact): five long-standing classic Interface\Icons raster icons,
-- chosen for their subject matter; see the evidence comment for the list
-- and the in-game QA note.
if _G.Enum.ItemConsumableSubclass then
    categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Consumable] = {
        [_G.Enum.ItemConsumableSubclass.Potion] = {texture = "Interface\\Icons\\INV_Potion_93"},
        [_G.Enum.ItemConsumableSubclass.Flasksphials] = {texture = "Interface\\Icons\\INV_Potion_97"},
        [_G.Enum.ItemConsumableSubclass.Fooddrink] = {texture = "Interface\\Icons\\INV_Misc_Food_15"},
        [_G.Enum.ItemConsumableSubclass.Bandage] = {texture = "Interface\\Icons\\INV_Misc_Bandage_08"},
        [_G.Enum.ItemConsumableSubclass.Elixir] = {texture = "Interface\\Icons\\INV_Potion_31"},
    }
end

-- Recipe: both pinned artifacts' ItemConstantsDocumentation.lua list the
-- same 12 Enum.ItemRecipeSubclass members (Book = 0, Leatherworking = 1,
-- Tailoring = 2, Engineering = 3, Blacksmithing = 4, Cooking = 5,
-- Alchemy = 6, FirstAid = 7, Enchanting = 8, Fishing = 9,
-- Jewelcrafting = 10, Inscription = 11) -- all twelve keys below are
-- verified against that enum. The texture values are an art choice, not an
-- API claim (no per-profession atlas exists in either artifact, see the
-- evidence comment further down): a distinct Interface\Icons texture per
-- profession where a confidently-real, thematically fitting classic icon
-- exists, otherwise the same generic book texture as the Recipe parent
-- icon above. Guarded like Consumable above, for the same reason.
if _G.Enum.ItemRecipeSubclass then
    categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Recipe] = {
        [_G.Enum.ItemRecipeSubclass.Book] = {texture = "Interface\\Icons\\INV_Misc_Book_09"},
        [_G.Enum.ItemRecipeSubclass.Leatherworking] = {texture = "Interface\\Icons\\INV_Misc_Book_09"},
        [_G.Enum.ItemRecipeSubclass.Tailoring] = {texture = "Interface\\Icons\\INV_Misc_Book_09"},
        [_G.Enum.ItemRecipeSubclass.Engineering] = {texture = "Interface\\Icons\\INV_Misc_Gizmo_02"},
        [_G.Enum.ItemRecipeSubclass.Blacksmithing] = {texture = "Interface\\Icons\\INV_Hammer_01"},
        [_G.Enum.ItemRecipeSubclass.Cooking] = {texture = "Interface\\Icons\\INV_Misc_Food_15"},
        [_G.Enum.ItemRecipeSubclass.Alchemy] = {texture = "Interface\\Icons\\INV_Potion_92"},
        [_G.Enum.ItemRecipeSubclass.FirstAid] = {texture = "Interface\\Icons\\INV_Misc_Bandage_08"},
        [_G.Enum.ItemRecipeSubclass.Enchanting] = {texture = "Interface\\Icons\\INV_Enchant_Disenchant"},
        [_G.Enum.ItemRecipeSubclass.Fishing] = {texture = "Interface\\Icons\\INV_Fishingpole_01"},
        [_G.Enum.ItemRecipeSubclass.Jewelcrafting] = {texture = "Interface\\Icons\\INV_Misc_Gem_01"},
        [_G.Enum.ItemRecipeSubclass.Inscription] = {texture = "Interface\\Icons\\INV_Misc_Book_09"},
    }
end

-- Trade Goods (ITEM_CLASS.Tradegoods) subclasses are intentionally left
-- unmapped at the subclass level, unlike Consumable/Recipe above: neither
-- pinned artifact documents an Enum.ItemTradeGoodsSubclass (or similarly
-- named) enum anywhere in ItemConstantsDocumentation.lua,
-- ItemConstants_MainlineDocumentation.lua, or
-- ItemConstants_SharedDocumentation.lua, no GlobalStrings-style source file
-- exists in the mirror to verify the classic subclass name strings
-- ("Cloth", "Leather", etc.) either, and
-- Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionData.lua's own Trade
-- Goods category (`tradeGoodsCategory:GenerateSubCategoriesAndFiltersFromSubClass(
-- Enum.ItemClass.Tradegoods)`) builds its subclass list dynamically at
-- runtime rather than from any static, checkable table. Without a verified
-- key, per policy this stays on the parent categoryIconByClass entry above
-- rather than guessing numeric subclassIDs from memory.

local inventoryConstants = _G.Constants.InventoryConstants
local REAGENT_BAG_ID = inventoryConstants.NumBagSlots + inventoryConstants.NumReagentBagSlots

local combinedFrame
local bagSlotsButton
local bagSidebar
local initialized
local moduleEnabled
local itemLevelDisplayActive
local refreshPending
local layoutInProgress
local layoutEntryCount = 0
local emptyButtonCount = 0
local layoutAddSlotsTarget
local layoutEpoch = 0
local snapshotCount = 0
local snapshotViewMode
local snapshotCategoryKey
local snapshotShowBagSlots
local snapshotColumns
local snapshotSpacing
local snapshotSidebarCollapsed
local snapshotWidth
local snapshotHeight
local snapshotFooterHeight
local hoveredBagID
local activeCategoryKey
local portraitWasShown
local portraitMouseEnabled
local portraitAlpha
local UpdateEmptyRepresentativeForCursor
local previousCombinedBags
local hasPreviousCombinedBags
local suppressedReagentFrame
local suppressedReagentAlpha

local bagButtons = {}
local sectionHeaders = {}
local categoryCache = {}
local categoryGroups = {}
local categoryGroupPool = {}
local categoryGroupByKey = {}
local categoryGroupPoolCount = 0
local individualGroups = {}
local individualGroupPool = {}
local individualGroupByBag = {}
local flatGroup = {items = {}}
local reagentItemButtons = {}
local suppressedMouseStates = {}
local portraitProxyMouseStates = {}
local emptyCountsByBag = {}
local bagFamilies = {}
local emptyButtons = {}
local emptyButtonBagIDs = {}
local emptyButtonFamilies = {}
local emptyButtonKinds = {}
local emptyStates = {
    [EMPTY_KIND_BAG] = {},
    [EMPTY_KIND_REAGENT] = {},
}
local styledItemButtons = setmetatable({}, {__mode = "k"})
local itemLevelButtons = setmetatable({}, {__mode = "k"})
local layoutObjects = {}
local layoutObjectX = {}
local layoutObjectY = {}
local snapshotButtons = {}
local snapshotBagIDs = {}
local snapshotSlotIDs = {}
local snapshotItemIDs = {}
local snapshotExtended = {}
local blizzardBagBarWasShown
local hasBlizzardBagBarState
local cleanupTooltipState = {}
local sidebarModel = {}

local VIEW_MODE_COMBINED = "combined"
local VIEW_MODE_CATEGORIES = "categories"
local VIEW_MODE_INDIVIDUAL = "individual"

-- API and lifecycle evidence: Retail 12.0.7
-- Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua and
-- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua. The native combined
-- container owns item interaction, search, sorting, currency, and its
-- show-only event registrations. BFI only extends its pooled layout.
-- Blizzard_MainMenuBarBagButtons/Shared/BagsBar.lua and
-- Blizzard_FrameXMLBase/Mainline/FrameLocks.lua show that BagsBar separately
-- owns the persistent HUD buttons and may have a lock-managed logical state.
-- Item-level evidence: Retail 12.0.7.68887 source commit
-- 4383ced30106d51b27e3e86d1987f1552f0d259d and Retail 12.1.0.68914
-- source commit d3915c78aba77a7a9be76acbfa35c674bbb6abe9.
-- ItemDocumentation.lua documents IsEquippableItem and GetCurrentItemLevel;
-- ContainerFrame.lua waits on ContinuableContainer before UpdateItems.
-- ItemButtonTemplate.xml gives stack counts NumberFontNormal, while
-- ItemButtonTemplate.lua applies HIGHLIGHT_FONT_COLOR; item levels mirror both.
-- Child-category icon evidence: the same two pinned commits'
-- Blizzard_APIDocumentationGenerated/ItemConstantsDocumentation.lua
-- enumerate Enum.ItemConsumableSubclass identically on both 12.0.7.68887
-- (4383ced30106d51b27e3e86d1987f1552f0d259d) and 12.1.0.68914
-- (d3915c78aba77a7a9be76acbfa35c674bbb6abe9): Generic = 0, Potion = 1,
-- Elixir = 2, Flasksphials = 3, Scroll = 4, Fooddrink = 5,
-- Itemenhancement = 6, Bandage = 7, Other = 8, VantusRune = 9,
-- UtilityCurio = 10, CombatCurio = 11, Relic = 12. categoryIconBySubclass
-- below uses Potion, Flasksphials, Fooddrink, Bandage, and Elixir; the
-- remaining subclasses (including Other) fall back to the parent
-- Consumables icon via the child.icon or group.icon chain in
-- BuildSidebarModel, since no distinct icon is mapped for them.
--
-- Native icon evidence (Task 5, same two pinned commits: Retail 12.0.7.68887
-- 4383ced30106d51b27e3e86d1987f1552f0d259d and Retail 12.1.0.68914
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9):
--
-- 1. GetInventorySlotInfo(slotName) -> id/invSlot, textureName/slotTexture,
--    checkRelic. Confirmed by direct call site in both commits'
--    Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua
--    (PaperDollItemSlotButton_OnLoad): 12.0.7.68887 calls the bare global
--    `GetInventorySlotInfo(slotName)`; 12.1.0.68914 calls the same
--    signature behind the new `C_PaperDollInfo.GetInventorySlotInfo`
--    namespace. The three-return contract (invSlot, slotTexture,
--    checkRelic) is also documented at 12.1.0.68914 in
--    Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua
--    (Namespace = "C_PaperDollInfo"); that function is not yet listed in
--    the same doc file at 12.0.7.68887, consistent with it still being a
--    bare global there. equipmentSlotOrder.categoryIconByEquipLoc's
--    load-time do-block above prefers the namespaced form when present and
--    falls back to the bare global, so slot-art resolution survives the
--    future client's migration; if neither exists (e.g. a minimal test
--    environment) the loop is skipped entirely and every equipment child
--    icon is absent, which BuildSidebarModel's child.icon or group.icon
--    chain resolves to the parent Equipment icon below.
-- 2. INVTYPE -> slot-name: verified against the ItemButton names in both
--    commits' Blizzard_UIPanels_Game/Mainline/PaperDollFrame.xml (identical
--    at both commits): CharacterHeadSlot, CharacterNeckSlot,
--    CharacterShoulderSlot, CharacterBackSlot, CharacterChestSlot,
--    CharacterShirtSlot, CharacterTabardSlot, CharacterWristSlot,
--    CharacterHandsSlot, CharacterWaistSlot, CharacterLegsSlot,
--    CharacterFeetSlot, CharacterFinger0Slot/Finger1Slot,
--    CharacterTrinket0Slot/Trinket1Slot, CharacterMainHandSlot,
--    CharacterSecondaryHandSlot (PaperDollItemSlotButton_GetSlotName strips
--    the leading "Character"). Neither commit defines a Ranged slot frame
--    (removed pre-Legion; retail's paper doll has only MainHandSlot and
--    SecondaryHandSlot), so INVTYPE_WEAPON, INVTYPE_2HWEAPON, and
--    INVTYPE_RANGED all resolve to MainHandSlot, matching how the client
--    itself equips one-handed, two-handed, and ranged weapons.
--    INVTYPE_PROFESSION_TOOL, INVTYPE_PROFESSION_GEAR, and INVTYPE_BAG have
--    no matching ItemButton in either commit's PaperDollFrame.xml (searched
--    the full file; profession tools/gear are equipped through
--    Blizzard_Professions, not the character pane, and bags have no
--    paper-doll slot at all) and are intentionally left out of
--    INV_TYPE_TO_SLOT, per policy: unverifiable entries fall back to the
--    parent Equipment icon rather than being guessed.
-- 3. Parent-category atlases: both commits' identical
--    Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua defines a
--    `BAG_FILTER_ICONS` table (~line 218) keyed by Enum.BagSlotFlags,
--    consumed by `ContainerFrame_GetBestFilterIcon` to badge each
--    container's portrait button with its configured bag-type filter:
--      [Enum.BagSlotFlags.ClassEquipment]       = "bags-icon-equipment"
--      [Enum.BagSlotFlags.ClassConsumables]     = "bags-icon-consumables"
--      [Enum.BagSlotFlags.ClassProfessionGoods] = "bags-icon-profession-goods"
--      [Enum.BagSlotFlags.ClassJunk]            = "bags-icon-junk"
--      [Enum.BagSlotFlags.ClassQuestItems]      = "bags-icon-questitem"
--      [Enum.BagSlotFlags.ClassReagents]        = "bags-icon-reagents"
--    "bags-icon-reagents" additionally corroborates REAGENT_SPACE_ICON
--    above, already in production use. categoryIconByClass and GetCategory's
--    equipment parentIcon below use these six atlases directly (Gem,
--    Tradegoods, ItemEnhancement, and Profession share
--    "bags-icon-profession-goods", matching BFI's pre-existing decision to
--    group them under one icon). No filter class exists for Recipe or
--    Housing in either commit's BAG_FILTER_ICONS; both use a hand-picked
--    Interface\Icons texture instead (item 5 below), not an atlas claim.
-- 4. Per-profession subclass keys and atlases (Trade Goods / Recipes): both
--    commits' ItemConstantsDocumentation.lua document ItemProfessionSubclass
--    (0-13, one member per profession, matching ITEM_CLASS.Profession) and
--    ItemRecipeSubclass (0-11, matching ITEM_CLASS.Recipe) identically.
--    Neither commit's Blizzard_Professions or Blizzard_ProfessionsBook
--    source defines a static per-profession atlas (no `atlas=` usage tied
--    to a profession identity in Blizzard_ProfessionsFrame.lua/.xml or
--    Blizzard_ProfessionsBook.lua/.xml at either commit; the profession
--    tab/spec icons those files do draw come from runtime API calls such as
--    GetChildProfessionInfo, not a fixed literal a static Lua table could
--    reference), so Recipe's subclass icons use hand-picked textures
--    instead (item 5 below), keyed by the verified ItemRecipeSubclass
--    members. No Enum.ItemTradegoodsSubclass or Enum.ItemEnhancementSubclass
--    exists in either commit's ItemConstantsDocumentation.lua/
--    ItemConstants_MainlineDocumentation.lua/
--    ItemConstants_SharedDocumentation.lua either -- confirmed by grepping
--    all three files at both commits for any "*Subclass" enumeration tied
--    to Trade Goods. No GlobalStrings-equivalent source file exists in the
--    mirror to verify the classic Trade Goods subclass name strings
--    ("Cloth", "Leather", etc.) as an alternative string key either.
--    Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionData.lua's own Trade
--    Goods browse category
--    (`tradeGoodsCategory:GenerateSubCategoriesAndFiltersFromSubClass(
--    Enum.ItemClass.Tradegoods)`) builds its subclass list dynamically at
--    runtime, not from any static literal this file could cite either. Per
--    policy, ITEM_CLASS.Tradegoods therefore stays unmapped at the subclass
--    level (no numeric subclassID is guessed), falling back to its parent
--    class icon (categoryIconByClass) above.
-- 5. Art-choice textures (Consumable/Recipe subtypes, Recipe/Housing
--    parents): hand-picked per the brief/owner ruling, not an API claim, so
--    none of the following are gated on either pinned commit -- only the
--    *keys* above (Enum.ItemConsumableSubclass/Enum.ItemRecipeSubclass
--    members, or the classID itself) carry an artifact-verification
--    requirement, which items 1-4 already satisfy. Consumable subtypes:
--    Interface\Icons\INV_Potion_93 (Potion), INV_Potion_97 (Flasksphials),
--    INV_Misc_Food_15 (Fooddrink), INV_Misc_Bandage_08 (Bandage),
--    INV_Potion_31 (Elixir). Recipe subtypes: INV_Misc_Book_09
--    (Book/Leatherworking/Tailoring/Inscription -- shared generic book,
--    per the owner's explicit "one shared book icon" fallback allowance,
--    used where a distinct per-profession book/scroll filename could not be
--    picked with confidence), INV_Misc_Gizmo_02 (Engineering), INV_Hammer_01
--    (Blacksmithing), INV_Misc_Food_15 (Cooking, reused from the consumable
--    Fooddrink pick above), INV_Potion_92 (Alchemy), INV_Misc_Bandage_08
--    (FirstAid, reused from the consumable Bandage pick above),
--    INV_Enchant_Disenchant (Enchanting), INV_Fishingpole_01 (Fishing),
--    INV_Misc_Gem_01 (Jewelcrafting). Recipe parent: INV_Misc_Book_09 (same
--    generic book as its Book/Leatherworking/Tailoring/Inscription
--    subtypes). Housing parent: INV_Misc_GarrisonHearthstone (a real,
--    literally house-shaped classic item icon). Final visual fit for all of
--    the above is an in-game QA gate, not verified here.
-- 6. textureTint: AbstractFramework/Widgets/TreeList.lua's ApplyNodeIcon
--    (commit 973d708d144971970176f3fff2429cda17aaae2b on
--    codex/bag-sidebar-foundation) resets a string/glyph icon's row.icon to
--    `SetVertexColor(1, 1, 1, ROW_ICON_ALPHA)` -- full-white, at the row's
--    existing baseline alpha. Modules/Bags/Sidebar.lua's textureTint =
--    {1, 1, 1} reuses that exact RGB so the new atlas/texture category
--    icons desaturate to the same flat white tone the rail's remaining
--    glyph rows already render at, instead of showing their own full-color
--    native art.

local function IsEnabled()
    return moduleEnabled and B.config and B.config.enabled
end

local function GetViewMode()
    local mode = B.config and B.config.viewMode
    if mode == VIEW_MODE_COMBINED or mode == VIEW_MODE_INDIVIDUAL then
        return mode
    end
    return VIEW_MODE_COMBINED
end

local function GetDisplayMode()
    if activeCategoryKey then
        return VIEW_MODE_CATEGORIES
    end
    return GetViewMode()
end

local function IsBlizzardBagBarLogicallyShown(bagsBar)
    if _G.IsFrameSmartShown then
        return _G.IsFrameSmartShown(bagsBar)
    end
    return bagsBar:IsShown()
end

local function ShouldShowBlizzardBagBar()
    return B.config.showBlizzardBagBar
        and not _G.C_GameRules.IsGameRuleActive(_G.Enum.GameRule.BagsUIDisabled)
end

local function SetBlizzardBagBarShown(bagsBar, shown)
    if shown then
        bagsBar:Show()
    else
        bagsBar:Hide()
    end
end

local function UpdateBlizzardBagBarVisibility()
    if not IsEnabled() then return end

    local bagsBar = _G.BagsBar
    if not bagsBar then
        B:RegisterEvent("ADDON_LOADED", B.ADDON_LOADED)
        return
    end

    if not hasBlizzardBagBarState then
        blizzardBagBarWasShown = IsBlizzardBagBarLogicallyShown(bagsBar)
        hasBlizzardBagBarState = true
    end

    local shouldShow = ShouldShowBlizzardBagBar()
    if IsBlizzardBagBarLogicallyShown(bagsBar) ~= shouldShow then
        SetBlizzardBagBarShown(bagsBar, shouldShow)
    end
end

local function RestoreBlizzardBagBar()
    local bagsBar = _G.BagsBar
    if hasBlizzardBagBarState and bagsBar
        and IsBlizzardBagBarLogicallyShown(bagsBar) ~= blizzardBagBarWasShown then
        SetBlizzardBagBarShown(bagsBar, blizzardBagBarWasShown)
    end

    blizzardBagBarWasShown = nil
    hasBlizzardBagBarState = nil
end

local function ApplyPosition()
    if not IsEnabled() or not combinedFrame or not combinedFrame:IsShown() then return end
    if combinedFrame.mover and combinedFrame.mover.isDragging then return end
    -- No frame-scale shrink-to-fit here: the baseline-height layout model
    -- keeps icons at native size instead (removed twice before: cc5b545,
    -- baa7b82). Do not reintroduce combinedFrame:SetScale().
    BFI.funcs.LoadPosition(combinedFrame, B.config.position)
end

local function GetCategory(itemID)
    local cached = categoryCache[itemID]
    if cached then
        return cached[1], cached[2], cached[3], cached[4], cached[5], cached[6], cached[7], cached[8]
    end

    local _, itemType, itemSubType, itemEquipLoc, _, classID, subclassID =
        _G.C_Item.GetItemInfoInstant(itemID)
    if classID == nil then
        classID = -1
        subclassID = -1
    end

    local parentKey
    local parentLabel
    local parentOrder
    local parentIcon
    local childKey
    local childLabel
    local childOrder
    local childIcon

    -- Retail 12.0.7 uses this non-empty sentinel for non-equippable items.
    if itemEquipLoc
        and itemEquipLoc ~= ""
        and itemEquipLoc ~= NON_EQUIPMENT_LOCATION then
        itemEquipLoc = equipmentSlotAliases[itemEquipLoc] or itemEquipLoc
        parentKey = "parent:equipment"
        parentLabel = L["Equipment"]
        parentOrder = 100
        parentIcon = {atlas = "bags-icon-equipment"}
        childKey = "equipment:" .. itemEquipLoc
        childLabel = _G[itemEquipLoc] or itemEquipLoc
        childOrder = equipmentSlotOrder[itemEquipLoc] or 99
        childIcon = equipmentSlotOrder.categoryIconByEquipLoc[itemEquipLoc]
    else
        parentKey = classID == ITEM_CLASS.Questitem
            and "parent:quest"
            or "parent:class:" .. classID
        if classID == ITEM_CLASS.Questitem then
            parentLabel = _G.BAG_FILTER_QUEST_ITEMS or itemType or L["Quest Items"]
        else
            parentLabel = itemType
            if not parentLabel or parentLabel == "" then
                parentLabel = L["Miscellaneous"]
            end
        end
        parentOrder = categoryOrderByClass[classID] or 600
        parentIcon = categoryIconByClass[classID] or "Bag_Misc"
        childKey = "class:" .. classID .. ":" .. (subclassID or -1)
        if itemSubType and itemSubType ~= "" and itemSubType ~= parentLabel then
            childLabel = itemSubType
        else
            childLabel = L["Other"]
        end
        childOrder = subclassID or 0
        local subclassIcons = categoryOrderByClass.categoryIconBySubclass
            and categoryOrderByClass.categoryIconBySubclass[classID]
        childIcon = subclassIcons and subclassIcons[subclassID] or nil
    end

    cached = {
        parentKey,
        parentLabel,
        parentOrder,
        parentIcon,
        childKey,
        childLabel,
        childOrder,
        childIcon,
    }
    categoryCache[itemID] = cached
    return parentKey, parentLabel, parentOrder, parentIcon, childKey, childLabel, childOrder, childIcon
end

local function ResetCategoryGroups()
    wipe(categoryGroupByKey)
    for index = 1, categoryGroupPoolCount do
        local group = categoryGroupPool[index]
        wipe(group.items)
        wipe(group.children)
        group.key = nil
        group.label = nil
        group.order = nil
        group.icon = nil
        group.parentKey = nil
    end
    categoryGroupPoolCount = 0
    wipe(categoryGroups)
end

local function AcquireCategoryGroup(key, label, order, icon, parent)
    local group = categoryGroupByKey[key]
    if group then return group end

    categoryGroupPoolCount = categoryGroupPoolCount + 1
    group = categoryGroupPool[categoryGroupPoolCount]
    if not group then
        group = {items = {}, children = {}}
        categoryGroupPool[categoryGroupPoolCount] = group
    end

    group.key = key
    group.label = label
    group.order = order
    group.icon = icon
    group.parentKey = parent and parent.key
    if parent then
        parent.children[#parent.children + 1] = group
    else
        categoryGroups[#categoryGroups + 1] = group
    end
    categoryGroupByKey[key] = group
    return group
end

local function AddItemToCategoryGroups(itemButton, itemID)
    local parentKey, parentLabel, parentOrder, parentIcon,
        childKey, childLabel, childOrder, childIcon = GetCategory(itemID)
    local parent = AcquireCategoryGroup(
        parentKey,
        parentLabel,
        parentOrder,
        parentIcon
    )
    parent.items[#parent.items + 1] = itemButton

    local child = AcquireCategoryGroup(
        childKey,
        childLabel,
        childOrder,
        childIcon,
        parent
    )
    child.items[#child.items + 1] = itemButton
end

local function CompareCategoryGroups(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.label < b.label
end

local function SortCategoryGroups()
    sort(categoryGroups, CompareCategoryGroups)
    for _, group in ipairs(categoryGroups) do
        sort(group.children, CompareCategoryGroups)
    end
end

local function ItemButtonOnEnter(button)
    if UpdateEmptyRepresentativeForCursor then
        UpdateEmptyRepresentativeForCursor(button)
    end
end

local function ClearItemLevelText(button)
    local text = button.BFIItemLevel
    if not text then return end
    text:SetText("")
    text:Hide()
end

local function GetItemLevelText(button)
    local text = button.BFIItemLevel
    if text then return text end

    text = AF.CreateFontString(button, nil, nil, "NumberFontNormal", "ARTWORK")
    AF.SetPoint(text, "BOTTOMLEFT", 5, 2)
    text:SetJustifyH("LEFT")

    button.BFIItemLevel = text
    itemLevelButtons[button] = true
    return text
end

local function UpdateItemLevelText(button)
    local bagID = button:GetBagID()
    local slotID = button:GetID()
    local info = _G.C_Container.GetContainerItemInfo(
        bagID,
        slotID
    )
    local itemLink = info and info.hyperlink
    if not itemLink or not IsEquippableItem(itemLink) then
        ClearItemLevelText(button)
        return
    end

    local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
    local itemLevel = GetCurrentItemLevel(itemLocation)
    if not itemLevel then
        ClearItemLevelText(button)
        return
    end

    local text = GetItemLevelText(button)
    text:SetText(itemLevel)
    text:SetTextColor(_G.HIGHLIGHT_FONT_COLOR:GetRGB())
    text:Show()
end

local function HideItemLevelTexts()
    if not itemLevelDisplayActive then return end
    itemLevelDisplayActive = nil
    for button in next, itemLevelButtons do
        ClearItemLevelText(button)
    end
end

local function RefreshItemLevelTexts()
    if not B.config.showItemLevel then
        HideItemLevelTexts()
        return
    end
    if not combinedFrame or not combinedFrame.Items then return end

    itemLevelDisplayActive = true
    for _, button in ipairs(combinedFrame.Items) do
        UpdateItemLevelText(button)
    end
end

local function StyleItemButton(button)
    styledItemButtons[button] = true
    if button._BFIBagStyled then
        if button.BFIBagHighlight then
            button.BagIndicator = button.BFIBagHighlight
            button.BagIndicator:Hide()
            button.BagIndicator:SetBackdropBorderColor(AF.GetColorRGB("BFI"))
        end
        if button._BFIBlizzardBagIndicator then
            button._BFIBlizzardBagIndicator:Hide()
        end
        return
    end
    button._BFIBagStyled = true
    button:HookScript("OnEnter", ItemButtonOnEnter)

    local icon = button.Icon or button.icon
    if icon then
        S.StyleIcon(icon)
    end

    S.CreateBackdrop(button, true, nil, 1)
    if button.IconBorder then
        S.StyleIconBorder(button.IconBorder, button.BFIBackdrop)
    end
    if button.ItemSlotBackground then
        button.ItemSlotBackground:SetAlpha(0)
    end
    local normalTexture = button:GetNormalTexture()
    if normalTexture then
        normalTexture:SetAlpha(0)
    end

    -- Retail 12.0.7 only toggles BagIndicator with SetShown. Replace its
    -- padded store artwork with a crisp exterior border without disturbing
    -- the quality-colored BFIBackdrop underneath.
    if button.BagIndicator then
        button._BFIBlizzardBagIndicator = button.BagIndicator
        button._BFIBlizzardBagIndicator:Hide()

        local bagHighlight = _G.CreateFrame("Frame", nil, button, "BackdropTemplate")
        AF.ApplyDefaultBackdrop_NoBackground(bagHighlight)
        bagHighlight:SetBackdropBorderColor(AF.GetColorRGB("BFI"))
        AF.SetOnePixelOutside(bagHighlight, button.BFIBackdrop)
        AF.SetFrameLevel(bagHighlight, 2, button)
        bagHighlight:EnableMouse(false)
        bagHighlight:Hide()
        AF.AddToPixelUpdater_CustomGroup("BFIStyled", bagHighlight)

        button.BFIBagHighlight = bagHighlight
        button.BagIndicator = bagHighlight
    end
end

local function GetSectionHeader(index)
    local header = sectionHeaders[index]
    if header then return header end

    header = AF.CreateFontString(combinedFrame, nil, "BFI")
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    sectionHeaders[index] = header
    return header
end

local function HideUnusedSectionHeaders(firstUnused)
    for index = firstUnused, #sectionHeaders do
        sectionHeaders[index]:Hide()
    end
end

local function UpdateBagButton(button)
    local bagID = button.bagID
    local inventoryID = bagID > 0 and _G.C_Container.ContainerIDToInventoryID(bagID)
    local texture = inventoryID and GetInventoryItemTexture("player", inventoryID)
    button.icon:SetTexture(texture or (bagID == 0 and BACKPACK_ICON) or EMPTY_BAG_ICON)
    button.count:SetText(_G.C_Container.GetContainerNumSlots(bagID))
end

local function ResetEmptyStates()
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        if state.representative and state.representative.BagIndicator then
            state.representative.BagIndicator:Hide()
        end
        if state.overlay then
            state.overlay:Hide()
        end
        state.representative = nil
        state.representativePriority = nil
        state.entryIndex = nil
        state.count = 0
    end
end

local function ClearItemBagHighlights()
    for itemButton in next, styledItemButtons do
        if itemButton.BFIBagHighlight then
            itemButton.BFIBagHighlight:Hide()
        end
        if itemButton._BFIBlizzardBagIndicator then
            itemButton._BFIBlizzardBagIndicator:Hide()
        end
    end
end

local function RestoreItemBagIndicators()
    for itemButton in next, styledItemButtons do
        if itemButton._BFIBlizzardBagIndicator then
            itemButton.BFIBagHighlight:Hide()
            itemButton.BagIndicator = itemButton._BFIBlizzardBagIndicator
        end
    end
end

local function UpdateAggregateEmptyState()
    local hoveredKind
    if hoveredBagID ~= nil then
        hoveredKind = hoveredBagID == REAGENT_BAG_ID and EMPTY_KIND_REAGENT or EMPTY_KIND_BAG
    end

    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        local displayedCount = state.count or 0
        if hoveredKind == kind then
            displayedCount = emptyCountsByBag[hoveredBagID] or 0
        end
        if state.text then
            state.text:SetText(displayedCount)
        end

        local representative = state.representative
        if representative and representative.BagIndicator then
            representative.BagIndicator:SetShown(
                hoveredKind == kind
                and displayedCount > 0
                and representative:IsShown()
            )
        end
    end
end

local function BagButtonOnEnter(button)
    hoveredBagID = button.bagID
    combinedFrame:SetItemsMatchingBagHighlighted(button.bagID, true)
    UpdateAggregateEmptyState()

    _G.GameTooltip:SetOwner(button, "ANCHOR_TOP")
    local inventoryID = button.bagID > 0 and _G.C_Container.ContainerIDToInventoryID(button.bagID)
    if not inventoryID or not _G.GameTooltip:SetInventoryItem("player", inventoryID) then
        local name = _G.C_Container.GetBagName(button.bagID)
        _G.GameTooltip_SetTitle(_G.GameTooltip, name or L["Bag Slots"])
    end
    _G.GameTooltip:Show()
end

local function BagButtonOnLeave(button)
    combinedFrame:SetItemsMatchingBagHighlighted(button.bagID, false)
    hoveredBagID = nil
    UpdateAggregateEmptyState()
    _G.GameTooltip_Hide()
end

local function CreateBagButtons()
    for bagID = _G.Enum.BagIndex.Backpack, REAGENT_BAG_ID do
        local button = _G.CreateFrame("Button", nil, combinedFrame)
        button.bagID = bagID
        AF.ApplyLightweightBackdropWithColors(button, "widget", "border")
        button.UpdatePixels = function(self)
            AF.DefaultUpdatePixels(self)
            AF.UpdateLightweightBackdropPixels(self)
        end
        AF.AddToPixelUpdater_CustomGroup("BFIStyled", button)

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexCoord(AF.GetDefaultTexCoord())

        button.count = AF.CreateFontString(button, nil, "white", "AF_FONT_OUTLINE")
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)

        button:SetScript("OnEnter", BagButtonOnEnter)
        button:SetScript("OnLeave", BagButtonOnLeave)
        bagButtons[#bagButtons + 1] = button
    end
end

local function LayoutBagButtons(spacing, contentInset)
    local show = B.config.showBagSlots
    local size = 34

    for index, button in ipairs(bagButtons) do
        button:SetShown(show)
        if show then
            AF.SetSize(button, size, size)
            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT",
                combinedFrame,
                "TOPLEFT",
                HORIZONTAL_PADDING + contentInset + ((index - 1) * (size + spacing)),
                -58
            )
            UpdateBagButton(button)
        end
    end
end

local function LayoutControls(contentInset)
    contentInset = contentInset or (B.Sidebar and B.Sidebar.GetContentInset()) or 0
    local searchBox = _G.BagItemSearchBox
    local sortButton = _G.BagItemAutoSortButton
    local sortIsAttached = sortButton and sortButton:GetParent() == combinedFrame
    if sortIsAttached then
        sortButton:ClearAllPoints()
        sortButton:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT", -8, -27)
    end

    bagSlotsButton:ClearAllPoints()
    if sortIsAttached then
        bagSlotsButton:SetPoint("RIGHT", sortButton, "LEFT", -3, 0)
    else
        bagSlotsButton:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT", -8, -27)
    end
    bagSlotsButton:Show()
    bagSlotsButton:SetTextureColor(HEADER_ICON_COLOR)
    if B.config.showBagSlots then
        bagSlotsButton:LockHighlight()
    else
        bagSlotsButton:UnlockHighlight()
    end

    local sidebarButton = combinedFrame.BFISidebarCollapseButton
    sidebarButton:ClearAllPoints()
    sidebarButton:SetPoint(
        "TOPLEFT",
        combinedFrame,
        "TOPLEFT",
        HORIZONTAL_PADDING + contentInset,
        -27
    )
    sidebarButton:Show()
    sidebarButton:UpdateCollapsedState()

    if searchBox and searchBox:GetParent() == combinedFrame then
        searchBox:ClearAllPoints()
        searchBox:SetPoint("TOPLEFT", sidebarButton, "TOPRIGHT", 3, 0)
        searchBox:SetPoint("TOPRIGHT", bagSlotsButton, "TOPLEFT", -3, 0)
    end

    local tokenFrame = _G.BackpackTokenFrame
    if tokenFrame and tokenFrame:GetParent() == combinedFrame and tokenFrame.Border then
        tokenFrame.Border:SetAlpha(0)
    end
end

local function SetShownIfChanged(object, shown)
    if shown then
        if not object:IsShown() then
            object:Show()
        end
    elseif object:IsShown() then
        object:Hide()
    end
end

local function ClearLayoutEntries()
    for index = 1, layoutEntryCount do
        layoutObjects[index] = nil
        layoutObjectX[index] = nil
        layoutObjectY[index] = nil
    end
    layoutEntryCount = 0
end

local function AddLayoutEntry(object, isHeader, x, y)
    layoutEntryCount = layoutEntryCount + 1
    layoutObjects[layoutEntryCount] = object
    layoutObjectX[layoutEntryCount] = x
    layoutObjectY[layoutEntryCount] = y
    if not isHeader then
        object._BFIBagLayoutEpoch = layoutEpoch
    end
    return layoutEntryCount
end

local function GetBagFamily(bagID)
    local bagFamily = bagFamilies[bagID]
    if bagFamily == nil then
        local _
        _, bagFamily = _G.C_Container.GetContainerNumFreeSlots(bagID)
        bagFamily = bagFamily or -1
        bagFamilies[bagID] = bagFamily
    end
    return bagFamily
end

local function InvalidateLayoutSnapshot()
    wipe(snapshotButtons)
    wipe(snapshotBagIDs)
    wipe(snapshotSlotIDs)
    wipe(snapshotItemIDs)
    wipe(snapshotExtended)
    snapshotCount = 0
    snapshotViewMode = nil
    snapshotCategoryKey = nil
    snapshotShowBagSlots = nil
    snapshotColumns = nil
    snapshotSpacing = nil
    snapshotSidebarCollapsed = nil
    snapshotWidth = nil
    snapshotHeight = nil
    snapshotFooterHeight = nil
end

local function ClearLayoutState()
    ClearItemBagHighlights()
    ResetEmptyStates()
    for index = 1, emptyButtonCount do
        emptyButtons[index] = nil
        emptyButtonBagIDs[index] = nil
        emptyButtonFamilies[index] = nil
        emptyButtonKinds[index] = nil
    end
    emptyButtonCount = 0
    ClearLayoutEntries()
    InvalidateLayoutSnapshot()
    wipe(emptyCountsByBag)
    wipe(bagFamilies)
    layoutAddSlotsTarget = nil
    hoveredBagID = nil
end

local function CaptureLayoutSnapshot(force)
    local footerHeight = combinedFrame:CalculateExtraHeight() + FOOTER_PADDING
    local screenWidth = floor(_G.UIParent:GetWidth())
    local screenHeight = floor(_G.UIParent:GetHeight())
    local itemCount = #combinedFrame.Items
    local changed = force
        or itemCount ~= snapshotCount
        or GetDisplayMode() ~= snapshotViewMode
        or activeCategoryKey ~= snapshotCategoryKey
        or B.config.showBagSlots ~= snapshotShowBagSlots
        or B.config.columns ~= snapshotColumns
        or B.config.spacing ~= snapshotSpacing
        or B.config.sidebarCollapsed ~= snapshotSidebarCollapsed
        or screenWidth ~= snapshotWidth
        or screenHeight ~= snapshotHeight
        or footerHeight ~= snapshotFooterHeight

    for index, itemButton in ipairs(combinedFrame.Items) do
        local bagID = itemButton:GetBagID()
        local slotID = itemButton:GetID()
        local itemID = _G.C_Container.GetContainerItemID(bagID, slotID) or false
        local isExtended = itemButton:IsExtended()

        if itemButton ~= snapshotButtons[index]
            or bagID ~= snapshotBagIDs[index]
            or slotID ~= snapshotSlotIDs[index]
            or itemID ~= snapshotItemIDs[index]
            or isExtended ~= snapshotExtended[index] then
            changed = true
        end

        snapshotButtons[index] = itemButton
        snapshotBagIDs[index] = bagID
        snapshotSlotIDs[index] = slotID
        snapshotItemIDs[index] = itemID
        snapshotExtended[index] = isExtended
    end

    for index = itemCount + 1, snapshotCount do
        snapshotButtons[index] = nil
        snapshotBagIDs[index] = nil
        snapshotSlotIDs[index] = nil
        snapshotItemIDs[index] = nil
        snapshotExtended[index] = nil
    end

    snapshotCount = itemCount
    snapshotViewMode = GetDisplayMode()
    snapshotCategoryKey = activeCategoryKey
    snapshotShowBagSlots = B.config.showBagSlots
    snapshotColumns = B.config.columns
    snapshotSpacing = B.config.spacing
    snapshotSidebarCollapsed = B.config.sidebarCollapsed
    snapshotWidth = screenWidth
    snapshotHeight = screenHeight
    snapshotFooterHeight = footerHeight
    return changed, footerHeight, screenWidth, screenHeight
end

local function RenderLayout()
    for index = 1, layoutEntryCount do
        local object = layoutObjects[index]
        object:ClearAllPoints()
        object:SetPoint("TOPLEFT", combinedFrame, "TOPLEFT", layoutObjectX[index], layoutObjectY[index])
        SetShownIfChanged(object, true)
    end

    local showAggregateEmpty = GetDisplayMode() ~= VIEW_MODE_INDIVIDUAL
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        local representative = state.representative
        if showAggregateEmpty and state.overlay and representative and representative:IsShown() then
            state.overlay:ClearAllPoints()
            state.overlay:SetAllPoints(representative)
            state.overlay:SetFrameLevel(representative:GetFrameLevel() + 3)
            state.overlay:Show()
        elseif state.overlay then
            state.overlay:Hide()
        end
    end
    UpdateAggregateEmptyState()

    local addSlotsButton = combinedFrame.AddSlotsButton
    if addSlotsButton then
        local showAddSlots = layoutAddSlotsTarget
            and layoutAddSlotsTarget:IsShown()
            and not _G.IsAccountSecured()
        if showAddSlots then
            addSlotsButton:ClearAllPoints()
            addSlotsButton:SetPoint("LEFT", layoutAddSlotsTarget, "LEFT", -14, -2)
        end
        SetShownIfChanged(addSlotsButton, showAddSlots)
    end
end

local function GetEmptyStateForButton(button)
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        if state.representative == button then
            return state, kind
        end
    end
end

-- Each aggregate tile stays backed by a real empty slot. The general tile may
-- swap between bags 0-4 for native specialty-bag validation; the reagent tile
-- always remains backed by bag 5 so normal items continue to be rejected.
UpdateEmptyRepresentativeForCursor = function(button)
    local state, kind = GetEmptyStateForButton(button)
    if not state or not state.entryIndex or not _G.CursorHasItem() then return end
    if kind == EMPTY_KIND_REAGENT then return end

    local cursorItemLocation = _G.C_Cursor.GetCursorItem()
    if not cursorItemLocation then return end

    local itemID = _G.C_Item.GetItemID(cursorItemLocation)
    if not itemID then return end

    local itemFamily = _G.C_Item.GetItemFamily(itemID) or 0
    local compatibleButton
    local compatiblePriority = math.huge

    for index = 1, emptyButtonCount do
        if emptyButtonKinds[index] == kind then
            local emptyButton = emptyButtons[index]
            local bagID = emptyButtonBagIDs[index]
            local bagFamily = emptyButtonFamilies[index]
            local isStillEmpty = not _G.C_Container.GetContainerItemID(bagID, emptyButton:GetID())
            local isCompatible
            local priority

            if bagID == _G.Enum.BagIndex.Backpack then
                isCompatible = true
                priority = 1
            elseif bagFamily == 0 then
                isCompatible = true
                priority = 2
            elseif bagFamily > 0 and itemFamily > 0 then
                isCompatible = band(bagFamily, itemFamily) ~= 0
                priority = 3
            end

            if isStillEmpty and isCompatible and priority < compatiblePriority then
                compatibleButton = emptyButton
                compatiblePriority = priority
            end
        end
    end

    if not compatibleButton or compatibleButton == state.representative then return end

    local previousRepresentative = state.representative
    previousRepresentative._BFIBagLayoutEpoch = nil
    compatibleButton._BFIBagLayoutEpoch = layoutEpoch
    layoutObjects[state.entryIndex] = compatibleButton
    state.representative = compatibleButton

    if previousRepresentative.BagIndicator then
        previousRepresentative.BagIndicator:Hide()
    end
    SetShownIfChanged(previousRepresentative, false)
    AF.SetSize(compatibleButton, ITEM_SIZE, ITEM_SIZE)

    if hoveredBagID then
        combinedFrame:SetItemsMatchingBagHighlighted(hoveredBagID, true)
    end
    RenderLayout()
end

-- WoW's Lua runtime limits each function to 60 captured upvalues, so keep the
-- layout pipeline split into focused phases instead of merging these helpers.
local function ResetIndividualGroups()
    wipe(individualGroupByBag)
    for index, group in ipairs(individualGroups) do
        wipe(group.items)
        group.bagID = nil
        group.label = nil
        group.order = nil
        group.layoutY = nil
        group.layoutColumns = nil
        group.layoutWidth = nil
        individualGroupPool[index] = group
    end
    wipe(individualGroups)
end

local function ResetLayoutModel()
    layoutEpoch = layoutEpoch + 1
    layoutAddSlotsTarget = nil
    ClearItemBagHighlights()
    ResetEmptyStates()
    ResetCategoryGroups()
    ResetIndividualGroups()
    wipe(flatGroup.items)
    ClearLayoutEntries()
    wipe(emptyCountsByBag)
    wipe(bagFamilies)
    for index = 1, emptyButtonCount do
        emptyButtons[index] = nil
        emptyButtonBagIDs[index] = nil
        emptyButtonFamilies[index] = nil
        emptyButtonKinds[index] = nil
    end
    emptyButtonCount = 0
end

local function GetBagSectionLabel(bagID)
    if bagID == _G.Enum.BagIndex.Backpack then
        return L["Backpack"]
    elseif bagID == REAGENT_BAG_ID then
        return L["Reagent Bag"]
    end
    return L["Bag %d"]:format(bagID)
end

local function AcquireIndividualGroup(bagID)
    local group = individualGroupByBag[bagID]
    if group then return group end

    local index = #individualGroups + 1
    group = individualGroupPool[index]
    if not group then
        group = {items = {}}
    end

    group.bagID = bagID
    group.label = GetBagSectionLabel(bagID)
    group.order = bagID
    individualGroups[index] = group
    individualGroupByBag[bagID] = group
    return group
end

local function RegisterEmptyButton(itemButton, bagID)
    local kind = bagID == REAGENT_BAG_ID and EMPTY_KIND_REAGENT or EMPTY_KIND_BAG
    local state = emptyStates[kind]
    state.count = state.count + 1
    emptyCountsByBag[bagID] = (emptyCountsByBag[bagID] or 0) + 1
    local bagFamily = GetBagFamily(bagID)
    emptyButtonCount = emptyButtonCount + 1
    emptyButtons[emptyButtonCount] = itemButton
    emptyButtonBagIDs[emptyButtonCount] = bagID
    emptyButtonFamilies[emptyButtonCount] = bagFamily
    emptyButtonKinds[emptyButtonCount] = kind

    local priority
    if kind == EMPTY_KIND_REAGENT or bagID == _G.Enum.BagIndex.Backpack then
        priority = 1
    else
        priority = bagFamily == 0 and 2 or 3
    end

    if priority < (state.representativePriority or math.huge) then
        state.representative = itemButton
        state.representativePriority = priority
    end
end

local function AddAggregateEmptyGroups()
    local emptyGroup
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local representative = emptyStates[kind].representative
        if representative then
            flatGroup.items[#flatGroup.items + 1] = representative
            emptyGroup = emptyGroup or AcquireCategoryGroup(
                "empty",
                _G.EMPTY or "Empty",
                1000,
                "Bag_Empty"
            )
            emptyGroup.items[#emptyGroup.items + 1] = representative
        end
    end
end

local function BuildItemGroups()
    for index, itemButton in ipairs(combinedFrame.Items) do
        StyleItemButton(itemButton)

        local bagID = snapshotBagIDs[index]
        local itemID = snapshotItemIDs[index]
        if itemID == false then
            itemID = nil
        end

        local bagGroup = AcquireIndividualGroup(bagID)
        bagGroup.items[#bagGroup.items + 1] = itemButton

        if itemID then
            AddItemToCategoryGroups(itemButton, itemID)
            flatGroup.items[#flatGroup.items + 1] = itemButton
        elseif snapshotExtended[index] then
            layoutAddSlotsTarget = layoutAddSlotsTarget or itemButton
            flatGroup.items[#flatGroup.items + 1] = itemButton
            local lockedGroup = AcquireCategoryGroup(
                "locked",
                L["Bag Slots"],
                900,
                "Bag_Empty"
            )
            lockedGroup.items[#lockedGroup.items + 1] = itemButton
        else
            RegisterEmptyButton(itemButton, bagID)
        end
    end

    AddAggregateEmptyGroups()
    SortCategoryGroups()
    sort(individualGroups, function(a, b) return a.order < b.order end)
end

local function BuildSidebarModel()
    wipe(sidebarModel)
    sidebarModel[1] = {kind = "heading", label = L["Views"]}
    sidebarModel[2] = {
        id = "view:" .. VIEW_MODE_COMBINED,
        kind = "view",
        viewMode = VIEW_MODE_COMBINED,
        label = L["Combined View"],
        icon = "Bag_All",
    }
    sidebarModel[3] = {
        id = "view:" .. VIEW_MODE_INDIVIDUAL,
        kind = "view",
        viewMode = VIEW_MODE_INDIVIDUAL,
        label = L["Individual Bags View"],
        icon = "Bag_IndividualBags",
    }
    sidebarModel[4] = {kind = "heading", label = L["Categories"]}

    for _, group in ipairs(categoryGroups) do
        local node = {
            id = "category:" .. group.key,
            kind = "category",
            categoryKey = group.key,
            label = group.label,
            icon = group.icon,
        }
        if #group.children > 0 then
            node.children = {}
            for _, child in ipairs(group.children) do
                node.children[#node.children + 1] = {
                    id = "category:" .. child.key,
                    kind = "category",
                    categoryKey = child.key,
                    label = child.label,
                    icon = child.icon or group.icon,
                }
            end
        end
        sidebarModel[#sidebarModel + 1] = node
    end

    B.Sidebar.SetModel(sidebarModel)
    if activeCategoryKey and categoryGroupByKey[activeCategoryKey] then
        B.Sidebar.SetSelection("category:" .. activeCategoryKey)
        return categoryGroupByKey[activeCategoryKey]
    end

    activeCategoryKey = nil
    B.Sidebar.SetSelection("view:" .. GetViewMode())
    return flatGroup
end

local function GetGridWidth(columnCount, spacing)
    return (columnCount * ITEM_SIZE) + ((columnCount - 1) * spacing)
end

local function GetGridHeight(itemCount, columnCount, spacing)
    local rowCount = ceil(itemCount / columnCount)
    if rowCount == 0 then return 0 end
    return (rowCount * ITEM_SIZE) + ((rowCount - 1) * spacing)
end

local function GetLayoutConstraints(spacing, screenWidth, screenHeight, contentInset)
    local minimumFrameWidth = ITEM_SIZE + (HORIZONTAL_PADDING * 2) + contentInset
    local maxFrameWidth = math.max(
        minimumFrameWidth,
        screenWidth - (SCREEN_EDGE_MARGIN * 2)
    )
    local maxColumns = math.max(
        1,
        floor(
            (maxFrameWidth - (HORIZONTAL_PADDING * 2) - contentInset + spacing)
                / (ITEM_SIZE + spacing)
        )
    )
    local maxFrameHeight = math.max(1, screenHeight - (SCREEN_EDGE_MARGIN * 2))
    local minFrameWidth = math.min(MIN_FRAME_WIDTH + contentInset, maxFrameWidth)
    return maxColumns, maxFrameHeight, minFrameWidth
end

function B.GetMinimumFrameHeight(maxFrameHeight, footerHeight)
    return math.min(maxFrameHeight, SIDEBAR_TOP + SIDEBAR_MIN_HEIGHT + footerHeight)
end

local function CalculateFlatLayoutMetrics(
    itemCount,
    requestedColumns,
    spacing,
    top,
    footerHeight,
    screenWidth,
    screenHeight,
    contentInset
)
    local maxColumns, maxFrameHeight, minFrameWidth = GetLayoutConstraints(
        spacing,
        screenWidth,
        screenHeight,
        contentInset
    )
    local columns = math.min(requestedColumns, maxColumns)
    local height = top + GetGridHeight(itemCount, columns, spacing) + footerHeight

    while height > maxFrameHeight and columns < maxColumns do
        columns = columns + 1
        height = top + GetGridHeight(itemCount, columns, spacing) + footerHeight
    end

    height = math.max(height, B.GetMinimumFrameHeight(maxFrameHeight, footerHeight))

    local width = math.max(
        minFrameWidth,
        (HORIZONTAL_PADDING * 2) + contentInset + GetGridWidth(columns, spacing)
    )
    return columns, width, height
end

local function MeasureIndividualGroups(columnCount, spacing)
    local contentHeight = 0
    local contentWidth = ITEM_SIZE

    for index, group in ipairs(individualGroups) do
        local itemCount = #group.items
        local groupColumns = math.min(columnCount, math.max(1, itemCount))
        local groupWidth = GetGridWidth(groupColumns, spacing)
        local groupHeight = SECTION_HEADER_HEIGHT
            + SECTION_HEADER_GAP
            + GetGridHeight(itemCount, groupColumns, spacing)

        group.layoutY = contentHeight
        group.layoutColumns = groupColumns
        group.layoutWidth = groupWidth
        contentWidth = math.max(contentWidth, groupWidth)
        contentHeight = contentHeight + groupHeight
        if index < #individualGroups then
            contentHeight = contentHeight + SECTION_SPACING
        end
    end

    return contentWidth, contentHeight
end

local function CalculateIndividualLayoutMetrics(
    requestedColumns,
    spacing,
    top,
    footerHeight,
    screenWidth,
    screenHeight,
    contentInset
)
    local maxColumns, maxFrameHeight, minFrameWidth = GetLayoutConstraints(
        spacing,
        screenWidth,
        screenHeight,
        contentInset
    )
    local columns = math.min(requestedColumns, maxColumns)
    local contentWidth, contentHeight = MeasureIndividualGroups(columns, spacing)
    local height = top + contentHeight + footerHeight

    while height > maxFrameHeight and columns < maxColumns do
        columns = columns + 1
        contentWidth, contentHeight = MeasureIndividualGroups(columns, spacing)
        height = top + contentHeight + footerHeight
    end

    height = math.max(
        height,
        B.GetMinimumFrameHeight(maxFrameHeight, footerHeight)
    )
    local width = math.max(
        minFrameWidth,
        (HORIZONTAL_PADDING * 2) + contentInset + contentWidth
    )
    return width, height
end

local function PrepareLayoutFrame(width, height)
    if hoveredBagID then
        combinedFrame:SetItemsMatchingBagHighlighted(hoveredBagID, true)
    end

    combinedFrame:SetSize(width, height)
end

local function RecordEmptyEntryIndex(itemButton, entryIndex)
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        if itemButton == state.representative then
            state.entryIndex = entryIndex
            return
        end
    end
end

local function BuildFlatLayoutEntries(columns, spacing, top, contentInset, group)
    if not group then return end

    local cursorY = -top
    for itemIndex, itemButton in ipairs(group.items) do
        local row = floor((itemIndex - 1) / columns)
        local column = (itemIndex - 1) % columns
        AF.SetSize(itemButton, ITEM_SIZE, ITEM_SIZE)
        local entryIndex = AddLayoutEntry(
            itemButton,
            false,
            HORIZONTAL_PADDING + contentInset + (column * (ITEM_SIZE + spacing)),
            cursorY - (row * (ITEM_SIZE + spacing))
        )
        RecordEmptyEntryIndex(itemButton, entryIndex)
    end
end

local function BuildIndividualLayoutEntries(spacing, top, contentInset)
    for groupIndex, group in ipairs(individualGroups) do
        local groupX = HORIZONTAL_PADDING + contentInset
        local headerY = -top - group.layoutY
        local header = GetSectionHeader(groupIndex)
        header:SetText(group.label)
        header:SetSize(group.layoutWidth, SECTION_HEADER_HEIGHT)
        AddLayoutEntry(header, true, groupX, headerY)

        local itemTop = headerY - SECTION_HEADER_HEIGHT - SECTION_HEADER_GAP
        for itemIndex, itemButton in ipairs(group.items) do
            local row = floor((itemIndex - 1) / group.layoutColumns)
            local column = (itemIndex - 1) % group.layoutColumns
            AF.SetSize(itemButton, ITEM_SIZE, ITEM_SIZE)
            AddLayoutEntry(
                itemButton,
                false,
                groupX + (column * (ITEM_SIZE + spacing)),
                itemTop - (row * (ITEM_SIZE + spacing))
            )
        end
    end
end

local function FinalizeLayoutEntries(spacing, contentInset, sectionCount)
    for _, itemButton in ipairs(combinedFrame.Items) do
        if itemButton._BFIBagLayoutEpoch ~= layoutEpoch then
            SetShownIfChanged(itemButton, false)
        end
    end

    HideUnusedSectionHeaders((sectionCount or 0) + 1)
    LayoutBagButtons(spacing, contentInset)
end

local function LayoutItemsInternal(force)
    B.Sidebar.SetCollapsed(B.config.sidebarCollapsed, true)
    local changed, footerHeight, screenWidth, screenHeight = CaptureLayoutSnapshot(force)
    if not changed then return end

    local requestedColumns = B.config.columns
    local spacing = B.config.spacing
    local top = B.config.showBagSlots and BAG_TOP_WITH_SLOTS or BAG_TOP_WITHOUT_SLOTS

    B.Sidebar.SetShown(true)
    local contentInset = B.Sidebar.GetContentInset()
    if bagSidebar then
        local sidebarRight = HORIZONTAL_PADDING + B.Sidebar.GetDesiredWidth()
        bagSidebar:ClearAllPoints()
        bagSidebar:SetPoint("TOPRIGHT", combinedFrame, "TOPLEFT", sidebarRight, -SIDEBAR_TOP)
        bagSidebar:SetPoint("BOTTOMRIGHT", combinedFrame, "BOTTOMLEFT", sidebarRight, footerHeight)
    end

    ResetLayoutModel()
    BuildItemGroups()
    local group = BuildSidebarModel()
    local viewMode = GetDisplayMode()

    -- Baseline-height layout model: Combined's natural size is recomputed
    -- from scratch on every pass (never cached) and used as the reference
    -- for every other mode. BuildItemGroups always fills flatGroup
    -- regardless of the active view, so this is safe to compute
    -- unconditionally.
    local baselineColumns, baselineWidth, baselineHeight = CalculateFlatLayoutMetrics(
        #flatGroup.items,
        requestedColumns,
        spacing,
        top,
        footerHeight,
        screenWidth,
        screenHeight,
        contentInset
    )

    local width
    local height
    if viewMode == VIEW_MODE_INDIVIDUAL then
        width, height = CalculateIndividualLayoutMetrics(
            requestedColumns,
            spacing,
            top,
            footerHeight,
            screenWidth,
            screenHeight,
            contentInset
        )
        -- Individual grows from the Combined baseline and shrinks back to
        -- it automatically on the next pass (nothing here is cached). Icons
        -- always stay at native ITEM_SIZE: do not reintroduce frame-scale
        -- shrink-to-fit (removed twice before: cc5b545, baa7b82).
        height = math.max(height, baselineHeight)
        width = math.max(width, baselineWidth)
        PrepareLayoutFrame(width, height)
        BuildIndividualLayoutEntries(spacing, top, contentInset)
        FinalizeLayoutEntries(spacing, contentInset, #individualGroups)
    else
        -- Combined and category-filtered views both render at the baseline
        -- column count and frame size. A category is always a subset of
        -- Combined's items, so it never needs more rows at baselineColumns
        -- than Combined does: the window stays pixel-identical across every
        -- category selection, with no shrink and no grow.
        width, height = baselineWidth, baselineHeight
        PrepareLayoutFrame(width, height)
        BuildFlatLayoutEntries(baselineColumns, spacing, top, contentInset, group)
        FinalizeLayoutEntries(spacing, contentInset, 0)
    end

    -- Individual Bags keeps every physical slot in its own labeled section;
    -- Combined and category selections retain the compact aggregate-empty model.
    LayoutControls(contentInset)
    RenderLayout()
    ApplyPosition()
end

local function LayoutItems(force)
    if layoutInProgress or not IsEnabled() or not combinedFrame or not combinedFrame.Items then return end
    layoutInProgress = true
    local success = xpcall(function()
        LayoutItemsInternal(force)
    end, _G.geterrorhandler())
    layoutInProgress = nil
    if not success then
        InvalidateLayoutSnapshot()
    end
end

local function AppendReagentBagSlots(frame)
    if not IsEnabled() then return end

    wipe(reagentItemButtons)
    local size = _G.C_Container.GetContainerNumSlots(REAGENT_BAG_ID)
    for index = 1, size do
        local itemButton = frame:AcquireNewItemButton()
        local slotID = size - index + 1
        itemButton:Initialize(REAGENT_BAG_ID, slotID)
        reagentItemButtons[slotID] = itemButton
    end
    -- ContainerFrameCombinedBagsMixin:SetBagSize intentionally ignores its
    -- argument, so extend the BaseContainerFrameMixin iterator count directly.
    frame.size = #frame.Items
end

local function DisableMouseRecursively(frame)
    suppressedMouseStates[frame] = frame:IsMouseEnabled()
    frame:EnableMouse(false)
    for _, child in ipairs({frame:GetChildren()}) do
        DisableMouseRecursively(child)
    end
end

local function SuppressReagentFrame()
    if not IsEnabled() then return end

    local frame = _G.ContainerFrameUtil_GetShownFrameForID(REAGENT_BAG_ID)
    if not frame or frame == combinedFrame then return end

    if suppressedReagentFrame ~= frame then
        suppressedReagentFrame = frame
        suppressedReagentAlpha = frame:GetAlpha()
        wipe(suppressedMouseStates)
        DisableMouseRecursively(frame)
    end
    frame:SetAlpha(0)
end

local function RestoreReagentFrame()
    if not suppressedReagentFrame then return end
    suppressedReagentFrame:SetAlpha(suppressedReagentAlpha or 1)
    for frame, mouseEnabled in next, suppressedMouseStates do
        frame:EnableMouse(mouseEnabled)
    end
    wipe(suppressedMouseStates)
    suppressedReagentFrame = nil
    suppressedReagentAlpha = nil
    _G.UpdateContainerFrameAnchors()
end

local function RefreshContents(rebuildSlots)
    if not IsEnabled() or not combinedFrame or not combinedFrame:IsShown() then return end

    if rebuildSlots then
        combinedFrame:UpdateItemSlots()
        combinedFrame:UpdateFrameSize()
        combinedFrame:UpdateItemLayout()
    end
    combinedFrame:Update()
end

local function QueueRefresh(rebuildSlots)
    if refreshPending == "rebuild" or (refreshPending and not rebuildSlots) then return end
    refreshPending = rebuildSlots and "rebuild" or "update"

    _G.C_Timer.After(0, function()
        local pending = refreshPending
        refreshPending = nil
        RefreshContents(pending == "rebuild")
    end)
end

local function OnCombinedFrameShow()
    if not IsEnabled() then return end
    B.Sidebar.SetShown(true)
    B:RegisterEvent("BAG_UPDATE", B.BAG_UPDATE)
    B:RegisterEvent("ITEM_LOCK_CHANGED", B.ITEM_LOCK_CHANGED)
    B:RegisterEvent("DISPLAY_SIZE_CHANGED", B.DISPLAY_SIZE_CHANGED)

    -- Keep the suppressed reagent container logically open alongside the
    -- combined container so Blizzard's unmodified ToggleAllBags accounting
    -- continues to close both on the next hotkey press.
    _G.C_Timer.After(0, function()
        if IsEnabled()
            and combinedFrame:IsShown()
            and _G.C_Container.GetContainerNumSlots(REAGENT_BAG_ID) > 0
            and not _G.IsBagOpen(REAGENT_BAG_ID) then
            _G.OpenBag(REAGENT_BAG_ID)
        end
    end)
end

local function OnCombinedFrameHide()
    B.Sidebar.SetShown(false)
    B.Cleanup:Cancel(false)
    HideItemLevelTexts()
    B:UnregisterEvent("BAG_UPDATE")
    B:UnregisterEvent("ITEM_LOCK_CHANGED")
    B:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    wipe(categoryCache)
    ResetCategoryGroups()
    ResetIndividualGroups()
    HideUnusedSectionHeaders(1)
    ClearLayoutState()
    _G.C_Timer.After(0, function()
        if IsEnabled() and not combinedFrame:IsShown() then
            if _G.IsBagOpen(REAGENT_BAG_ID) then
                _G.CloseBag(REAGENT_BAG_ID)
            end
            RestoreReagentFrame()
        end
    end)
end

local function SetCombinedBags()
    if not GetCVarBool("combinedBags") then
        SetCVar("combinedBags", 1)
    end
end

local function SuppressCombinedMenu()
    local portraitButton = combinedFrame.PortraitButton
    if portraitButton then
        if portraitWasShown == nil then
            portraitWasShown = portraitButton:IsShown()
            portraitMouseEnabled = portraitButton:IsMouseEnabled()
            portraitAlpha = portraitButton:GetAlpha()
        end
        portraitButton:Hide()
        portraitButton:EnableMouse(false)
        portraitButton:SetAlpha(0)
    end

    for _, child in ipairs({combinedFrame:GetChildren()}) do
        if child.routeToSibling == "PortraitButton" then
            if portraitProxyMouseStates[child] == nil then
                portraitProxyMouseStates[child] = child:IsMouseEnabled()
            end
            child:EnableMouse(false)
        end
    end
end

local function RestoreCombinedMenu()
    local portraitButton = combinedFrame.PortraitButton
    if portraitButton and portraitWasShown ~= nil then
        portraitButton:SetAlpha(portraitAlpha or 1)
        portraitButton:EnableMouse(portraitMouseEnabled)
        portraitButton:SetShown(portraitWasShown)
    end
    for child, mouseEnabled in next, portraitProxyMouseStates do
        child:EnableMouse(mouseEnabled)
    end

    wipe(portraitProxyMouseStates)
    portraitWasShown = nil
    portraitMouseEnabled = nil
    portraitAlpha = nil
end

local function CreateEmptyStateOverlays()
    for kind = EMPTY_KIND_BAG, EMPTY_KIND_REAGENT do
        local state = emptyStates[kind]
        local overlay = _G.CreateFrame("Frame", nil, combinedFrame)
        overlay:EnableMouse(false)
        AF.SetSize(overlay, ITEM_SIZE, ITEM_SIZE)

        local icon = overlay:CreateTexture(nil, "ARTWORK")
        AF.SetSize(icon, 15, 15)
        icon:SetPoint("TOPLEFT", 3, -3)
        if kind == EMPTY_KIND_REAGENT then
            icon:SetAtlas(REAGENT_SPACE_ICON)
        else
            icon:SetTexture(SHOW_BAGS_ICON)
        end
        icon:SetVertexColor(AF.GetColorRGB(HEADER_ICON_COLOR))

        local text = AF.CreateFontString(overlay, nil, "white", "AF_FONT_OUTLINE")
        text:SetPoint("BOTTOMRIGHT", -3, 3)

        state.overlay = overlay
        state.icon = icon
        state.text = text
        overlay:Hide()
    end
end

local function UpdateCombinedFrameTitle(frame)
    if IsEnabled() then
        frame:SetTitle(L["Bags"])
    end
end

local function StyleBagSearchBox()
    local searchBox = _G.BagItemSearchBox
    S.StyleEditBox(searchBox)
    AF.SetHeight(searchBox, 22)
    searchBox:SetTextInsets(20, 22, 0, 0)

    searchBox.searchIcon:ClearAllPoints()
    searchBox.searchIcon:SetPoint("LEFT", 5, 0)

    searchBox.Instructions:ClearAllPoints()
    searchBox.Instructions:SetPoint("TOPLEFT", 20, 0)
    searchBox.Instructions:SetPoint("BOTTOMRIGHT", -22, 0)
end

local function CleanupButtonOnEnter(button)
    if not IsEnabled() then return end
    _G.GameTooltip:Hide()
    AF.ShowTooltip(button, "TOPLEFT", 0, 2, cleanupTooltipState.lines)
end

local function CleanupButtonOnLeave()
    AF.HideTooltip()
end

local function SetupCleanupTooltip()
    local button = _G.BagItemAutoSortButton
    if not button then return end

    cleanupTooltipState.lines = cleanupTooltipState.lines or {}
    cleanupTooltipState.lines[1] = _G.BAG_CLEANUP_BAGS
    cleanupTooltipState.lines[2] = _G.BAG_CLEANUP_BAGS_DESCRIPTION
    button.accentColor = "BFI"

    if not cleanupTooltipState.hooked then
        -- Preserve Blizzard and BFI scripts; our post-hook swaps the visible tooltip.
        cleanupTooltipState.hooked = true
        button:HookScript("OnEnter", CleanupButtonOnEnter)
        button:HookScript("OnLeave", CleanupButtonOnLeave)
    end
end

local function StyleCleanupButton()
    local button = _G.BagItemAutoSortButton
    S.StyleIconButton(button, AF.GetIcon("Refresh"), 16, HEADER_ICON_COLOR, "gray")
    AF.SetSize(button, 24, 22)
    SetupCleanupTooltip()
    B.Cleanup:Install(button)
end

local function StyleCombinedFrame()
    -- AF r30's lightweight panel primitive follows Retail 12.1.0.68914
    -- (wow-ui-source d3915c78aba7) without BackdropTemplate's nine regions
    -- and OnSizeChanged texture-coordinate work.
    S.StyleTitledFrame(combinedFrame, nil, true)

    -- Auto-hide reserves only the compact icon rail in the item layout. While
    -- hovered, expand the styled shell left with the rail without resizing the
    -- Blizzard container or moving its items, controls, or saved anchor.
    local visualShell = _G.CreateFrame("Frame", nil, combinedFrame)
    combinedFrame.BFIVisualShell = visualShell
    visualShell:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT")
    visualShell:SetPoint("BOTTOMRIGHT", combinedFrame, "BOTTOMRIGHT")
    visualShell.sidebarExtension = 0
    function visualShell:SyncWidth()
        AF.SetWidth(
            self,
            combinedFrame:GetWidth() + (self.sidebarExtension or 0)
        )
    end
    function visualShell:SetSidebarPresentationWidth(width, reservedWidth)
        self.sidebarExtension = math.max(0, width - reservedWidth)
        self:SyncWidth()
    end
    visualShell:SyncWidth()

    combinedFrame.BFIBg:ClearAllPoints()
    combinedFrame.BFIBg:SetAllPoints(visualShell)
    combinedFrame.BFIHeader:ClearAllPoints()
    combinedFrame.BFIHeader:SetPoint("TOPLEFT", visualShell, "TOPLEFT")
    combinedFrame.BFIHeader:SetPoint("TOPRIGHT", visualShell, "TOPRIGHT")
    combinedFrame:HookScript("OnSizeChanged", function()
        visualShell:SyncWidth()
    end)

    combinedFrame:SetClampedToScreen(true)
    SuppressCombinedMenu()
    UpdateCombinedFrameTitle(combinedFrame)

    -- Retail 12.0.7 UpdateName restores COMBINED_BAG_TITLE during updates.
    hooksecurefunc(combinedFrame, "UpdateName", UpdateCombinedFrameTitle)

    if combinedFrame.MoneyFrame and combinedFrame.MoneyFrame.Border then
        combinedFrame.MoneyFrame.Border:SetAlpha(0)
    end

    StyleBagSearchBox()
    StyleCleanupButton()

    bagSlotsButton = AF.CreateButton(combinedFrame, nil, "gray", 24, 22)
    bagSlotsButton:SetTexture(SHOW_BAGS_ICON, {16, 16}, {"CENTER", 0, 0})
    bagSlotsButton:SetTextureColor(HEADER_ICON_COLOR)
    bagSlotsButton:SetTooltip(L["Show Bags"])
    bagSlotsButton:SetOnClick(function()
        B.config.showBagSlots = not B.config.showBagSlots
        LayoutItems(true)
        AF.Fire("BFI_RefreshOptions", "bags")
    end)

    local sidebarButton = AF.CreateButton(combinedFrame, nil, "gray", 24, 22)
    combinedFrame.BFISidebarCollapseButton = sidebarButton
    sidebarButton:SetTexture(AF.GetIcon("ArrowRight1"), {16, 16}, {"CENTER", 0, 0})
    sidebarButton:SetTextureColor(HEADER_ICON_COLOR)
    function sidebarButton:UpdateCollapsedState()
        local collapsed = B.Sidebar.GetCollapsed()
        self:SetTexture(AF.GetIcon(collapsed and "ArrowLeft1" or "ArrowRight1"))
        self:SetTextureColor(HEADER_ICON_COLOR)
        self:SetTooltip(collapsed and L["Expand Sidebar"] or L["Collapse Sidebar"])
        if collapsed then
            self:LockHighlight()
        else
            self:UnlockHighlight()
        end
    end
    sidebarButton:SetOnClick(function()
        B.Sidebar.ToggleCollapsed()
    end)
    sidebarButton:UpdateCollapsedState()

    CreateEmptyStateOverlays()

    CreateBagButtons()

    B.Sidebar.SetCollapsed(B.config.sidebarCollapsed, true)
    bagSidebar = B.Sidebar.Initialize(combinedFrame, function(_, entry)
        if entry.kind == "view" then
            activeCategoryKey = nil
            B.config.viewMode = entry.viewMode
            AF.Fire("BFI_RefreshOptions", "bags")
        elseif entry.kind == "category" then
            activeCategoryKey = entry.categoryKey
        end
        LayoutItems(true)
    end)
    B.Sidebar.SetOnPresentationWidthChanged(function(width, reservedWidth)
        visualShell:SetSidebarPresentationWidth(width, reservedWidth)
    end)
    B.Sidebar.SetOnCollapsedChanged(function(collapsed)
        B.config.sidebarCollapsed = collapsed
        LayoutItems(true)
        AF.Fire("BFI_RefreshOptions", "bags")
    end)

    AF.SetDraggable(combinedFrame.BFIHeader, combinedFrame, true, nil, function(frame)
        AF.SavePositionAsTable(frame, B.config.position)
    end)
    AF.CreateMover(combinedFrame, "BFI: " .. L["Bags"], L["Bags"], B.config.position)
end

local function Initialize()
    if initialized then return true end

    combinedFrame = _G.ContainerFrameCombinedBags
    if not combinedFrame then
        B:RegisterEvent("ADDON_LOADED", B.ADDON_LOADED)
        return false
    end

    initialized = true
    StyleCombinedFrame()

    hooksecurefunc(combinedFrame, "UpdateItemSlots", AppendReagentBagSlots)
    hooksecurefunc(combinedFrame, "UpdateItemLayout", function()
        LayoutItems(true)
    end)
    hooksecurefunc(combinedFrame, "UpdateItems", function()
        if IsEnabled() then
            RefreshItemLevelTexts()
            LayoutItems(false)
        end
    end)
    hooksecurefunc(combinedFrame, "UpdateSearchBox", function()
        if IsEnabled() then
            LayoutControls()
        end
    end)
    hooksecurefunc("OpenBag", function(bagID)
        if bagID == REAGENT_BAG_ID then
            SuppressReagentFrame()
            if IsEnabled() and not combinedFrame:IsShown() then
                _G.OpenBag(_G.Enum.BagIndex.Backpack)
            end
        end
    end)
    hooksecurefunc("ToggleBag", function(bagID)
        if not IsEnabled() or bagID ~= REAGENT_BAG_ID then return end
        if _G.C_Container.GetContainerNumSlots(REAGENT_BAG_ID) == 0 then return end

        if _G.IsBagOpen(REAGENT_BAG_ID) then
            SuppressReagentFrame()
            if not combinedFrame:IsShown() then
                _G.OpenBag(_G.Enum.BagIndex.Backpack)
            end
        elseif combinedFrame:IsShown() then
            _G.CloseBackpack()
        end
    end)
    hooksecurefunc("UpdateContainerFrameAnchors", ApplyPosition)

    combinedFrame:HookScript("OnShow", OnCombinedFrameShow)
    combinedFrame:HookScript("OnHide", OnCombinedFrameHide)
    return true
end

local function EnableModule()
    moduleEnabled = true
    UpdateBlizzardBagBarVisibility()

    if not Initialize() then return end
    B.Sidebar.SetShown(true)
    SetupCleanupTooltip()
    B.Cleanup:Install(_G.BagItemAutoSortButton)

    if not hasPreviousCombinedBags then
        previousCombinedBags = GetCVarBool("combinedBags")
        hasPreviousCombinedBags = true
    end

    if _G.BagsBar then
        B:UnregisterEvent("ADDON_LOADED")
    end

    SuppressCombinedMenu()
    AF.UpdateMoverSave(combinedFrame, B.config.position)
    B:RegisterEvent("USE_COMBINED_BAGS_CHANGED", B.USE_COMBINED_BAGS_CHANGED)
    SetCombinedBags()

    local combinedWasShown = combinedFrame:IsShown()
    if _G.IsBagOpen(REAGENT_BAG_ID) then
        SuppressReagentFrame()
        if not combinedWasShown then
            _G.OpenBag(_G.Enum.BagIndex.Backpack)
        end
    end

    if combinedWasShown then
        OnCombinedFrameShow()
        SuppressReagentFrame()
        RefreshContents(true)
    end
end

local function DisableModule()
    moduleEnabled = nil
    HideItemLevelTexts()
    RestoreBlizzardBagBar()
    B.Cleanup:Restore()
    B:UnregisterAllEvents()
    if not initialized then return end
    AF.HideTooltip()

    RestoreReagentFrame()
    wipe(reagentItemButtons)
    wipe(categoryCache)
    ResetCategoryGroups()
    ResetIndividualGroups()
    HideUnusedSectionHeaders(1)
    ClearLayoutState()
    RestoreItemBagIndicators()
    -- No frame-scale reset here: layout no longer scales the frame (removed
    -- twice before: cc5b545, baa7b82). Do not reintroduce SetScale().

    bagSlotsButton:Hide()
    combinedFrame.BFISidebarCollapseButton:Hide()
    B.Sidebar.SetShown(false)
    for _, button in ipairs(bagButtons) do
        button:Hide()
    end
    if combinedFrame:IsShown() then
        combinedFrame:SetBagSize()
        combinedFrame:UpdateItemSlots()
        combinedFrame:UpdateFrameSize()
        combinedFrame:UpdateItemLayout()
        combinedFrame:Update()
    end

    RestoreCombinedMenu()

    if hasPreviousCombinedBags then
        SetCVar("combinedBags", previousCombinedBags and 1 or 0)
        hasPreviousCombinedBags = nil
    end
end

function B:ADDON_LOADED(_, addonName)
    if addonName ~= "Blizzard_UIPanels_Game"
        and addonName ~= "Blizzard_MainMenuBarBagButtons" then
        return
    end

    if B.config and B.config.enabled then
        EnableModule()
    end
end

function B:USE_COMBINED_BAGS_CHANGED(_, useCombinedBags)
    if IsEnabled() and not useCombinedBags then
        SetCombinedBags()
    end
end

function B:BAG_UPDATE(_, bagID)
    if bagID == REAGENT_BAG_ID then
        if B.Cleanup:IsActive() then return end
        QueueRefresh(false)
    end
end

function B:ITEM_LOCK_CHANGED(_, bagID, slotID)
    if bagID ~= REAGENT_BAG_ID or not slotID then return end
    local itemButton = reagentItemButtons[slotID]
    if not itemButton then return end

    local info = _G.C_Container.GetContainerItemInfo(bagID, slotID)
    _G.SetItemButtonDesaturated(itemButton, info and info.isLocked)
end

function B:DISPLAY_SIZE_CHANGED()
    LayoutItems(true)
end

function B.SetViewMode(mode)
    if mode ~= VIEW_MODE_COMBINED and mode ~= VIEW_MODE_INDIVIDUAL then return false end
    B.config.viewMode = mode
    activeCategoryKey = nil
    B.Refresh()
    return true
end

function B.Refresh()
    UpdateBlizzardBagBarVisibility()
    if IsEnabled() and not B.config.showItemLevel then
        HideItemLevelTexts()
    end
    if IsEnabled() and combinedFrame and combinedFrame:IsShown() then
        RefreshItemLevelTexts()
        LayoutItems(true)
    end
end

local function UpdateBags(_, module)
    if module and module ~= "bags" then return end
    if not B.config then return end

    if B.config.enabled then
        EnableModule()
    else
        DisableModule()
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateBags)

AF.RegisterCallback("BFI_UpdateProfile", function()
    -- Sidebar selection is transient navigation state. A newly selected
    -- profile must open its own persisted Combined/Individual default.
    activeCategoryKey = nil
    if B.config then
        B.Sidebar.SetCollapsed(B.config.sidebarCollapsed, true)
    end
end)
