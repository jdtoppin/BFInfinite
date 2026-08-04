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
assertContains(defaults, "sidebarAutoHide = false",
    "sidebar labels are pinned open by default")
assertContains(defaults, 'if type(config.sidebarAutoHide) ~= "boolean" then',
    "saved auto-hide state is normalized")
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
assertContains(bags, 'AF.RegisterCallback("BFI_UpdateProfile", function()',
    "profile changes reset transient sidebar navigation")
assertContains(bags, "activeCategoryKey = nil",
    "a new profile is not overridden by the previous category filter")
assertContains(bags, "B.Sidebar.SetAutoHide(B.config.sidebarAutoHide)",
    "profile and layout refreshes synchronize persisted auto-hide state")
assertContains(bags, "B.Sidebar.SetOnAutoHideChanged(function(enabled)",
    "the header toggle publishes user auto-hide changes")
assertContains(bags, "B.config.sidebarAutoHide = enabled",
    "user auto-hide changes persist in the active bag profile")
assertContains(bags,
    "B.config.sidebarAutoHide = enabled\n        LayoutItems(true)",
    "changing reserved sidebar width forces an item relayout")
assertContains(bags,
    "or B.config.sidebarAutoHide ~= snapshotSidebarAutoHide",
    "auto-hide width participates in the layout snapshot")
assertContains(bags,
    "snapshotSidebarAutoHide = B.config.sidebarAutoHide",
    "captured layouts retain their auto-hide width state")

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

-- Narrow category filters retain a useful navigation viewport. The rail is
-- right-anchored so hover expansion grows left into the pinned rail's space.
assertContains(bags, "local SIDEBAR_MIN_HEIGHT = 320",
    "narrow category results retain a useful minimum bag height")
assertContains(bags, "function B.GetMinimumFrameHeight(maxFrameHeight, footerHeight)",
    "flat and individual layouts share one screen-capped minimum")
assertContains(bags,
    "return math.min(maxFrameHeight, SIDEBAR_TOP + SIDEBAR_MIN_HEIGHT + footerHeight)",
    "the minimum remains footer-aware and screen-capped")
assertCount(bags, "B.GetMinimumFrameHeight(maxFrameHeight, footerHeight)", 3,
    "the minimum helper must be defined and used by both layout paths")
assertContains(bags,
    "local sidebarRight = HORIZONTAL_PADDING + B.Sidebar.GetDesiredWidth()",
    "the rail's fixed right edge follows its reserved pinned or compact width")
assertContains(bags,
    'bagSidebar:SetPoint("TOPRIGHT", combinedFrame, "TOPLEFT", sidebarRight, -SIDEBAR_TOP)',
    "the rail expands left from its top-right anchor")
assertContains(bags,
    'bagSidebar:SetPoint("BOTTOMRIGHT", combinedFrame, "BOTTOMLEFT", sidebarRight, footerHeight)',
    "the rail expands left from its bottom-right anchor")
assertNotContains(bags,
    'bagSidebar:SetPoint("TOPLEFT", combinedFrame, "TOPLEFT"',
    "hover expansion must not grow right across bag items")

-- The reserved compact rail keeps item layout stable while a right-anchored
-- presentation proxy grows the full styled bag shell left with the hover rail.
assertContains(bags,
    'local visualShell = _G.CreateFrame("Frame", nil, combinedFrame)',
    "auto-hide expansion must use a template-free visual shell")
assertContains(bags,
    'visualShell:SetPoint("TOPRIGHT", combinedFrame, "TOPRIGHT")',
    "the visual shell must preserve the bag window's right edge")
assertContains(bags,
    'visualShell:SetPoint("BOTTOMRIGHT", combinedFrame, "BOTTOMRIGHT")',
    "the visual shell must span the full bag window height")
assertContains(bags,
    "combinedFrame:GetWidth() + (self.sidebarExtension or 0)",
    "the shell must add only transient rail width to the container width")
assertContains(bags,
    "self.sidebarExtension = math.max(0, width - reservedWidth)",
    "the shell must exclude the sidebar width already reserved by layout")
assertContains(bags,
    "combinedFrame.BFIBg:SetAllPoints(visualShell)",
    "the full lightweight background must expand with the hover rail")
assertContains(bags,
    'combinedFrame.BFIHeader:SetPoint("TOPLEFT", visualShell, "TOPLEFT")',
    "the title strip must expand left with the visual shell")
assertContains(bags,
    'combinedFrame.BFIHeader:SetPoint("TOPRIGHT", visualShell, "TOPRIGHT")',
    "the title strip must retain the bag window's right edge")
assertContains(bags,
    'combinedFrame:HookScript("OnSizeChanged", function()',
    "the visual shell must follow later Blizzard container resizes")
assertContains(bags,
    "B.Sidebar.SetOnPresentationWidthChanged(function(width, reservedWidth)",
    "the sidebar must publish animated width changes to the visual shell")
assertContains(bags,
    "visualShell:SetSidebarPresentationWidth(width, reservedWidth)",
    "the presentation callback must resize the complete styled shell")
assertContains(bags,
    "local function OnCombinedFrameShow()\n    if not IsEnabled() then return end\n    B.Sidebar.SetShown(true)",
    "showing the bag window must restore sidebar presentation updates")
assertContains(bags,
    "local function OnCombinedFrameHide()\n    B.Sidebar.SetShown(false)",
    "hiding the bag window must settle and hide the sidebar presentation")

