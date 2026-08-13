-- Consumer-contract tests for Modules/Bags/Sidebar.lua. As of the AF
-- CreateSidebarRail migration, all row/scroll/animation machinery lives in
-- AbstractFramework/Widgets/TreeList.lua and is covered by
-- AbstractFramework/tests/tree_list_test.lua. This file only covers what
-- Sidebar.lua itself is responsible for: the B.Sidebar.* API surface,
-- delegating to AF.CreateSidebarRail/rail.treeList, and pre-Initialize
-- buffering. Every model node BuildSidebarModel produces already carries an
-- explicit icon (see Modules/Bags/Bags.lua), and AF.CreateSidebarRail's
-- fallbackIcon option covers any iconless node, so Sidebar.lua has no
-- icon-by-id default logic of its own to test.

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

---------------------------------------------------------------------
-- source-level contracts
---------------------------------------------------------------------
local source = readFile("Modules/Bags/Sidebar.lua")
local loadOrder = readFile("Modules/Bags/Load.xml")

for _, api in ipairs({
    "function Sidebar.Initialize(",
    "function Sidebar.SetModel(",
    "function Sidebar.SetSelection(",
    "function Sidebar.SetExpanded(",
    "function Sidebar.ToggleExpanded(",
    "function Sidebar.SetShown(",
    "function Sidebar.SetCollapsed(",
    "function Sidebar.GetCollapsed(",
    "function Sidebar.ToggleCollapsed(",
    "function Sidebar.SetOnSelected(",
    "function Sidebar.SetOnCollapsedChanged(",
    "function Sidebar.SetOnPresentationWidthChanged(",
    "function Sidebar.GetDesiredWidth(",
    "function Sidebar.GetContentInset(",
}) do
    assertContains(source, api, "sidebar integration API")
end

assertContains(
    source,
    "AF.CreateSidebarRail(",
    "the sidebar must delegate widget construction to the shared AF rail"
)

assertNotContains(source, "AutoHide",
    "the sidebar controller uses the AF rail's manual collapse naming, not "
        .. "the removed auto-hide naming")

assertNotContains(source, "ICON_BY_ID",
    "sidebar has no icon-by-id default map; nodes carry explicit icons and "
        .. "the AF widget's fallbackIcon covers any iconless node")

for _, machineryRemnant in ipairs({
    'CreateFrame("ScrollFrame"',
    'CreateFrame("Slider"',
    "AnimateExpandedChange",
    "showNestedEntries",
    'SetScript("OnUpdate"',
}) do
    assertNotContains(
        source,
        machineryRemnant,
        "row/scroll/animation machinery now belongs to AF.CreateSidebarRail"
    )
end

assertBefore(
    loadOrder,
    '<Script file="Sidebar.lua"/>',
    '<Script file="Bags.lua"/>',
    "sidebar controller must load before its Bags.lua integrator"
)

---------------------------------------------------------------------
-- recording AF.CreateSidebarRail stub
---------------------------------------------------------------------
local railInstances = {}

