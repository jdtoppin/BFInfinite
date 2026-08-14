local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local function copy(value)
    if type(value) ~= "table" then return value end

    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local function wipeTable(value)
    for key in pairs(value) do
        value[key] = nil
    end
end

local callbacks = {}
local panes = {}
local buttons = {}
local checkButtons = {}
local sliders = {}
local fontStrings = {}
local dropdowns = {}
local dialogs = {}
local fires = {}
local previewCalls = {}
local clearHistoryCalls = 0
local nativeObjectiveTrackerHeight = 650
local nativeObjectiveTrackerHeightReason
local nativeObjectiveTrackerHeightWrites = 0
local nativeObjectiveTrackerPlacementIsDefault = true
local nativeObjectiveTrackerPlacementReason
local nativeObjectiveTrackerPlacementWrites = 0
local nativeObjectiveTrackerPlacementCanSet = true
local nativeObjectiveTrackerPlacementCanSetReason
local nativeEditModeShown
local optionsHidden = false

local AF = {
    noop = function()
    end,
}

function AF.Copy(value)
    return copy(value)
end

function AF.GetColorTable(name)
    return {name = name}
end

function AF.GetColorRGB()
    return 1, 1, 1
end

function AF.Merge(target, source)
    for key, value in pairs(source) do
        target[key] = copy(value)
    end
end

