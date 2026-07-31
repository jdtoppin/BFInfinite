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
assertEqual(type(removeTracker), "function", "managed-container helper")

local accessorCalls = 0
local removalCalls = 0
local managedContainer = {}
function managedContainer:RemoveManagedFrame(frame)
    removalCalls = removalCalls + 1
    assertEqual(self, managedContainer, "managed container self")
    assertEqual(frame, tracker, "managed ObjectiveTrackerFrame")
end
environment.GetRightManagedFrameContainer = function()
    accessorCalls = accessorCalls + 1
    return managedContainer
end

removeTracker()
assertEqual(accessorCalls, 1, "12.1 managed-container accessor")
assertEqual(removalCalls, 1, "12.1 managed-frame removal")

print("objective_tracker_managed_container_test.lua: ok")
