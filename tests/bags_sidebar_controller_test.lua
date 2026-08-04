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
    "AF.CreateSidebarRail(",
    "the sidebar must delegate widget construction to the shared AF rail"
)

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
        autoHide = false,
        setParentCalls = 0,
        shownCalls = {},
        autoHideCalls = {},
        toggleAutoHideCalls = 0,
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

    function rail:SetAutoHide(autoHide)
        self.autoHide = autoHide
        self.autoHideCalls[#self.autoHideCalls + 1] = autoHide
        return true
    end

    function rail:GetAutoHide()
        return self.autoHide
    end

    function rail:ToggleAutoHide()
        self.toggleAutoHideCalls = self.toggleAutoHideCalls + 1
        self:SetAutoHide(not self.autoHide)
        if self.onAutoHideChanged then
            self.onAutoHideChanged(self.autoHide)
        end
        return self.autoHide
    end

    function rail:SetOnAutoHideChanged(callback)
        self.onAutoHideChanged = callback
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
        return self.autoHide
            and (self.options.collapsedWidth or 40)
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
assertEqual(Sidebar.GetAutoHide(), false, "auto-hide is initially disabled")
assertEqual(Sidebar.SetAutoHide("yes"), false, "non-boolean auto-hide state rejected")

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

local autoHideCalls = {}
assertEqual(Sidebar.SetOnAutoHideChanged("yes"), false,
    "non-function auto-hide callback rejected")
assertEqual(Sidebar.SetOnAutoHideChanged(function(enabled)
    autoHideCalls[#autoHideCalls + 1] = enabled
end), true, "auto-hide callback accepted")

assertEqual(Sidebar.SetAutoHide(true), true, "auto-hide can be buffered before Initialize")
assertEqual(#presentationCalls, 2, "buffered auto-hide republishes presentation width")
assertEqual(presentationCalls[2][1], 40, "buffered auto-hide publishes the compact width")
assertEqual(presentationCalls[2][2], 40, "buffered auto-hide publishes the compact reserved width")
assertEqual(Sidebar.GetAutoHide(), true, "buffered auto-hide is queryable before Initialize")
assertEqual(Sidebar.GetDesiredWidth(), 40, "buffered compact desired width")
assertEqual(Sidebar.GetContentInset(), 48, "buffered compact content inset")
assertEqual(#autoHideCalls, 0, "programmatic auto-hide synchronization stays silent")

assertEqual(Sidebar.SetAutoHide(true), true, "reapplying the same buffered state is accepted")
assertEqual(#presentationCalls, 2, "idempotent buffered auto-hide does not republish")

assertEqual(Sidebar.ToggleAutoHide(), false,
    "header toggle can restore the pinned buffered state before Initialize")
assertEqual(#presentationCalls, 3, "buffered toggle republishes presentation width")
assertEqual(presentationCalls[3][1], 170, "pinned buffered presentation width")
assertEqual(#autoHideCalls, 1, "buffered header toggle fires the auto-hide callback")
assertEqual(autoHideCalls[1], false, "buffered header toggle reports the disabled state")

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
assertEqual(rail.options.collapsedWidth, 40, "collapsed width option")
assertEqual(rail.options.rowHeight, 26, "row height option")
assertEqual(rail.options.headingHeight, 22, "heading height option")
assertEqual(rail.options.iconSize, 16, "icon size option")
assertEqual(rail.options.accentColor, "BFI", "accent color option")
assertEqual(rail.options.fallbackIcon, "Bag_Misc", "fallback icon option")

-- the buffered pre-Initialize state (shown=true, autoHide=false after the
-- toggle sequence above) is flushed onto the freshly created rail
assertEqual(rail.shownCalls[#rail.shownCalls], true, "buffered shown state is flushed")
assertEqual(rail.autoHideCalls[#rail.autoHideCalls], false, "buffered auto-hide state is flushed")
assertEqual(type(rail.treeList.onSelected), "function",
    "the Initialize callback is wired to the tree list")
assertEqual(type(rail.onAutoHideChanged), "function",
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
-- fixtures mirror production ids/icons: BuildSidebarModel (Modules/Bags/Bags.lua)
-- always prefixes ids (view:combined, category:parent:equipment, ...) and
-- always sets an explicit icon, so Sidebar.lua has nothing to fill in.
local suppliedModel = {
    {kind = "heading", label = "Views"},
    {id = "view:combined", label = "Combined View", icon = "Bag_All"},
    {id = "view:individual", label = "Individual Bags View", icon = "Bag_IndividualBags"},
    {kind = "heading", label = "Categories"},
    {
        id = "category:equipment",
        label = "Equipment",
        icon = "Bag_Equipment",
        expanded = true,
        children = {
            {id = "category:equipment:misc", label = "Misc Children", icon = "Bag_Misc"},
            {id = "category:equipment:chest", label = "Chest", icon = "Custom_Icon"},
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
assertEqual(appliedModel[2].icon, "Bag_All", "explicit icon pass-through (combined)")
local equipment = appliedModel[5]
assertEqual(equipment.id, "category:equipment", "nested parent entry pass-through")
assertEqual(equipment.icon, "Bag_Equipment", "explicit icon pass-through (top-level entry)")
assertEqual(equipment.expanded, true, "non-icon fields pass through untouched")
assertEqual(equipment.children[1].icon, "Bag_Misc", "explicit icon pass-through (nested child)")
assertEqual(equipment.children[2].icon, "Custom_Icon", "explicit nested icon pass-through")

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
assertEqual(Sidebar.GetDesiredWidth(), 170, "expanded desired width pass-through")
assertEqual(Sidebar.GetContentInset(), 178, "expanded content inset pass-through")
assertEqual(Sidebar.SetAutoHide(true), true, "auto-hide can be enabled after Initialize")
assertEqual(Sidebar.GetDesiredWidth(), 40, "compact desired width pass-through")
assertEqual(Sidebar.GetContentInset(), 48, "compact content inset pass-through")
assertEqual(Sidebar.SetAutoHide(false), true, "auto-hide can be disabled after Initialize")
assertEqual(Sidebar.GetDesiredWidth(), 170, "restored expanded desired width")

---------------------------------------------------------------------
-- post-Initialize: silent SetAutoHide vs. ToggleAutoHide firing the callback
---------------------------------------------------------------------
assertEqual(#autoHideCalls, 1, "no auto-hide callback fired yet from post-Initialize calls")
assertEqual(Sidebar.SetAutoHide(true), true, "programmatic auto-hide after Initialize")
assertEqual(#autoHideCalls, 1, "programmatic SetAutoHide after Initialize stays silent")
assertEqual(Sidebar.ToggleAutoHide(), false, "ToggleAutoHide after Initialize flips state")
assertEqual(#autoHideCalls, 2, "ToggleAutoHide after Initialize fires the callback")
assertEqual(autoHideCalls[2], false, "ToggleAutoHide reports the new state")
assertEqual(Sidebar.GetAutoHide(), false, "ToggleAutoHide's new state is queryable")

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
