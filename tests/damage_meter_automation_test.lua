local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function loadAutomation()
    local state = {
        applyCalls = 0,
        events = {},
        operations = {},
        refreshCalls = 0,
        resetCalls = 0,
        resetSequence = {},
        runtimeSessions = {
            [1] = {mode = "history", sessionID = 10},
            [3] = {mode = "history", sessionID = 30},
        },
        sessionCalls = {},
        typeCalls = {},
    }

    local frame = {}
    function frame:SetScript(script, callback)
        self[script] = callback
    end
    function frame:RegisterEvent(event)
        state.events[event] = true
    end
    function frame:UnregisterAllEvents()
        state.events = {}
    end

    local damageMeter = {
        config = {
            windowCount = 1,
            windowTypes = {
                "DamageDone",
                "HealingDone",
                "DamageTaken",
            },
            windowSessions = {
                {mode = "current"},
                {mode = "overall"},
                {mode = "current"},
            },
            windowAutoCurrentOnCombat = {
                true,
                true,
                true,
            },
            windowAutoCurrentOnMythicPlusStart = {
                false,
                true,
                true,
            },
            windowAutoOverallOnMythicPlusComplete = {
                true,
                false,
                true,
            },
            mythicPlusWindowTypes = {
                false,
                "Dps",
                "HealingDone",
            },
            resetOnMythicPlusStart = true,
        },
        Data = {
            Reset = function()
                state.resetCalls = state.resetCalls + 1
                state.resetSequence[#state.resetSequence + 1] = "reset"
                return true
            end,
        },
        Renderer = {},
    }

    function damageMeter.Renderer.ApplySettings()
        state.applyCalls = state.applyCalls + 1
    end
    function damageMeter.Renderer.Refresh()
        state.refreshCalls = state.refreshCalls + 1
    end
    function damageMeter.Renderer.GetWindowSession(index)
        local selection = state.runtimeSessions[index]
            or damageMeter.config.windowSessions[index]
        return selection.mode, selection.sessionID
    end
    function damageMeter.Renderer.SetWindowSession(
        index,
        mode,
        sessionID,
        options
    )
        state.sessionCalls[#state.sessionCalls + 1] = {
            index = index,
            mode = mode,
            options = options,
            sessionID = sessionID,
        }
        state.operations[#state.operations + 1] =
            ("session:%d:%s"):format(index, mode)
        damageMeter.config.windowSessions[index] = {
            mode = mode,
            sessionID = sessionID,
        }
        state.runtimeSessions[index] = nil
        return true
    end
    function damageMeter.Renderer.SetWindowType(
        index,
        typeName,
        options
    )
        state.typeCalls[#state.typeCalls + 1] = {
            index = index,
            options = options,
            typeName = typeName,
        }
        state.operations[#state.operations + 1] =
            ("type:%d:%s"):format(index, typeName)
        damageMeter.config.windowTypes[index] = typeName
        return true
    end

    local BFI = {
        modules = {
            DamageMeter = damageMeter,
            UIWidgets = {
                MythicPlus = {
                    PrepareForDamageMeterReset = function(reason)
                        state.resetSequence[
                            #state.resetSequence + 1
                        ] = "prepare:" .. tostring(reason)
                        return true
                    end,
                },
            },
        },
    }
    local environment = {
        CreateFrame = function()
            return frame
        end,
        math = math,
        select = select,
        type = type,
    }
    environment._G = environment

    local chunk, loadError = loadfile(
        "Modules/DamageMeter/Automation.lua"
    )
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return damageMeter, state, frame
end

local DM, state, frame = loadAutomation()
assertEqual(DM.Automation.IsEnabled(), false, "automation initially disabled")

DM.Automation.SetEnabled(true)
assertEqual(DM.Automation.IsEnabled(), true, "automation enabled")
assertEqual(state.events.PLAYER_REGEN_DISABLED, true, "combat event")
assertEqual(state.events.CHALLENGE_MODE_START, true, "challenge start event")
assertEqual(
    state.events.CHALLENGE_MODE_COMPLETED,
    true,
    "challenge complete event"
)

frame.OnEvent(frame, "PLAYER_REGEN_DISABLED")
assertEqual(#state.sessionCalls, 2, "all opted-in history returned")
assertEqual(state.sessionCalls[1].index, 1, "first history window returned")
assertEqual(state.sessionCalls[1].mode, "current", "returned to current")
assertEqual(state.sessionCalls[1].options.sync, false, "automation skips sync")
assertEqual(
    state.sessionCalls[1].options.refresh,
    false,
    "automation batches refresh"
)
assertEqual(
    state.sessionCalls[2].index,
    3,
    "hidden history window returned"
)
assertEqual(state.refreshCalls, 1, "combat automation refreshed once")

state.operations = {}
frame.OnEvent(frame, "CHALLENGE_MODE_START")
assertEqual(state.resetCalls, 1, "challenge start reset is opt-in")
assertEqual(
    state.resetSequence[1],
    "prepare:mythicPlusStart",
    "timer is prepared before the intentional reset"
)
assertEqual(
    state.resetSequence[2],
    "reset",
    "intentional reset follows timer preparation"
)
assertEqual(DM.config.windowTypes[1], "DamageDone", "first type retained")
assertEqual(DM.config.windowTypes[2], "Dps", "second type selected")
assertEqual(DM.config.windowTypes[3], "HealingDone", "third type selected")
assertEqual(DM.config.windowSessions[2].mode, "current", "second current")
assertEqual(DM.config.windowSessions[3].mode, "current", "third current")
assertEqual(#state.typeCalls, 2, "configured hidden types use renderer setter")
assertEqual(state.typeCalls[1].index, 2, "second type setter target")
assertEqual(state.typeCalls[1].typeName, "Dps", "second type setter value")
assertEqual(
    state.typeCalls[1].options.refresh,
    false,
    "type automation batches renderer application"
)
assertEqual(state.typeCalls[2].index, 3, "third type setter target")
assertEqual(
    state.operations[1],
    "session:2:current",
    "second meter activates Current before resetting its type viewport"
)
assertEqual(
    state.operations[2],
    "type:2:Dps",
    "second meter type follows its Current session"
)
assertEqual(
    state.operations[3],
    "session:3:current",
    "third meter activates Current before resetting its type viewport"
)
assertEqual(
    state.operations[4],
    "type:3:HealingDone",
    "third meter type follows its Current session"
)
assertEqual(state.applyCalls, 1, "challenge start applied once")

frame.OnEvent(frame, "CHALLENGE_MODE_COMPLETED")
assertEqual(DM.config.windowSessions[1].mode, "overall", "first overall")
assertEqual(DM.config.windowSessions[2].mode, "current", "second unchanged")
assertEqual(DM.config.windowSessions[3].mode, "overall", "third overall")
assertEqual(state.refreshCalls, 2, "challenge completion refreshed once")

DM.Automation.SetEnabled(false)
assertEqual(DM.Automation.IsEnabled(), false, "automation disabled")
assertEqual(next(state.events), nil, "automation events removed")

print("damage_meter_automation_test.lua: ok")
