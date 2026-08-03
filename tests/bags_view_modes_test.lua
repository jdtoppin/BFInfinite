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
assertContains(sidebar, 'scrollFrame:SetPoint("TOPLEFT")',
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

print("bags_view_modes_test.lua: ok")
