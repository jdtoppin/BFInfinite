local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertContains(source, text, message)
    if not source:find(text, 1, true) then
        error(message or ("missing source text: " .. text), 2)
    end
end

local function assertNotContains(source, text, message)
    if source:find(text, 1, true) then
        error(message or ("unexpected source text: " .. text), 2)
    end
end

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local callbacks = {}
local events = {}
local fired = {}
local settingsCallbacks = {}
local nativeEnabled = false
local nativeModifier = "NONE"
local inCombat = false
local cvarWrites = 0
local modifierWrites = 0
local writeOrder = {}
local registeredSettings = false
local settingsWrites = {}

local function invokeEvent(event, ...)
    local registered = events[event]
    if not registered then return end

    local pending = {}
    for callback in pairs(registered) do
        pending[#pending + 1] = callback
    end
    for _, callback in ipairs(pending) do
        callback(nil, event, ...)
    end
end

local AF = {}
function AF.Fire(event, ...)
    fired[#fired + 1] = {event, ...}
end
function AF.RegisterCallback(event, callback, priority)
    callbacks[event] = {
        callback = callback,
        priority = priority,
    }
end

local AB = {
    config = {
        general = {enabled = false},
        sharedButtonConfig = {
            cast = {
                mouseover = {false, "NONE"},
            },
        },
    },
}

function AB:RegisterEvent(event, callback)
    events[event] = events[event] or {}
    events[event][callback] = true
end

function AB:UnregisterEvent(event, callback)
    if events[event] then
        events[event][callback] = nil
    end
end

local BFI = {
    modules = {
        ActionBars = AB,
    },
}

local Settings = {}
function Settings.SetOnValueChangedCallback(variable, callback)
    settingsCallbacks[variable] = callback
end
function Settings.GetSetting(variable)
    if not registeredSettings then return end
    if variable == "enableMouseoverCast" or variable == "MOUSEOVERCAST" then
        return true
    end
end
function Settings.SetValue(variable, value, force)
    settingsWrites[#settingsWrites + 1] = {
        variable = variable,
        value = value,
        force = force,
    }

    if variable == "enableMouseoverCast" then
        nativeEnabled = value
        settingsCallbacks[variable]()
        invokeEvent("CVAR_UPDATE", variable, tostring(value))
    else
        nativeModifier = value
        settingsCallbacks[variable]()
        invokeEvent("UPDATE_BINDINGS")
    end
end
function Settings.NotifyUpdate(variable)
    if registeredSettings then
        settingsCallbacks[variable]()
    end
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    GetCVarBool = function(cvar)
        assertEqual(cvar, "enableMouseoverCast", "queried CVar")
        return nativeEnabled
    end,
    GetModifiedClick = function(action)
        assertEqual(action, "MOUSEOVERCAST", "queried modified click")
        return nativeModifier
    end,
    InCombatLockdown = function()
        return inCombat
    end,
    SetCVar = function(cvar, value)
        assertEqual(cvar, "enableMouseoverCast", "written CVar")
        cvarWrites = cvarWrites + 1
        writeOrder[#writeOrder + 1] = "cvar"
        nativeEnabled = value == 1 or value == true
        invokeEvent("CVAR_UPDATE", cvar, tostring(value))
    end,
    SetModifiedClick = function(action, modifier)
        assertEqual(action, "MOUSEOVERCAST", "written modified click")
        modifierWrites = modifierWrites + 1
        writeOrder[#writeOrder + 1] = "modifier"
        nativeModifier = modifier
        invokeEvent("UPDATE_BINDINGS")
    end,
    Settings = Settings,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local controllerPath = "Modules/ActionBars/MouseoverCast.lua"
local chunk, loadError = loadfile(controllerPath)
assertEqual(type(chunk), "function", loadError or "MouseoverCast.lua load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(callbacks.BFI_UpdateProfile.callback), "function",
    "profile callback registered")
assertEqual(callbacks.BFI_UpdateProfile.priority, "low",
    "profile callback runs after Defaults")
assertEqual(type(callbacks.BFI_UpdateModule.callback), "function",
    "module callback registered")
assertEqual(type(settingsCallbacks.enableMouseoverCast), "function",
    "Blizzard CVar setting callback registered")
assertEqual(type(settingsCallbacks.MOUSEOVERCAST), "function",
    "Blizzard modifier setting callback registered")

local profile = AB.config.sharedButtonConfig.cast.mouseover
profile[1], profile[2] = true, "CTRL"
callbacks.BFI_UpdateProfile.callback()
assertEqual(nativeEnabled, true, "profile enables native mouseover")
assertEqual(nativeModifier, "CTRL", "profile applies native modifier")
assertEqual(cvarWrites, 1, "profile CVar write count")
assertEqual(modifierWrites, 1, "profile modifier write count")
assertEqual(writeOrder[1], "modifier", "modifier applies before CVar")
assertEqual(writeOrder[2], "cvar", "CVar applies after modifier")
assertEqual(profile[1], true, "fallback callbacks preserve profile toggle")
assertEqual(profile[2], "CTRL", "fallback callbacks preserve profile modifier")
assertEqual(#fired, 1, "profile apply emits only its intentional refresh")

cvarWrites, modifierWrites = 0, 0
callbacks.BFI_UpdateModule.callback(nil, "unitFrames")
assertEqual(cvarWrites, 0, "unrelated module leaves CVar alone")
assertEqual(modifierWrites, 0, "unrelated module leaves modifier alone")

profile[1], profile[2] = false, "SHIFT"
callbacks.BFI_UpdateProfile.callback()
assertEqual(nativeEnabled, false,
    "disabled ActionBars profile still applies native toggle")
assertEqual(nativeModifier, "SHIFT",
    "disabled profile preserves its selected modifier")

fired = {}
assertEqual(AB.SetMouseoverCast(true, "ALT"), true,
    "BFI setter reports profile change")
assertEqual(profile[1], true, "BFI setter stores enabled state")
assertEqual(profile[2], "ALT", "BFI setter stores modifier")
assertEqual(nativeEnabled, true, "BFI setter mirrors native CVar")
assertEqual(nativeModifier, "ALT", "BFI setter mirrors native modifier")
assertEqual(#fired, 1, "BFI setter emits one focused refresh")
assertEqual(fired[1][1], "BFI_MouseoverCastChanged",
    "shared mouseover options refresh")

nativeEnabled = false
settingsCallbacks.enableMouseoverCast()
assertEqual(profile[1], false, "Blizzard checkbox updates active profile")
assertEqual(profile[2], "ALT", "Blizzard checkbox preserves modifier")

nativeModifier = "SHIFT"
settingsCallbacks.MOUSEOVERCAST()
assertEqual(profile[2], "SHIFT", "Blizzard modifier updates active profile")

nativeEnabled = true
invokeEvent("CVAR_UPDATE", "enableMouseoverCast", "1")
assertEqual(profile[1], true, "console CVar update reaches active profile")

nativeModifier = "CTRL"
invokeEvent("UPDATE_BINDINGS")
assertEqual(profile[2], "CTRL", "binding API update reaches active profile")

cvarWrites, modifierWrites = 0, 0
AB.ApplyMouseoverCastProfile()
assertEqual(cvarWrites, 0, "matching profile does not rewrite CVar")
assertEqual(modifierWrites, 0, "matching profile does not rewrite modifier")

inCombat = true
AB.SetMouseoverCast(false, "NONE")
assertEqual(nativeEnabled, true, "combat defers native CVar write")
assertEqual(nativeModifier, "CTRL", "combat defers native modifier write")
assertEqual(type(next(events.PLAYER_REGEN_ENABLED)), "function",
    "combat registers deferred apply")
inCombat = false
invokeEvent("PLAYER_REGEN_ENABLED")
assertEqual(nativeEnabled, false, "deferred CVar applies after combat")
assertEqual(nativeModifier, "NONE", "deferred modifier applies after combat")
assertEqual(next(events.PLAYER_REGEN_ENABLED), nil,
    "deferred apply unregisters itself")

registeredSettings = true
settingsWrites = {}
cvarWrites, modifierWrites = 0, 0
fired = {}
profile[1], profile[2] = true, "CTRL"
callbacks.BFI_UpdateProfile.callback()
assertEqual(#settingsWrites, 2, "registered Settings applies both values")
assertEqual(settingsWrites[1].variable, "MOUSEOVERCAST",
    "registered Settings applies modifier first")
assertEqual(settingsWrites[1].value, "CTRL",
    "registered Settings applies profile modifier")
assertEqual(settingsWrites[1].force, true,
    "registered Settings applies modifier immediately")
assertEqual(settingsWrites[2].variable, "enableMouseoverCast",
    "registered Settings applies CVar second")
assertEqual(settingsWrites[2].value, true,
    "registered Settings applies profile toggle")
assertEqual(settingsWrites[2].force, true,
    "registered Settings applies CVar immediately")
assertEqual(cvarWrites, 0, "registered CVar setting avoids raw fallback")
assertEqual(modifierWrites, 0,
    "registered modified-click setting avoids raw fallback")
assertEqual(profile[1], true,
    "registered Settings callbacks preserve profile toggle")
assertEqual(profile[2], "CTRL",
    "registered Settings callbacks preserve profile modifier")
assertEqual(#fired, 1,
    "registered Settings echoes do not add option refreshes")

settingsWrites = {}
fired = {}
AB.SetMouseoverCast(false)
assertEqual(#settingsWrites, 1, "toggle-only change writes one setting")
assertEqual(settingsWrites[1].variable, "enableMouseoverCast",
    "toggle-only change writes the CVar setting")
assertEqual(#fired, 1, "toggle-only change refreshes options once")

settingsWrites = {}
fired = {}
AB.SetMouseoverCast(nil, "ALT")
assertEqual(#settingsWrites, 1, "modifier-only change writes one setting")
assertEqual(settingsWrites[1].variable, "MOUSEOVERCAST",
    "modifier-only change writes the modified-click setting")
assertEqual(#fired, 1, "modifier-only change refreshes options once")

settingsWrites = {}
AB.ApplyMouseoverCastProfile()
assertEqual(#settingsWrites, 0, "matching registered settings are not rewritten")

fired = {}
nativeEnabled = true
settingsCallbacks.enableMouseoverCast()
invokeEvent("CVAR_UPDATE", "enableMouseoverCast", "1")
assertEqual(profile[1], true,
    "duplicate native CVar notifications update the profile")
assertEqual(#fired, 1,
    "duplicate native CVar notifications refresh options once")

fired = {}
nativeModifier = "SHIFT"
settingsCallbacks.MOUSEOVERCAST()
invokeEvent("UPDATE_BINDINGS")
assertEqual(profile[2], "SHIFT",
    "duplicate native binding notifications update the profile")
assertEqual(#fired, 1,
    "duplicate native binding notifications refresh options once")

AB.config = nil
assertEqual(AB.GetMouseoverCast(), false, "missing profile uses disabled fallback")
assertEqual(AB.SetMouseoverCast(true, "ALT"), false,
    "missing profile cannot be mutated")
invokeEvent("CVAR_UPDATE", "enableMouseoverCast", "1")
invokeEvent("UPDATE_BINDINGS")

local commonSource = readFile("Modules/ActionBars/Common.lua")
assertContains(commonSource, 'b:SetAttribute("checkmouseovercast", true)',
    "BFI action buttons permanently opt into native mouseover")

local mainBarsSource = readFile("Modules/ActionBars/MainBars.lua")
assertNotContains(mainBarsSource, "enableMouseoverCast",
    "per-button loop no longer writes mouseover CVar")
assertNotContains(mainBarsSource, 'SetModifiedClick("MOUSEOVERCAST"',
    "per-button loop no longer writes mouseover modifier")
assertNotContains(mainBarsSource, 'SetAttribute("checkmouseovercast"',
    "per-button loop no longer toggles mouseover opt-in")

local actionBarOptionsSource = readFile("Options/ActionBars_Options.lua")
assertNotContains(actionBarOptionsSource, "sharedCfg.cast.mouseover[",
    "ActionBars controls use the shared controller")
assertContains(actionBarOptionsSource, "AB.SetMouseoverCast",
    "ActionBars controls call the shared setter")
assertContains(actionBarOptionsSource, '"BFI_MouseoverCastChanged"',
    "ActionBars controls subscribe to shared refreshes")

local generalOptionsSource = readFile("Options/General.lua")
assertContains(generalOptionsSource, 'type = "mouseoverCast"',
    "General CVars exposes profile-backed mouseover controls")
assertContains(generalOptionsSource, "AB.GetMouseoverCast",
    "General CVars reads the shared profile setting")
assertContains(generalOptionsSource, "AB.SetMouseoverCast",
    "General CVars writes the shared profile setting")
assertContains(generalOptionsSource, '"BFI_MouseoverCastChanged"',
    "General CVars subscribes to shared refreshes")

local controllerSource = readFile(controllerPath)
assertContains(controllerSource, "Settings.SetValue",
    "registered Blizzard settings use the native Settings API")
assertContains(controllerSource, "Settings.NotifyUpdate",
    "fallback modifier writes notify Blizzard settings")

local loadOrderSource = readFile("Modules/ActionBars/Load.xml")
assertContains(loadOrderSource, '<Script file="MouseoverCast.lua"/>',
    "mouseover controller is loaded")

print("mouseover_cast_sync_test.lua: ok")
