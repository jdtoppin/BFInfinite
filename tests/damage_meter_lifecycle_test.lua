local NATIVE_ADDON = "Blizzard_DamageMeter"

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function loadLifecycle(options)
    options = options or {}

    local state = {
        addonCallbacks = {},
        applyCalls = 0,
        createFrameCalls = 0,
        disableCalls = 0,
        frames = {},
        inCombat = options.inCombat == true,
        installCalls = 0,
        loadAddonCalls = 0,
        loaded = options.loaded == true,
        registerAddonCalls = 0,
        registerEventCalls = 0,
        unregisterAddonCalls = 0,
        unregisterEventCalls = 0,
        updateCallbacks = {},
    }
    local loadSucceeds = options.loadSucceeds ~= false
    local damageMeter = {
        config = {
            enabled = false,
        },
        Skin = {
            ApplyAll = function()
                state.applyCalls = state.applyCalls + 1
            end,
            Disable = function()
                state.disableCalls = state.disableCalls + 1
            end,
            Install = function()
                state.installCalls = state.installCalls + 1
                if options.installResult == nil then
                    return true
                end
                return options.installResult
            end,
        },
    }
    local BFI = {
        modules = {
            DamageMeter = damageMeter,
        },
    }
    local AF = {
        RegisterAddonLoaded = function(addonName, callback)
            state.registerAddonCalls = state.registerAddonCalls + 1
            state.addonCallbacks[addonName] = callback
        end,
        RegisterCallback = function(name, callback)
            state.updateCallbacks[name] = callback
        end,
        UnregisterAddonLoaded = function(addonName, callback)
            state.unregisterAddonCalls = state.unregisterAddonCalls + 1
            if state.addonCallbacks[addonName] == callback then
                state.addonCallbacks[addonName] = nil
            end
        end,
    }
    local environment = {
        AbstractFramework = AF,
        C_AddOns = {
            IsAddOnLoaded = function(addonName)
                assertEqual(addonName, NATIVE_ADDON, "loaded query addon")
                return state.loaded
            end,
            LoadAddOn = function(addonName)
                assertEqual(addonName, NATIVE_ADDON, "load addon")
                state.loadAddonCalls = state.loadAddonCalls + 1
                if loadSucceeds then
                    state.loaded = true
                end
            end,
        },
        CreateFrame = function(frameType)
            assertEqual(frameType, "Frame", "deferred frame type")
            state.createFrameCalls = state.createFrameCalls + 1

            local frame = {
                events = {},
                scripts = {},
            }
            function frame:RegisterEvent(event)
                state.registerEventCalls = state.registerEventCalls + 1
                self.events[event] = true
            end
            function frame:SetScript(scriptName, callback)
                self.scripts[scriptName] = callback
            end
            function frame:Trigger(event)
                if self.events[event] and self.scripts.OnEvent then
                    self.scripts.OnEvent(self, event)
                end
            end
            function frame:UnregisterEvent(event)
                state.unregisterEventCalls = state.unregisterEventCalls + 1
                self.events[event] = nil
            end

            state.frames[#state.frames + 1] = frame
            return frame
        end,
        InCombatLockdown = function()
            return state.inCombat
        end,
        select = select,
        type = type,
    }
    environment._G = environment

    local chunk, loadError = loadfile("Modules/DamageMeter/DamageMeter.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return damageMeter, state
end

local function assertDormant(state, message)
    assertEqual(state.applyCalls, 0, message .. " apply")
    assertEqual(state.disableCalls, 0, message .. " disable")
    assertEqual(state.installCalls, 0, message .. " install")
    assertEqual(state.loadAddonCalls, 0, message .. " load")
    assertEqual(state.registerAddonCalls, 0, message .. " addon registration")
end

local dormantDM, dormant = loadLifecycle()
local dormantUpdate = dormant.updateCallbacks.BFI_UpdateModule
local dormantFont = dormant.updateCallbacks.BFI_UpdateFont
assertEqual(type(dormantUpdate), "function", "module callback registration")
assertEqual(type(dormantFont), "function", "font callback registration")
assertEqual(dormantDM.IsActive(), false, "initial active state")
dormantUpdate(nil, "damageMeter")
dormantDM.Refresh()
dormantFont()
assertDormant(dormant, "disabled module")

dormantDM.config.enabled = true
dormantUpdate(nil, "otherModule")
assertEqual(dormantDM.IsActive(), false, "unrelated module remains inactive")
assertDormant(dormant, "unrelated module")

local loadedDM, loaded = loadLifecycle({
    loaded = true,
})
local loadedUpdate = loaded.updateCallbacks.BFI_UpdateModule
loadedDM.config.enabled = true
loadedUpdate(nil, "damageMeter")
assertEqual(loadedDM.IsActive(), true, "loaded enable active")
assertEqual(loaded.installCalls, 1, "loaded enable install")
assertEqual(loaded.applyCalls, 1, "loaded enable apply")
assertEqual(loaded.loadAddonCalls, 0, "loaded enable avoids load")
assertEqual(loaded.registerAddonCalls, 0, "loaded enable avoids callback")

loadedDM.Refresh()
loadedDM.Refresh()
assertEqual(loaded.installCalls, 3, "repeated refresh install")
assertEqual(loaded.applyCalls, 3, "repeated refresh apply")
assertEqual(loaded.loadAddonCalls, 0, "repeated refresh avoids reload")

loadedUpdate(nil, "damageMeter")
assertEqual(loaded.installCalls, 3, "repeated enable avoids reinstall")
assertEqual(loaded.applyCalls, 4, "repeated enable reapplies")
loaded.updateCallbacks.BFI_UpdateFont()
assertEqual(loaded.applyCalls, 5, "active font refresh reapplies")

loadedDM.config.enabled = false
loadedUpdate(nil, "damageMeter")
assertEqual(loadedDM.IsActive(), false, "disable active state")
assertEqual(loaded.disableCalls, 1, "disable restoration callback")
loadedUpdate(nil, "damageMeter")
loadedDM.Refresh()
loaded.updateCallbacks.BFI_UpdateFont()
assertEqual(loaded.disableCalls, 1, "repeated disable remains dormant")
assertEqual(loaded.applyCalls, 5, "disabled refresh remains dormant")

local callbackDM, callbackState = loadLifecycle({
    loadSucceeds = false,
})
callbackDM.config.enabled = true
callbackState.updateCallbacks.BFI_UpdateModule(nil, "damageMeter")
assertEqual(callbackDM.IsActive(), true, "callback enable active")
assertEqual(callbackState.loadAddonCalls, 1, "callback enable requests load")
assertEqual(callbackState.registerAddonCalls, 1, "callback enable registers")
assertEqual(callbackState.installCalls, 0, "callback enable waits to install")
assertEqual(callbackState.applyCalls, 0, "callback enable waits to apply")

local addonLoadedCallback = callbackState.addonCallbacks[NATIVE_ADDON]
assertEqual(type(addonLoadedCallback), "function", "native addon callback")
callbackState.loaded = true
addonLoadedCallback()
assertEqual(callbackState.unregisterAddonCalls, 1, "native callback unregisters")
assertEqual(callbackState.addonCallbacks[NATIVE_ADDON], nil, "native callback cleared")
assertEqual(callbackState.installCalls, 1, "native callback install")
assertEqual(callbackState.applyCalls, 1, "native callback apply")

local combatDM, combat = loadLifecycle({
    inCombat = true,
})
combatDM.config.enabled = true
combat.updateCallbacks.BFI_UpdateModule(nil, "damageMeter")
assertEqual(combat.registerAddonCalls, 1, "combat addon callback registration")
assertEqual(combat.createFrameCalls, 1, "combat deferred frame")
assertEqual(combat.registerEventCalls, 1, "combat deferred event")
assertEqual(combat.loadAddonCalls, 0, "combat avoids load")

combatDM.Refresh()
assertEqual(combat.registerAddonCalls, 1, "combat callback registration reused")
assertEqual(combat.createFrameCalls, 1, "combat deferred frame reused")
assertEqual(combat.registerEventCalls, 2, "combat refresh keeps deferral")

combat.inCombat = false
combat.frames[1]:Trigger("PLAYER_REGEN_ENABLED")
assertEqual(combat.frames[1].events.PLAYER_REGEN_ENABLED, nil, "regen event cleared")
assertEqual(combat.loadAddonCalls, 1, "regen loads addon")
assertEqual(combat.unregisterAddonCalls, 1, "regen clears addon callback")
assertEqual(combat.installCalls, 1, "regen install")
assertEqual(combat.applyCalls, 1, "regen apply")

local cancelledDM, cancelled = loadLifecycle({
    inCombat = true,
})
cancelledDM.config.enabled = true
cancelled.updateCallbacks.BFI_UpdateModule(nil, "damageMeter")
local cancelledFrame = cancelled.frames[1]
cancelledDM.config.enabled = false
cancelled.updateCallbacks.BFI_UpdateModule(nil, "damageMeter")
assertEqual(cancelledDM.IsActive(), false, "cancelled deferral inactive")
assertEqual(cancelled.unregisterAddonCalls, 1, "cancelled addon callback")
assertEqual(cancelledFrame.events.PLAYER_REGEN_ENABLED, nil, "cancelled regen event")
assertEqual(cancelled.disableCalls, 1, "cancelled restoration callback")

cancelled.inCombat = false
cancelledFrame:Trigger("PLAYER_REGEN_ENABLED")
assertEqual(cancelled.loadAddonCalls, 0, "cancelled deferral avoids load")
assertEqual(cancelled.installCalls, 0, "cancelled deferral avoids install")
assertEqual(cancelled.applyCalls, 0, "cancelled deferral avoids apply")

print("damage_meter_lifecycle_test.lua: ok")