-- Auto-hide is a header action beside the other bag controls. Its arrow
-- communicates the next action rather than using the old lock metaphor.
assertContains(bags,
    'local sidebarButton = AF.CreateButton(combinedFrame, nil, "gray", 24, 22)',
    "auto-hide uses the same header button treatment as bag controls")
assertContains(bags,
    'self:SetTexture(AF.GetIcon(autoHide and "ArrowLeft1" or "ArrowRight1"))',
    "the header uses AF arrows that follow the action available from the current state")
assertContains(bags,
    'self:SetTooltip(autoHide and L["Keep Sidebar Open"] or L["Auto Hide Sidebar"])',
    "the header toggle explains its current action")
assertContains(bags,
    'searchBox:SetPoint("TOPLEFT", sidebarButton, "TOPRIGHT", 3, 0)',
    "the auto-hide toggle sits immediately left of search")
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

assertContains(bags,
    '[ITEM_CLASS.Tradegoods] = "Bag_TradeGoods"',
    "trade-skill goods retain the crossed-tools icon")
assertContains(bags,
    '[ITEM_CLASS.Reagent] = "Bag_Reagent"',
    "reagents use the distinct flask icon")
assertNotContains(bags,
    '[ITEM_CLASS.Reagent] = "Bag_TradeGoods"',
    "reagents must not share the trade-skill goods icon")
assertContains(bags,
    "if ITEM_CLASS.Housing then",
    "housing class support must remain compatible with clients lacking the enum")
assertContains(bags,
    'categoryIconByClass[ITEM_CLASS.Housing] = "Bag_Housing"',
    "housing items use a distinct furnishings icon")

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
assertContains(bags,
    "categoryOrderByClass.categoryIconBySubclass = {",
    "consumable subclass icons are keyed by classID then subclassID")
assertContains(bags,
    "[_G.Enum.ItemConsumableSubclass.Potion] = \"Bag_Potions\"",
    "potions use their own icon")
assertContains(bags,
    "[_G.Enum.ItemConsumableSubclass.Flasksphials] = \"Bag_Flasks\"",
    "flasks and phials use their own icon")
assertContains(bags,
    "[_G.Enum.ItemConsumableSubclass.Fooddrink] = \"Bag_Food\"",
    "food and drink use their own icon")
assertContains(bags,
    "[_G.Enum.ItemConsumableSubclass.Bandage] = \"Bag_Bandages\"",
    "bandages use their own icon")
assertContains(bags,
    "[_G.Enum.ItemConsumableSubclass.Elixir] = \"Bag_Elixirs\"",
    "elixirs use their own icon")
assertContains(bags,
    "equipmentSlotOrder.categoryIconByEquipLoc = {",
    "equipment slot icons are keyed by post-alias INVTYPE")
for _, equipSlotIcon in ipairs({
    'INVTYPE_HEAD = "Bag_Slot_Head"',
    'INVTYPE_NECK = "Bag_Slot_Neck"',
    'INVTYPE_SHOULDER = "Bag_Slot_Shoulder"',
    'INVTYPE_CLOAK = "Bag_Slot_Back"',
    'INVTYPE_CHEST = "Bag_Slot_Chest"',
    'INVTYPE_WRIST = "Bag_Slot_Wrist"',
    'INVTYPE_HAND = "Bag_Slot_Hands"',
    'INVTYPE_WAIST = "Bag_Slot_Waist"',
    'INVTYPE_LEGS = "Bag_Slot_Legs"',
    'INVTYPE_FEET = "Bag_Slot_Feet"',
    'INVTYPE_FINGER = "Bag_Slot_Finger"',
    'INVTYPE_TRINKET = "Bag_Slot_Trinket"',
    'INVTYPE_WEAPONMAINHAND = "Bag_Slot_MainHand"',
    'INVTYPE_WEAPONOFFHAND = "Bag_Slot_OffHand"',
    'INVTYPE_WEAPON = "Bag_Slot_OneHand"',
    'INVTYPE_2HWEAPON = "Bag_Slot_TwoHand"',
    'INVTYPE_RANGED = "Bag_Slot_Ranged"',
    'INVTYPE_BODY = "Bag_Slot_Shirt"',
    'INVTYPE_TABARD = "Bag_Slot_Tabard"',
    'INVTYPE_PROFESSION_TOOL = "Bag_Slot_ProfessionTool"',
    'INVTYPE_PROFESSION_GEAR = "Bag_Slot_ProfessionGear"',
    'INVTYPE_BAG = "Bag_Slot_Bag"',
}) do
    assertContains(bags, equipSlotIcon,
        "every rendered equipment slot maps to its Task 1 Bag_Slot_* icon")
end
-- Aliased INVTYPEs (ROBE, SHIELD, HOLDABLE, RANGEDRIGHT, THROWN) are
-- substituted to their canonical target before childKey/childIcon lookup,
-- so they must never appear as separate icon-map keys of their own.
for _, aliasedEquipSlotIcon in ipairs({
    "INVTYPE_ROBE = \"Bag_Slot_",
    "INVTYPE_SHIELD = \"Bag_Slot_",
    "INVTYPE_HOLDABLE = \"Bag_Slot_",
    "INVTYPE_RANGEDRIGHT = \"Bag_Slot_",
    "INVTYPE_THROWN = \"Bag_Slot_",
}) do
    assertNotContains(bags, aliasedEquipSlotIcon,
        "aliased INVTYPEs must not get their own icon-map entry; " ..
        "they resolve through equipmentSlotAliases to a canonical slot")
end

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
-- something even for subclasses/slots with no distinct glyph (e.g. the
-- consumable "Other" subclass falls back to Bag_Consumables).
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
