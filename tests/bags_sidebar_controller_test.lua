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
    "function Sidebar.SetMode(",
    "function Sidebar.SetEntries(",
    "function Sidebar.SetSelection(",
    "function Sidebar.SetOnSelected(",
    "function Sidebar.GetDesiredWidth(",
    "function Sidebar.GetContentInset(",
}) do
    assertContains(source, api, "sidebar integration API")
end

assertContains(
    source,
    'mode == "combined" and 0 or DESIRED_WIDTH + CONTENT_GAP',
    "combined mode must not reserve hidden rail space"
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
    "category buttons must be pooled"
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
    "row.icon:SetTexture(AF.GetIcon(FALLBACK_ICON_BY_MODE[mode]))",
    "older AF versions must retain a safe generic icon"
)
assertContains(
    source,
    "AF.SetWidth(row.indicator, 1)",
    "idle rows must retain the options-style one-pixel class marker"
)
assertContains(
    source,
    "and not entriesById[selectionByMode[mode]] then",
    "removed entries must silently clear stale selection"
)

for _, forbidden in ipairs({
    "BackdropTemplate",
    "NineSlice",
    "OnUpdate",
    "AF.CreateButton(",
    "AF.CreateButtonGroup(",
    "InCombatLockdown",
    "PLAYER_REGEN_ENABLED",
}) do
    assertNotContains(
        source,
        forbidden,
        "sidebar must stay on the lightweight event-driven path"
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
assertEqual(bags.Sidebar.GetContentInset(), 0, "combined content inset")
assertEqual(bags.Sidebar.SetMode("invalid"), false, "invalid mode rejected")
assertEqual(bags.Sidebar.SetMode("categories"), true, "category mode accepted")
assertEqual(bags.Sidebar.GetContentInset(), 178, "category content inset")

local callbackCalls = 0
assertEqual(bags.Sidebar.SetOnSelected(function()
    callbackCalls = callbackCalls + 1
end), true, "selected callback accepted")
bags.Sidebar.SetEntries({
    {id = "equipment", label = "Equipment", icon = "Bag_Equipment"},
})
assertEqual(bags.Sidebar.SetSelection("equipment"), true,
    "known selection accepted")
assertEqual(callbackCalls, 0, "programmatic selection is silent")

bags.Sidebar.SetEntries({})
assertEqual(bags.Sidebar.SetSelection("equipment"), false,
    "removed selection is no longer accepted")
assertEqual(callbackCalls, 0, "entry removal is silent")
assertEqual(bags.Sidebar.SetMode("individual"), true,
    "individual mode accepted")
assertEqual(bags.Sidebar.GetContentInset(), 178, "individual content inset")

print("bags_sidebar_controller_test.lua: ok")
