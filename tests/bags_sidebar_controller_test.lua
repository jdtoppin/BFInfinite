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
    "function Sidebar.SetOnPresentationWidthChanged(",
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
    "local hasChildren = entry and entry.hasChildren",
    "the full parent row must recognize expandable categories"
)
assertContains(
    source,
    "end\n\n    if hasChildren then\n        Sidebar.ToggleExpanded(id)",
    "a category title must toggle even when it is already selected"
)
assertBefore(
    source,
    "onSelected(id, entry)",
    "Sidebar.ToggleExpanded(id)",
    "a parent title click must select before it toggles the category"
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
    "local ROW_RIGHT_INSET = SCROLLBAR_WIDTH + 4",
    "navigation rows must reserve a dedicated scrollbar lane"
)
assertContains(
    source,
    "local COMPACT_ICON_AREA_WIDTH = COLLAPSED_WIDTH - ROW_RIGHT_INSET",
    "compact icons must be centered outside the scrollbar lane"
)
assertContains(
    source,
    "compact and ((COMPACT_ICON_AREA_WIDTH - ICON_SIZE) / 2)",
    "compact icons must remain clear of the visible scrollbar"
)
assertContains(
    source,
    'scrollBar:SetPoint("TOPRIGHT", rail, "TOPRIGHT")',
    "the scrollbar lane must stay beside the compact icon column"
)
assertContains(
    source,
    'scrollBar:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT")',
    "the scrollbar lane must span the rail beside its icons"
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
assertNotContains(
    source,
    "if needed == scrollBarNeeded then return end",
    "overflow geometry must keep updating after the transient thumb fades"
)
assertContains(
    source,
    "local SCROLLBAR_FADE_DELAY = 0.9",
    "overflow feedback must linger briefly after interaction"
)
assertContains(
    source,
    "local function ScheduleScrollBarFadeOut()",
    "visible overflow feedback must schedule a transient fade"
)
assertContains(
    source,
    "local generation = scrollBarFadeGeneration",
    "new scrollbar activity must invalidate stale fade timers"
)
assertContains(
    source,
    "_G.C_Timer.After(SCROLLBAR_FADE_DELAY, function()",
    "the transient scrollbar must use an event-driven delayed fade"
)
assertContains(
    source,
    "generation ~= scrollBarFadeGeneration",
    "stale scrollbar fade callbacks must be ignored"
)
assertContains(
    source,
    "or scrollBar:IsMouseOver() then",
    "the transient thumb must remain visible while directly hovered"
)
assertContains(
    source,
    "scrollBar:EnableMouse(false)",
    "a faded scrollbar must not retain invisible hit testing"
)
assertContains(
    source,
    "scrollBar:EnableMouse(true)",
    "revealing the scrollbar must restore drag hit testing"
)
assertContains(source, "scrollBar:FadeIn()",
    "overflow must reveal the scrollbar")
assertContains(source, "scrollBar:FadeOut()",
    "inactive or resolved overflow must fade the scrollbar away")
assertContains(
    source,
    "if scheduleFade ~= false then\n        ScheduleScrollBarFadeOut()",
    "revealed overflow must fade again after interaction ends"
)
assertContains(
    source,
    'scrollBar:SetScript("OnMouseDown", function()',
    "dragging the thumb must enter a persistent interaction state"
)
assertContains(
    source,
    "SetScrollBarDragging(true)",
    "thumb dragging must hold the transient scrollbar open"
)
assertContains(
    source,
    "SetScrollBarDragging(false)",
    "releasing the thumb must resume the transient fade"
)
assertContains(
    source,
    "local wasDragging = scrollBarDragging",
    "a hidden thumb must remember whether it interrupted a drag"
)
assertContains(
    source,
    "if wasDragging then\n            PointerLeave()",
    "overflow resolution during a drag must retry auto-hide collapse"
)
assertContains(
    source,
    "scrollBar:EnableMouseWheel(true)",
    "the dedicated scrollbar lane must accept wheel input"
)
assertContains(
    source,
    'scrollBar:SetScript("OnMouseWheel", function(_, delta)',
    "wheel input over the scrollbar lane must scroll the category list"
)
assertContains(
    source,
    "RevealScrollBar()\n    SetScroll(scrollFrame:GetVerticalScroll()",
    "wheel input must reveal the scrollbar before changing its offset"
)
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
    "local function AnimateExpandedChange(id, expanded)",
    "nested category changes must use a dedicated transition"
)
assertContains(
    source,
    "local oldRowsByKey = {}",
    "category transitions must reuse the existing pooled rows by identity"
)
assertContains(
    source,
    "row = AcquireRow(nextPoolIndex)",
    "category transitions must acquire only missing pooled rows"
)
assertContains(
    source,
    "local function PositionAnimatedRows(animation, progress)",
    "category transitions must smoothly interpolate row positions"
)
assertContains(
    source,
    "row:SetAlpha(alpha)",
    "category transitions must fade nested rows in and out"
)
assertContains(
    source,
    "fromAlpha = incoming and 0 or 1",
    "new nested rows must fade in from the parent branch"
)
assertContains(
    source,
    "local parent = oldLayout[entry.parentId]",
    "each incoming branch must animate from its own parent"
)
assertContains(
    source,
    "survivingParent = targetLayout[parentId]",
    "outgoing descendants must find their nearest surviving parent"
)
assertContains(
    source,
    "survivingParent.bottom + ROW_SPACING",
    "outgoing branches must converge on their own parent origin"
)
assertContains(
    source,
    "toAlpha = 0",
    "removed nested rows must fade out toward the parent branch"
)
assertContains(
    source,
    "AF.AnimatedResize(\n        scrollContent",
    "the shared timer animation must interpolate category content height"
)
assertContains(
    source,
    "if modelAnimation then return false end",
    "rapid category toggles must not corrupt an active pooled-row transition"
)
assertContains(
    source,
    "FinishModelAnimation = function()",
    "external model changes must be able to settle an active transition"
)
assertContains(
    source,
    "row:SetAlpha(1)",
    "normal pooled-row binding must clear transient animation alpha"
)
assertContains(
    source,
    "SetScroll(animation.targetOffset)",
    "chevron-only transitions must retain the user's category scroll position"
)

