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
        if not name then
            return nil
        elseif name == targetName then
            return value
        end
        index = index + 1
    end
end

local callbacks = {}
local cvars = {
    deselectOnClick = "0",
}
local setCalls = {}
local backupNotices = 0

local eventHandler = {}
local AF = {
    player = {
        battleTagMD5 = "ACCOUNT",
    },
}

function AF.CreateSimpleEventHandler()
    return eventHandler
end

function AF.RegisterCallback(name, callback)
    callbacks[name] = callback
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    BFIConfig = {},
    C_SpecializationInfo = {
        GetNumSpecializationsForClassID = function()
            return 0
        end,
    },
    GetCVar = function(name)
        return cvars[name] or ("original:" .. name)
    end,
    SetCVar = function(name, value)
        setCalls[#setCalls + 1] = {
            name = name,
            value = value,
        }
        cvars[name] = tostring(value)
    end,
    GetPhysicalScreenSize = function()
        return 1920, 1080
    end,
    InCombatLockdown = function()
        return false
    end,
    wipe = function(value)
        for key in pairs(value) do
            value[key] = nil
        end
    end,
}
environment._G = environment
setmetatable(environment, {__index = _G})

local BFI = {
    funcs = {
        ShowCVarBackupNotice = function()
            backupNotices = backupNotices + 1
        end,
    },
    vars = {},
}

local chunk, loadError = loadfile("Core.lua")
assertEqual(type(chunk), "function", loadError or "Core.lua load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local loginCallback = callbacks.AF_PLAYER_LOGIN_DELAYED
assertEqual(type(loginCallback), "function", "login callback")
local initialize = findUpvalue(loginCallback, "InitAndBackupCVars")
assertEqual(type(initialize), "function", "CVar initializer upvalue")

initialize()

assertEqual(environment.BFICVarBackup.cvars.deselectOnClick, "0",
    "original mouse deselection setting is backed up")
assertEqual(environment.BFIConfig.cvarInited, "ACCOUNT",
    "first-run CVar marker")
assertEqual(backupNotices, 1, "backup notice count")

local mouseDeselectSetCount = 0
for _, call in ipairs(setCalls) do
    if call.name == "deselectOnClick" then
        mouseDeselectSetCount = mouseDeselectSetCount + 1
        assertEqual(call.value, 1, "first-run mouse deselection value")
    end
end
assertEqual(mouseDeselectSetCount, 1,
    "first-run mouse deselection assignment count")

-- A later user choice remains authoritative because initialization is
-- account-scoped and the original backup is not overwritten.
cvars.deselectOnClick = "0"
initialize()

local secondPassSetCount = 0
for _, call in ipairs(setCalls) do
    if call.name == "deselectOnClick" then
        secondPassSetCount = secondPassSetCount + 1
    end
end
assertEqual(secondPassSetCount, 1,
    "later mouse deselection assignment count")
assertEqual(cvars.deselectOnClick, "0", "later user choice")
assertEqual(environment.BFICVarBackup.cvars.deselectOnClick, "0",
    "original mouse deselection backup")

print("core_mouse_deselect_default_test.lua: ok")
