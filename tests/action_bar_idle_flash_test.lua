local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertContains(source, pattern, message)
    if not source:match(pattern) then
        error(message or ("missing source pattern: " .. pattern), 2)
    end
end

local function findUpvalue(func, targetName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(func, index)
        if not name then
            return nil
        elseif name == targetName then
            return value
        end
        index = index + 1
    end
end

local function makeFrame()
    local frame = {
        scripts = {},
        shown = true,
    }

    function frame:GetScript(scriptName)
        return self.scripts[scriptName]
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:IsVisible()
        return self.shown
    end

    function frame:SetScript(scriptName, script)
        self.scripts[scriptName] = script
    end

    function frame:Show()
        self.shown = true
    end

    function frame:UnregisterAllEvents()
    end

    return frame
end

local function makeNamespace()
    return setmetatable({}, {
        __index = function(namespace, key)
            local stub = function()
            end
            rawset(namespace, key, stub)
            return stub
        end,
    })
end

local callbackHandler = {}
function callbackHandler:New()
    return {
        Fire = function()
        end,
    }
end

local library = {}
local LibStub = setmetatable({}, {
    __call = function(_, name)
        if name == "CallbackHandler-1.0" then
            return callbackHandler
        end
    end,
})
function LibStub:NewLibrary()
    return library
end

local environment = {
    _G = false,
    AbstractFramework = {},
    ATTACK_BUTTON_FLASH_TIME = 0.4,
    C_ActionBar = makeNamespace(),
    C_Container = makeNamespace(),
    C_CVar = makeNamespace(),
    C_Item = makeNamespace(),
    C_LevelLink = makeNamespace(),
    C_Spell = makeNamespace(),
    C_SpellActivationOverlay = makeNamespace(),
    C_SpellBook = makeNamespace(),
    C_ToyBox = makeNamespace(),
    C_UnitAuras = makeNamespace(),
    CreateFrame = function()
        return makeFrame()
    end,
    Enum = {
        SpellBookSpellBank = {
            Player = 1,
        },
    },
    GetTime = function()
        return 0
    end,
    hooksecurefunc = function()
    end,
    LibStub = LibStub,
    RANGE_INDICATOR = "RANGE",
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 2,
    WOW_PROJECT_CATACLYSM_CLASSIC = 5,
    WOW_PROJECT_CLASSIC = 2,
    WOW_PROJECT_ID = 1,
    WOW_PROJECT_MAINLINE = 1,
    WOW_PROJECT_WRATH_CLASSIC = 3,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local libraryPath = "Libs/LibActionButton-1.0/LibActionButton-1.0.lua"
local chunk, loadError = loadfile(libraryPath)
assertEqual(type(chunk), "function", loadError or "library load")
setfenv(chunk, environment)
chunk()

local controller = library.flashController
local updateController = controller:GetScript("OnUpdate")
assertEqual(type(updateController), "function", "shared flash controller update")
assertEqual(controller:IsShown(), false, "controller sleeps at idle")

local genericMT = findUpvalue(library.CreateButton, "Generic_MT")
local generic = genericMT and genericMT.__index
assertEqual(type(generic), "table", "generic button prototype")
assertEqual(generic.OnUpdate, nil, "button prototype has no idle OnUpdate")

local update = findUpvalue(generic.UpdateAction, "Update")
local updateFlash = findUpvalue(update, "UpdateFlash")
local startFlash = findUpvalue(updateFlash, "StartFlash")
local stopFlash = findUpvalue(updateFlash, "StopFlash")
assertEqual(type(startFlash), "function", "start flash helper")
assertEqual(type(stopFlash), "function", "stop flash helper")

local function makeButton()
    local button = {
        Flash = {
            shown = false,
        },
        visible = true,
    }

    function button.Flash:Hide()
        self.shown = false
    end

    function button.Flash:IsShown()
        return self.shown
    end

    function button.Flash:SetShown(shown)
        self.shown = shown
    end

    function button:IsAutoRepeat()
        return false
    end

    function button:IsCurrentlyActive()
        return false
    end

    function button:IsVisible()
        return self.visible
    end

    function button:SetChecked(checked)
        self.checked = checked
    end

    return button
end

local first = makeButton()
startFlash(first)
assertEqual(first.flashing, true, "flashing state starts")
assertEqual(library.flashingButtons[first], true, "visible flasher registration")
assertEqual(controller:IsShown(), true, "controller wakes for first flasher")

updateController(controller, 0.01)
assertEqual(first.Flash:IsShown(), true, "first flash edge")
assertEqual(first.flashTime, 0.39, "per-button flash cadence")

first.visible = false
generic.OnHide(first)
assertEqual(library.flashingButtons[first], nil, "hidden flasher deregistration")
assertEqual(controller:IsShown(), false, "controller sleeps with hidden flasher")
assertEqual(first.flashing, true, "hidden flasher retains logical state")

first.visible = true
generic.OnShow(first)
assertEqual(library.flashingButtons[first], true, "shown flasher registration")
assertEqual(controller:IsShown(), true, "controller resumes for shown flasher")

local second = makeButton()
startFlash(second)
stopFlash(first)
assertEqual(controller:IsShown(), true, "controller remains active for another flasher")
stopFlash(second)
assertEqual(controller:IsShown(), false, "controller sleeps after last flasher")
assertEqual(second.Flash:IsShown(), false, "stopped flash texture hidden")

local stale = makeButton()
stale.flashing = false
library.flashingButtons[stale] = true
controller:Show()
updateController(controller, 0.01)
assertEqual(library.flashingButtons[stale], nil, "stale flasher cleanup")
assertEqual(controller:IsShown(), false, "controller sleeps after stale cleanup")

local sourceFile = assert(io.open(libraryPath, "r"))
local source = sourceFile:read("*a")
sourceFile:close()
assertEqual(source:match('self:SetScript%("OnUpdate", Generic%.OnUpdate%)'), nil,
    "per-button OnUpdate attachment removed")
assertContains(source, "NonActionButtons%[self%] = nil%s+StopFlash%(self%)",
    "buttons that lose their action must stop flashing")
assertContains(source, "else%s+StopFlash%(self%)%s+self%.icon:Hide%(%)",
    "buttons that lose their texture must stop flashing")

print("action_bar_idle_flash_test.lua: ok")
