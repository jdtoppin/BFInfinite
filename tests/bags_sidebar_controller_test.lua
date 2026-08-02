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
        error(message .. ": missing " .. text, 2)
    end
end

local function assertNotContains(contents, text, message)
    if contents:find(text, 1, true) then
        error(message .. ": found " .. text, 2)
    end
end

local function assertBefore(contents, first, second, message)
    local firstAt = contents:find(first, 1, true)
    local secondAt = contents:find(second, 1, true)
    if not firstAt or not secondAt or firstAt >= secondAt then
        error(message, 2)
    end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local source = readFile("Modules/Bags/Sidebar.lua")
local loadOrder = readFile("Modules/Bags/Load.xml")

for _, icon in ipairs({
    "Bag_All",
    "Bag_Equipment",
    "Bag_Consumables",
    "Bag_TradeGoods",
    "Bag_Recipes",
    "Bag_Quest",
    "Bag_Misc",
    "Bag_Empty",
    "Bag_Backpack",
    "Bag_Reagent",
    "Bag_IndividualBags",
}) do
    assertContains(source, icon, "sidebar adaptive icon allowlist")
end

for _, api in ipairs({
    "function Sidebar.Initialize(",
    "function Sidebar.SetModel(",
    "function Sidebar.SetSelection(",
    "function Sidebar.SetExpanded(",
    "function Sidebar.ToggleExpanded(",
    "function Sidebar.SetShown(",
    "function Sidebar.SetOnSelected(",
    "function Sidebar.GetDesiredWidth(",
    "function Sidebar.GetContentInset(",
}) do
    assertContains(source, api, "sidebar integration API")
end

assertContains(
    source,
    "return DESIRED_WIDTH + CONTENT_GAP",
    "every enabled bag view must reserve the persistent rail"
)
assertContains(
    source,
    'local row = _G.CreateFrame("Button", nil, scrollContent)',
    "pooled rows must use template-free buttons"
)
assertContains(
    source,
    'scrollFrame = _G.CreateFrame("ScrollFrame", nil, rail)',
    "many category rows must use a clipped scroll frame"
)
assertContains(
    source,
    "local function AcquireRow(index)",
    "hierarchical rows must be pooled"
)
assertContains(
    source,
    'source.kind == "heading"',
    "the permanent model must support separate section headings"
)
assertContains(
    source,
    "entry.children",
    "the permanent model must support nested category children"
)
assertContains(
    source,
    "expandedById[entry.id]",
    "expanded parents must reveal their nested children"
)
assertContains(
    source,
    'row.toggle:SetScript("OnClick"',
    "parent expansion must have an independent chevron target"
)
assertContains(
    source,
    "local function IsSelectedRow(row)",
    "collapsed parents must surface an active child selection"
)
assertContains(
    source,
    "if selected.parentId == row.id then",
    "active descendants must highlight their collapsed parent"
)
assertContains(
    source,
    'and "ArrowDown1" or "ArrowRight1"',
    "chevrons must communicate expanded state"
)
assertContains(
    source,
    "row.highlight:SetColorTexture(1, 1, 1, 0.11)",
    "selected rows must use a subtle neutral full-row treatment"
)
assertContains(
    source,
    "if AF.hasBagIcons and AF.SetAdaptiveIcon then",
    "row icons must use AF's adaptive icon helper"
)
assertContains(
    source,
    "AF.SetAdaptiveIcon(row.icon, entry.icon)",
    "available bag icons must use AF's adaptive icon helper"
)
assertContains(
    source,
    'row.icon:SetTexture(AF.GetIcon("Menu4"))',
    "older AF versions must retain a safe generic icon"
)
assertContains(
    source,
    "if selectionId ~= nil and not entriesById[selectionId] then",
    "removed entries must silently clear stale selection"
)
assertNotContains(
    source,
    "expandedById = nextExpandedById",
    "temporarily absent category parents must retain expansion state"
)

for _, forbidden in ipairs({
    "BackdropTemplate",
    "NineSlice",
    "OnUpdate",
    "CreateGradientTexture",
    "row.indicator",
    "AF.CreateButton(",
    "AF.CreateButtonGroup(",
    "InCombatLockdown",
    "PLAYER_REGEN_ENABLED",
}) do
    assertNotContains(
        source,
        forbidden,
        "sidebar must stay on the lightweight neutral event-driven path"
    )
end

assertBefore(
    loadOrder,
    '<Script file="Sidebar.lua"/>',
    '<Script file="Bags.lua"/>',
    "sidebar controller must load before its Bags.lua integrator"
)

local bags = {}
local environment = {
    AbstractFramework = {},
    math = math,
    pairs = pairs,
    select = select,
    type = type,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local chunk, loadError = loadfile("Modules/Bags/Sidebar.lua")
assertEqual(type(chunk), "function", loadError or "sidebar module load")
setfenv(chunk, environment)
chunk("BFInfinite", {
    modules = {
        Bags = bags,
    },
})

assertEqual(bags.Sidebar.GetDesiredWidth(), 170, "rail desired width")
assertEqual(bags.Sidebar.GetContentInset(), 178, "persistent content inset")
assertEqual(bags.Sidebar.SetShown("yes"), false, "non-boolean shown state rejected")
assertEqual(bags.Sidebar.SetShown(false), true, "rail can be explicitly disabled")
assertEqual(bags.Sidebar.SetShown(true), true, "rail can be explicitly enabled")

local callbackCalls = 0
assertEqual(bags.Sidebar.SetOnSelected(function()
    callbackCalls = callbackCalls + 1
end), true, "selected callback accepted")
assertEqual(bags.Sidebar.SetModel({
    {kind = "heading", label = "Views"},
    {id = "combined", label = "Combined View", icon = "Bag_All"},
    {id = "individual", label = "Individual Bags", icon = "Bag_IndividualBags"},
    {kind = "heading", label = "Categories"},
    {
        id = "equipment",
        label = "Equipment",
        icon = "Bag_Equipment",
        expanded = true,
        children = {
            {id = "equipment:chest", label = "Chest"},
            {id = "equipment:gloves", label = "Gloves"},
        },
    },
}), true, "hierarchical model accepted")
assertEqual(bags.Sidebar.SetSelection("equipment"), true,
    "aggregate parent selection accepted")
assertEqual(bags.Sidebar.SetSelection("equipment:chest"), true,
    "nested short-label selection accepted")
assertEqual(callbackCalls, 0, "programmatic selection is silent")
assertEqual(bags.Sidebar.SetExpanded("equipment", false), true,
    "known parent can collapse")
assertEqual(bags.Sidebar.ToggleExpanded("equipment"), true,
    "known parent can toggle")
assertEqual(bags.Sidebar.SetExpanded("combined", false), false,
    "leaf expansion rejected")
assertEqual(bags.Sidebar.SetSelection("missing"), false,
    "unknown selection rejected")

assertEqual(bags.Sidebar.SetModel({}), true, "model can be cleared")
assertEqual(bags.Sidebar.SetSelection("equipment"), false,
    "removed selection is no longer accepted")
assertEqual(callbackCalls, 0, "entry removal is silent")

print("bags_sidebar_controller_test.lua: ok")
