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
    "Bag_Housing",
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
    "function Sidebar.SetAutoHide(",
    "function Sidebar.GetAutoHide(",
    "function Sidebar.ToggleAutoHide(",
    "function Sidebar.SetOnSelected(",
    "function Sidebar.SetOnAutoHideChanged(",
    "function Sidebar.GetDesiredWidth(",
    "function Sidebar.GetContentInset(",
}) do
    assertContains(source, api, "sidebar integration API")
end

assertContains(
    source,
    "local COLLAPSED_WIDTH = 40",
    "auto-hide must retain a compact icon rail"
)
assertContains(
    source,
    "return autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH",
    "the reserved rail width must follow the persisted auto-hide state"
)
assertContains(
    source,
    "return Sidebar.GetDesiredWidth() + CONTENT_GAP",
    "the item inset must include the current rail width and content gap"
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
    "parents must surface an active child selection"
)
assertContains(
    source,
    "if IsNestedTreeShown() and expandedById[row.id] then return false end",
    "expanded labeled parents leave the active treatment on their visible child"
)
assertContains(
    source,
    "while selected and selected.parentId do",
    "compact and collapsed parents must walk the active child's ancestry"
)
assertContains(
    source,
    "if selected.parentId == row.id then",
    "active descendants must highlight their compact or collapsed parent"
)
assertContains(
    source,
    'and "ArrowDown1" or "ArrowRight1"',
    "chevrons must communicate expanded state"
)
assertContains(
    source,
    "row.highlight = AF.CreateGradientTexture(",
    "rows must use the main BFI navigation accent gradient"
)
assertContains(
    source,
    'AF.GetColorTable("BFI", 0.9)',
    "the navigation gradient must use the BFI accent color"
)
assertContains(
    source,
    'local targetWidth = state == "selected" and DESIRED_WIDTH',
    "active rows must fill the labeled navigation width"
)
assertContains(
    source,
    'or state == "hover" and 7',
    "hovered rows must use the main menu's narrow accent treatment"
)
assertContains(
    source,
    'local shouldShow = state ~= "idle"',
    "idle rows must not retain a left accent line"
)
assertContains(
    source,
    "AF.AnimatedResize(",
    "hover and active navigation changes must animate like the main BFI menu"
)
assertContains(
    source,
    "if AF.hasBagIcons and AF.SetAdaptiveIcon then",
    "row icons must use AF's adaptive icon helper"
)
assertContains(
    source,
    "AF.SetAdaptiveIcon(row.icon, icon)",
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

assertContains(
    source,
    'scrollFrame:SetPoint("TOPLEFT")',
    "the scrolling view/category list must use the rail's full height"
)
for _, removedUtilityContract in ipairs({
    "CreateAutoHideControl",
    "autoHideClip",
    "autoHideButton",
    "UTILITY_HEIGHT",
    "UTILITY_GAP",
    'local icon = autoHide and "Unlock" or "Lock"',
}) do
    assertNotContains(
        source,
        removedUtilityContract,
        "auto-hide belongs in the bag header rather than the navigation rail"
    )
end

assertContains(
    source,
    "local function IsNestedTreeShown()",
    "auto-hide must distinguish its stable top-level view from an opened tree"
)
assertContains(
    source,
    "if entry.hasChildren and IsNestedTreeShown() and expandedById[entry.id] then",
    "nested children must stay closed until the labeled tree is explicitly opened"
)
assertContains(
    source,
    "row.label:SetShown(not compact)",
    "compact mode must hide navigation labels"
)
assertContains(
    source,
    "row.label:SetShown(not IsCompact())",
    "compact mode must hide section headings"
)
assertContains(
    source,
    "if entry.hasChildren and not compact then",
    "compact mode must hide nested expansion targets"
)

assertContains(
    source,
    'scrollBar = _G.CreateFrame("Slider", nil, rail)',
    "overflow navigation must use a template-free native slider"
)
assertContains(
    source,
    'scrollBar:SetOrientation("VERTICAL")',
    "the overflow control must be a vertical scrollbar"
)
assertContains(
    source,
    "scrollBar:SetThumbTexture(scrollThumb)",
    "the sidebar scrollbar must expose a draggable thumb"
)
assertContains(
    source,
    "AF.SetFrameLevel(scrollBar, 10, scrollContent)",
    "the scrollbar must remain above pooled navigation rows for hit testing"
)
assertContains(
    source,
    'row.toggle:SetPoint("RIGHT", -(SCROLLBAR_WIDTH + 2), 0)',
    "nested chevrons must not overlap the visible scrollbar"
)
assertContains(
    source,
    "AF.CreateFadeInOutAnimation(scrollBar, 0.18)",
    "the scrollbar must use the shared fade animation"
)
assertContains(
    source,
    "local needed = range > 0",
    "the scrollbar must only be required when content overflows"
)
assertContains(
    source,
    "if needed == scrollBarNeeded then return end",
    "unchanged overflow state must not restart the fade animation"
)
assertContains(source, "scrollBar:FadeIn()",
    "overflow must reveal the scrollbar")
assertContains(source, "scrollBar:FadeOut()",
    "resolved overflow must fade the scrollbar away")
assertContains(
    source,
    "expandedScrollOffset = offset",
    "expanded navigation must preserve its own scroll offset"
)
assertContains(
    source,
    "compactScrollOffset = offset",
    "the icon rail must preserve an independent useful scroll offset"
)
assertContains(
    source,
    "expandedScrollOffset = compactScrollOffset",
    "hover expansion must keep the icon under the pointer stable"
)
assertContains(
    source,
    "showNestedEntries = false",
    "automatic collapse must return to a compact top-level category list"
)

assertContains(
    source,
    "local function IsRailMouseOver()",
    "auto-hide collapse must share one pointer-boundary check"
)
assertContains(
    source,
    "_G.C_Timer.After(0, function()",
    "pointer exit must defer collapse until child enter events settle"
)
assertContains(
    source,
    "if generation ~= leaveGeneration then return end",
    "a newer pointer transition must cancel a stale deferred collapse"
)
assertContains(
    source,
    "if scrollBarDragging or IsRailMouseOver() then return end",
    "the rail must remain expanded while hovered or dragging its scrollbar"
)

for _, forbidden in ipairs({
    "BackdropTemplate",
    "NineSlice",
    "OnUpdate",
    "row.indicator",
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

assertNotContains(
    source,
    "row.highlight:SetColorTexture",
    "rows must not fall back to the lost neutral hover/active treatment"
)

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
    L = {},
    modules = {
        Bags = bags,
    },
})

assertEqual(bags.Sidebar.GetDesiredWidth(), 170, "rail desired width")
assertEqual(bags.Sidebar.GetContentInset(), 178, "persistent content inset")
assertEqual(bags.Sidebar.GetAutoHide(), false, "auto-hide is initially disabled")
assertEqual(bags.Sidebar.SetAutoHide("yes"), false,
    "non-boolean auto-hide state rejected")

local autoHideCalls = {}
assertEqual(bags.Sidebar.SetOnAutoHideChanged("yes"), false,
    "non-function auto-hide callback rejected")
assertEqual(bags.Sidebar.SetOnAutoHideChanged(function(enabled)
    autoHideCalls[#autoHideCalls + 1] = enabled
end), true, "auto-hide callback accepted")
assertEqual(bags.Sidebar.SetAutoHide(true), true,
    "auto-hide can be enabled programmatically")
assertEqual(bags.Sidebar.GetAutoHide(), true, "auto-hide state is queryable")
assertEqual(bags.Sidebar.GetDesiredWidth(), 40, "compact rail desired width")
assertEqual(bags.Sidebar.GetContentInset(), 48, "compact content inset")
assertEqual(#autoHideCalls, 0,
    "programmatic auto-hide synchronization is silent")
assertEqual(bags.Sidebar.SetAutoHide(true), true,
    "reapplying the current auto-hide state is accepted")
assertEqual(#autoHideCalls, 0,
    "idempotent auto-hide synchronization stays silent")
assertEqual(bags.Sidebar.ToggleAutoHide(), false,
    "header toggle can pin the labeled rail open")
assertEqual(autoHideCalls[1], false,
    "header toggle reports the disabled auto-hide state")
assertEqual(bags.Sidebar.GetDesiredWidth(), 170,
    "pinned rail restores its full desired width")
assertEqual(bags.Sidebar.GetContentInset(), 178,
    "pinned rail restores its full content inset")
assertEqual(bags.Sidebar.ToggleAutoHide(), true,
    "header toggle can restore compact auto-hide")
assertEqual(autoHideCalls[2], true,
    "header toggle reports the enabled auto-hide state")
assertEqual(bags.Sidebar.SetAutoHide(false), true,
    "profile synchronization can restore pinned mode")
assertEqual(#autoHideCalls, 2,
    "programmatic profile synchronization does not emit a header callback")
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
