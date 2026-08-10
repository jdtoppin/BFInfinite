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
}
-- categoryIconByEquipLoc: childIcon lookups for ordinary equipment slots,
-- keyed by the post-alias INVTYPE (see equipmentSlotAliases above). These
-- are full-color representative item icons rather than the monochrome
-- paper-doll empty-slot art: the latter reads poorly in a collapsed rail.
-- The texture selections are presentation choices, subject to in-game QA,
-- not API claims. The nested tables avoid a new top-level local because this
-- chunk remains at Lua 5.1's 200-local limit.
equipmentSlotOrder.categoryIconByEquipLoc = {
    INVTYPE_HEAD = {texture = "Interface\\Icons\\INV_Helmet_03"},
    INVTYPE_NECK = {texture = "Interface\\Icons\\INV_Jewelry_Necklace_03"},
    INVTYPE_SHOULDER = {texture = "Interface\\Icons\\INV_Shoulder_25"},
    INVTYPE_CLOAK = {texture = "Interface\\Icons\\INV_Misc_Cape_11"},
    INVTYPE_CHEST = {texture = "Interface\\Icons\\INV_Chest_Chain"},
    INVTYPE_WRIST = {texture = "Interface\\Icons\\INV_Bracer_07"},
    INVTYPE_HAND = {texture = "Interface\\Icons\\INV_Gauntlets_05"},
    INVTYPE_WAIST = {texture = "Interface\\Icons\\INV_Belt_03"},
    INVTYPE_LEGS = {texture = "Interface\\Icons\\INV_Pants_06"},
    INVTYPE_FEET = {texture = "Interface\\Icons\\INV_Boots_05"},
    INVTYPE_FINGER = {texture = "Interface\\Icons\\INV_Jewelry_Ring_04"},
    INVTYPE_TRINKET = {texture = "Interface\\Icons\\INV_Misc_Orb_05"},
    INVTYPE_WEAPONMAINHAND = {texture = "Interface\\Icons\\INV_Sword_04"},
    INVTYPE_WEAPONOFFHAND = {texture = "Interface\\Icons\\INV_Shield_06"},
    INVTYPE_WEAPON = {texture = "Interface\\Icons\\INV_Mace_01"},
    INVTYPE_2HWEAPON = {texture = "Interface\\Icons\\INV_Axe_09"},
    INVTYPE_RANGED = {texture = "Interface\\Icons\\INV_Weapon_Rifle_01"},
    INVTYPE_BODY = {texture = "Interface\\Icons\\INV_Shirt_02"},
    INVTYPE_TABARD = {texture = "Interface\\Icons\\INV_Shirt_GuildTabard_01"},
}
-- Profession tools, profession equipment, and equippable bags are not
-- conventional paper-doll equipment. Keep them together under the one
-- Miscellaneous parent and give each compact row a purpose-built AF icon.
-- childKey is separately namespaced in GetCategory, so it cannot collide
-- with a real item-class fallback that shares this parent.
equipmentSlotOrder.miscellaneous = {
    icon = "Bag_Miscellaneous",
    order = 700,
    byEquipLoc = {
        INVTYPE_PROFESSION_TOOL = {
            label = "Profession Tool",
            order = 1,
            icon = "Bag_ProfessionTool",
        },
        INVTYPE_PROFESSION_GEAR = {
            label = "Profession Equipment",
            order = 2,
            icon = "Bag_ProfessionEquipment",
        },
        INVTYPE_BAG = {
            label = "Bag",
            order = 3,
            icon = "Bag_Bag",
        },
    },
}
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
-- categoryIconBySubclass: childIcon lookups for consumable, recipe, trade
-- goods, and housing subclasses. Nested as a nonnumeric field on this
-- existing categoryOrderByClass local (same 200-local-ceiling reason as
-- equipmentSlotOrder.categoryIconByEquipLoc further up); categoryOrderByClass's
-- own classID keys never collide with this "categoryIconBySubclass" string
-- key. Created here, unconditionally (never nil) and before the
-- ITEM_CLASS.Housing block below, because that block populates this table's
-- Housing entry directly; every other populated entry further down follows
-- the same unconditional-host, guarded-entry pattern. GetCategory's
-- "categoryOrderByClass.categoryIconBySubclass and
-- categoryOrderByClass.categoryIconBySubclass[classID]" guard always finds
-- a table to index (possibly with no entry for a given classID); each
-- classID's own entry is populated only behind its own enum-presence guard,
-- independently.
categoryOrderByClass.categoryIconBySubclass = {}

