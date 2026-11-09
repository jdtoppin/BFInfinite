local source = "Modules/UnitFrames/Indicators/IncDmgHealText.lua"
local secretAmount = setmetatable({}, {
    __lt = function() error("secret amount compared in Lua") end,
    __tostring = function() error("secret amount converted in Lua") end,
})

local eventCallback
local displayed
local formatterCalls = {}
local AF = {
    isAsian = false,
    FormatSecretNumber = function(value)
        assert(value == secretAmount)
        formatterCalls[#formatterCalls + 1] = "western"
        return "1K"
    end,
    FormatSecretNumber_Asian = function(value)
        assert(value == secretAmount)
        formatterCalls[#formatterCalls + 1] = "asian"
        return "1千"
    end,
    FormatNumber = function() error("unsafe formatter called") end,
    FormatNumber_Asian = function() error("unsafe formatter called") end,
    SetFont = function() end,
    UnpackColor = function() return 1, 1, 1 end,
    CreateContinualFadeInOutAnimation = function() end,
    AddEventHandler = function() end,
    noop = function() end,
}

local UF = {LoadIndicatorPosition = function() end}
local BFI = {modules = {UnitFrames = UF}}
local environment = {_G = {AbstractFramework = AF}}
setmetatable(environment, {__index = _G})
local chunk = assert(loadfile(source))
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local text = {
    Hide = function() end,
    RegisterUnitEvent = function(_, event, unit, callback)
        assert(event == "UNIT_COMBAT" and unit == "player")
        eventCallback = callback
    end,
    SetTextColor = function() end,
    SetFormattedText = function(_, formatString, value, suffix)
        assert(formatString == "%s%s")
        displayed = {value, suffix}
    end,
    FadeInOut = function() end,
}
local parent = {CreateFontString = function() return text end}
local indicator = UF.CreateIncDmgHealText(parent, "TestIncomingText")
local config = {
    font = {},
    position = {},
    types = {
        damage = {enabled = true, color = {1, 1, 1}},
        healing = {enabled = true, color = {1, 1, 1}},
    },
    format = {numeric = "current_short", useAsianUnits = false},
}

indicator:LoadConfig(config)
indicator:Enable()
eventCallback(indicator, "UNIT_COMBAT", "player", "HEAL", "CRITICAL", secretAmount, 0)
assert(formatterCalls[1] == "western")
assert(displayed[1] == "1K" and displayed[2] == "!")

AF.isAsian = true
config.format.useAsianUnits = true
indicator:LoadConfig(config)
eventCallback(indicator, "UNIT_COMBAT", "player", "WOUND", "", secretAmount, 0)
assert(formatterCalls[2] == "asian")
assert(displayed[1] == "1千" and displayed[2] == "")

config.format.numeric = "current"
indicator:LoadConfig(config)
eventCallback(indicator, "UNIT_COMBAT", "player", "WOUND", "", secretAmount, 0)
assert(displayed[1] == secretAmount)
assert(#formatterCalls == 2)

print("unit_frame_inc_dmg_heal_text_secret_test: ok")
