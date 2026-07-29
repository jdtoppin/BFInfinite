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
local dropdowns = {}
local dialogs = {}
local fires = {}
local previewCalls = {}
local clearHistoryCalls = 0

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
    function button:SetOnClick(callback)
        self.onClick = callback
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
    checkButtons[#checkButtons + 1] = checkButton
    return checkButton
end

function AF.CreateSlider(_, label, width, minimum, maximum, step)
    local slider = {
        labelText = label,
        width = width,
        minimum = minimum,
        maximum = maximum,
        step = step,
    }
    function slider:SetOnValueChanged(callback)
        self.onValueChanged = callback
    end
    function slider:SetAfterValueChanged(callback)
        self.afterValueChanged = callback
    end
    function slider:SetValue(value)
        self.value = value
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

function AF.SetPoint()
end

function AF.LSM_GetFontDropdownItems()
    return {}
end

function AF.LSM_GetFontOutlineDropdownItems()
    return {}
end

local W = {
    MythicPlus = {
        SetPreview = function(shown)
            previewCalls[#previewCalls + 1] = shown
        end,
        ClearHistory = function()
            clearHistoryCalls = clearHistoryCalls + 1
        end,
    },
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
    BFIOptionsFrame_UIWidgetsPanel = {},
    READY_CHECK = "Ready Check",
    RESET = "Reset",
    ROLE_POLL = "Role Poll",
    ipairs = ipairs,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
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
width.onValueChanged(410)
assertEqual(info.cfg.width, 410, "width setting")

local cutoff = findByLabel(sliders, "Extended-run Baseline Cutoff")
assertTrue(cutoff, "extended-run cutoff slider")
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
assertTrue(toc:find("120100", 1, true), "12.1 interface declaration")
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
