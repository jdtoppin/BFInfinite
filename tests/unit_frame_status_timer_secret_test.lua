local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function findUpvalue(func, targetName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(func, index)
        if not name then return nil end
        if name == targetName then return value end
        index = index + 1
    end
end

local secret = {}
local state = {
    connected = true,
    afk = secret,
    dead = false,
    ghost = false,
}
local AF = {
    UnitIsPlayer = function() return true end,
}
local UF = {}
local environment = {
    _G = false,
    AbstractFramework = AF,
    CreateFrame = function() return {} end,
    GetTime = function() return 0 end,
    UnitGUID = function() return "Player-1" end,
    UnitIsAFK = function() return state.afk end,
    UnitIsConnected = function() return state.connected end,
    UnitIsDeadOrGhost = function() return state.dead end,
    UnitIsGhost = function() return state.ghost end,
    debug = debug,
    next = next,
    select = select,
    type = type,
    unpack = unpack,
}
environment._G = environment

local BFI = {
    L = setmetatable({}, {__index = function(_, key) return key end}),
    funcs = {
        isValueNonSecret = function(value)
            return value ~= secret
        end,
    },
    modules = {
        UnitFrames = UF,
    },
}

local chunk, loadError =
    loadfile("Modules/UnitFrames/Indicators/StatusTimer.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local statusTimerUpdate = findUpvalue(
    UF.CreateStatusTimer,
    "StatusTimer_Update"
)
assertEqual(type(statusTimerUpdate), "function", "status update function")
local updateStatus = findUpvalue(statusTimerUpdate, "UpdateStatus")
assertEqual(type(updateStatus), "function", "unit status reader")

local indicator = {
    root = {unit = "player"},
    showTimer = false,
    useEn = true,
    SetText = function(self, value)
        self.text = value
    end,
}

updateStatus(indicator)
assertEqual(indicator.text, "",
    "secret AFK state is not interpreted as true")

state.afk = true
updateStatus(indicator)
assertEqual(indicator.text, "AFK", "public AFK state still renders")

state.afk = false
state.dead = true
state.ghost = secret
updateStatus(indicator)
assertEqual(indicator.text, "",
    "secret ghost state is not interpreted as true")

state.ghost = false
updateStatus(indicator)
assertEqual(indicator.text, "DEAD", "public dead state still renders")

print("unit_frame_status_timer_secret_test.lua: ok")