local function makeRail(parent, options)
    local rail = {
        parent = parent,
        options = options,
        shown = true,
        collapsed = false,
        setParentCalls = 0,
        shownCalls = {},
        collapsedCalls = {},
        toggleCollapsedCalls = 0,
    }

    local treeList = {
        modelCalls = {},
        selectionCallCount = 0,
        expandedCalls = {},
        toggleCalls = {},
        nextSelectionReturn = true,
    }
    rail.treeList = treeList

    function treeList:SetModel(model)
        self.modelCalls[#self.modelCalls + 1] = model
        return true
    end

    -- id may legitimately be nil (a clear); track the last call with an
    -- explicit flag/count rather than an array (a trailing nil is invisible
    -- to the # operator)
    function treeList:SetSelection(id)
        self.selectionCallCount = self.selectionCallCount + 1
        self.lastSelectionId = id
        if id == nil then return false end
        return self.nextSelectionReturn
    end

    function treeList:SetExpanded(id, expanded)
        self.expandedCalls[#self.expandedCalls + 1] = {id, expanded}
        return true
    end

    function treeList:ToggleExpanded(id)
        self.toggleCalls[#self.toggleCalls + 1] = id
        return true
    end

    function treeList:SetOnSelected(callback)
        self.onSelected = callback
        return true
    end

    function rail:GetParent()
        return self.parent
    end

    function rail:SetParent(newParent)
        self.setParentCalls = self.setParentCalls + 1
        self.parent = newParent
    end

    function rail:SetShown(shown)
        self.shown = shown
        self.shownCalls[#self.shownCalls + 1] = shown
        return true
    end

    -- Mirrors AF_SidebarRailMixin:SetCollapsed/ToggleCollapsed exactly
    -- (AbstractFramework/Widgets/TreeList.lua): Set returns whether the
    -- state actually changed and only fires the callback when changed and
    -- not silent; Toggle always fires because it always changes the state.
    function rail:SetCollapsed(collapsed, silent)
        if self.collapsed == collapsed then return false end
        self.collapsed = collapsed
        self.collapsedCalls[#self.collapsedCalls + 1] = collapsed
        if not silent and self.onCollapsedChanged then
            self.onCollapsedChanged(collapsed)
        end
        return true
    end

    function rail:GetCollapsed()
        return self.collapsed
    end

    function rail:ToggleCollapsed()
        self.toggleCollapsedCalls = self.toggleCollapsedCalls + 1
        local collapsed = not self.collapsed
        self:SetCollapsed(collapsed)
        return collapsed
    end

    function rail:SetOnCollapsedChanged(callback)
        self.onCollapsedChanged = callback
        return true
    end

    function rail:SetOnPresentationWidthChanged(callback)
        self.onPresentationWidthChanged = callback
        if callback then
            callback(self:GetDesiredWidth(), self:GetDesiredWidth())
        end
        return true
    end

    function rail:GetDesiredWidth()
        return self.collapsed
            and (self.options.collapsedWidth or 44)
            or (self.options.expandedWidth or 170)
    end

    function rail:GetContentInset(gap)
        return self:GetDesiredWidth() + (gap or 8)
    end

    railInstances[#railInstances + 1] = rail
    return rail
end

local frameLevelCalls = {}
local AF = {
    CreateSidebarRail = function(parent, options)
        return makeRail(parent, options)
    end,
    SetFrameLevel = function(frame, level, relativeTo)
        frameLevelCalls[#frameLevelCalls + 1] = {frame, level, relativeTo}
    end,
}

local environment = {
    AbstractFramework = AF,
    type = type,
    pairs = pairs,
    ipairs = ipairs,
    select = select,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local bags = {}
local chunk, loadError = loadfile("Modules/Bags/Sidebar.lua")
assertEqual(type(chunk), "function", loadError or "sidebar module load")
setfenv(chunk, environment)
chunk("BFInfinite", {
    L = {},
    modules = {
        Bags = bags,
    },
})

local Sidebar = bags.Sidebar

---------------------------------------------------------------------
-- pre-Initialize: safe buffering, no rail created yet
---------------------------------------------------------------------
assertEqual(Sidebar.GetDesiredWidth(), 170, "default desired width before Initialize")
assertEqual(Sidebar.GetContentInset(), 178, "default content inset before Initialize")
assertEqual(Sidebar.GetCollapsed(), false, "the sidebar is expanded by default")
assertEqual(Sidebar.SetCollapsed("yes"), false, "non-boolean collapsed state rejected")

local presentationCalls = {}
assertEqual(Sidebar.SetOnPresentationWidthChanged("yes"), false,
    "non-function presentation callback rejected")
assertEqual(Sidebar.SetOnPresentationWidthChanged(function(width, reservedWidth)
    presentationCalls[#presentationCalls + 1] = {width, reservedWidth}
end), true, "presentation callback accepted")
assertEqual(#presentationCalls, 1,
    "presentation callback immediately synchronizes even without a rail")
assertEqual(presentationCalls[1][1], 170, "initial presentation width")
assertEqual(presentationCalls[1][2], 170, "initial reserved width")

local collapsedCalls = {}
assertEqual(Sidebar.SetOnCollapsedChanged("yes"), false,
    "non-function collapsed callback rejected")
assertEqual(Sidebar.SetOnCollapsedChanged(function(collapsed)
    collapsedCalls[#collapsedCalls + 1] = collapsed
end), true, "collapsed callback accepted")

-- Set(changed, unsilenced) fires; Set(unchanged) never fires; Set(changed,
-- silent) is applied but suppressed; Toggle always fires because it always
-- changes the state. This buffered pre-Initialize path must match the AF
-- rail's own SetCollapsed/ToggleCollapsed contract exactly.
assertEqual(Sidebar.SetCollapsed(true), true, "collapsing can be buffered before Initialize")
assertEqual(#presentationCalls, 2, "buffered collapse republishes presentation width")
assertEqual(presentationCalls[2][1], 44, "buffered collapse publishes the compact width with scrollbar lane")
assertEqual(presentationCalls[2][2], 44, "buffered collapse publishes the compact reserved width")
assertEqual(Sidebar.GetCollapsed(), true, "buffered collapsed state is queryable before Initialize")
assertEqual(Sidebar.GetDesiredWidth(), 44, "buffered compact desired width")
assertEqual(Sidebar.GetContentInset(), 52, "buffered compact content inset")
assertEqual(#collapsedCalls, 1, "an unsilenced buffered change fires the callback")
assertEqual(collapsedCalls[1], true, "the fired callback reports the new collapsed state")

assertEqual(Sidebar.SetCollapsed(true), false,
    "reapplying the same buffered state reports no change")
assertEqual(#presentationCalls, 2, "idempotent buffered collapse does not republish")
assertEqual(#collapsedCalls, 1, "an unchanged buffered state never fires the callback")

assertEqual(Sidebar.SetCollapsed(false, true), true,
    "a silent buffered change is still applied and reported as changed")
assertEqual(#presentationCalls, 3, "a silent buffered change still republishes presentation width")
assertEqual(presentationCalls[3][1], 170, "silently restored buffered presentation width")
assertEqual(#collapsedCalls, 1, "a silent buffered change suppresses the callback")
assertEqual(Sidebar.GetCollapsed(), false, "the silent change still updates the buffered state")

assertEqual(Sidebar.ToggleCollapsed(), true,
    "header toggle can collapse the buffered state before Initialize")
assertEqual(#presentationCalls, 4, "buffered toggle republishes presentation width")
assertEqual(presentationCalls[4][1], 44, "buffered toggle presentation width")
assertEqual(#collapsedCalls, 2, "unlike Set, Toggle always fires the callback")
assertEqual(collapsedCalls[2], true, "buffered toggle reports the new collapsed state")

assertEqual(Sidebar.SetShown("yes"), false, "non-boolean shown state rejected")
assertEqual(Sidebar.SetShown(false), true, "shown state can be buffered before Initialize")
assertEqual(Sidebar.SetShown(true), true, "shown state can be buffered before Initialize")

assertEqual(Sidebar.SetModel({{kind = "heading", label = "x"}}), false,
    "SetModel is a safe no-op before Initialize")
assertEqual(Sidebar.SetModel("not a table"), false,
    "non-table models are always rejected")
assertEqual(Sidebar.SetSelection("anything"), false,
    "SetSelection is a safe no-op before Initialize")
assertEqual(Sidebar.SetExpanded("anything", true), false,
    "SetExpanded is a safe no-op before Initialize")
assertEqual(Sidebar.ToggleExpanded("anything"), false,
    "ToggleExpanded is a safe no-op before Initialize")

assertEqual(Sidebar.Initialize(nil, function() end), nil,
    "Initialize without a parent frame is a safe no-op")
assertEqual(#railInstances, 0, "no rail is created without a parent frame")

---------------------------------------------------------------------
-- Initialize: rail creation, options, and buffered-state flush
---------------------------------------------------------------------
local selectedCalls = {}
local parent = {name = "combinedFrame"}
local returnedRail = Sidebar.Initialize(parent, function(id, entry)
    selectedCalls[#selectedCalls + 1] = {id, entry}
end)

assertEqual(#railInstances, 1, "Initialize creates exactly one AF sidebar rail")
local rail = railInstances[1]
assertEqual(returnedRail, rail, "Initialize returns the AF rail frame")
assertEqual(Sidebar.frame, rail, "Sidebar.frame exposes the AF rail frame")
assertEqual(rail.parent, parent, "the rail is parented to the caller's frame")

assertEqual(rail.options.expandedWidth, 170, "expanded width option")
assertEqual(rail.options.collapsedWidth, 44, "collapsed width reserves compact icon clearance and the scrollbar lane")
assertEqual(rail.options.headingHeight, 22, "heading height option")
assertEqual(rail.options.accentColor, "BFI", "accent color option")
assertEqual(rail.options.fallbackIcon.texture, "Interface\\Icons\\INV_Misc_Gear_01",
    "fallback icon is native colored item art")
-- Task 3 (sidebar v3): rowHeight/iconSize are no longer passed, so AF's own
-- TreeList.lua defaults govern (DEFAULT_ROW_HEIGHT = 28, DEFAULT_ICON_SIZE
-- = 20), and textureTint is gone entirely (AF deleted the option; passing
-- it would be inert).
assertEqual(rail.options.rowHeight, nil, "row height option is no longer overridden")
assertEqual(rail.options.iconSize, nil, "icon size option is no longer overridden")
assertEqual(rail.options.textureTint, nil, "the deleted textureTint option is never passed")

-- the buffered pre-Initialize state (shown=true, collapsed=true after the
-- toggle sequence above) is flushed onto the freshly created rail, silently
-- (the flush passes silent=true, and it also runs before SetOnCollapsedChanged
-- wires the callback onto the rail, so it cannot leak into collapsedCalls)
assertEqual(rail.shownCalls[#rail.shownCalls], true, "buffered shown state is flushed")
assertEqual(rail.collapsedCalls[#rail.collapsedCalls], true, "buffered collapsed state is flushed")
assertEqual(type(rail.treeList.onSelected), "function",
    "the Initialize callback is wired to the tree list")
assertEqual(type(rail.onCollapsedChanged), "function",
    "a callback registered before Initialize is wired to the rail")
assertEqual(type(rail.onPresentationWidthChanged), "function",
    "a presentation callback registered before Initialize is wired to the rail")

rail.treeList.onSelected("view:combined", {kind = "view"})
assertEqual(#selectedCalls, 1, "Initialize's callback argument fires through the tree list")
assertEqual(selectedCalls[1][1], "view:combined", "selected id pass-through")

---------------------------------------------------------------------
-- re-Initialize: reparent without creating a second rail
---------------------------------------------------------------------
assertEqual(Sidebar.Initialize(parent), rail, "re-Initializing with the same parent is a no-op")
assertEqual(#railInstances, 1, "no additional rail is created for the same parent")
assertEqual(rail.setParentCalls, 0, "SetParent is skipped when the parent is unchanged")

local otherParent = {name = "otherFrame"}
assertEqual(Sidebar.Initialize(otherParent), rail, "reparenting reuses the existing rail")
assertEqual(#railInstances, 1, "reparenting does not create a second rail")
assertEqual(rail.setParentCalls, 1, "SetParent is called when the parent changes")
assertEqual(rail.parent, otherParent, "the rail is reparented")
assertEqual(#frameLevelCalls, 1, "reparenting resets the rail's frame level")
assertEqual(frameLevelCalls[1][1], rail, "frame level is applied to the rail")
assertEqual(frameLevelCalls[1][2], 30, "frame level matches the rail's stacking order")
assertEqual(frameLevelCalls[1][3], otherParent, "frame level is relative to the new parent")

---------------------------------------------------------------------
-- post-Initialize: model pass-through
---------------------------------------------------------------------
-- Fixtures mirror production ids/icons: BuildSidebarModel (Modules/Bags/Bags.lua)
-- always prefixes ids (view:combined, category:parent:equipment, ...) and
-- always supplies an explicit native texture table, so Sidebar.lua has
-- nothing to fill in or transform.
local suppliedModel = {
    {kind = "heading", label = "Views"},
    {
        id = "view:combined",
        label = "Combined View",
        icon = {texture = "Interface\\Icons\\INV_Misc_Bag_10_Blue"},
    },
    {
        id = "view:individual",
        label = "Individual Bags View",
        icon = {texture = "Interface\\Icons\\INV_Misc_Bag_08"},
    },
    {kind = "heading", label = "Categories"},
    {
        id = "category:equipment",
        label = "Equipment",
        icon = {texture = "Interface\\Icons\\INV_Chest_Plate04"},
        expanded = true,
        children = {
            {
                id = "category:equipment:misc",
                label = "Misc Children",
                icon = {texture = "Interface\\Icons\\INV_Misc_Gear_01"},
            },
            {
                id = "category:equipment:chest",
                label = "Chest",
                icon = {texture = "Interface\\Icons\\INV_Chest_Chain"},
            },
        },
    },
}
assertEqual(Sidebar.SetModel(suppliedModel), true, "hierarchical model accepted")

assertEqual(#rail.treeList.modelCalls, 1, "SetModel delegates to the tree list exactly once")
local appliedModel = rail.treeList.modelCalls[1]
assertEqual(appliedModel, suppliedModel,
    "SetModel passes the caller's model straight through, unmodified")
assertEqual(appliedModel[1].kind, "heading", "headings pass through unchanged")
assertEqual(appliedModel[1].label, "Views", "heading label pass-through")
assertEqual(appliedModel[2].icon.texture, "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    "explicit native icon pass-through (combined)")
local equipment = appliedModel[5]
assertEqual(equipment.id, "category:equipment", "nested parent entry pass-through")
assertEqual(equipment.icon.texture, "Interface\\Icons\\INV_Chest_Plate04",
    "explicit native icon pass-through (top-level entry)")
assertEqual(equipment.expanded, true, "non-icon fields pass through untouched")
assertEqual(equipment.children[1].icon.texture, "Interface\\Icons\\INV_Misc_Gear_01",
    "explicit native icon pass-through (nested child)")
assertEqual(equipment.children[2].icon.texture, "Interface\\Icons\\INV_Chest_Chain",
    "explicit native nested icon pass-through")

assertEqual(Sidebar.SetModel("not a table"), false,
    "non-table models are rejected after Initialize too")

---------------------------------------------------------------------
-- post-Initialize: selection/expansion pass-through
---------------------------------------------------------------------
rail.treeList.nextSelectionReturn = true
assertEqual(Sidebar.SetSelection("equipment"), true, "selection accepted pass-through")
assertEqual(rail.treeList.lastSelectionId, "equipment", "the selected id reaches the tree list")

rail.treeList.nextSelectionReturn = false
assertEqual(Sidebar.SetSelection("missing"), false, "selection rejection pass-through")

-- rail.treeList:SetSelection(nil) returns false on a successful silent
-- clear; Sidebar.SetSelection must pass that through as-is, not special-case it
local selectionCallsBefore = rail.treeList.selectionCallCount
assertEqual(Sidebar.SetSelection(nil), false, "clearing the selection returns false, not an error")
assertEqual(rail.treeList.selectionCallCount, selectionCallsBefore + 1,
    "nil selection still reaches the tree list")
assertEqual(rail.treeList.lastSelectionId, nil, "nil selection reaches the tree list")

assertEqual(Sidebar.SetExpanded("equipment", false), true, "SetExpanded pass-through")
assertEqual(rail.treeList.expandedCalls[#rail.treeList.expandedCalls][1], "equipment",
    "SetExpanded id pass-through")
assertEqual(rail.treeList.expandedCalls[#rail.treeList.expandedCalls][2], false,
    "SetExpanded value pass-through")

assertEqual(Sidebar.ToggleExpanded("equipment"), true, "ToggleExpanded pass-through")
assertEqual(rail.treeList.toggleCalls[#rail.treeList.toggleCalls], "equipment",
    "ToggleExpanded id pass-through")

---------------------------------------------------------------------
-- post-Initialize: width/inset math pass-through
---------------------------------------------------------------------
-- entering this block the rail is collapsed (the flushed buffered state);
-- post-Initialize, Sidebar.SetCollapsed delegates straight to the rail,
-- whose SetOnCollapsedChanged wiring is now live, so unsilenced changes fire
assertEqual(Sidebar.GetDesiredWidth(), 44, "compact desired width pass-through")
assertEqual(Sidebar.GetContentInset(), 52, "compact content inset pass-through")
assertEqual(Sidebar.SetCollapsed(false), true, "the sidebar can be expanded after Initialize")
assertEqual(#collapsedCalls, 3, "the expand fires the callback")
assertEqual(Sidebar.GetDesiredWidth(), 170, "expanded desired width pass-through")
assertEqual(Sidebar.GetContentInset(), 178, "expanded content inset pass-through")
assertEqual(Sidebar.SetCollapsed(true), true, "the sidebar can be collapsed after Initialize")
assertEqual(#collapsedCalls, 4, "the collapse fires the callback")
assertEqual(Sidebar.GetDesiredWidth(), 44, "restored compact desired width")

---------------------------------------------------------------------
-- post-Initialize: silent SetCollapsed vs. ToggleCollapsed firing the callback
---------------------------------------------------------------------
assertEqual(#collapsedCalls, 4, "call count entering the silent-vs-toggle checks")
assertEqual(Sidebar.SetCollapsed(true), false,
    "reapplying the same state after Initialize reports no change")
assertEqual(#collapsedCalls, 4, "an unchanged state after Initialize never fires the callback")
assertEqual(Sidebar.SetCollapsed(false, true), true,
    "a silent change after Initialize is still applied")
assertEqual(#collapsedCalls, 4, "a silent change after Initialize suppresses the callback")
assertEqual(Sidebar.GetCollapsed(), false, "the silent change still updates the rail's state")
assertEqual(Sidebar.ToggleCollapsed(), true, "ToggleCollapsed after Initialize flips state")
assertEqual(#collapsedCalls, 5, "ToggleCollapsed after Initialize always fires the callback")
assertEqual(collapsedCalls[5], true, "ToggleCollapsed reports the new state")
assertEqual(Sidebar.GetCollapsed(), true, "ToggleCollapsed's new state is queryable")

---------------------------------------------------------------------
-- post-Initialize: SetOnSelected re-registration delegates directly
---------------------------------------------------------------------
local laterSelected = {}
assertEqual(Sidebar.SetOnSelected(function(id)
    laterSelected[#laterSelected + 1] = id
end), true, "SetOnSelected after Initialize is accepted")
rail.treeList.onSelected("custom")
assertEqual(#laterSelected, 1, "re-registering SetOnSelected rewires the tree list callback")
assertEqual(laterSelected[1], "custom", "the new callback receives the tree list's call")

print("bags_sidebar_controller_test.lua: ok")