-- Parent-category icons (Task 3, sidebar v3): AbstractFramework's TreeList.lua
-- now renders every row's icon at full native color on a squared plate
-- (crop-on-texture; no more textureTint desaturation, see Sidebar.lua's
-- OPTIONS comment), so every "bags-icon-*" BAG_FILTER_ICONS atlas reference
-- is retired from this table per the owner's ruling -- all parent-category
-- icons are now hand-picked Interface\Icons textures, the same art-choice
-- treatment Recipe and Housing already used before this task. None of the
-- paths below are an API claim; see the evidence comment further down for
-- every chosen path and the in-game QA note. Gem, Tradegoods,
-- ItemEnhancement, and Profession keep BFI's pre-existing design choice of
-- sharing one icon (order 300/400 above); that grouping predates this task
-- and is unchanged by the atlas-to-texture swap.
local categoryIconByClass = {
    [ITEM_CLASS.Consumable] = {texture = "Interface\\Icons\\INV_Potion_51"},
    [ITEM_CLASS.Gem] = {texture = "Interface\\Icons\\INV_Crate_01"},
    [ITEM_CLASS.Tradegoods] = {texture = "Interface\\Icons\\INV_Crate_01"},
    [ITEM_CLASS.Reagent] = {texture = "Interface\\Icons\\INV_Misc_Bag_11"},
    [ITEM_CLASS.ItemEnhancement] = {texture = "Interface\\Icons\\INV_Crate_01"},
    [ITEM_CLASS.Profession] = {texture = "Interface\\Icons\\INV_Crate_01"},
    [ITEM_CLASS.Recipe] = {texture = "Interface\\Icons\\INV_Misc_Book_09"},
    [ITEM_CLASS.Questitem] = {texture = "Interface\\Icons\\INV_Misc_Note_01"},
}
-- ItemConstantsDocumentation.lua lists ItemClass.Housing (EnumValue = 20)
-- identically at both pinned commits (Retail 12.0.7.68887
-- 4383ced30106d51b27e3e86d1987f1552f0d259d and Retail 12.1.0.68914
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9) -- it is not a 12.1.0-only
-- addition. Keep the nil guard anyway for clients/environments older or
-- more minimal than either pinned artifact, where this enum member has not
-- been verified present. The icon itself is a hand-picked house-themed
-- Interface\Icons texture (art choice, not an API claim; see the evidence
-- comment further down), same as Recipe's above. Task 3 correction: the
-- texture name below is INV_Garrison_Hearthstone, not
-- INV_Misc_GarrisonHearthstone as an earlier round picked -- the
-- Misc-prefixed spelling does not resolve to a real icon file (checked via
-- the Wowhead/Zamimg icon render endpoint, which 404s for the Misc-prefixed
-- name and 200s for the corrected one); this task also fixes the same class
-- of typo in the Recipe Engineering subtype below (INV_Misc_Gizmo_02 ->
-- INV_Misc_Wrench_01, see the Recipe subclass comment).
if ITEM_CLASS.Housing then
    categoryOrderByClass[ITEM_CLASS.Housing] = 600
    categoryIconByClass[ITEM_CLASS.Housing] = {texture = "Interface\\Icons\\INV_Garrison_Hearthstone"}
    -- Housing subclasses: unlike Trade Goods below, both pinned artifacts'
    -- ItemConstantsDocumentation.lua DO document a static
    -- Enum.ItemHousingSubclass (Decor = 0, Dye = 1, Room = 2,
    -- RoomCustomization = 3, ExteriorCustomization = 4, ServiceItem = 5),
    -- verified identically at both commits for this task -- so Housing
    -- children get the same evidence-bar treatment as Consumable/Recipe
    -- below (a verified enum key, hand-picked texture value), not the Trade
    -- Goods exemption. Guarded by two nested checks: the outer
    -- ITEM_CLASS.Housing check above (categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Housing]
    -- would otherwise index with a nil key on a client/environment lacking
    -- ITEM_CLASS.Housing itself) and this inner Enum.ItemHousingSubclass
    -- check, guarded like Consumable/Recipe below because the enum table
    -- itself -- not just a member on it -- can be absent on some minimal
    -- test/client environments even though every member used here is
    -- present on both pinned Retail artifacts.
    if _G.Enum.ItemHousingSubclass then
        categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Housing] = {
            [_G.Enum.ItemHousingSubclass.Decor] = {texture = "Interface\\Icons\\INV_Misc_Statue_02"},
            [_G.Enum.ItemHousingSubclass.Dye] = {texture = "Interface\\Icons\\INV_Potion_162"},
            [_G.Enum.ItemHousingSubclass.Room] = {texture = "Interface\\Icons\\INV_Misc_Map_01"},
            [_G.Enum.ItemHousingSubclass.RoomCustomization] = {texture = "Interface\\Icons\\INV_Misc_Ribbon_01"},
            [_G.Enum.ItemHousingSubclass.ExteriorCustomization] = {texture = "Interface\\Icons\\INV_Misc_Shovel_01"},
            [_G.Enum.ItemHousingSubclass.ServiceItem] = {texture = "Interface\\Icons\\INV_Misc_Bell_01"},
        }
    end
