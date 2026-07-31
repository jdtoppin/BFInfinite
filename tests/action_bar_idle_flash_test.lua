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

local timerCreations = 0
local assistedCombatRate = "0.2"
local assistedCombatRateCallback
local actionBar = makeNamespace()
function actionBar.IsAssistedCombatAction(action)
    return action == 42
end
local assistedCombat = {
    nextSpell = 101,
}
function assistedCombat.GetNextCastSpell()
    return assistedCombat.nextSpell
end
local spellAPI = makeNamespace()
function spellAPI.GetSpellTexture(spellID)
    return "spell:" .. tostring(spellID)
end
local timerAPI = {}
function timerAPI.NewTicker(interval, callback)
    timerCreations = timerCreations + 1
    local ticker = {
        callback = callback,
        interval = interval,
    }
    function ticker:Cancel()
        self.cancelled = true
    end
    return ticker
end
local cvarAPI = makeNamespace()
function cvarAPI.GetCVar()
    return assistedCombatRate
end
local cvarCallbackRegistry = {}
function cvarCallbackRegistry:RegisterCallback(name, callback)
    if name == "assistedCombatIconUpdateRate" then
        assistedCombatRateCallback = callback
    end
end

local environment = {
    _G = false,
    AbstractFramework = {},
    ATTACK_BUTTON_FLASH_TIME = 0.4,
    C_ActionBar = actionBar,
    C_AssistedCombat = assistedCombat,
    C_Container = makeNamespace(),
    C_CVar = cvarAPI,
    C_Item = makeNamespace(),
    C_LevelLink = makeNamespace(),
    C_Spell = spellAPI,
    C_SpellActivationOverlay = makeNamespace(),
    C_SpellBook = makeNamespace(),
    C_ToyBox = makeNamespace(),
    C_Timer = timerAPI,
    C_UnitAuras = makeNamespace(),
    CVarCallbackRegistry = cvarCallbackRegistry,
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

local function makeAssistedButton()
    local button = {
        _state_type = "action",
        _state_action = 42,
        visible = true,
        config = {
            outOfRangeColoring = "button",
            colors = {
                range = {1, 0, 0},
                mana = {0, 0, 1},
                notUsable = {0.4, 0.4, 0.4},
            },
        },
        cooldown = {},
        chargeCooldown = {},
        lossOfControlCooldown = {},
        Count = {},
        icon = {},
        AssistedCombatRotationFrame = {shown = true},
    }
    function button.AssistedCombatRotationFrame:IsShown()
        return self.shown
    end
    function button:IsVisible()
        return self.visible
    end
    function button:GetTexture()
        return "fallback"
    end
    function button:GetCooldownInfo()
        return {isActive = false}
    end
    function button:GetChargeInfo()
        return {isActive = false}
    end
    function button:GetLossOfControlCooldownInfo()
        return {isActive = false, shouldReplaceNormalCooldown = false}
    end
    function button:GetCooldownDuration()
    end
    function button:GetChargeDuration()
    end
    function button:GetLossOfControlCooldownDuration()
    end
    function button:HasAction()
        return true
    end
    function button:GetDisplayCount()
        return 1
    end
    function button:IsUsable()
        return true, false
    end
    function button.cooldown:Clear()
        button.cooldownUpdates = (button.cooldownUpdates or 0) + 1
    end
    button.chargeCooldown.Clear = button.cooldown.Clear
    button.lossOfControlCooldown.Clear = button.cooldown.Clear
    function button.Count:SetText(text)
        self.text = text
    end
    function button.icon:SetTexture(texture)
        self.texture = texture
    end
    function button.icon:Show()
        self.shown = true
    end
    function button.icon:SetVertexColor()
    end
    function button.icon:SetDesaturated()
    end
    return button
end

local assistedFirst = makeAssistedButton()
generic.OnShow(assistedFirst)
assertEqual(timerCreations, 1, "first assisted button creates one shared ticker")
assertEqual(library.assistedCombatTicker.interval, 0.2,
    "assisted ticker has a 5 Hz ceiling")
assertEqual(assistedFirst.icon.texture, "spell:101",
    "assisted registration paints the current recommendation")
assertEqual(library.buttonToSlot[assistedFirst], 42,
    "visible action registers range checking")

local originalAssistedTicker = library.assistedCombatTicker
assistedCombatRate = "0.8"
assistedCombatRateCallback()
assertEqual(originalAssistedTicker.cancelled, true,
    "runtime assisted rate change cancels the old ticker")
assertEqual(library.assistedCombatTicker.interval, 0.8,
    "runtime assisted rate change restarts at the new cadence")
assertEqual(timerCreations, 2,
    "runtime assisted rate change creates one replacement ticker")

local assistedSecond = makeAssistedButton()
generic.OnShow(assistedSecond)
assertEqual(timerCreations, 2, "multiple assisted buttons share one ticker")
local assistedTicker = library.assistedCombatTicker
assistedCombat.nextSpell = 202
assistedTicker.callback()
assertEqual(assistedFirst.icon.texture, "spell:202",
    "shared ticker updates first assisted button")
assertEqual(assistedSecond.icon.texture, "spell:202",
    "shared ticker updates second assisted button")

assistedFirst.visible = false
generic.OnHide(assistedFirst)
assertEqual(library.assistedCombatButtons[assistedFirst], nil,
    "hidden assisted button deregisters")
assertEqual(library.buttonToSlot[assistedFirst], nil,
    "hidden action releases range checking")
assertEqual(assistedTicker.cancelled, nil,
    "shared ticker remains for another visible assisted button")
assistedSecond.visible = false
generic.OnHide(assistedSecond)
assertEqual(assistedTicker.cancelled, true,
    "last hidden assisted button cancels shared ticker")
assertEqual(library.assistedCombatTicker, nil,
    "assisted ticker is released at idle")

local sourceFile = assert(io.open(libraryPath, "r"))
local source = sourceFile:read("*a")
sourceFile:close()
assertEqual(source:match('self:SetScript%("OnUpdate", Generic%.OnUpdate%)'), nil,
    "per-button OnUpdate attachment removed")
assertContains(source, "NonActionButtons%[self%] = nil%s+StopFlash%(self%)",
    "buttons that lose their action must stop flashing")
assertContains(source, "else%s+StopFlash%(self%)%s+self%.icon:Hide%(%)",
    "buttons that lose their texture must stop flashing")
assertContains(source,
    'assistedCombatRotationFrame:SetScript%("OnUpdate", nil%)',
    "native assisted per-frame updater removed")
assertContains(source, "lib%.actionSlotButtons%[arg1%]",
    "slot changes use a targeted action-slot map")
assertContains(source,
    "elseif arg1 == 0 then.-for button in next, ButtonRegistry do",
    "full slot invalidation still refreshes empty action buttons")

local commonPath = "Modules/ActionBars/Common.lua"
local commonFile = assert(io.open(commonPath, "r"))
local commonSource = commonFile:read("*a")
commonFile:close()
assertContains(commonSource, 'b:SetScript%("OnUpdate", nil%)',
    "native pet per-button updater removed")
assertContains(commonSource, "petFlashController:SetScript",
    "pet attack flashing uses one shared controller")
assertContains(commonSource, "if b%.SlotArt then b%.SlotArt:Hide%(%) end",
    "redundant Retail slot art is hidden")

print("action_bar_idle_flash_test.lua: ok")
