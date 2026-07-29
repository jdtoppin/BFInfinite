local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
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

local callback
local tracker = {}
local W = {}
local AF = {
    RegisterCallback = function(_, registeredCallback)
        callback = registeredCallback
    end,
}
local environment = {
    _G = false,
    AbstractFramework = AF,
    GenerateClosure = function()
    end,
    ObjectiveTrackerFrame = tracker,
    ObjectiveTrackerManager = {},
    ScenarioObjectiveTracker = {},
    ScenarioRewardsFrame = {},
    debug = debug,
    ipairs = ipairs,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
    table = table,
    tostring = tostring,
    type = type,
}
environment._G = environment

local BFI = {
    funcs = {},
    L = {},
    modules = {
        Style = {},
        UIWidgets = W,
    },
}

local chunk, loadError =
    loadfile("Modules/UIWidgets/ObjectiveTracker.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(callback), "function", "module callback")
local setupTracker = findUpvalue(callback, "SetupTracker")
assertEqual(type(setupTracker), "function", "tracker setup upvalue")
local removeTracker = findUpvalue(
    setupTracker,
    "RemoveTrackerFromRightManagedFrameContainer"
)
assertEqual(type(removeTracker), "function", "compatibility helper upvalue")

local legacyCalls = 0
local accessorCalls = 0
local legacyContainer = {}
function legacyContainer:RemoveManagedFrame(frame)
    legacyCalls = legacyCalls + 1
    assertEqual(self, legacyContainer, "legacy container self")
    assertEqual(frame, tracker, "legacy tracker")
end

environment.UIParentRightManagedFrameContainer = legacyContainer
environment.GetRightManagedFrameContainer = function()
    accessorCalls = accessorCalls + 1
    return {}
end
removeTracker()
assertEqual(legacyCalls, 1, "12.0.7 legacy removal")
assertEqual(accessorCalls, 0, "legacy contract takes precedence")

local modernCalls = 0
local modernContainer = {}
function modernContainer:RemoveManagedFrame(frame)
    modernCalls = modernCalls + 1
    assertEqual(self, modernContainer, "modern container self")
    assertEqual(frame, tracker, "modern tracker")
end

environment.UIParentRightManagedFrameContainer = nil
environment.GetRightManagedFrameContainer = function()
    accessorCalls = accessorCalls + 1
    return modernContainer
end
removeTracker()
assertEqual(accessorCalls, 1, "12.1 accessor call")
assertEqual(modernCalls, 1, "12.1 managed-frame removal")

environment.GetRightManagedFrameContainer = nil
removeTracker()
assertEqual(modernCalls, 1, "missing manager is a no-op")

environment.GetRightManagedFrameContainer = function()
    return {}
end
removeTracker()
assertTrue(true, "manager without removal capability is a no-op")

print("objective_tracker_12_1_compat_test.lua: ok")
