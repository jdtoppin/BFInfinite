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

local function makeWidget(kind, harness)
    local widget = {
        kind = kind,
    }

    function widget:SetChecked(value)
        self.checked = value
    end

    function widget:SetEnabled(value)
        self.enabled = value
    end

    function widget:SetItems(items)
        self.items = items
    end

    function widget:SetLabel(value)
        self.label = value
    end

    function widget:SetOnCheck(callback)
        self.onCheck = callback
    end

    function widget:SetOnSelect(callback)
        self.onSelect = callback
    end

    function widget:SetOnValueChanged(callback)
        self.onValueChanged = callback
    end

    function widget:SetSelectedValue(value)
        self.selectedValue = value
    end

    function widget:SetText(value)
        self.text = value
    end

    function widget:SetValue(value)
        self.value = value
    end

    harness[kind][#harness[kind] + 1] = widget
    return widget
end

local function makeHarness()
    local harness = {
        checkButtons = {},
        callbacks = {},
        configLoads = {},
        dialogs = {},
        dropdowns = {},
        positionLoads = {},
        reloadChecks = 0,
        reloadCalls = 0,
        sliders = {},
    }
    local UF = {}
    local AF = {}
    local F = {}
    local availableDialogs = {}
    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })

    function AF.CreateBorderedFrame()
        return {}
    end

    function AF.CreateCheckButton()
        return makeWidget("checkButtons", harness)
    end

    function AF.CreateDropdown()
        return makeWidget("dropdowns", harness)
    end

    function AF.CreateSlider()
        return makeWidget("sliders", harness)
    end

    function AF.GetDropdownItems_AnchorPoint()
        return {
            {text = "TOPLEFT", value = "TOPLEFT"},
            {text = "BOTTOMRIGHT", value = "BOTTOMRIGHT"},
        }
    end

    function AF.Debug()
    end

    function AF.GetColorStr()
        return ""
    end

    function AF.RegisterCallback(event, callback)
        harness.callbacks[event] = callback
    end

    local function CreateDialog()
        local dialog = {}

        function dialog:Hide()
            if not self.active then return end

            self.shown = false
            self.active = false
            self.onConfirm = nil
            self.onCancel = nil
            availableDialogs[#availableDialogs + 1] = self
        end

        function dialog:IsShown()
            return self.shown == true
        end

        function dialog:SetOnConfirm(callback)
            self.onConfirm = callback
        end

        function dialog:SetOnCancel(callback)
            self.onCancel = callback
        end

        return dialog
    end

    function AF.IsDialogActive(dialog)
        return dialog and dialog.active == true
    end

    function AF.GetDialog(owner, text, width)
        local dialog =
            table.remove(availableDialogs) or CreateDialog()
        dialog.active = true
        dialog.owner = owner
        dialog.shown = true
        dialog.text = text
        dialog.width = width

        harness.dialogs[#harness.dialogs + 1] = dialog
        return dialog
    end

    function AF.SetPoint()
    end

    function AF.SetEnabled(enabled, ...)
        for index = 1, select("#", ...) do
            local widget = select(index, ...)
            widget:SetEnabled(enabled)
        end
    end

    function UF.LoadIndicatorConfig(frame, id, config)
        harness.configLoads[#harness.configLoads + 1] = {
            frame = frame,
            id = id,
            config = config,
        }
    end

    function UF.LoadIndicatorPosition(
        indicator,
        position,
        anchorTo,
        parent
    )
        harness.positionLoads[#harness.positionLoads + 1] = {
            indicator = indicator,
            position = position,
            anchorTo = anchorTo,
            parent = parent,
        }
    end

    local BFI = {
        funcs = F,
        L = L,
        modules = {
            UnitFrames = UF,
        },
    }
    local unitFramesPanel = {}
    local function ReloadUI()
        harness.reloadCalls = harness.reloadCalls + 1
    end
    local environment = {
        _G = false,
        AbstractFramework = AF,
        BFIOptionsFrame_UnitFramesPanel = unitFramesPanel,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        rawget = rawget,
        ReloadUI = ReloadUI,
        select = select,
        string = string,
        table = table,
        tinsert = table.insert,
        tostring = tostring,
        type = type,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected UnitFrames_Options global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError =
        loadfile("Options/UnitFrames_Options.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local builders
    local index = 1
    while true do
        local name, value = debug.getupvalue(
            F.GetUnitFrameOptions,
            index
        )
        if not name then break end
        if name == "builder" then
            builders = value
            break
        end
        index = index + 1
    end
    assertTrue(builders, "options builder registry")

    harness.AF = AF
    harness.builders = builders
    harness.F = F
    harness.reloadUI = ReloadUI
    harness.UF = UF
    harness.unitFramesPanel = unitFramesPanel

    function harness:ConfirmDialog(dialog)
        local callback = dialog.onConfirm
        if callback then callback() end
        dialog:Hide()
    end

    function harness:CancelDialog(dialog)
        local callback = dialog.onCancel
        if callback then callback() end
        dialog:Hide()
    end

    function harness:ClearLoads()
        self.configLoads = {}
        self.positionLoads = {}
        self.reloadChecks = 0
    end

    function harness:FireCallback(event, ...)
        local callback = self.callbacks[event]
        assertTrue(callback, "missing callback: " .. event)
        callback(event, ...)
    end

    return harness
end

local function newFrame()
    return {
        indicators = {
            buffs = {},
            debuffs = {},
            dispels = {},
            healthBar = {},
            raidIcon = {},
        },
    }
end

local function newInfo(id, owner)
    owner = owner or "target"
    local target
    if owner == "party" or owner == "raid" then
        local count = owner == "party" and 5 or 40
        target = {
            header = {},
        }
        for index = 1, count do
            target.header[index] = newFrame()
        end
    elseif owner == "boss" then
        target = {}
        for index = 1, 8 do
            target[index] = newFrame()
        end
    else
        target = newFrame()
    end

    local frame = {
        owner = owner,
        id = id,
        target = target,
    }
    frame.cfg = {
        anchorTo = "root",
        position = {"TOPLEFT", "TOPLEFT", 1, -1},
        tooltip = {
            enabled = true,
            anchorTo = "self",
            position = {
                "BOTTOMRIGHT",
                "TOPRIGHT",
                1,
                -1,
            },
        },
    }
    return frame
end

local function GetInfoFrames(info)
    if info.owner == "party" or info.owner == "raid" then
        return info.target.header
    elseif info.owner == "boss" then
        return info.target
    end
    return {info.target}
end

local function SetReloadRequirement(info, harness, predicate)
    for index, frame in ipairs(GetInfoFrames(info)) do
        frame.indicators[info.id].RequiresReloadForConfig =
            function(_, config)
                harness.reloadChecks =
                    harness.reloadChecks + 1
                assertEqual(
                    #harness.configLoads,
                    0,
                    "reload query precedes config fan-out"
                )
                assertEqual(
                    config,
                    info.cfg,
                    "reload query config identity"
                )
                return predicate(index)
            end
    end
end

local dependentHarness = makeHarness()
local dependentPane = dependentHarness.builders.frameLevel({})
local dependentInfo = newInfo("healthBar", "raid")
dependentInfo.cfg.frameLevel = 3
local raidDispels = {sentinel = "raid-dispels"}
dependentHarness.UF.config = {
    raid = {
        indicators = {
            dispels = raidDispels,
        },
    },
}
for _, frame in ipairs(dependentInfo.target.header) do
    frame.indicators.dispels.RequiresReloadForConfig =
        function(_, config)
            dependentHarness.reloadChecks =
                dependentHarness.reloadChecks + 1
            assertEqual(config, raidDispels,
                "Raid dependent Dispel config identity")
            return false
        end
end
dependentPane.Load(dependentInfo)
dependentHarness:ClearLoads()
dependentHarness.sliders[1].onValueChanged(4)
assertEqual(#dependentHarness.configLoads, 80,
    "Raid Health Bar and Dispel dependent fan-out")
for index, load in ipairs(dependentHarness.configLoads) do
    local expectedID = index <= 40 and "healthBar" or "dispels"
    assertEqual(load.id, expectedID,
        "Raid dependent ordered load " .. index)
    if index > 40 then
        assertEqual(load.config, raidDispels,
            "Raid dependent Dispel config " .. index)
    end
end
assertEqual(dependentHarness.reloadChecks, 40,
    "Raid dependent Dispel reload checks")
assertEqual(#dependentHarness.dialogs, 0,
    "Raid dependent tuning avoids reload prompt")

for _, case in ipairs({
    {owner = "target", count = 1},
    {owner = "party", count = 5},
    {owner = "boss", count = 8},
}) do
    local harness = makeHarness()
    local pane = harness.builders.tooltip({})
    local info = newInfo("buffs", case.owner)
    SetReloadRequirement(info, harness, function(index)
        return index == case.count
    end)
    pane.Load(info)
    harness:ClearLoads()
    harness.checkButtons[1].onCheck(false)

    assertEqual(
        #harness.configLoads,
        case.count,
        case.owner .. " structural aura fan-out"
    )
    assertEqual(
        harness.reloadChecks,
        case.count,
        case.owner .. " structural aura reload checks"
    )
    assertEqual(
        #harness.dialogs,
        1,
        case.owner .. " structural aura reload prompt"
    )
end

local reloadHarness = makeHarness()
local reloadPane = reloadHarness.builders.tooltip({})
local reloadInfo = newInfo("debuffs", "raid")
SetReloadRequirement(reloadInfo, reloadHarness, function()
    return true
end)
reloadPane.Load(reloadInfo)
reloadHarness:ClearLoads()
reloadHarness.checkButtons[1].onCheck(false)

assertEqual(
    #reloadHarness.configLoads,
    40,
    "Raid structural aura fan-out"
)
assertEqual(
    #reloadHarness.dialogs,
    1,
    "Raid structural aura prompt count"
)
assertEqual(
    reloadHarness.dialogs[1].owner,
    reloadHarness.unitFramesPanel,
    "Raid reload prompt owner"
)
assertTrue(
    reloadHarness.dialogs[1].text:find(
        "UI reload",
        1,
        true
    ),
    "Raid reload prompt text"
)
assertTrue(
    type(reloadHarness.dialogs[1].onConfirm) == "function",
    "Raid reload confirmation callback"
)
assertTrue(
    type(reloadHarness.dialogs[1].onCancel) == "function",
    "Raid reload cancellation callback"
)
assertEqual(
    reloadHarness.reloadCalls,
    0,
    "Raid structural change never auto-reloads"
)

reloadHarness:ClearLoads()
reloadHarness.checkButtons[1].onCheck(true)
assertEqual(
    #reloadHarness.configLoads,
    40,
    "repeated Raid structural aura fan-out"
)
assertEqual(
    #reloadHarness.dialogs,
    1,
    "shown Raid reload prompt deduplicated"
)
assertEqual(
    reloadHarness.reloadCalls,
    0,
    "deduplicated Raid prompt never auto-reloads"
)

local releasedReloadDialog = reloadHarness.dialogs[1]
releasedReloadDialog:Hide()
assertTrue(
    not reloadHarness.AF.IsDialogActive(releasedReloadDialog),
    "hidden Raid reload prompt released"
)

local otherConfirmationCalls = 0
local reusedDialog = reloadHarness.AF.GetDialog(
    reloadHarness.unitFramesPanel,
    "Another confirmation",
    250
)
assertEqual(
    reusedDialog,
    releasedReloadDialog,
    "released reload frame reused by another confirmation"
)
reusedDialog:SetOnConfirm(function()
    otherConfirmationCalls = otherConfirmationCalls + 1
    reloadHarness:ClearLoads()
    reloadHarness.checkButtons[1].onCheck(false)
end)
reloadHarness:ConfirmDialog(reusedDialog)

assertEqual(
    otherConfirmationCalls,
    1,
    "reused confirmation callback invoked"
)
assertEqual(
    #reloadHarness.configLoads,
    40,
    "reused confirmation triggers Raid aura load"
)
assertEqual(
    #reloadHarness.dialogs,
    3,
    "reused non-aura dialog does not suppress reload prompt"
)

local replacementReloadDialog = reloadHarness.dialogs[3]
assertTrue(
    replacementReloadDialog ~= reusedDialog,
    "reload prompt does not claim active pooled dialog"
)
assertTrue(
    reloadHarness.AF.IsDialogActive(replacementReloadDialog),
    "replacement reload prompt active"
)
assertTrue(
    replacementReloadDialog.text:find("UI reload", 1, true),
    "replacement reload prompt text"
)

reloadHarness:ClearLoads()
reloadHarness.checkButtons[1].onCheck(true)
assertEqual(
    #reloadHarness.dialogs,
    3,
    "active replacement reload prompt deduplicated"
)

reloadHarness:CancelDialog(replacementReloadDialog)
assertEqual(
    reloadHarness.reloadCalls,
    0,
    "cancelling reload prompt does not reload"
)
reloadHarness:ClearLoads()
reloadHarness.checkButtons[1].onCheck(false)
assertEqual(
    #reloadHarness.dialogs,
    4,
    "cancelled reload prompt can be shown again"
)

reloadHarness:ConfirmDialog(reloadHarness.dialogs[4])
assertEqual(
    reloadHarness.reloadCalls,
    1,
    "confirming reload prompt reloads once"
)

local globalReloadHarness = makeHarness()
globalReloadHarness:FireCallback(
    "BFI_NativeAuraReloadRequired"
)
assertEqual(
    #globalReloadHarness.dialogs,
    1,
    "Global Colors reload callback prompt"
)
globalReloadHarness:FireCallback(
    "BFI_NativeAuraReloadRequired"
)
assertEqual(
    #globalReloadHarness.dialogs,
    1,
    "Global Colors reload callback deduplicated"
)
globalReloadHarness:CancelDialog(
    globalReloadHarness.dialogs[1]
)
globalReloadHarness:FireCallback(
    "BFI_NativeAuraReloadRequired"
)
assertEqual(
    #globalReloadHarness.dialogs,
    2,
    "Global Colors reload callback can reopen"
)

local tuningHarness = makeHarness()
local tuningPane = tuningHarness.builders.tooltip({})
local tuningInfo = newInfo("debuffs", "raid")
SetReloadRequirement(tuningInfo, tuningHarness, function()
    return false
end)
tuningPane.Load(tuningInfo)
tuningHarness:ClearLoads()
tuningHarness.checkButtons[1].onCheck(false)
assertEqual(
    tuningHarness.reloadChecks,
    40,
    "Raid tuning reload checks"
)
assertEqual(
    #tuningHarness.configLoads,
    40,
    "Raid tuning fan-out"
)
assertEqual(
    #tuningHarness.dialogs,
    0,
    "Raid tuning avoids reload prompt"
)

local legacyHarness = makeHarness()
local legacyPane = legacyHarness.builders.tooltip({})
local legacyInfo = newInfo("buffs")
legacyPane.Load(legacyInfo)
legacyHarness:ClearLoads()
legacyHarness.checkButtons[1].onCheck(false)
assertEqual(
    #legacyHarness.configLoads,
    1,
    "legacy aura config load"
)
assertEqual(
    #legacyHarness.dialogs,
    0,
    "legacy aura avoids reload prompt"
)

local nonAuraHarness = makeHarness()
local nonAuraPane = nonAuraHarness.builders.frameLevel({})
local nonAuraInfo = newInfo("raidIcon", "raid")
nonAuraInfo.cfg.frameLevel = 1
SetReloadRequirement(nonAuraInfo, nonAuraHarness, function()
    return true
end)
nonAuraPane.Load(nonAuraInfo)
nonAuraHarness:ClearLoads()
nonAuraHarness.sliders[1].onValueChanged(2)
assertEqual(
    nonAuraHarness.reloadChecks,
    0,
    "non-aura avoids reload checks"
)
assertEqual(
    #nonAuraHarness.configLoads,
    40,
    "non-aura config fan-out"
)
assertEqual(
    #nonAuraHarness.dialogs,
    0,
    "non-aura avoids reload prompt"
)

local positionHarness = makeHarness()
local positionPane =
    positionHarness.builders["position,anchorTo"]({})
local positionControls = {
    {
        widget = positionHarness.dropdowns[1],
        callback = "onSelect",
        value = "healthBar",
        get = function(info)
            return info.cfg.anchorTo
        end,
    },
    {
        widget = positionHarness.dropdowns[2],
        callback = "onSelect",
        value = "BOTTOMRIGHT",
        get = function(info)
            return info.cfg.position[1]
        end,
    },
    {
        widget = positionHarness.dropdowns[3],
        callback = "onSelect",
        value = "BOTTOMRIGHT",
        get = function(info)
            return info.cfg.position[2]
        end,
    },
    {
        widget = positionHarness.sliders[1],
        callback = "onValueChanged",
        value = 7,
        get = function(info)
            return info.cfg.position[3]
        end,
    },
    {
        widget = positionHarness.sliders[2],
        callback = "onValueChanged",
        value = -8,
        get = function(info)
            return info.cfg.position[4]
        end,
    },
}

for _, id in ipairs({"buffs", "debuffs"}) do
    local auraInfo = newInfo(id)
    positionPane.Load(auraInfo)
    for index, control in ipairs(positionControls) do
        positionHarness:ClearLoads()
        control.widget[control.callback](
            control.value
        )
        assertEqual(
            control.get(auraInfo),
            control.value,
            id .. " position control " .. index .. " saved"
        )
        assertEqual(
            #positionHarness.configLoads,
            1,
            id .. " position control " .. index
                .. " full reload"
        )
        assertEqual(
            positionHarness.configLoads[1].id,
            id,
            id .. " position reload id"
        )
        assertEqual(
            #positionHarness.positionLoads,
            0,
            id .. " position avoids partial reload"
        )
    end
end

local iconInfo = newInfo("raidIcon")
positionPane.Load(iconInfo)
for index, control in ipairs(positionControls) do
    positionHarness:ClearLoads()
    control.widget[control.callback](control.value)
    assertEqual(
        control.get(iconInfo),
        control.value,
        "non-aura position control " .. index .. " saved"
    )
    assertEqual(
        #positionHarness.configLoads,
        0,
        "non-aura position avoids full reload"
    )
    assertEqual(
        #positionHarness.positionLoads,
        1,
        "non-aura position partial reload"
    )
end

for _, case in ipairs({
    {owner = "target", count = 1},
    {owner = "party", count = 5},
    {owner = "raid", count = 40},
    {owner = "boss", count = 8},
}) do
    local info = newInfo("debuffs", case.owner)
    positionPane.Load(info)
    positionHarness:ClearLoads()
    positionHarness.dropdowns[2].onSelect("BOTTOMRIGHT")
    assertEqual(
        #positionHarness.configLoads,
        case.count,
        case.owner .. " aura position reload fan-out"
    )
    for _, load in ipairs(positionHarness.configLoads) do
        assertEqual(
            load.id,
            "debuffs",
            case.owner .. " aura position reload id"
        )
        assertEqual(
            load.config,
            info.cfg,
            case.owner .. " aura position config identity"
        )
    end
    assertEqual(
        #positionHarness.positionLoads,
        0,
        case.owner .. " aura position avoids partial reload"
    )
end

local tooltipHarness = makeHarness()
local tooltipPane = tooltipHarness.builders.tooltip({})
local tooltipInfo = newInfo("buffs")
tooltipPane.Load(tooltipInfo)
local tooltipControls = {
    {
        widget = tooltipHarness.checkButtons[1],
        callback = "onCheck",
        value = false,
        get = function(info)
            return info.cfg.tooltip.enabled
        end,
    },
    {
        widget = tooltipHarness.dropdowns[1],
        callback = "onSelect",
        value = "root",
        get = function(info)
            return info.cfg.tooltip.anchorTo
        end,
    },
    {
        widget = tooltipHarness.dropdowns[2],
        callback = "onSelect",
        value = "TOPLEFT",
        get = function(info)
            return info.cfg.tooltip.position[1]
        end,
    },
    {
        widget = tooltipHarness.dropdowns[3],
        callback = "onSelect",
        value = "BOTTOMRIGHT",
        get = function(info)
            return info.cfg.tooltip.position[2]
        end,
    },
    {
        widget = tooltipHarness.sliders[1],
        callback = "onValueChanged",
        value = 9,
        get = function(info)
            return info.cfg.tooltip.position[3]
        end,
    },
    {
        widget = tooltipHarness.sliders[2],
        callback = "onValueChanged",
        value = -6,
        get = function(info)
            return info.cfg.tooltip.position[4]
        end,
    },
}

for index, control in ipairs(tooltipControls) do
    tooltipHarness:ClearLoads()
    control.widget[control.callback](control.value)
    assertEqual(
        control.get(tooltipInfo),
        control.value,
        "aura tooltip control " .. index .. " saved"
    )
    assertEqual(
        #tooltipHarness.configLoads,
        1,
        "aura tooltip control " .. index .. " live reload"
    )
    assertEqual(
        #tooltipHarness.positionLoads,
        0,
        "aura tooltip avoids partial reload"
    )
end

for _, id in ipairs({"general_single", "general_party"}) do
    local info = newInfo(id)
    tooltipPane.Load(info)
    for index, control in ipairs(tooltipControls) do
        tooltipHarness:ClearLoads()
        control.widget[control.callback](control.value)
        assertEqual(
            control.get(info),
            control.value,
            id .. " tooltip control " .. index .. " saved"
        )
        assertEqual(
            #tooltipHarness.configLoads,
            0,
            id .. " tooltip avoids indicator reload"
        )
        assertEqual(
            #tooltipHarness.positionLoads,
            0,
            id .. " tooltip avoids position reload"
        )
    end
end

print("unit frame aura options tests: ok")
