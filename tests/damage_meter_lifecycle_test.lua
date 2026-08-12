local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function loadLifecycle()
    local state = {
        applyCalls = 0,
        refreshCalls = 0,
        setEnabledCalls = {},
        updateCallbacks = {},
    }
    local damageMeter = {
        config = {
            enabled = false,
        },
        Renderer = {
            ApplySettings = function()
                state.applyCalls = state.applyCalls + 1
                return true
            end,
            Refresh = function()
                state.refreshCalls = state.refreshCalls + 1
                return true
            end,
            SetEnabled = function(enabled)
                state.setEnabledCalls[#state.setEnabledCalls + 1] = enabled
                return true
            end,
        },
    }
    local BFI = {
        modules = {
            DamageMeter = damageMeter,
        },
    }
    local AF = {
        RegisterCallback = function(name, callback)
            state.updateCallbacks[name] = callback
        end,
    }
    local environment = {
        AbstractFramework = AF,
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

local DM, state = loadLifecycle()
local update = state.updateCallbacks.BFI_UpdateModule
local updateFont = state.updateCallbacks.BFI_UpdateFont
assertEqual(type(update), "function", "module callback registration")
assertEqual(type(updateFont), "function", "font callback registration")
assertEqual(DM.IsActive(), false, "initial active state")

update(nil, "otherModule")
assertEqual(#state.setEnabledCalls, 0, "unrelated module ignored")

update(nil, "damageMeter")
assertEqual(#state.setEnabledCalls, 1, "disabled state reconciled")
assertEqual(state.setEnabledCalls[1], false, "renderer disabled")
assertEqual(DM.IsActive(), false, "disabled remains inactive")
DM.Refresh()
updateFont()
assertEqual(state.refreshCalls, 0, "disabled refresh ignored")
assertEqual(state.applyCalls, 0, "disabled font update ignored")

DM.config.enabled = true
update(nil, "damageMeter")
assertEqual(DM.IsActive(), true, "enabled active state")
assertEqual(#state.setEnabledCalls, 2, "renderer enable call")
assertEqual(state.setEnabledCalls[2], true, "renderer enabled")

DM.Refresh()
updateFont()
assertEqual(state.refreshCalls, 1, "active refresh delegated")
assertEqual(state.applyCalls, 1, "active font update reapplies")

update(nil, "damageMeter")
assertEqual(#state.setEnabledCalls, 3, "active settings reapplied")
assertEqual(state.setEnabledCalls[3], true, "active renderer remains enabled")

DM.config.enabled = false
update(nil, "damageMeter")
assertEqual(DM.IsActive(), false, "disable clears active state")
assertEqual(#state.setEnabledCalls, 4, "renderer disable delegated")
assertEqual(state.setEnabledCalls[4], false, "renderer disabled after toggle")

print("damage_meter_lifecycle_test.lua: ok")
