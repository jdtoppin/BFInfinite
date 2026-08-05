local function readFile(path)
    local file, openError = io.open(path, "r")
    if not file then
        error(openError or ("unable to open " .. path), 2)
    end
    local contents = file:read("*a")
    file:close()
    return contents
end

local function assertContains(contents, text, message)
    if not contents:find(text, 1, true) then
        error((message or "missing source contract") .. ": " .. text, 2)
    end
end

local function assertNotContains(contents, text, message)
    if contents:find(text, 1, true) then
        error((message or "unexpected source contract") .. ": " .. text, 2)
    end
end

local function assertCount(contents, text, expected, message)
    local count = 0
    local offset = 1
    while true do
        local found = contents:find(text, offset, true)
        if not found then break end
        count = count + 1
        offset = found + #text
    end
    if count ~= expected then
        error((message or "unexpected source contract count")
            .. (": expected %d, got %d for %s"):format(expected, count, text), 2)
    end
end

local function assertBefore(contents, first, second, message)
    local firstAt = contents:find(first, 1, true)
    local secondAt = contents:find(second, 1, true)
    if not firstAt or not secondAt or firstAt >= secondAt then
        error(message or (first .. " must precede " .. second), 2)
    end
end

local bags = readFile("Modules/Bags/Bags.lua")
local sidebar = readFile("Modules/Bags/Sidebar.lua")
local defaults = readFile("Modules/Bags/Defaults.lua")
local options = readFile("Options/Bags.lua")
local style = readFile("Modules/Style/Style.lua")

assertContains(defaults, 'viewMode = "combined"', "default bag view")
assertContains(defaults, "sidebarCollapsed = false",
    "sidebar labels are expanded by default")
assertContains(defaults, 'if type(config.sidebarCollapsed) ~= "boolean" then',
    "saved collapsed state is normalized")
assertContains(defaults, "config.sidebarCollapsed = config.sidebarAutoHide == true",
    "the legacy auto-hide setting migrates true to collapsed true")
assertContains(defaults, "config.sidebarAutoHide = nil",
    "the legacy auto-hide key is consumed after migration")
assertContains(defaults, "local validViewModes = {", "saved bag view allowlist")
assertContains(defaults, "combined = true", "combined saved view")
assertContains(defaults, "individual = true", "individual saved view")
assertNotContains(defaults, "categories = true", "categories are not a saved main view")
assertContains(defaults, "config.viewMode = defaults.viewMode",
    "legacy category view falls back to Combined")
assertContains(defaults, "config.categories = nil",
    "legacy category preference is removed")
assertContains(options, "AF.CreateDropdown(appearancePane, 165)",
    "bag view selector")
assertContains(options, '{text = L["Combined View"], value = "combined"}',
    "combined bag option")
assertContains(options, '{text = L["Individual Bags View"], value = "individual"}',
    "individual bag option")
assertNotContains(options, 'value = "categories"',
    "categories are selected from the sidebar")
assertContains(options, "B.SetViewMode(value)",
    "view options use the validated bag API")
assertContains(options, 'AF.CreateCheckButton(appearancePane, L["Collapse Sidebar"])',
    "the sidebar collapse toggle is also exposed in options")
assertContains(options, "B.config.sidebarCollapsed = checked",
    "the options checkbox persists the collapsed state")
assertContains(bags, 'AF.RegisterCallback("BFI_UpdateProfile", function()',
    "profile changes reset transient sidebar navigation")
assertContains(bags, "activeCategoryKey = nil",
    "a new profile is not overridden by the previous category filter")
assertContains(bags, "B.Sidebar.SetCollapsed(B.config.sidebarCollapsed, true)",
    "profile and layout refreshes silently synchronize persisted collapsed state")
assertContains(bags, "B.Sidebar.SetOnCollapsedChanged(function(collapsed)",
    "the header toggle publishes user collapse changes")
assertContains(bags, "B.config.sidebarCollapsed = collapsed",
    "user collapse changes persist in the active bag profile")
assertContains(bags,
    "B.config.sidebarCollapsed = collapsed\n        LayoutItems(true)",
    "changing reserved sidebar width forces an item relayout")
assertContains(bags,
    "or B.config.sidebarCollapsed ~= snapshotSidebarCollapsed",
    "collapsed width participates in the layout snapshot")
assertContains(bags,
    "snapshotSidebarCollapsed = B.config.sidebarCollapsed",
    "captured layouts retain their collapsed width state")

-- The rail is one permanent navigation model: main views first, then the
-- independently selectable category tree. Combined never hides the rail.
assertContains(bags, "local function BuildSidebarModel()",
    "bags build one permanent sidebar model")
assertContains(bags, 'sidebarModel[1] = {kind = "heading", label = L["Views"]}',
    "views section heading")
assertContains(bags, 'sidebarModel[4] = {kind = "heading", label = L["Categories"]}',
    "categories section heading")
assertBefore(bags,
    'label = L["Combined View"]',
    'label = L["Categories"]',
    "main views precede categories")
