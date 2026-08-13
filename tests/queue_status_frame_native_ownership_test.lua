local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local callback
local iconHooked
local globalHooked
local poison = setmetatable({}, {
    __index = function(_, key)
        error("Queue Status must remain native: " .. tostring(key), 2)
    end,
})
local AF = {
    RegisterCallback = function(_, registeredCallback)
        callback = registeredCallback
    end,
}
local environment = {
    _G = false,
    AbstractFramework = AF,
    IconIntroTracker = {
        HookScript = function(_, script)
            assertEqual(script, "OnEvent", "icon intro hook")
            iconHooked = true
        end,
    },
    QueueStatusButton = poison,
    QueueStatusFrame = poison,
    hooksecurefunc = function(name)
        assertEqual(name, "SetCheckButtonIsRadio", "global style hook")
        globalHooked = true
    end,
    ipairs = ipairs,
    select = select,
    tostring = tostring,
}
environment._G = environment

local BFI = {
    modules = {
        Style = {
            CreateBackdrop = function()
                error("Queue Status backdrop must not be created", 2)
            end,
            RemoveNineSliceAndBackground = function()
                error("Queue Status artwork must remain native", 2)
            end,
        },
    },
}

local chunk, loadError = loadfile("Modules/Blizzard/Style/Misc.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(callback), "function", "style callback")
callback()
assertEqual(iconHooked, true, "unrelated icon styling remains active")
assertEqual(globalHooked, true, "unrelated check-button styling remains active")

print("queue_status_frame_native_ownership_test.lua: ok")
