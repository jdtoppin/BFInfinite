local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local state = {
    afk = true,
    afkCalls = 0,
    guidCalls = 0,
    guidRejections = 0,
    guidSecret = false,
    lockdown = true,
    secretRejections = 0,
    timerShows = 0,
}
local secretAFK = {}
local secretGUID = {}
local UF = {}
local BFI = {
    funcs = {
        isValueNonSecret = function(value)
            if value == secretAFK then
                state.secretRejections = state.secretRejections + 1
                return false
            end
            if value == secretGUID then
                state.guidRejections = state.guidRejections + 1
                return false
            end
            return true
        end,
    },
    L = {},
    modules = {
        UnitFrames = UF,
    },
}
local AF = {
    AddEventHandler = function()
    end,
    UnitClassBase = function()
        return "MAGE"
    end,
    UnitIsPlayer = function()
        return true
    end,
}

local parent = {
    unit = "party1",
}
function parent.CreateFontString()
    local text = {}
    function text:Hide()
    end
    function text:SetText(value)
        self.text = value
    end
    function text:SetTextColor()
    end
    return text
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    CreateFrame = function()
        local frame = {}
        function frame:Hide()
            self.shown = false
        end
        function frame:Show()
            self.shown = true
            state.timerShows = state.timerShows + 1
        end
        return frame
    end,
    GetTime = function()
        return 1
    end,
    UnitGUID = function()
        state.guidCalls = state.guidCalls + 1
        if state.guidSecret then
            return secretGUID
        end
        return "GUID-party1"
    end,
    UnitIsAFK = function()
        state.afkCalls = state.afkCalls + 1
        if state.lockdown then
            return secretAFK
        end
        return state.afk
    end,
    UnitIsConnected = function()
        return true
    end,
    UnitIsDeadOrGhost = function()
        return false
    end,
    UnitIsGhost = function()
        return false
    end,
    error = error,
    select = select,
    tostring = tostring,
    unpack = unpack,
}
environment._G = environment

local chunk, loadError =
    loadfile("Modules/UnitFrames/Indicators/StatusTimer.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local indicator = UF.CreateStatusTimer(parent, "StatusTimer")
indicator.color = {
    type = "rgb",
    rgb = {1, 1, 1},
}
indicator.showTimer = false
indicator.useEn = true

indicator:Update()
assertEqual(state.afkCalls, 1, "lockdown AFK calls")
assertEqual(state.secretRejections, 1, "secret AFK rejections")
assertEqual(indicator.text, "", "lockdown status text")

state.lockdown = false
indicator:Update()
assertEqual(state.afkCalls, 2, "unrestricted AFK calls")
assertEqual(state.secretRejections, 1, "unrestricted secret rejections")
assertEqual(indicator.text, "AFK", "unrestricted status text")

state.guidSecret = true
indicator.showTimer = true
indicator:Update()
assertEqual(state.guidCalls, 1, "secret show GUID calls")
assertEqual(state.guidRejections, 1, "secret show GUID rejections")
assertEqual(state.timerShows, 0, "secret GUID timer shows")

state.afk = false
indicator:Update()
assertEqual(state.guidCalls, 2, "secret hide GUID calls")
assertEqual(state.guidRejections, 2, "secret hide GUID rejections")
assertEqual(indicator.text, "", "secret GUID cleared status text")

print("unit_frame_status_timer_test.lua: ok")