assertBefore(bags,
    'label = L["Individual Bags View"]',
    'label = L["Categories"]',
    "individual view precedes categories")
assertContains(bags, "B.Sidebar.SetModel(sidebarModel)",
    "bags publish the complete navigation model")
assertContains(bags, "B.Sidebar.SetShown(true)",
    "all enabled bag views keep the sidebar shown")
assertContains(bags, "local contentInset = B.Sidebar.GetContentInset()",
    "all item layouts reserve the sidebar inset")
assertContains(sidebar, "return Sidebar.GetDesiredWidth() + CONTENT_GAP",
    "the sidebar inset follows pinned or compact width, not selected view")

-- Narrow category filters retain a useful navigation viewport.
assertContains(bags, "local SIDEBAR_MIN_HEIGHT = 320",
    "narrow category results retain a useful minimum bag height")
assertContains(bags, "function B.GetMinimumFrameHeight(maxFrameHeight, footerHeight)",
    "flat and individual layouts share one screen-capped minimum")
assertContains(bags,
    "return math.min(maxFrameHeight, SIDEBAR_TOP + SIDEBAR_MIN_HEIGHT + footerHeight)",
    "the minimum remains footer-aware and screen-capped")
assertCount(bags, "B.GetMinimumFrameHeight(maxFrameHeight, footerHeight)", 3,
    "the minimum helper must be defined and used by both layout paths")

