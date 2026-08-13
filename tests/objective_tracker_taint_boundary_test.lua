local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function readFile(path)
    local file, openError = io.open(path, "rb")
    assertEqual(type(file), "userdata", openError or ("open " .. path))
    local source = file:read("*a")
    file:close()
    return source
end

local function assertNotContains(source, pattern, message)
    if source:find(pattern, 1, true) then
        error(message .. ": found " .. pattern, 2)
    end
end

local function setUpvalue(func, targetName, replacement)
    local index = 1
    while true do
        local name = debug.getupvalue(func, index)
        if not name then
            error("missing upvalue: " .. targetName, 2)
        elseif name == targetName then
            debug.setupvalue(func, index, replacement)
            return
        end
        index = index + 1
    end
end

local function forbiddenCall(name)
    return function()
        error(name .. " must remain Blizzard-owned", 2)
    end
end

local callback
local originalPositionCheck = function() return true end
local tracker = {
    IsInDefaultPosition = originalPositionCheck,
    ignoreFramePositionManager = "blizzard",
    isManagedFrame = "blizzard",
    isRightManagedFrame = "blizzard",
    Update = forbiddenCall("ObjectiveTrackerFrame:Update"),
    UpdateHeight = forbiddenCall("ObjectiveTrackerFrame:UpdateHeight"),
    MarkDirty = forbiddenCall("ObjectiveTrackerFrame:MarkDirty"),
    ClearAllPoints = forbiddenCall("ObjectiveTrackerFrame:ClearAllPoints"),
    SetPoint = forbiddenCall("ObjectiveTrackerFrame:SetPoint"),
}
local scenarioTracker = {
    StageBlock = {
        Stage = {},
        CompleteLabel = {},
        Name = {},
    },
}
local rewardsFrame = {}
local fontUpdates = 0
local AF = {
    RegisterCallback = function(_, registeredCallback)
        callback = registeredCallback
    end,
    SetFont = function()
        fontUpdates = fontUpdates + 1
    end,
}
local W = {
    config = {
        objectiveTracker = {
            enabled = true,
            font = {"Test Font", 12, "none"},
        },
    },
}
local environment = {
    _G = false,
    AbstractFramework = AF,
    GenerateClosure = function() end,
    GetRightManagedFrameContainer = forbiddenCall(
        "GetRightManagedFrameContainer"
    ),
    ObjectiveTrackerFrame = tracker,
    ObjectiveTrackerHeaderFont = {},
    ObjectiveTrackerLineFont = {},
    ObjectiveTrackerManager = {},
    ScenarioObjectiveTracker = scenarioTracker,
    ScenarioRewardsFrame = rewardsFrame,
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
    modules = {
        Style = {},
        UIWidgets = W,
    },
}

local trackerSource = readFile("Modules/UIWidgets/ObjectiveTracker.lua")
local forbiddenOwnership = {
    "F.DisableEditMode(tracker",
    "GetRightManagedFrameContainer",
    "RemoveManagedFrame",
    "CreateMover(tracker",
    "tracker:Update(",
    "tracker:UpdateHeight(",
    "tracker:MarkDirty(",
    "tracker:ClearAllPoints(",
    "tracker:SetPoint(",
    "tracker.IsInDefaultPosition =",
    "tracker.editModeHeight =",
    "tracker.ignoreFramePositionManager =",
    "tracker.isManagedFrame =",
    "tracker.isRightManagedFrame =",
}
for _, pattern in ipairs(forbiddenOwnership) do
    assertNotContains(trackerSource, pattern,
        "Objective Tracker layout must remain Blizzard-owned")
end

local optionsSource = readFile("Options/UIWidgets_Options.lua")
local objectiveSettings = optionsSource:match(
    "objectiveTracker%s*=%s*{(.-)\n%s*},"
)
assertEqual(type(objectiveSettings), "string",
    "Objective Tracker options block")
assertNotContains(objectiveSettings, '"height"',
    "removed height control must not return")

local defaultsSource = readFile("Modules/UIWidgets/Defaults.lua")
local objectiveDefaults = defaultsSource:match(
    "objectiveTracker%s*=%s*{(.-)\n%s*},"
)
assertEqual(type(objectiveDefaults), "string",
    "Objective Tracker defaults block")
assertNotContains(objectiveDefaults, "position =",
    "removed position setting must not return")
assertNotContains(objectiveDefaults, "height =",
    "removed height setting must not return")

local chunk, loadError =
    loadfile("Modules/UIWidgets/ObjectiveTracker.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(callback), "function", "module callback")
setUpvalue(callback, "trackerStyled", true)
callback(nil, "uiWidgets", "objectiveTracker")

assertEqual(fontUpdates, 5, "visual font styling remains active")
assertEqual(tracker.IsInDefaultPosition, originalPositionCheck,
    "default-position method remains Blizzard-owned")
assertEqual(tracker.ignoreFramePositionManager, "blizzard",
    "frame-position-manager flag remains untouched")
assertEqual(tracker.isManagedFrame, "blizzard",
    "managed-frame flag remains untouched")
assertEqual(tracker.isRightManagedFrame, "blizzard",
    "right-managed-frame flag remains untouched")

print("objective_tracker_taint_boundary_test.lua: ok")
