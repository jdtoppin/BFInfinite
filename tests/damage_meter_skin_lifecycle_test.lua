local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertArray(actual, expected, message)
    assertEqual(#actual, #expected, message .. " length")
    for i, value in ipairs(expected) do
        assertEqual(actual[i], value, message .. " value " .. i)
    end
end

local function loadSkin()
    local state = {
        active = true,
        arrangeCalls = {},
        inCombat = false,
        skinCalls = {},
        unavailableIndices = {},
        windows = {
            [2] = {},
            [3] = {},
        },
    }

    local DM = {
        config = {
            accentHeader = true,
            enabled = true,
        },
    }
    function DM.IsActive()
        return state.active
    end
    function DM.ArrangeSecondaryWindows(indices)
        local copy = {}
        for i, index in ipairs(indices) do
            copy[i] = index
        end
        state.arrangeCalls[#state.arrangeCalls + 1] = copy

        if state.unavailableIndices[indices[1]] then
            return false, "window_unavailable"
        end
        if state.inCombat then
            return false, "combat"
        end
        return true
    end

    local damageMeter = {}
    function damageMeter:ForEachSessionWindow()
    end
    function damageMeter:GetSessionWindow(index)
        return state.windows[index]
    end
    function damageMeter:SetupSessionWindow()
    end

    local BFI = {
        modules = {
            DamageMeter = DM,
            Style = {},
        },
    }
    local environment = {
        AbstractFramework = {},
        CreateFrame = function()
            local frame = {
                registered = {},
            }
            function frame:RegisterEvent(event)
                self.registered[event] = true
            end
            function frame:SetScript(_, script)
                self.script = script
            end
            function frame:UnregisterEvent(event)
                self.registered[event] = nil
            end
            state.placementFrame = frame
            return frame
        end,
        DamageMeter = damageMeter,
        hooksecurefunc = function(owner, method, callback)
            assertEqual(owner, damageMeter, "setup hook owner")
            assertEqual(method, "SetupSessionWindow", "setup hook method")
            state.setupHook = callback
        end,
        ipairs = ipairs,
        next = next,
        select = select,
        setmetatable = setmetatable,
        type = type,
    }
    environment._G = environment

    local chunk, loadError = loadfile("Modules/DamageMeter/Skin.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    DM.Skin.ApplySessionWindow = function(window)
        state.skinCalls[#state.skinCalls + 1] = window
    end
    assertEqual(DM.Skin.Install(), true, "skin install")

    return DM.Skin, state, damageMeter
end

local Skin, state, damageMeter = loadSkin()

state.inCombat = false
state.setupHook(damageMeter, 2)
assertArray(state.arrangeCalls[1], {2}, "immediate secondary placement")
assertEqual(state.placementFrame, nil,
    "immediate placement does not create event frame")

state.inCombat = true
state.setupHook(damageMeter, 2)
state.setupHook(damageMeter, 2)
state.setupHook(damageMeter, 3)
assertEqual(
    state.placementFrame.registered.PLAYER_REGEN_ENABLED,
    true,
    "combat placement event registered"
)

state.inCombat = false
state.unavailableIndices[3] = true
state.placementFrame.script(
    state.placementFrame,
    "PLAYER_REGEN_ENABLED"
)
assertArray(
    state.arrangeCalls[#state.arrangeCalls - 1],
    {2},
    "visible combat placement replayed"
)
assertArray(
    state.arrangeCalls[#state.arrangeCalls],
    {3},
    "closed combat placement does not block another"
)
assertEqual(#state.arrangeCalls, 6, "combat placements deduplicated")
assertEqual(
    state.placementFrame.registered.PLAYER_REGEN_ENABLED,
    nil,
    "combat placement event unregistered"
)

state.inCombat = true
state.setupHook(damageMeter, 2)
Skin.Disable()
assertEqual(
    state.placementFrame.registered.PLAYER_REGEN_ENABLED,
    nil,
    "disable cancels pending placement"
)

print("damage_meter_skin_lifecycle_test.lua: ok")
