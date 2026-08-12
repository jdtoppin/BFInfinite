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
        configLoads = {},
        dropdowns = {},
        positionLoads = {},
        sliders = {},
    }
    local UF = {}
    local AF = {}
    local F = {}
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
    local environment = {
        _G = false,
        AbstractFramework = AF,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
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
    harness.UF = UF

    function harness:ClearLoads()
        self.configLoads = {}
        self.positionLoads = {}
    end

    return harness
end

local function newFrame()
    return {
        indicators = {
            buffs = {},
            debuffs = {},
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
