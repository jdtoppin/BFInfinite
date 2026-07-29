local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function loadNative()
    local state = {
        cvars = {
            damageMeterEnabled = true,
            damageMeterResetOnNewInstance = false,
        },
        failedWrites = {},
        reads = {},
        writes = {},
    }
    local damageMeter = {}
    local BFI = {
        modules = {
            DamageMeter = damageMeter,
        },
    }
    local environment = {
        C_CVar = {
            GetCVarBool = function(name)
                state.reads[#state.reads + 1] = name
                return state.cvars[name]
            end,
            SetCVar = function(name, value)
                state.writes[#state.writes + 1] = {
                    name = name,
                    value = value,
                }
                if state.failedWrites[name] then
                    return false
                end
                state.cvars[name] = value == "1"
                return true
            end,
        },
        select = select,
        type = type,
    }
    environment._G = environment

    local chunk, loadError = loadfile("Modules/DamageMeter/Native.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return damageMeter.Native, state
end

local Native, state = loadNative()
assertEqual(Native.GetEnabled(), true, "native enabled read")
assertEqual(state.reads[1], "damageMeterEnabled", "enabled CVar name")

local ok, reason = Native.SetEnabled(false)
assertEqual(ok, true, "native disable")
assertEqual(reason, nil, "native disable reason")
assertEqual(state.cvars.damageMeterEnabled, false, "native disabled value")
assertEqual(state.writes[1].name, "damageMeterEnabled", "enabled write name")
assertEqual(state.writes[1].value, "0", "enabled write value")

assertEqual(
    Native.GetResetOnNewInstance(),
    false,
    "reset-on-instance read"
)
assertEqual(
    state.reads[2],
    "damageMeterResetOnNewInstance",
    "reset CVar name"
)

ok, reason = Native.SetResetOnNewInstance(true)
assertEqual(ok, true, "reset-on-instance enable")
assertEqual(reason, nil, "reset-on-instance reason")
assertEqual(
    state.cvars.damageMeterResetOnNewInstance,
    true,
    "reset-on-instance value"
)
assertEqual(
    state.writes[2].name,
    "damageMeterResetOnNewInstance",
    "reset write name"
)
assertEqual(state.writes[2].value, "1", "reset write value")

ok, reason = Native.SetEnabled("yes")
assertEqual(ok, false, "invalid enabled rejected")
assertEqual(reason, "invalid_value", "invalid enabled reason")

state.failedWrites.damageMeterEnabled = true
ok, reason = Native.SetEnabled(true)
assertEqual(ok, false, "failed enabled write")
assertEqual(reason, "cvar_write_failed", "failed enabled reason")
assertEqual(state.cvars.damageMeterEnabled, false, "failed write unchanged")

state.failedWrites.damageMeterResetOnNewInstance = true
ok, reason = Native.SetResetOnNewInstance(false)
assertEqual(ok, false, "failed reset write")
assertEqual(reason, "cvar_write_failed", "failed reset reason")
assertEqual(
    state.cvars.damageMeterResetOnNewInstance,
    true,
    "failed reset unchanged"
)

print("damage_meter_native_test.lua: ok")