function AF.MergeMissingKeys(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = copy(value)
        end
    end
end

function AF.RegisterCallback(event, callback)
    callbacks[event] = callback
end

function AF.WrapTextInColor(text)
    return text
end

function AF.CreateBorderedFrame(_, name, _, height)
    local pane = {
        name = name,
        height = height or 0,
    }
    function pane:Hide()
        self.shown = false
    end
    function pane:Show()
        self.shown = true
    end
    function pane:SetBorderColor()
    end
    function pane:SetHeight(value)
        self.height = value
    end
    function pane:GetHeight()
        return self.height
    end
    panes[#panes + 1] = pane
    return pane
end

function AF.CreateButton(_, label)
    local button = {
        labelText = label,
    }
    function button:SetEnabled(value)
        self.enabled = value
    end
    function button:SetOnClick(callback)
        self.onClick = callback
    end
    function button:SetTooltip(...)
        self.tooltip = {...}
    end
    buttons[#buttons + 1] = button
    return button
end

function AF.CreateCheckButton(_, label)
    local checkButton = {
        labelText = label,
        label = {
            SetTextColor = function()
            end,
        },
    }
    function checkButton:SetOnCheck(callback)
        self.onCheck = callback
    end
    function checkButton:SetChecked(value)
        self.checked = value
    end
    function checkButton:SetEnabled(value)
        self.enabled = value
    end
    function checkButton:SetTooltip(...)
        self.tooltip = {...}
    end
    checkButtons[#checkButtons + 1] = checkButton
    return checkButton
end

function AF.CreateSlider(_, label, width, minimum, maximum, step)
    local slider = {
        labelText = label,
        label = {},
        width = width,
        minimum = minimum,
        maximum = maximum,
        step = step,
    }
    function slider.label:SetJustifyH(value)
        self.justifyH = value
    end
    function slider:SetOnValueChanged(callback)
        self.onValueChanged = callback
    end
    function slider:SetAfterValueChanged(callback)
        self.afterValueChanged = callback
    end
    function slider:SetValue(value)
        self.value = value
    end
    function slider:SetEnabled(value)
        self.enabled = value
    end
    function slider:SetTooltip(...)
        self.tooltip = {...}
    end
    sliders[#sliders + 1] = slider
    return slider
end

function AF.CreateDropdown()
    local dropdown = {}
    function dropdown:SetLabel(value)
        self.label = value
    end
    function dropdown:SetItems(value)
        self.items = value
    end
    function dropdown:SetOnSelect(callback)
        self.onSelect = callback
    end
    function dropdown:SetSelectedValue(value)
        self.value = value
    end
    dropdowns[#dropdowns + 1] = dropdown
    return dropdown
end

function AF.CreateFontString(_, text)
    local fontString = {
        text = text,
    }
    function fontString:SetJustifyH(value)
        self.justifyH = value
    end
    function fontString:SetText(value)
        self.text = value
    end
    function fontString:SetShown(value)
        self.shown = value
    end
    function fontString:SetWordWrap(value)
        self.wordWrap = value
    end
    fontStrings[#fontStrings + 1] = fontString
    return fontString
end

function AF.GetDialog(_, text)
    local dialog = {
        text = text,
    }
    function dialog:SetPoint()
    end
    function dialog:SetOnConfirm(callback)
        self.onConfirm = callback
    end
    dialogs[#dialogs + 1] = dialog
    return dialog
end

function AF.Fire(...)
    fires[#fires + 1] = {...}
end

function AF.ClearPoints(region)
    region.point = nil
end

function AF.SetPoint(region, ...)
    region.point = {...}
end

function AF.LSM_GetFontDropdownItems()
    return {}
end

function AF.LSM_GetFontOutlineDropdownItems()
    return {}
end

local W = {
    GetObjectiveTrackerNativeHeight = function()
        return nativeObjectiveTrackerHeight,
            nativeObjectiveTrackerHeightReason
    end,
    GetObjectiveTrackerNativePlacement = function()
        return nativeObjectiveTrackerPlacementIsDefault,
            nativeObjectiveTrackerPlacementReason
    end,
    CanSetObjectiveTrackerBFIRightStackPlacement = function()
        return nativeObjectiveTrackerPlacementCanSet,
            nativeObjectiveTrackerPlacementCanSetReason
    end,
    MythicPlus = {
        SetPreview = function(shown)
            previewCalls[#previewCalls + 1] = shown
        end,
        ClearHistory = function()
            clearHistoryCalls = clearHistoryCalls + 1
        end,
    },
    SetObjectiveTrackerNativeHeight = function(value)
        nativeObjectiveTrackerHeight = value
        nativeObjectiveTrackerHeightWrites =
            nativeObjectiveTrackerHeightWrites + 1
        return true
    end,
    SetObjectiveTrackerBFIRightStackPlacement = function()
        nativeObjectiveTrackerPlacementIsDefault = false
        nativeObjectiveTrackerHeight = 640
        nativeObjectiveTrackerPlacementWrites =
            nativeObjectiveTrackerPlacementWrites + 1
        return true
    end,
}
local F = {}
local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
local BFI = {
    name = "BFInfinite",
    funcs = F,
    L = L,
    modules = {
        UIWidgets = W,
    },
}
local environment = {
    _G = false,
    AbstractFramework = AF,
    BFIOptionsFrame = {
        Hide = function()
            optionsHidden = true
        end,
    },
    BFIOptionsFrame_UIWidgetsPanel = {},
    EditModeManagerFrame = {
        CanEnterEditMode = function()
            return true
        end,
    },
    InCombatLockdown = function()
        return false
    end,
    READY_CHECK = "Ready Check",
    RESET = "Reset",
    ROLE_POLL = "Role Poll",
    ipairs = ipairs,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
    ShowUIPanel = function(frame)
        nativeEditModeShown = frame
    end,
    table = table,
    tinsert = table.insert,
    tostring = tostring,
    type = type,
    wipe = wipeTable,
}
environment._G = environment

local defaultsChunk, defaultsLoadError =
    loadfile("Modules/UIWidgets/Defaults.lua")
assertEqual(type(defaultsChunk), "function",
    defaultsLoadError or "defaults module load")
setfenv(defaultsChunk, environment)
defaultsChunk("BFInfinite", BFI)

local updateProfile = callbacks.BFI_UpdateProfile
assertEqual(type(updateProfile), "function", "profile callback")

local freshProfile = {}
updateProfile(nil, freshProfile)
local defaults = freshProfile.uiWidgets.mythicPlus
assertEqual(defaults.enabled, false, "Mythic+ defaults are opt-in")
assertEqual(defaults.width, 320, "default timer width")
assertEqual(defaults.extendedRunMultiplier, 1.5,
    "default extended-run cutoff")
assertEqual(defaults.hideObjectiveTracker, true,
    "default tracker replacement")
assertEqual(defaults.showPlayerBreakdown, true,
    "default player breakdown display")
local objectiveDefaults = freshProfile.uiWidgets.objectiveTracker
assertEqual(objectiveDefaults.enabled, true,
    "Objective Tracker styling defaults to enabled")
assertEqual(objectiveDefaults.backgroundAlpha, 0.85,
    "default Objective Tracker background opacity")
assertEqual(objectiveDefaults.autoAcceptQuests, false,
    "Objective Tracker auto-accept defaults to off")
assertEqual(objectiveDefaults.autoTurnInQuests, false,
    "Objective Tracker auto-turn-in defaults to off")

local existingProfile = {
    uiWidgets = {
        microMenu = {
            enabled = true,
        },
    },
}
updateProfile(nil, existingProfile)
assertEqual(existingProfile.uiWidgets.mythicPlus.enabled, false,
    "existing profile receives new module defaults")
assertEqual(existingProfile.uiWidgets.objectiveTracker.backgroundAlpha, 0.85,
    "existing profile receives Objective Tracker background defaults")
assertEqual(existingProfile.uiWidgets.objectiveTracker.autoAcceptQuests, false,
    "existing profile receives opt-in quest automation defaults")

local partialProfile = {
    uiWidgets = {
        mythicPlus = {
            enabled = true,
        },
    },
}
updateProfile(nil, partialProfile)
assertEqual(partialProfile.uiWidgets.mythicPlus.enabled, true,
    "existing Mythic+ choice is preserved")
assertEqual(partialProfile.uiWidgets.mythicPlus.width, 320,
    "partial Mythic+ config is filled")

local partialObjectiveProfile = {
    uiWidgets = {
        objectiveTracker = {
            enabled = true,
            backgroundAlpha = 0.37,
            autoAcceptQuests = true,
        },
    },
}
updateProfile(nil, partialObjectiveProfile)
assertEqual(
    partialObjectiveProfile.uiWidgets.objectiveTracker.backgroundAlpha,
    0.37,
    "existing Objective Tracker opacity is preserved"
)
assertEqual(
    type(partialObjectiveProfile.uiWidgets.objectiveTracker.font),
    "table",
    "partial Objective Tracker config is filled"
)
assertEqual(
    partialObjectiveProfile.uiWidgets.objectiveTracker.autoAcceptQuests,
    true,
    "existing Objective Tracker auto-accept choice is preserved"
)
assertEqual(
    partialObjectiveProfile.uiWidgets.objectiveTracker.autoTurnInQuests,
    false,
    "missing Objective Tracker auto-turn-in choice is filled"
)

local optionsChunk, optionsLoadError =
    loadfile("Options/UIWidgets_Options.lua")
assertEqual(type(optionsChunk), "function",
    optionsLoadError or "options module load")
setfenv(optionsChunk, environment)
optionsChunk("BFInfinite", BFI)

local info = {
    cfg = partialProfile.uiWidgets.mythicPlus,
    id = "mythicPlus",
    ownerName = "Mythic+ Timer",
    SetTextColor = function()
    end,
}
local optionPanes = F.GetUIWidgetOptions({}, info)
assertTrue(#optionPanes >= 7, "Mythic+ options panes")
for _, pane in ipairs(optionPanes) do
    pane.Load(info)
end

local function findByLabel(widgets, label)
    for _, widget in ipairs(widgets) do
        if widget.labelText == label then
            return widget
        end
    end
end

local function findByText(widgets, text)
    for _, widget in ipairs(widgets) do
        if widget.text == text then return widget end
    end
end

local objectiveInfo = {
    cfg = partialProfile.uiWidgets.objectiveTracker,
    id = "objectiveTracker",
    ownerName = "Objective Tracker",
    SetTextColor = function()
    end,
}
local objectiveOptionPanes = F.GetUIWidgetOptions({}, objectiveInfo)
assertTrue(#objectiveOptionPanes >= 5, "Objective Tracker options panes")
for _, pane in ipairs(objectiveOptionPanes) do
    pane.Load(objectiveInfo)
end

local nativePlacement = findByLabel(buttons, "Set Default Position & Height")
assertTrue(nativePlacement, "Objective Tracker native placement action")
assertEqual(nativePlacement.enabled, true,
    "native placement remains enabled for the active Blizzard layout")
assertEqual(nativePlacement.tooltip[1], "Objective Tracker Position & Height",
    "native placement tooltip title")
nativePlacement.onClick()
assertEqual(nativeObjectiveTrackerPlacementIsDefault, false,
    "native placement leaves Blizzard's managed tracker column")
assertEqual(nativeObjectiveTrackerPlacementWrites, 1,
    "native placement writes once through the Blizzard adapter")
assertEqual(nativeObjectiveTrackerHeight, 640,
    "native placement applies BFI's default Objective Tracker height")
assertEqual(objectiveInfo.cfg.position, nil,
    "native placement is not stored in the BFI profile")
local nativePlacementStatus = findByText(fontStrings,
    "Saved default position and 640 height where supported. Open and close Blizzard Edit Mode to apply it; temporary Blizzard layouts take precedence.")
assertTrue(nativePlacementStatus,
    "native placement explains how Blizzard applies the saved layout")
assertEqual(nativePlacementStatus.shown, true,
    "native placement refresh guidance is visible")

local openBlizzardEditMode = findByLabel(buttons, "Open Blizzard Edit Mode")
assertTrue(openBlizzardEditMode,
    "Objective Tracker opens its native Blizzard Edit Mode")
assertEqual(openBlizzardEditMode.enabled, true,
    "native Edit Mode launcher is available out of combat")
assertEqual(openBlizzardEditMode.tooltip[1], "Objective Tracker Position & Height",
    "native Edit Mode launcher tooltip title")
assertEqual(openBlizzardEditMode.point[1], "TOPLEFT",
    "native Edit Mode launcher stacks below the placement action")
assertEqual(openBlizzardEditMode.point[2], nativePlacement,
    "native Edit Mode launcher stays inside the options viewport")
assertEqual(openBlizzardEditMode.point[3], "BOTTOMLEFT",
    "native Edit Mode launcher anchors below the placement action")
openBlizzardEditMode.onClick()
assertEqual(nativeEditModeShown, environment.EditModeManagerFrame,
    "native Edit Mode launcher opens Blizzard's manager")
assertEqual(optionsHidden, true,
    "native Edit Mode launcher closes BFI options first")

nativeObjectiveTrackerPlacementReason = "customLayout"
nativeObjectiveTrackerPlacementCanSet = true
nativeObjectiveTrackerPlacementCanSetReason = "createsLayout"
for _, pane in ipairs(objectiveOptionPanes) do
    if pane.name == "BFI_UIWidgetOption_ObjectiveTrackerPlacement" then
        pane.Load(objectiveInfo)
        break
    end
end
assertEqual(nativePlacement.enabled, true,
    "fresh preset enables BFI native placement to create its layout")
local createLayoutStatus = findByText(fontStrings,
    "Click Set Default Position & Height to create and activate BFI's Blizzard layout.")
assertTrue(createLayoutStatus,
    "fresh preset placement explains that BFI will create a native layout")
local placementWritesBeforeCreate = nativeObjectiveTrackerPlacementWrites
nativePlacement.onClick()
assertEqual(nativeObjectiveTrackerPlacementWrites,
    placementWritesBeforeCreate + 1,
    "fresh preset placement delegates to the BFI layout creator")

nativeObjectiveTrackerPlacementCanSet = false
nativeObjectiveTrackerPlacementCanSetReason = "customLayout"
for _, pane in ipairs(objectiveOptionPanes) do
    if pane.name == "BFI_UIWidgetOption_ObjectiveTrackerPlacement" then
        pane.Load(objectiveInfo)
        break
    end
end
assertEqual(nativePlacement.enabled, false,
    "saved custom layouts retain the explicit BFI placement boundary")
nativeObjectiveTrackerPlacementReason = nil
nativeObjectiveTrackerPlacementCanSet = true
nativeObjectiveTrackerPlacementCanSetReason = nil

local nativeHeight = findByLabel(sliders, "Objective Tracker Height")
assertTrue(nativeHeight, "Objective Tracker native height slider")
assertEqual(nativeHeight.minimum, 400, "native height minimum")
assertEqual(nativeHeight.maximum, 1000, "native height maximum")
assertEqual(nativeHeight.step, 10, "native height step")
assertEqual(nativeHeight.value, 650,
    "native height loads the active Blizzard layout value")
assertEqual(nativeHeight.enabled, true,
    "writable native height remains enabled")
nativeHeight.afterValueChanged(500)
assertEqual(nativeObjectiveTrackerHeight, 500,
    "native height writes through the Blizzard adapter")
assertEqual(nativeObjectiveTrackerHeightWrites, 1,
    "native height writes once per completed slider edit")
assertEqual(objectiveInfo.cfg.height, nil,
    "native height is not stored in the BFI profile")
local nativeHeightStatus = findByText(fontStrings,
    "Saved. Open and close Blizzard Edit Mode to apply it.")
assertTrue(nativeHeightStatus,
    "native height explains the no-reload Blizzard layout refresh")
assertEqual(nativeHeightStatus.shown, true,
    "native height refresh guidance is visible")

nativeObjectiveTrackerHeightReason = "customPosition"
for _, pane in ipairs(objectiveOptionPanes) do
    if pane.name == "BFI_UIWidgetOption_ObjectiveTrackerNativeHeight" then
        pane.Load(objectiveInfo)
        break
    end
end
assertEqual(nativeHeight.enabled, false,
    "default-position tracker disables the native height slider")
nativeObjectiveTrackerHeightReason = nil

local backgroundOpacity = findByLabel(sliders, "Background Opacity")
assertTrue(backgroundOpacity, "Objective Tracker background opacity slider")
assertEqual(backgroundOpacity.minimum, 0, "background opacity minimum")
assertEqual(backgroundOpacity.maximum, 1, "background opacity maximum")
assertEqual(backgroundOpacity.value, 0.85,
    "background opacity loads the profile value")
backgroundOpacity.onValueChanged(0.62)
assertEqual(objectiveInfo.cfg.backgroundAlpha, 0.62,
    "background opacity setting")
assertEqual(fires[#fires][1], "BFI_UpdateModule",
    "background opacity refreshes the Objective Tracker")
assertEqual(fires[#fires][3], "objectiveTracker",
    "background opacity refresh targets the Objective Tracker")

local autoAcceptQuests = findByLabel(checkButtons, "Auto Accept Quests")
local autoTurnInQuests = findByLabel(checkButtons, "Auto Turn In Quests")
assertTrue(autoAcceptQuests and autoTurnInQuests,
    "Objective Tracker quest automation toggles")
assertEqual(autoAcceptQuests.checked, false,
    "auto-accept loads the profile value")
assertEqual(autoTurnInQuests.checked, false,
    "auto-turn-in loads the profile value")
local questAutomationTooltip = "Hold Shift to pause quest automation. "
    .. "Item-started and remote completions, multiple reward choices, "
    .. "PvP confirmations, and payments stay manual."
assertEqual(autoAcceptQuests.tooltip[1], "Auto Accept Quests",
    "auto-accept tooltip title")
assertEqual(autoAcceptQuests.tooltip[2], questAutomationTooltip,
    "auto-accept tooltip body")
assertEqual(autoAcceptQuests._tooltipOwner,
    environment.BFIOptionsFrame_UIWidgetsPanel,
    "auto-accept tooltip escapes the settings scroll viewport")
assertEqual(autoTurnInQuests.tooltip[1], "Auto Turn In Quests",
    "auto-turn-in tooltip title")
assertEqual(autoTurnInQuests.tooltip[2], questAutomationTooltip,
    "auto-turn-in tooltip body")
assertEqual(autoTurnInQuests._tooltipOwner,
    environment.BFIOptionsFrame_UIWidgetsPanel,
    "auto-turn-in tooltip escapes the settings scroll viewport")
autoAcceptQuests.onCheck(true)
autoTurnInQuests.onCheck(true)
assertEqual(objectiveInfo.cfg.autoAcceptQuests, true,
    "auto-accept setting")
assertEqual(objectiveInfo.cfg.autoTurnInQuests, true,
    "auto-turn-in setting")

local showAffixes = findByLabel(checkButtons, "Show Affixes")
assertTrue(showAffixes, "affix display toggle")
showAffixes.onCheck(false)
assertEqual(info.cfg.showAffixes, false, "affix display config")
assertEqual(fires[#fires][1], "BFI_UpdateModule", "display update event")

local showObjectives = findByLabel(checkButtons, "Show Objectives")
local showSplits = findByLabel(checkButtons, "Show Split Comparisons")
assertTrue(showObjectives and showSplits,
    "objective and split display toggles")
showObjectives.onCheck(false)
assertEqual(showSplits.enabled, false,
    "split comparison is unavailable without objective rows")
showObjectives.onCheck(true)
assertEqual(showSplits.enabled, true,
    "split comparison follows objective row availability")

local showDebrief = findByLabel(
    checkButtons,
    "Show End-of-Run Debrief"
)
local showPlayers = findByLabel(checkButtons, "Show Player Breakdown")
assertTrue(showDebrief and showPlayers,
    "debrief and player breakdown toggles")
showDebrief.onCheck(false)
assertEqual(showPlayers.enabled, false,
    "player breakdown is unavailable without the debrief")
showDebrief.onCheck(true)
assertEqual(showPlayers.enabled, true,
    "player breakdown follows debrief availability")

local preview = findByLabel(checkButtons, "Show Preview")
assertTrue(preview, "preview toggle")
assertEqual(preview.enabled, true,
    "preview is available while the module is enabled")
preview.onCheck(true)
assertEqual(previewCalls[#previewCalls], true, "preview enabled")
assertTrue(callbacks.BFI_HideMythicPlusPreview,
    "preview cleanup callback is registered")
callbacks.BFI_HideMythicPlusPreview()
assertEqual(previewCalls[#previewCalls], false,
    "leaving the options hides the preview")
assertEqual(preview.checked, false,
    "leaving the options resets the preview control")

local width = findByLabel(sliders, "Width")
assertTrue(width, "Mythic+ width slider")
assertEqual(width.minimum, 260, "width minimum")
assertEqual(width.maximum, 500, "width maximum")
assertEqual(width.label.justifyH, "LEFT",
    "width title follows left-aligned AF option labels")
assertEqual(width.label.point[1], "BOTTOMLEFT",
    "width title uses the AF option-label anchor")
assertEqual(width.label.point[4], 2,
    "width title uses the AF option-label inset")
width.onValueChanged(410)
assertEqual(info.cfg.width, 410, "width setting")

local xOffset = findByLabel(sliders, "X Offset")
local yOffset = findByLabel(sliders, "Y Offset")
assertTrue(xOffset and yOffset, "Mythic+ position sliders")
assertEqual(xOffset.minimum, -500, "X position minimum")
assertEqual(xOffset.maximum, 500, "X position maximum")
assertEqual(yOffset.minimum, -500, "Y position minimum")
assertEqual(yOffset.maximum, 500, "Y position maximum")
assertEqual(yOffset.point[5], -40,
    "Y position row clears the width slider values")
xOffset.afterValueChanged(42)
yOffset.afterValueChanged(-73)
assertEqual(info.cfg.position[2], 42, "X position setting")
assertEqual(info.cfg.position[3], -73, "Y position setting")
assertEqual(fires[#fires][1], "BFI_UpdateModule",
    "position edits reload the Mythic+ frame")
assertEqual(xOffset.label.justifyH, "LEFT",
    "X position title follows left-aligned AF option labels")
assertEqual(yOffset.label.justifyH, "LEFT",
    "Y position title follows left-aligned AF option labels")
assertEqual(xOffset.label.point[1], "BOTTOMLEFT",
    "X position title uses the AF option-label anchor")
assertEqual(yOffset.label.point[1], "BOTTOMLEFT",
    "Y position title uses the AF option-label anchor")

local cutoff = findByLabel(sliders, "Extended-run Baseline Cutoff")
assertTrue(cutoff, "extended-run cutoff slider")
assertEqual(cutoff.label.justifyH, "LEFT",
    "extended-run title follows left-aligned AF option labels")
assertEqual(cutoff.label.point[1], "BOTTOMLEFT",
    "extended-run title uses the AF option-label anchor")
assertTrue(cutoff.tooltip and #cutoff.tooltip == 3,
    "extended-run guidance uses the AF slider tooltip")
cutoff.onValueChanged(1.75)
assertEqual(info.cfg.extendedRunMultiplier, 1.75,
    "extended-run cutoff setting")

local clearHistory = findByLabel(buttons, "Clear Mythic+ History")
assertTrue(clearHistory, "clear-history action")
clearHistory.onClick()
assertEqual(clearHistoryCalls, 0, "history is not cleared before confirmation")
assertEqual(#dialogs, 1, "clear-history confirmation")
dialogs[1].onConfirm()
assertEqual(clearHistoryCalls, 1, "confirmed history clear")

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local loadXML = readFile("Modules/UIWidgets/Load.xml")
local historyAt = assert(loadXML:find('file="MythicPlusHistory.lua"', 1, true))
local modelAt = assert(loadXML:find('file="MythicPlusModel.lua"', 1, true))
local meterAt = assert(loadXML:find('file="MythicPlusMeter.lua"', 1, true))
local analysisAt = assert(loadXML:find('file="MythicPlusAnalysis.lua"', 1, true))
local runtimeAt = assert(loadXML:find('file="MythicPlus.lua"', 1, true))
assertTrue(historyAt < modelAt and modelAt < meterAt
    and meterAt < analysisAt and analysisAt < runtimeAt,
    "Mythic+ dependency load order")

local toc = readFile("BFInfinite.toc")
local interfaceVersion = toc:match("## Interface: ([^\r\n]+)")
assertEqual(interfaceVersion, "120100", "12.1-only interface declaration")
assertTrue(toc:find("BFIMythicPlusHistory", 1, true),
    "Mythic+ saved variable declaration")

local optionsFrameSource = readFile("Options/OptionsFrame.lua")
local optionsHideAt = assert(optionsFrameSource:find(
    "optionsFrame:SetOnHide(function()",
    1,
    true
))
local previewCleanupAt = assert(optionsFrameSource:find(
    'AF.Fire("BFI_HideMythicPlusPreview")',
    optionsHideAt,
    true
))
assertTrue(previewCleanupAt - optionsHideAt < 200,
    "closing the options frame clears the Mythic+ preview")

print("mythic_plus_options_integration_test.lua: ok")