assertContains(
    source,
    "local function PublishPresentationWidth(width)",
    "rail presentation changes must be published to the bag shell"
)
assertContains(
    source,
    "onPresentationWidthChanged(\n            width,",
    "presentation callbacks must receive the animated rail width"
)
assertContains(
    source,
    "autoHide and COLLAPSED_WIDTH or DESIRED_WIDTH",
    "presentation callbacks must also report the reserved layout width"
)
assertContains(
    source,
    "function(width)\n            PublishPresentationWidth(width)",
    "each rail resize tick must drive the visible bag shell"
)
assertBefore(
    source,
    "StopResize(rail)\n\n    if not hoverExpanded then",
    "if presentationWidth >= DESIRED_WIDTH then return end",
    "re-entering before the first collapse tick must cancel the stale resize"
)
assertContains(
    source,
    "if scrollBarDragging or IsRailMouseOver() then\n                ExpandRail()",
    "a guarded collapse completion must reverse toward the open rail"
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
assertContains(
    source,
    "if shown == nextShown then return true end",
    "routine bag layouts must not interrupt hover or category animations"
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

local presentationCalls = {}
assertEqual(bags.Sidebar.SetOnPresentationWidthChanged("yes"), false,
    "non-function presentation callback rejected")
assertEqual(bags.Sidebar.SetOnPresentationWidthChanged(function(width, reservedWidth)
    presentationCalls[#presentationCalls + 1] = {width, reservedWidth}
end), true, "presentation callback accepted")
assertEqual(#presentationCalls, 1,
    "presentation callback immediately synchronizes the current rail")
assertEqual(presentationCalls[1][1], 170,
    "initial presentation width is the labeled rail width")
assertEqual(presentationCalls[1][2], 170,
    "initial reserved width is the labeled rail width")

local autoHideCalls = {}
assertEqual(bags.Sidebar.SetOnAutoHideChanged("yes"), false,
    "non-function auto-hide callback rejected")
assertEqual(bags.Sidebar.SetOnAutoHideChanged(function(enabled)
    autoHideCalls[#autoHideCalls + 1] = enabled
end), true, "auto-hide callback accepted")
assertEqual(bags.Sidebar.SetAutoHide(true), true,
    "auto-hide can be enabled programmatically")
assertEqual(presentationCalls[2][1], 40,
    "auto-hide publishes the compact presentation width")
assertEqual(presentationCalls[2][2], 40,
    "auto-hide publishes the compact reserved width")
assertEqual(bags.Sidebar.GetAutoHide(), true, "auto-hide state is queryable")
assertEqual(bags.Sidebar.GetDesiredWidth(), 40, "compact rail desired width")
assertEqual(bags.Sidebar.GetContentInset(), 48, "compact content inset")
assertEqual(#autoHideCalls, 0,
    "programmatic auto-hide synchronization is silent")
assertEqual(bags.Sidebar.SetAutoHide(true), true,
    "reapplying the current auto-hide state is accepted")
assertEqual(#presentationCalls, 2,
    "idempotent auto-hide state does not republish its width")
assertEqual(#autoHideCalls, 0,
    "idempotent auto-hide synchronization stays silent")
assertEqual(bags.Sidebar.ToggleAutoHide(), false,
    "header toggle can pin the labeled rail open")
assertEqual(presentationCalls[3][1], 170,
    "pinning the rail publishes the labeled presentation width")
assertEqual(presentationCalls[3][2], 170,
    "pinning the rail publishes the labeled reserved width")
assertEqual(autoHideCalls[1], false,
    "header toggle reports the disabled auto-hide state")
assertEqual(bags.Sidebar.GetDesiredWidth(), 170,
    "pinned rail restores its full desired width")
assertEqual(bags.Sidebar.GetContentInset(), 178,
    "pinned rail restores its full content inset")
assertEqual(bags.Sidebar.ToggleAutoHide(), true,
    "header toggle can restore compact auto-hide")
assertEqual(presentationCalls[4][1], 40,
    "restoring auto-hide republishes the compact presentation width")
assertEqual(presentationCalls[4][2], 40,
    "restoring auto-hide republishes the compact reserved width")
assertEqual(autoHideCalls[2], true,
    "header toggle reports the enabled auto-hide state")
assertEqual(bags.Sidebar.SetAutoHide(false), true,
    "profile synchronization can restore pinned mode")
assertEqual(presentationCalls[5][1], 170,
    "profile synchronization republishes the pinned presentation width")
assertEqual(presentationCalls[5][2], 170,
    "profile synchronization republishes the pinned reserved width")
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
