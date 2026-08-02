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
assertContains(sidebar, "return DESIRED_WIDTH + CONTENT_GAP",
    "the sidebar inset does not depend on selected view")

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