-- Task 7: the rail sits flush against the styled shell's inner border
-- (left/top/bottom, full height) instead of inset like other panel content.
-- It anchors to the visual shell -- not the fixed Blizzard combinedFrame --
-- with the same 1px pixel-perfect offset the shell's own flush children use
-- (AF.SetOnePixelInside's TOPLEFT +1,-1 / bottom +1,+1 convention).
assertContains(bags,
    'AF.SetPoint(bagSidebar, "TOPLEFT", combinedFrame.BFIVisualShell, "TOPLEFT", 1, -1)',
    "the rail's top-left corner sits flush inside the shell's border")
assertContains(bags,
    'AF.SetPoint(bagSidebar, "BOTTOMLEFT", combinedFrame.BFIVisualShell, "BOTTOMLEFT", 1, 1)',
    "the rail's bottom-left corner sits flush inside the shell's border, spanning full height")
assertNotContains(bags,
    "local sidebarRight = HORIZONTAL_PADDING + B.Sidebar.GetDesiredWidth()",
    "the rail no longer needs a computed right edge now that it anchors flush left")
assertNotContains(bags,
    'bagSidebar:SetPoint("TOPRIGHT", combinedFrame, "TOPLEFT"',
    "the rail no longer anchors a right edge to the fixed Blizzard frame")
assertNotContains(bags,
    'bagSidebar:SetPoint("TOPLEFT", combinedFrame, "TOPLEFT"',
    "the rail must anchor to the visual shell, not the fixed Blizzard frame")

-- The item grid, header controls, and section groups all originate from the
-- same flush 1px inset the rail now anchors with (not HORIZONTAL_PADDING),
-- so the 8px gap between the rail and the grid stays exactly 8px: the two
-- shift left together instead of leaving an 11px dead zone at the rail's
-- old inset. GetContentInset() itself (rail width + 8) is unchanged.
assertContains(bags, "1 + contentInset + ((index - 1) * (size + spacing)),",
    "the bag-slot row originates flush with the rail")
assertContains(bags, "1 + contentInset,\n        -27",
    "the collapse toggle originates flush with the rail")
assertContains(bags, "1 + contentInset + (column * (ITEM_SIZE + spacing)),",
    "the flat grid originates flush with the rail")
assertContains(bags, "local groupX = 1 + contentInset",
    "individual section groups originate flush with the rail")
assertCount(bags, "HORIZONTAL_PADDING + 1 + contentInset", 3,
    "total frame width keeps the shell's right-side padding alongside the rail's flush left inset")
assertContains(bags,
    "maxFrameWidth - HORIZONTAL_PADDING - 1 - contentInset + spacing",
    "the max-column fit subtracts the same flush left inset plus the unchanged right padding")

-- The rail is manual-collapse only, so its presentation width always equals
-- its reserved width; the styled shell mirrors the Blizzard container's
-- width 1:1 (right-anchored) rather than growing to fit a transient rail
-- width, since there is no transient width to fit.
assertContains(bags,
    'local visualShell = _G.CreateFrame("Frame", nil, combinedFrame)',
    "the styled shell must use a template-free visual shell")
assertContains(bags,
    'visualShell:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT")',
    "the visual shell must preserve the bag window's right edge")
assertContains(bags,
    'visualShell:SetPoint("BOTTOMRIGHT", combinedFrame, "BOTTOMRIGHT")',
    "the visual shell must span the full bag window height")
assertContains(bags,
    "AF.SetWidth(self, combinedFrame:GetWidth())",
    "the shell mirrors the container's width directly, with no extension")
assertNotContains(bags, "sidebarExtension",
    "the inert presentation-proxy extension must not be reintroduced")
assertNotContains(bags, "SetSidebarPresentationWidth",
    "the inert presentation-proxy method must not be reintroduced")
assertNotContains(bags, "B.Sidebar.SetOnPresentationWidthChanged",
    "the shell no longer needs presentation-width updates it can't act on")
assertContains(bags,
    "combinedFrame.BFIBg:SetAllPoints(visualShell)",
    "the lightweight background anchors to the visual shell")
assertContains(bags,
    'combinedFrame.BFIHeader:SetPoint("TOPLEFT", visualShell, "TOPLEFT")',
    "the title strip anchors to the visual shell")
assertContains(bags,
    'combinedFrame.BFIHeader:SetPoint("TOPRIGHT", visualShell, "TOPRIGHT")',
    "the title strip must retain the bag window's right edge")
assertContains(bags,
    'combinedFrame:HookScript("OnSizeChanged", function()',
    "the visual shell must follow later Blizzard container resizes")
assertContains(bags,
    "local function OnCombinedFrameShow()\n    if not IsEnabled() then return end\n    B.Sidebar.SetShown(true)",
    "showing the bag window must restore sidebar presentation updates")
assertContains(bags,
    "local function OnCombinedFrameHide()\n    B.Sidebar.SetShown(false)",
    "hiding the bag window must settle and hide the sidebar presentation")

-- Manual collapse is a header action beside the other bag controls. Its
-- arrow communicates the next action rather than using the old lock metaphor.
assertContains(bags,
    'local sidebarButton = AF.CreateButton(combinedFrame, nil, "gray", 24, 22)',
    "the collapse toggle uses the same header button treatment as bag controls")
assertContains(bags,
    'self:SetTexture(AF.GetIcon(collapsed and "ArrowLeft1" or "ArrowRight1"))',
    "the header uses AF arrows that follow the action available from the current state")
assertContains(bags,
    'self:SetTooltip(collapsed and L["Expand Sidebar"] or L["Collapse Sidebar"])',
    "the header toggle explains its current action")
assertContains(bags,
    'searchBox:SetPoint("TOPLEFT", sidebarButton, "TOPRIGHT", 3, 0)',
    "the collapse toggle sits immediately left of search")
assertBefore(bags,
    "sidebarButton:SetPoint(",
    'searchBox:SetPoint("TOPLEFT", sidebarButton',
    "the header toggle must be positioned before search anchors to it")
for _, removedUtilityContract in ipairs({
    "CreateAutoHideControl",
    "autoHideButton",
    'AF.SetAdaptiveIcon(autoHideButton.icon, "Lock")',
    'AF.SetAdaptiveIcon(autoHideButton.icon, "Unlock")',
}) do
    assertNotContains(sidebar, removedUtilityContract,
        "the rail must not retain the old lock utility row")
end
-- The rail is a single AF.CreateSidebarRail widget with no separate utility
-- row anchored above it, so navigation always spans the rail's full height
-- (AbstractFramework/tests/tree_list_test.lua covers the rail's own layout).
assertContains(sidebar, "AF.CreateSidebarRail(",
    "removing the utility row gives navigation the rail's full height")

-- Task 3 (sidebar v3): AF's TreeList.lua deletes textureTint entirely and
-- renders every row icon at full native color, so Sidebar.lua no longer
-- desaturates category icons -- and no longer overrides rowHeight/iconSize,
-- letting AF's own defaults (28/20) govern per Task 2.
assertNotContains(sidebar, "TEXTURE_TINT",
    "the tint local is removed along with the option it fed")
assertNotContains(sidebar, "textureTint = ",
    "Sidebar.lua must not pass the deleted textureTint option through")
assertNotContains(sidebar, "rowHeight = ",
    "Sidebar.lua must not override AF's default row height")
assertNotContains(sidebar, "iconSize = ",
    "Sidebar.lua must not override AF's default icon size")

-- Task 3: every parent-category icon retires its "bags-icon-*"
-- BAG_FILTER_ICONS atlas (Task 5's choice) in favor of a hand-picked
-- Interface\Icons texture, now that AF renders full-color plated art
-- instead of desaturating atlas/texture icons to the rail's flat glyph
-- tone. REAGENT_SPACE_ICON (a different UI element -- the item-grid
-- empty-reagent-slot overlay, unrelated to the sidebar rail) is
-- intentionally exempt and keeps "bags-icon-reagents".
for _, retiredParentAtlas in ipairs({
    '[ITEM_CLASS.Consumable] = {atlas = "bags-icon-consumables"}',
    '[ITEM_CLASS.Tradegoods] = {atlas = "bags-icon-profession-goods"}',
    '[ITEM_CLASS.Reagent] = {atlas = "bags-icon-reagents"}',
    '[ITEM_CLASS.Questitem] = {atlas = "bags-icon-questitem"}',
    'parentIcon = {atlas = "bags-icon-equipment"}',
}) do
    assertNotContains(bags, retiredParentAtlas,
        "no parent-category icon may still use a bags-icon-* atlas")
end
assertContains(bags,
    '[ITEM_CLASS.Consumable] = {texture = "Interface\\\\Icons\\\\INV_Potion_51"}',
    "consumables use a hand-picked bottle texture")
assertContains(bags,
    '[ITEM_CLASS.Tradegoods] = {texture = "Interface\\\\Icons\\\\INV_Crate_01"}',
    "trade goods use a hand-picked bundle texture")
assertContains(bags,
    '[ITEM_CLASS.Reagent] = {texture = "Interface\\\\Icons\\\\INV_Misc_Bag_11"}',
    "reagents use a hand-picked pouch texture")
assertContains(bags,
    '[ITEM_CLASS.Questitem] = {texture = "Interface\\\\Icons\\\\INV_Misc_Note_01"}',
    "quest items use a hand-picked scroll/note texture")
assertContains(bags,
    'parentIcon = {texture = "Interface\\\\Icons\\\\INV_Chest_Plate04"}',
    "the equipment parent category uses a hand-picked armor texture")
assertContains(bags,
    "if ITEM_CLASS.Housing then",
    "housing class support must remain compatible with clients lacking the enum")

-- Fix round 1 (still true): ItemClass.Housing (EnumValue = 20) is
-- documented identically at both pinned commits, so no comment may claim it
-- is a 12.1.0-only addition or otherwise unavailable at 12.0.7.
assertNotContains(bags, "adds ItemClass.Housing",
    "no comment may claim Housing is a 12.1.0-only addition; it is documented identically at both pinned commits")
assertNotContains(bags, "not available",
    "no comment may claim ItemClass.Housing is unavailable at the 12.0.7 pinned commit")

-- Task 3: the Recipe parent icon is unchanged (already a hand-picked
-- texture before this task); the Housing parent's texture name is corrected
-- from a nonexistent Misc-prefixed spelling to the real icon file.
assertContains(bags,
    '[ITEM_CLASS.Recipe] = {texture = "Interface\\\\Icons\\\\INV_Misc_Book_09"}',
    "recipes use a hand-picked book texture (no verified native atlas exists)")
assertContains(bags,
    'categoryIconByClass[ITEM_CLASS.Housing] = {texture = "Interface\\\\Icons\\\\INV_Garrison_Hearthstone"}',
    "housing uses the corrected, real hand-picked house-themed texture")
assertNotContains(bags, 'texture = "Interface\\\\Icons\\\\INV_Misc_GarrisonHearthstone"',
    "the nonexistent Misc-prefixed Housing texture spelling must not reappear as an actual icon value")

-- Fix round 1: Recipe subtypes get the same art-choice texture treatment as
-- Consumable subtypes, keyed by the verified Enum.ItemRecipeSubclass
-- members (same evidence bar as Consumable's Enum.ItemConsumableSubclass
-- keys). The host table is now created unconditionally so a missing
-- Consumable or Recipe enum never leaves the whole map nil.
assertContains(bags,
    "categoryOrderByClass.categoryIconBySubclass = {}",
    "the subclass icon host table exists unconditionally, independent of either enum's availability")
assertContains(bags,
    "categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Consumable] = {",
    "consumable subclass icons are populated behind their own enum guard")
assertContains(bags,
    "if _G.Enum.ItemRecipeSubclass then",
    "the recipe subclass icon map is nil-guarded like Consumable, for clients/environments lacking the enum")
assertContains(bags,
    "categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Recipe] = {",
    "recipe subclass icons are populated behind their own enum guard")
for _, recipeSubclassIcon in ipairs({
    '[_G.Enum.ItemRecipeSubclass.Book] = {texture = "Interface\\\\Icons\\\\INV_Misc_Book_09"}',
    '[_G.Enum.ItemRecipeSubclass.Leatherworking] = {texture = "Interface\\\\Icons\\\\INV_Weapon_ShortBlade_05"}',
    '[_G.Enum.ItemRecipeSubclass.Tailoring] = {texture = "Interface\\\\Icons\\\\INV_Misc_Thread_01"}',
    '[_G.Enum.ItemRecipeSubclass.Engineering] = {texture = "Interface\\\\Icons\\\\INV_Misc_Wrench_01"}',
    '[_G.Enum.ItemRecipeSubclass.Blacksmithing] = {texture = "Interface\\\\Icons\\\\INV_Hammer_01"}',
    '[_G.Enum.ItemRecipeSubclass.Cooking] = {texture = "Interface\\\\Icons\\\\INV_Misc_Food_15"}',
    '[_G.Enum.ItemRecipeSubclass.Alchemy] = {texture = "Interface\\\\Icons\\\\INV_Potion_92"}',
    '[_G.Enum.ItemRecipeSubclass.FirstAid] = {texture = "Interface\\\\Icons\\\\INV_Misc_Bandage_08"}',
    '[_G.Enum.ItemRecipeSubclass.Enchanting] = {texture = "Interface\\\\Icons\\\\INV_Enchant_Disenchant"}',
    '[_G.Enum.ItemRecipeSubclass.Fishing] = {texture = "Interface\\\\Icons\\\\INV_Fishingpole_01"}',
    '[_G.Enum.ItemRecipeSubclass.Jewelcrafting] = {texture = "Interface\\\\Icons\\\\INV_Misc_Gem_01"}',
    '[_G.Enum.ItemRecipeSubclass.Inscription] = {texture = "Interface\\\\Icons\\\\INV_Inscription_Scroll"}',
}) do
    assertContains(bags, recipeSubclassIcon,
        "every verified Enum.ItemRecipeSubclass member maps to a hand-picked art-choice texture")
end
-- Task 3 fix: Leatherworking, Tailoring, and Inscription no longer share
-- the generic Book texture -- only the Book member itself may still use it.
assertCount(bags, 'Interface\\\\Icons\\\\INV_Misc_Book_09"}', 2,
    "INV_Misc_Book_09 must appear exactly twice: the Recipe parent icon and the Book subclass, never a second profession")
assertNotContains(bags, 'texture = "Interface\\\\Icons\\\\INV_Misc_Gizmo_02"',
    "the nonexistent Misc-prefixed Engineering texture spelling must not reappear as an actual icon value")

-- Task 3: Trade Goods subclasses get an OWNER-GRANTED POLICY EXEMPTION --
-- runtime-observed numeric subclass IDs are now allowed for this one table,
-- in place of the artifact-verified key Consumable/Recipe/Housing use,
-- because neither pinned commit documents any such enum (re-verified for
-- this task, same result as v2). The exemption maintenance comment must be
-- present alongside the table.
assertContains(bags,
    "categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Tradegoods] = {",
    "trade goods subclasses are now populated under the owner-granted exemption")
assertContains(bags, "OWNER-GRANTED POLICY\n-- EXEMPTION",
    "the exemption maintenance comment marker must be present")
assertContains(bags, "still recommended before relying on this table",
    "the comment must flag that in-game confirmation is still outstanding")
for _, tradeGoodsSubclassIcon in ipairs({
    '[1] = {texture = "Interface\\\\Icons\\\\INV_Gizmo_02"}, -- Parts',
    '[4] = {texture = "Interface\\\\Icons\\\\INV_Misc_Gem_Variety_01"}, -- Jewelcrafting',
    '[5] = {texture = "Interface\\\\Icons\\\\INV_Fabric_Wool_01"}, -- Cloth',
    '[6] = {texture = "Interface\\\\Icons\\\\INV_Misc_LeatherScrap_01"}, -- Leather',
    '[7] = {texture = "Interface\\\\Icons\\\\INV_Ore_Copper_01"}, -- Metal & Stone',
    '[8] = {texture = "Interface\\\\Icons\\\\INV_Misc_Food_15"}, -- Cooking',
    '[9] = {texture = "Interface\\\\Icons\\\\INV_Misc_Herb_01"}, -- Herb',
    '[10] = {texture = "Interface\\\\Icons\\\\INV_Elemental_Mote_Fire01"}, -- Elemental',
    '[11] = {texture = "Interface\\\\Icons\\\\INV_Misc_Bag_09"}, -- Other',
    '[12] = {texture = "Interface\\\\Icons\\\\INV_Enchant_Dust"}, -- Enchanting',
    '[16] = {texture = "Interface\\\\Icons\\\\INV_Inscription_Tradeskill01"}, -- Inscription',
}) do
    assertContains(bags, tradeGoodsSubclassIcon,
        "every Trade Goods exemption subclass ID maps to its own hand-picked texture")
end

-- Task 3: Housing subclasses are a fully documented enum (unlike Trade
-- Goods above), so they get the same artifact-verified-key treatment as
-- Consumable/Recipe, not the exemption.
assertContains(bags,
    "categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Housing] = {",
    "housing subclasses are populated behind the verified ItemHousingSubclass enum")
for _, housingSubclassIcon in ipairs({
    '[_G.Enum.ItemHousingSubclass.Decor] = {texture = "Interface\\\\Icons\\\\INV_Misc_Statue_02"}',
    '[_G.Enum.ItemHousingSubclass.Dye] = {texture = "Interface\\\\Icons\\\\INV_Potion_162"}',
    '[_G.Enum.ItemHousingSubclass.Room] = {texture = "Interface\\\\Icons\\\\INV_Misc_Map_01"}',
    '[_G.Enum.ItemHousingSubclass.RoomCustomization] = {texture = "Interface\\\\Icons\\\\INV_Misc_Ribbon_01"}',
    '[_G.Enum.ItemHousingSubclass.ExteriorCustomization] = {texture = "Interface\\\\Icons\\\\INV_Misc_Shovel_01"}',
    '[_G.Enum.ItemHousingSubclass.ServiceItem] = {texture = "Interface\\\\Icons\\\\INV_Misc_Bell_01"}',
}) do
    assertContains(bags, housingSubclassIcon,
        "every verified Enum.ItemHousingSubclass member maps to a hand-picked art-choice texture")
end

-- Category families are selectable aggregate parents with nested, concise
-- subtype rows. In particular, equipment children read Chest/Gloves rather
-- than repeating the Equipment prefix on every line.
assertContains(bags, 'parentKey = "parent:equipment"',
    "equipment aggregate category")
assertContains(bags, 'parentLabel = L["Equipment"]',
    "equipment parent label")
assertContains(bags, "childLabel = _G[itemEquipLoc] or itemEquipLoc",
    "equipment children use native short slot labels")
assertContains(bags, "parentLabel = itemType",
    "non-equipment parents retain their native main category label")
assertContains(bags, "childLabel = itemSubType",
    "trade-skill, recipe, and other children use only their subtype label")
assertContains(bags, "parent.items[#parent.items + 1] = itemButton",
    "category parents select their full aggregate")
assertContains(bags, "parent.children[#parent.children + 1] = group",
    "category groups retain nested subtypes")
assertContains(bags, "node.children = {}",
    "sidebar category parents expose children")
assertContains(bags, "label = child.label",
    "sidebar child rows retain concise labels")
assertNotContains(bags, 'L["Equipment - %s"]',
    "equipment subtype rows do not repeat their parent")

-- Individual Bags is a real multi-section layout containing every physical
-- bag at once, not the former sidebar-driven single-bag filter.
assertContains(bags, "local function AcquireIndividualGroup(bagID)",
    "items are grouped by physical bag")
assertContains(bags, "local function BuildIndividualLayoutEntries(spacing, top, contentInset)",
    "individual view has a dedicated section layout")
assertContains(bags, "for groupIndex, group in ipairs(individualGroups) do",
    "individual layout walks every bag section")
assertContains(bags, "header:SetText(group.label)",
    "each physical bag has a visible section heading")
assertContains(bags, "BuildIndividualLayoutEntries(spacing, top, contentInset)",
    "individual mode renders its multi-section layout")
assertNotContains(bags, "activeBagID",
    "individual view no longer stores one active physical bag")
assertNotContains(bags, "bagID == activeBagID",
    "individual view no longer filters to one physical bag")
assertNotContains(bags, "ResolveCategorySelection",
    "categories no longer use the old flat per-mode controller")
assertNotContains(bags, "B.Sidebar.SetMode(",
    "sidebar navigation is no longer swapped per mode")
assertNotContains(bags, "B.Sidebar.SetEntries(",
    "sidebar navigation is no longer replaced with flat entries")

-- View selection lives in the permanent sidebar and options menu, leaving no
-- duplicate header button that cycles among modes.
for _, removedHeaderContract in ipairs({
    "local viewButton",
    "nextViewMode",
    "viewModeIcons",
    "viewModeLabels",
    "UpdateViewButtonState",
    "viewButton:SetOnClick",
}) do
    assertNotContains(bags, removedHeaderContract,
        "header view-cycle control is removed")
end

assertContains(bags, "S.StyleTitledFrame(combinedFrame, nil, true)",
    "bag shell opts into the lightweight border path")
assertContains(bags, 'local button = _G.CreateFrame("Button", nil, combinedFrame)',
    "bag-slot controls avoid BackdropTemplate")
assertContains(bags, "AF.ApplyLightweightBackdropWithColors(button, \"widget\", \"border\")",
    "bag-slot controls share the five-texture border path")
assertContains(style, "and AF.CreateLightweightBorderedFrame",
    "titled frames can use AF's five-texture primitive")
assertContains(style, "or AF.CreateBorderedFrame",
    "other titled frames keep their existing path")
assertNotContains(bags, 'SetScript("OnUpdate"',
    "bag presentation remains event-driven")
assertNotContains(sidebar, 'SetScript("OnUpdate"',
    "sidebar presentation remains event-driven")

-- Child-category rows in the collapsed rail are icon-only, so every
-- consumable subclass and equipment slot BFI renders needs a distinct
-- childIcon. Both mapping tables are nested as nonnumeric fields on an
-- existing top-level local (rather than declared as new top-level locals)
-- because Bags.lua's main chunk sits at Lua 5.1's 200-local ceiling.
--
-- Task 5: no Tabler Bag_Slot_* glyph may remain anywhere in Bags.lua --
-- equipment slot icons are now {texture = ...} tables resolved at load time
-- from the client's own paper-doll art via GetInventorySlotInfo, and any
-- INVTYPE that can't be resolved (unverifiable, or no API available) is
-- simply absent, falling back to the parent Equipment icon instead of a
-- guessed glyph.
assertNotContains(bags, "Bag_Slot_",
    "no Tabler bag-slot glyph may remain; equipment icons are native slot art")
assertContains(bags,
    "categoryOrderByClass.categoryIconBySubclass = {",
    "consumable subclass icons are keyed by classID then subclassID")
assertContains(bags,
    '[_G.Enum.ItemConsumableSubclass.Potion] = {texture = "Interface\\\\Icons\\\\INV_Potion_93"}',
    "potions use their own native icon texture")
assertContains(bags,
    '[_G.Enum.ItemConsumableSubclass.Flasksphials] = {texture = "Interface\\\\Icons\\\\INV_Potion_97"}',
    "flasks and phials use their own native icon texture")
assertContains(bags,
    '[_G.Enum.ItemConsumableSubclass.Fooddrink] = {texture = "Interface\\\\Icons\\\\INV_Misc_Food_15"}',
    "food and drink use their own native icon texture")
assertContains(bags,
    '[_G.Enum.ItemConsumableSubclass.Bandage] = {texture = "Interface\\\\Icons\\\\INV_Misc_Bandage_08"}',
    "bandages use their own native icon texture")
assertContains(bags,
    '[_G.Enum.ItemConsumableSubclass.Elixir] = {texture = "Interface\\\\Icons\\\\INV_Potion_31"}',
    "elixirs use their own native icon texture")
assertContains(bags,
    "equipmentSlotOrder.categoryIconByEquipLoc = {}",
    "equipment slot icons start empty and are populated at load time, not as static literals")
assertContains(bags,
    "local INV_TYPE_TO_SLOT = {",
    "post-alias INVTYPE to character-pane slot-name table drives slot-art resolution")
for _, invTypeToSlotName in ipairs({
    'INVTYPE_HEAD = "HeadSlot"',
    'INVTYPE_NECK = "NeckSlot"',
    'INVTYPE_SHOULDER = "ShoulderSlot"',
    'INVTYPE_CLOAK = "BackSlot"',
    'INVTYPE_CHEST = "ChestSlot"',
    'INVTYPE_BODY = "ShirtSlot"',
    'INVTYPE_TABARD = "TabardSlot"',
    'INVTYPE_WRIST = "WristSlot"',
    'INVTYPE_HAND = "HandsSlot"',
    'INVTYPE_WAIST = "WaistSlot"',
    'INVTYPE_LEGS = "LegsSlot"',
    'INVTYPE_FEET = "FeetSlot"',
    'INVTYPE_FINGER = "Finger0Slot"',
    'INVTYPE_TRINKET = "Trinket0Slot"',
    'INVTYPE_WEAPONMAINHAND = "MainHandSlot"',
    'INVTYPE_WEAPONOFFHAND = "SecondaryHandSlot"',
    'INVTYPE_WEAPON = "MainHandSlot"',
    'INVTYPE_2HWEAPON = "MainHandSlot"',
    'INVTYPE_RANGED = "MainHandSlot"',
}) do
    assertContains(bags, invTypeToSlotName,
        "every rendered equipment slot maps to its verified PaperDollFrame.xml slot name")
end
-- INVTYPE_PROFESSION_TOOL, INVTYPE_PROFESSION_GEAR, and INVTYPE_BAG have no
-- matching ItemButton in either pinned PaperDollFrame.xml and must not be
-- guessed into INV_TYPE_TO_SLOT.
for _, unverifiedEquipSlot in ipairs({
    'INVTYPE_PROFESSION_TOOL = "',
    'INVTYPE_PROFESSION_GEAR = "',
    'INVTYPE_BAG = "',
}) do
    assertNotContains(bags, unverifiedEquipSlot,
        "slots with no verified paper-doll frame must fall back to the parent icon, not a guess")
end
-- Aliased INVTYPEs (ROBE, SHIELD, HOLDABLE, RANGEDRIGHT, THROWN) are
-- substituted to their canonical target before childKey/childIcon lookup,
-- so they must never appear as their own INV_TYPE_TO_SLOT entry (the
-- exhaustive 19-pair whitelist above already excludes them; equipmentSlotAliases
-- itself legitimately contains "INVTYPE_ROBE = \"INVTYPE_CHEST\"" and similar,
-- so a substring check here would collide with that unrelated table).
assertCount(bags, "INVTYPE_ROBE = ", 1,
    "INVTYPE_ROBE appears only in equipmentSlotAliases, never as its own slot-art entry")
assertCount(bags, "INVTYPE_SHIELD = ", 1,
    "INVTYPE_SHIELD appears only in equipmentSlotAliases, never as its own slot-art entry")
assertCount(bags, "INVTYPE_HOLDABLE = ", 1,
    "INVTYPE_HOLDABLE appears only in equipmentSlotAliases, never as its own slot-art entry")
assertCount(bags, "INVTYPE_RANGEDRIGHT = ", 1,
    "INVTYPE_RANGEDRIGHT appears only in equipmentSlotAliases, never as its own slot-art entry")
assertCount(bags, "INVTYPE_THROWN = ", 1,
    "INVTYPE_THROWN appears only in equipmentSlotAliases, never as its own slot-art entry")
assertContains(bags,
    "local getInventorySlotInfo = (_G.C_PaperDollInfo and _G.C_PaperDollInfo.GetInventorySlotInfo)",
    "the 12.1.0.68914 C_PaperDollInfo namespace is preferred when present")
assertContains(bags,
    "or _G.GetInventorySlotInfo",
    "the 12.0.7.68887 bare global is the fallback when the namespace is absent")
assertContains(bags,
    "for invType, slotName in next, INV_TYPE_TO_SLOT do",
    "slot art is resolved once per rendered INVTYPE at load time")
assertContains(bags,
    "local _, textureName = getInventorySlotInfo(slotName)",
    "GetInventorySlotInfo's second return is the slot's texture, per its verified contract")
assertContains(bags,
    "equipmentSlotOrder.categoryIconByEquipLoc[invType] = {texture = textureName}",
    "resolved slot art is stored as a texture-shaped icon table")

-- GetCategory computes and caches childIcon as an eighth cache-tuple slot;
-- every read site (the cache hit early-return) and both write sites (the
-- table constructor and the fresh-computation return) must agree on the
-- new arity, or a cached lookup silently drops the icon.
assertContains(bags,
    "return cached[1], cached[2], cached[3], cached[4], cached[5], cached[6], cached[7], cached[8]",
    "the cache-hit path returns all eight GetCategory values, including childIcon")
assertContains(bags, "    local childIcon\n",
    "GetCategory declares childIcon alongside the other per-item fields")
assertContains(bags,
    "childIcon = equipmentSlotOrder.categoryIconByEquipLoc[itemEquipLoc]",
    "the equipment path resolves childIcon from the post-alias INVTYPE")
assertContains(bags,
    "local subclassIcons = categoryOrderByClass.categoryIconBySubclass\n"
        .. "            and categoryOrderByClass.categoryIconBySubclass[classID]",
    "the class path guards the two-level subclass lookup by table presence, " ..
    "then by classID")
assertContains(bags,
    'if _G.Enum.ItemConsumableSubclass then',
    "the subclass icon map itself is nil-guarded like ITEM_CLASS.Housing " ..
    "for clients/environments lacking the enum entirely")
assertContains(bags,
    "childIcon = subclassIcons and subclassIcons[subclassID] or nil",
    "classes without a subclass icon table (or subclass) fall back to nil, " ..
    "not an index-nil error")
assertContains(bags,
    "childKey,\n        childLabel,\n        childOrder,\n        childIcon,\n    }",
    "the cache table constructor stores childIcon as its eighth field")
assertContains(bags,
    "return parentKey, parentLabel, parentOrder, parentIcon, childKey, childLabel, childOrder, childIcon",
    "the fresh-computation return also carries the new eighth childIcon value")
assertContains(bags,
    "childKey, childLabel, childOrder, childIcon = GetCategory(itemID)",
    "AddItemToCategoryGroups destructures the new eighth childIcon return")
assertContains(bags,
    "local child = AcquireCategoryGroup(\n        childKey,\n        childLabel,\n        childOrder,\n        childIcon,\n        parent\n    )",
    "AddItemToCategoryGroups passes childIcon as the child group's icon parameter")

-- BuildSidebarModel child nodes fall back from an explicit child icon to
-- the parent group's icon, so every collapsed-rail row still shows
-- something even for subclasses/slots with no distinct icon (e.g. the
-- consumable "Other" subclass falls back to the Consumables parent atlas).
assertContains(bags, "icon = child.icon or group.icon,",
    "child nodes fall back explicit child icon -> parent icon -> " ..
    "the AF widget's fallbackIcon")

-- Baseline-height layout model (Task 5): frame-scale shrink-to-fit is gone
-- entirely. This pattern was already removed twice before (cc5b545,
-- baa7b82); the maintenance comments guard against a third reintroduction.
assertNotContains(bags, "SetScale(layoutScale)",
    "the frame must never scale itself to fit the screen")
assertNotContains(bags, "layoutScale = math.min",
    "the screen-fit scale calculation is removed, not just its application")
assertNotContains(bags, "local layoutScale",
    "the layoutScale local itself is removed")
assertContains(bags, "cc5b545",
    "a maintenance comment cites the first removed shrink-to-fit commit")
assertContains(bags, "baa7b82",
    "a maintenance comment cites the second removed shrink-to-fit commit")

-- Combined's natural metrics are the baseline every other view measures
-- against, recomputed fresh on every layout pass (never cached).
assertContains(bags,
    "local baselineColumns, baselineWidth, baselineHeight = CalculateFlatLayoutMetrics(",
    "the baseline is computed unconditionally after BuildSidebarModel")
assertContains(bags, "#flatGroup.items,",
    "the baseline uses flatGroup's always-populated item count")

-- Category filters render at baselineColumns/baselineWidth/baselineHeight
-- exactly, not a fresh computation over the filtered subset -- so every
-- category selection stays pixel-identical to Combined.
assertContains(bags, "width, height = baselineWidth, baselineHeight",
    "category and Combined both render at the baseline frame size exactly")
assertContains(bags, "BuildFlatLayoutEntries(baselineColumns, spacing, top, contentInset, group)",
    "category and Combined both lay out at baselineColumns, not requestedColumns")

-- Individual grows from the baseline and shrinks back to it automatically
-- (the recompute is per-pass, so nothing needs to be reset on view switch).
assertContains(bags, "height = math.max(height, baselineHeight)",
    "Individual metrics below baseline height are raised to baselineHeight")
assertContains(bags, "width = math.max(width, baselineWidth)",
    "Individual metrics below baseline width are raised to baselineWidth")

print("bags_view_modes_test.lua: ok")