end

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
-- exists; only the generic Book member keeps the same book texture as the
-- Recipe parent icon above. Guarded like Consumable above, for the same
-- reason. Task 3 fix: Leatherworking, Tailoring, and Inscription no longer
-- share Book's texture (the "one shared book icon" fallback was over-applied
-- in an earlier round; every profession below now gets its own distinct
-- pick), and Engineering's texture is corrected from INV_Misc_Gizmo_02 (not
-- a real icon file -- 404s via the Wowhead/Zamimg render endpoint) to
-- INV_Misc_Wrench_01 (200s, verified real).
if _G.Enum.ItemRecipeSubclass then
    categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Recipe] = {
        [_G.Enum.ItemRecipeSubclass.Book] = {texture = "Interface\\Icons\\INV_Misc_Book_09"},
        [_G.Enum.ItemRecipeSubclass.Leatherworking] = {texture = "Interface\\Icons\\INV_Weapon_ShortBlade_05"},
        [_G.Enum.ItemRecipeSubclass.Tailoring] = {texture = "Interface\\Icons\\INV_Misc_Thread_01"},
        [_G.Enum.ItemRecipeSubclass.Engineering] = {texture = "Interface\\Icons\\INV_Misc_Wrench_01"},
        [_G.Enum.ItemRecipeSubclass.Blacksmithing] = {texture = "Interface\\Icons\\INV_Hammer_01"},
        [_G.Enum.ItemRecipeSubclass.Cooking] = {texture = "Interface\\Icons\\INV_Misc_Food_15"},
        [_G.Enum.ItemRecipeSubclass.Alchemy] = {texture = "Interface\\Icons\\INV_Potion_92"},
        [_G.Enum.ItemRecipeSubclass.FirstAid] = {texture = "Interface\\Icons\\INV_Misc_Bandage_08"},
        [_G.Enum.ItemRecipeSubclass.Enchanting] = {texture = "Interface\\Icons\\INV_Enchant_Disenchant"},
        [_G.Enum.ItemRecipeSubclass.Fishing] = {texture = "Interface\\Icons\\INV_Fishingpole_01"},
        [_G.Enum.ItemRecipeSubclass.Jewelcrafting] = {texture = "Interface\\Icons\\INV_Misc_Gem_01"},
        [_G.Enum.ItemRecipeSubclass.Inscription] = {texture = "Interface\\Icons\\INV_Inscription_Scroll"},
    }
end

