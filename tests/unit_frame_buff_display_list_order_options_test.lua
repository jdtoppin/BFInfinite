local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local function assertContains(source, expected, message)
    assertTrue(
        source:find(expected, 1, true) ~= nil,
        message .. ": missing " .. expected
    )
end

local function readFile(path)
    local file, openError = io.open(path, "rb")
    assertTrue(file, openError)
    local contents = file:read("*a")
    file:close()
    return contents
end

local function section(source, first, last)
    local firstIndex = assert(
        source:find(first, 1, true),
        "missing section start: " .. first
    )
    local lastIndex = assert(
        source:find(last, firstIndex + #first, true),
        "missing section end: " .. last
    )
    return source:sub(firstIndex, lastIndex - 1)
end

local source = readFile("Options/UnitFrames_Options.lua")

local priorityContract = section(
    source,
    "local function UsesChildBuffSpellListPriority(t)",
    "local function RequiresNativeAuraReload"
)
assertContains(priorityContract, "t.displayID ~= nil",
    "priority ordering is child-display-only")
assertContains(priorityContract, 't.id == "buffs"',
    "priority ordering is Buffs-only")
assertContains(priorityContract, 't.cfg.mode == "whitelist"',
    "priority ordering consumes the whitelist")
assertContains(
    priorityContract,
    't.cfg.sortMode == "spell_list_priority"',
    "priority ordering follows the explicit sort mode"
)

local spellList = section(
    source,
    'builder["auraBlackListWhitelist"]',
    "-- auraTypeColor"
)
local modeSelection = section(
    spellList,
    "mode:SetOnSelect(function(value)",
    "pane:SetOnHide(function()"
)
assertContains(
    modeSelection,
    "pane.Load(pane.t)\n        LoadIndicatorConfig(pane.t)",
    "mode changes rebuild the list before applying the child display"
)

local loadIndicator = section(
    source,
    "LoadIndicatorConfig = function(t)",
    "local function RefreshOptionPaneHeight"
)
assertContains(loadIndicator, "if t.displayID then",
    "child display mutations request an options refresh")
assertContains(
    loadIndicator,
    'AF.Fire("BFI_RefreshOptions", "unitFrames")',
    "mode changes refresh whitelist-only Sort and order controls"
)

assertContains(spellList, "local function MoveSpell(button, offset)",
    "spell list exposes a reorder action")
assertContains(
    spellList,
    "pane.list[fromIndex], pane.list[toIndex] =\n            pane.list[toIndex], pane.list[fromIndex]",
    "reorder persists by swapping whitelist entries"
)
assertContains(spellList, "pane.Load(pane.t)\n        LoadIndicatorConfig(pane.t)",
    "reorder refreshes options and the unit-frame display")
assertContains(spellList, 'L["Move Up"]',
    "spell entries expose Move Up")
assertContains(spellList, 'L["Move Down"]',
    "spell entries expose Move Down")
assertContains(spellList, "MoveSpell(b, -1)",
    "Move Up decrements the saved index")
assertContains(spellList, "MoveSpell(b, 1)",
    "Move Down increments the saved index")
assertContains(spellList, "b.moveUp:SetEnabled(canEdit and i > 1)",
    "the first spell cannot move above the list")
assertContains(spellList, "b.moveDown:SetEnabled(canEdit and i < num)",
    "the last spell cannot move below the list")
assertContains(spellList, 'buttons[i - 1],\n                    "BOTTOMLEFT"',
    "priority spell order uses a visible single-column layout")
assertContains(spellList, "rows = num + 1",
    "priority list height includes every ordered spell")

local arrangement = section(
    source,
    'builder["auraArrangement"]',
    "-- cooldownStyle"
)
assertContains(
    arrangement,
    "width:SetMinMaxValues(isStandaloneBar and 4 or 10, 100)",
    "standalone bars accept compact widths"
)
assertContains(
    arrangement,
    "height:SetMinMaxValues(isStandaloneBar and 1 or 10, 100)",
    "standalone bars accept a thin one-pixel height"
)
assertContains(
    arrangement,
    "local usesPriorityOrder =\n            UsesChildBuffSpellListPriority(t)",
    "priority Max Displayed semantics override per-group wording")
assertContains(arrangement, 'numTotal:SetLabel(L["Max Displayed"])',
    "priority mode retains clear top-N wording")
assertContains(arrangement, "numPerLine:Hide()",
    "priority mode hides the ignored Displayed Per Line control")
assertContains(
    arrangement,
    'AF.SetPoint(\n                numTotal,\n                "TOPLEFT",\n                spacingX,\n                "BOTTOMLEFT",',
    "priority Max Displayed occupies the open layout row"
)
assertContains(arrangement, "numPerLine:Show()",
    "non-priority modes restore Displayed Per Line")
assertContains(
    arrangement,
    'AF.SetPoint(numTotal, "TOPLEFT", numPerLine, 185, 0)',
    "non-priority modes restore the two-control row"
)

local optionRouting = section(
    source,
    "function F.GetUnitFrameOptions(parent, info)",
    "return options\nend"
)
assertContains(
    optionRouting,
    'or presentation == "bar")\n            and option == "cooldownStyle"',
    "standalone bars hide icon cooldown-style controls"
)

print("unit_frame_buff_display_list_order_options_test.lua: ok")
