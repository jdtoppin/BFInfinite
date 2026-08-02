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

local bags = readFile("Modules/Bags/Bags.lua")
local defaults = readFile("Modules/Bags/Defaults.lua")
local options = readFile("Options/Bags.lua")
local style = readFile("Modules/Style/Style.lua")

for _, mode in ipairs({"combined", "categories", "individual"}) do
    assertContains(bags, '"' .. mode .. '"', "bag view mode")
end

assertContains(defaults, 'viewMode = "combined"', "default bag view")
assertContains(defaults, 'config.categories == true and "categories"',
    "legacy category preference migration")
assertContains(options, "AF.CreateDropdown(appearancePane, 165)",
    "bag view selector")
assertContains(options, '{text = L["Individual Bags View"], value = "individual"}',
    "individual bag option")

assertContains(bags, "B.Sidebar.SetMode(viewMode)",
    "layout drives the sidebar mode")
assertContains(bags, "ResolveCategorySelection(groupCount)",
    "category mode resolves one selected group")
assertContains(bags, "bagID == activeBagID",
    "individual mode filters pooled buttons by bag")
assertContains(bags, "BuildFlatLayoutEntries(columns, spacing, top, contentInset, group)",
    "every mode lays out only its selected flat group")
assertNotContains(bags, "BuildCategoryLayoutEntries",
    "the former all-category shelf layout is removed")

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

print("bags_view_modes_test.lua: ok")