-- Trade Goods (ITEM_CLASS.Tradegoods) subclass icons: OWNER-GRANTED POLICY
-- EXEMPTION. Neither pinned artifact documents an Enum.ItemTradeGoodsSubclass
-- (or similarly named) enum anywhere in ItemConstantsDocumentation.lua,
-- ItemConstants_MainlineDocumentation.lua, or
-- ItemConstants_SharedDocumentation.lua -- re-checked directly against both
-- pinned commits (Retail 12.0.7.68887 4383ced30106d51b27e3e86d1987f1552f0d259d,
-- Retail 12.1.0.68914 d3915c78aba77a7a9be76acbfa35c674bbb6abe9) for this
-- task, same result as the v2 evidence comment this table replaces: no
-- GlobalStrings-style source file exists in the mirror to verify the
-- classic subclass name strings either, and
-- Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionData.lua's own Trade
-- Goods browse category (tradeGoodsCategory:GenerateSubCategoriesAndFiltersFromSubClass(
-- Enum.ItemClass.Tradegoods)) still builds its subclass list dynamically at
-- runtime, not from any static, checkable table -- verified twice now
-- (v2 and this task). GetCategory below reads subclassID directly off
-- C_Item.GetItemInfoInstant's raw numeric return (no named enum member
-- involved anywhere in this codepath) and uses it verbatim as this table's
-- key; there is no other numeric-subclass usage anywhere else in this file
-- to cross-check these particular ID values against.
--
-- Given the above, the owner granted an explicit exemption to the
-- artifact-evidence policy for this one table: runtime-observed numeric
-- subclass IDs are allowed here, with this maintenance comment standing in
-- place of an artifact citation. The IDs/names below are the brief's
-- candidates for Task 3, cross-checked against the long-standing
-- community-maintained Warcraft Wiki "ItemType" reference table for
-- ItemClass 7 (Tradeskill/Trade Goods), which lists the same eleven
-- id->name pairs used here (Parts=1, Jewelcrafting=4, Cloth=5, Leather=6,
-- "Metal & Stone"=7, Cooking=8, Herb=9, Elemental=10, Other=11,
-- Enchanting=12, Inscription=16; ids 0/2/3/13/14/15/17/18/19 are marked
-- OBSOLETE or otherwise unused on that same reference and are intentionally
-- left out). This is corroboration from a third-party community reference,
-- NOT an artifact-grade verification and NOT an actual in-game
-- C_Item.GetItemInfoInstant/GetItemSubClassInfo observation taken during
-- this task (no live client was available in this session) -- despite the
-- "IDs observed at runtime" phrasing the owner's exemption uses, treat the
-- table below as high-confidence, not confirmed. A one-time in-game
-- confirmation pass (mouse over one item of each subtype in a live client,
-- or call C_Item.GetItemSubClassInfo(7, id) and compare the returned name)
-- is still recommended before relying on this table for anything beyond
-- icon selection; see the report for this task for the same caveat. Any
-- subclassID not listed here falls back to the parent Trade Goods icon by
-- design, via GetCategory's "subclassIcons and subclassIcons[subclassID] or
-- nil" guard -- unlisted IDs are not an error, they are the intended
-- fallback path.
categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Tradegoods] = {
    [1] = {texture = "Interface\\Icons\\INV_Gizmo_02"}, -- Parts
    [4] = {texture = "Interface\\Icons\\INV_Misc_Gem_Variety_01"}, -- Jewelcrafting
    [5] = {texture = "Interface\\Icons\\INV_Fabric_Wool_01"}, -- Cloth
    [6] = {texture = "Interface\\Icons\\INV_Misc_LeatherScrap_01"}, -- Leather
    [7] = {texture = "Interface\\Icons\\INV_Ore_Copper_01"}, -- Metal & Stone
    [8] = {texture = "Interface\\Icons\\INV_Misc_Food_15"}, -- Cooking
    [9] = {texture = "Interface\\Icons\\INV_Misc_Herb_01"}, -- Herb
    [10] = {texture = "Interface\\Icons\\INV_Elemental_Mote_Fire01"}, -- Elemental
    [11] = {texture = "Interface\\Icons\\INV_Misc_Bag_09"}, -- Other
    [12] = {texture = "Interface\\Icons\\INV_Enchant_Dust"}, -- Enchanting
    [16] = {texture = "Interface\\Icons\\INV_Inscription_Tradeskill01"}, -- Inscription
}

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
-- 1. Equipment child rows use hand-picked full-color representative item
--    textures rather than PaperDollFrame's monochrome empty-slot art. This
--    is a presentation decision, not an API claim; the complete mapping is
--    declared next to equipmentSlotOrder and remains subject to in-game QA.
-- 2. INVTYPE_PROFESSION_TOOL, INVTYPE_PROFESSION_GEAR, and INVTYPE_BAG are
--    deliberately outside the Equipment parent. They share the dedicated
--    Miscellaneous aggregate with actual unknown-class items, and use the
--    purpose-built Bag_ProfessionTool, Bag_ProfessionEquipment, Bag_Bag,
--    and Bag_Miscellaneous adaptive icons supplied by AbstractFramework.
-- 3. Parent-category atlases (SUPERSEDED by Task 3, sidebar v3): both
--    commits' identical Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua
--    define a `BAG_FILTER_ICONS` table (~line 218) keyed by
--    Enum.BagSlotFlags, consumed by `ContainerFrame_GetBestFilterIcon` to
--    badge each container's portrait button with its configured bag-type
--    filter (ClassEquipment/ClassConsumables/ClassProfessionGoods/ClassJunk/
--    ClassQuestItems/ClassReagents -> "bags-icon-equipment"/"bags-icon-
--    consumables"/"bags-icon-profession-goods"/"bags-icon-junk"/"bags-icon-
--    questitem"/"bags-icon-reagents"). This evidence is retained here only
--    for history; categoryIconByClass and GetCategory's equipment
--    parentIcon no longer reference any of these six atlases as of Task 3 --
--    AbstractFramework/Widgets/TreeList.lua now renders every row icon at
--    full native color on a squared plate instead of the rail's flat
--    desaturated glyph tone (see item 6's replacement note below), so the
--    owner ruled every parent category becomes a hand-picked
--    Interface\Icons texture (item 5 below), matching Recipe/Housing's
--    pre-existing treatment instead of an atlas claim. REAGENT_SPACE_ICON
--    (the empty-reagent-slot overlay icon, unrelated to this sidebar
--    category system) still legitimately uses "bags-icon-reagents" and is
--    intentionally untouched by Task 3 -- it is a different UI element
--    (the item-grid empty-slot overlay, tinted with the player's class
--    color) than the sidebar rail's category icons this file's
--    categoryIconByClass/categoryIconBySubclass tables drive.
-- 4. Per-profession subclass keys (Trade Goods / Recipes / Housing): both
--    commits' ItemConstantsDocumentation.lua document ItemProfessionSubclass
--    (0-13, one member per profession, matching ITEM_CLASS.Profession),
--    ItemRecipeSubclass (0-11, matching ITEM_CLASS.Recipe), and (re-verified
--    for Task 3) ItemHousingSubclass (0-5, matching ITEM_CLASS.Housing --
--    Decor=0, Dye=1, Room=2, RoomCustomization=3, ExteriorCustomization=4,
--    ServiceItem=5) identically. Neither commit's Blizzard_Professions or
--    Blizzard_ProfessionsBook source defines a static per-profession atlas
--    (no `atlas=` usage tied to a profession identity in
--    Blizzard_ProfessionsFrame.lua/.xml or Blizzard_ProfessionsBook.lua/.xml
--    at either commit; the profession tab/spec icons those files do draw
--    come from runtime API calls such as GetChildProfessionInfo, not a
--    fixed literal a static Lua table could reference), so Recipe's and
--    Housing's subclass icons use hand-picked textures instead (item 5
--    below), keyed by their respective verified enum members. No
--    Enum.ItemTradeGoodsSubclass or Enum.ItemEnhancementSubclass exists in
--    either commit's ItemConstantsDocumentation.lua/
--    ItemConstants_MainlineDocumentation.lua/
--    ItemConstants_SharedDocumentation.lua either -- re-confirmed for Task 3
--    by grepping all three files at both commits for any "*Subclass"
--    enumeration tied to Trade Goods (same result as v2's evidence comment).
--    No GlobalStrings-equivalent source file exists in the mirror to verify
--    the classic Trade Goods subclass name strings ("Cloth", "Leather",
--    etc.) as an alternative string key either.
--    Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionData.lua's own Trade
--    Goods browse category
--    (`tradeGoodsCategory:GenerateSubCategoriesAndFiltersFromSubClass(
--    Enum.ItemClass.Tradegoods)`) builds its subclass list dynamically at
--    runtime, not from any static literal this file could cite either.
--    Task 3 changes this outcome from v2's "stays unmapped" policy result:
--    the owner granted an explicit exemption allowing a runtime-observed
--    numeric subclass table for Trade Goods specifically -- see the
--    dedicated exemption comment directly above
--    categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Tradegoods]'s
--    assignment below for the full exemption terms, ID provenance, and the
--    still-open in-game confirmation caveat. ItemEnhancement gets no
--    equivalent exemption or subclass table (out of scope for Task 3) and
--    stays on its parent categoryIconByClass entry.
-- 5. Art-choice textures (all parent-category icons, Consumable/Recipe/
--    Housing subtypes, Trade Goods exemption subtypes): hand-picked per the
--    brief/owner ruling, not an API claim, so none of the following are
--    gated on either pinned commit -- only the *keys* above
--    (Enum.ItemConsumableSubclass/ItemRecipeSubclass/ItemHousingSubclass
--    members, the classID itself, or -- under the Task 3 exemption -- the
--    Trade Goods runtime subclassID) carry an artifact-verification
--    requirement, which items 1-4 already satisfy. Parents: INV_Chest_Plate04
--    (Equipment), INV_Potion_51 (Consumables), INV_Crate_01 (Trade
--    Goods/Gem/ItemEnhancement/Profession, BFI's pre-existing shared
--    bucket), INV_Misc_Bag_11 (Reagents), INV_Misc_Note_01 (Quest),
--    INV_Misc_Book_09 (Recipes), INV_Garrison_Hearthstone (Housing --
--    corrected in Task 3 from the nonexistent INV_Misc_GarrisonHearthstone
--    spelling; see the ITEM_CLASS.Housing comment above). Consumable
--    subtypes: INV_Potion_93 (Potion), INV_Potion_97 (Flasksphials),
--    INV_Misc_Food_15 (Fooddrink), INV_Misc_Bandage_08 (Bandage),
--    INV_Potion_31 (Elixir). Recipe subtypes: INV_Misc_Book_09 (Book only,
--    the generic fallback), INV_Weapon_ShortBlade_05 (Leatherworking),
--    INV_Misc_Thread_01 (Tailoring), INV_Misc_Wrench_01 (Engineering --
--    corrected in Task 3 from the nonexistent INV_Misc_Gizmo_02 spelling),
--    INV_Hammer_01 (Blacksmithing), INV_Misc_Food_15 (Cooking, reused from
--    the consumable Fooddrink pick above), INV_Potion_92 (Alchemy),
--    INV_Misc_Bandage_08 (FirstAid, reused from the consumable Bandage pick
--    above), INV_Enchant_Disenchant (Enchanting), INV_Fishingpole_01
--    (Fishing), INV_Misc_Gem_01 (Jewelcrafting), INV_Inscription_Scroll
--    (Inscription). Housing subtypes: INV_Misc_Statue_02 (Decor),
--    INV_Potion_162 (Dye), INV_Misc_Map_01 (Room), INV_Misc_Ribbon_01
--    (RoomCustomization), INV_Misc_Shovel_01 (ExteriorCustomization),
--    INV_Misc_Bell_01 (ServiceItem). Trade Goods exemption subtypes:
--    INV_Gizmo_02 (Parts), INV_Misc_Gem_Variety_01 (Jewelcrafting),
--    INV_Fabric_Wool_01 (Cloth), INV_Misc_LeatherScrap_01 (Leather),
--    INV_Ore_Copper_01 (Metal & Stone), INV_Misc_Food_15 (Cooking, reused
--    again), INV_Misc_Herb_01 (Herb), INV_Elemental_Mote_Fire01 (Elemental),
--    INV_Misc_Bag_09 (Other), INV_Enchant_Dust (Enchanting),
--    INV_Inscription_Tradeskill01 (Inscription). Every texture path above
--    (including the two Task 3 corrections) was spot-checked against the
--    Wowhead/Zamimg icon render endpoint (200 = file exists, 404 = it does
--    not) during this task, which is how the two broken spellings were
--    caught -- that check confirms the file exists, not that it is the most
--    fitting art; final visual fit for all of the above remains an in-game
--    QA gate, not verified here.
-- 6. textureTint (REMOVED in Task 3): AbstractFramework/Widgets/TreeList.lua
--    no longer has a textureTint option at all as of codex/bag-sidebar-
--    foundation -- ApplyNodeIcon renders atlas/texture icons at their native
--    color unconditionally, with no SetVertexColor desaturation step.
--    Modules/Bags/Sidebar.lua's OPTIONS table (and the TEXTURE_TINT local
--    that fed it) are removed to match; passing textureTint would now be
--    silently inert, so BFI stops passing it rather than keep dead
--    configuration. See Sidebar.lua's OPTIONS comment for the replacement
--    explanation, including the paired rowHeight/iconSize removal that lets
--    AF's own row-sizing defaults govern instead.

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
    local miscellaneous = equipmentSlotOrder.miscellaneous

    -- Retail 12.0.7 uses this non-empty sentinel for non-equippable items.
    if itemEquipLoc
        and itemEquipLoc ~= ""
        and itemEquipLoc ~= NON_EQUIPMENT_LOCATION then
        itemEquipLoc = equipmentSlotAliases[itemEquipLoc] or itemEquipLoc
        local specialEquipment = miscellaneous.byEquipLoc[itemEquipLoc]
        if specialEquipment then
            parentKey = "parent:miscellaneous"
            parentLabel = L["Miscellaneous"]
            parentOrder = miscellaneous.order
            parentIcon = miscellaneous.icon
            childKey = "miscellaneous:equipment:" .. itemEquipLoc
            childLabel = _G[itemEquipLoc] or L[specialEquipment.label]
            childOrder = specialEquipment.order
            childIcon = specialEquipment.icon
        else
            parentKey = "parent:equipment"
            parentLabel = L["Equipment"]
            parentOrder = 100
            -- Task 3: was {atlas = "bags-icon-equipment"} (BAG_FILTER_ICONS);
            -- retired along with every other "bags-icon-*" parent atlas, see
            -- categoryIconByClass's comment above for why.
            parentIcon = {texture = "Interface\\Icons\\INV_Chest_Plate04"}
            childKey = "equipment:" .. itemEquipLoc
            childLabel = _G[itemEquipLoc] or itemEquipLoc
            childOrder = equipmentSlotOrder[itemEquipLoc] or 99
            childIcon = equipmentSlotOrder.categoryIconByEquipLoc[itemEquipLoc]
        end
    else
        if classID == ITEM_CLASS.Questitem then
            parentKey = "parent:quest"
            parentLabel = _G.BAG_FILTER_QUEST_ITEMS or itemType or L["Quest Items"]
        elseif classID == ITEM_CLASS.Miscellaneous or not itemType or itemType == "" then
            -- The special inventory locations above, the actual Miscellaneous
            -- item class, and unknown-class items intentionally share one
            -- Miscellaneous parent. Use the enum rather than a localized
            -- itemType label so this stays one category in every client locale.
            -- Their child keys retain distinct namespaces below.
            parentKey = "parent:miscellaneous"
            parentLabel = L["Miscellaneous"]
        else
            parentKey = "parent:class:" .. classID
            parentLabel = itemType
        end

        if parentKey == "parent:miscellaneous" then
            parentOrder = miscellaneous.order
            parentIcon = miscellaneous.icon
        else
            parentOrder = categoryOrderByClass[classID] or 600
            parentIcon = categoryIconByClass[classID] or miscellaneous.icon
        end
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
                1 + contentInset + ((index - 1) * (size + spacing)),
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
        1 + contentInset,
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
    local minimumFrameWidth = ITEM_SIZE + HORIZONTAL_PADDING + 1 + contentInset
    local maxFrameWidth = math.max(
        minimumFrameWidth,
        screenWidth - (SCREEN_EDGE_MARGIN * 2)
    )
    local maxColumns = math.max(
        1,
        floor(
            (maxFrameWidth - HORIZONTAL_PADDING - 1 - contentInset + spacing)
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
        HORIZONTAL_PADDING + 1 + contentInset + GetGridWidth(columns, spacing)
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
        HORIZONTAL_PADDING + 1 + contentInset + contentWidth
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
            1 + contentInset + (column * (ITEM_SIZE + spacing)),
            cursorY - (row * (ITEM_SIZE + spacing))
        )
        RecordEmptyEntryIndex(itemButton, entryIndex)
    end
end

local function BuildIndividualLayoutEntries(spacing, top, contentInset)
    for groupIndex, group in ipairs(individualGroups) do
        local groupX = 1 + contentInset
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
    if bagSidebar and combinedFrame.BFIVisualShell then
        bagSidebar:ClearAllPoints()
        AF.SetPoint(bagSidebar, "TOPLEFT", combinedFrame.BFIVisualShell, "TOPLEFT", 1, -1)
        AF.SetPoint(bagSidebar, "BOTTOMLEFT", combinedFrame.BFIVisualShell, "BOTTOMLEFT", 1, 1)
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

    -- The rail is manual-collapse only (see AF_SidebarRailMixin), so it
    -- always reports presentation width == reserved width: the styled
    -- shell never needs to grow past the Blizzard container's own width.
    -- It still exists as a template-free layer (right-anchored, mirroring
    -- the container's width 1:1) so the background/header/rail can anchor
    -- to it instead of the fixed Blizzard frame.
    local visualShell = _G.CreateFrame("Frame", nil, combinedFrame)
    combinedFrame.BFIVisualShell = visualShell
    visualShell:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT")
    visualShell:SetPoint("BOTTOMRIGHT", combinedFrame, "BOTTOMRIGHT")
    function visualShell:SyncWidth()
        AF.SetWidth(self, combinedFrame:GetWidth())
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
