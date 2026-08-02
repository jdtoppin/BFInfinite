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

local function assertContains(source, pattern, message)
    if not source:find(pattern, 1, true) then
        error(message .. ": missing " .. pattern, 2)
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
local trackerNineSlice = {}
local tracker = {
    IsInDefaultPosition = originalPositionCheck,
    ignoreFramePositionManager = "blizzard",
    isManagedFrame = "blizzard",
    isRightManagedFrame = "blizzard",
    Update = forbiddenCall("ObjectiveTrackerFrame:Update"),
    UpdateHeight = forbiddenCall("ObjectiveTrackerFrame:UpdateHeight"),
    MarkDirty = forbiddenCall("ObjectiveTrackerFrame:MarkDirty"),
    NineSlice = trackerNineSlice,
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
local backdropCreates = 0
local textureRemovals = 0
local backdropRelativeLevel
local backdropAnchor
local backdropParent
local backdropColor
local backdropBorderColor
local trackerBackdrop = {
    SetAllPoints = function(_, relativeTo)
        backdropAnchor = relativeTo
    end,
    SetBackdropColor = function(_, red, green, blue, alpha)
        backdropColor = {red, green, blue, alpha}
    end,
    SetBackdropBorderColor = function(_, red, green, blue, alpha)
        backdropBorderColor = {red, green, blue, alpha}
    end,
}
local AF = {
    CreateBorderedFrame = function(
        parent,
        name,
        width,
        height,
        backgroundColor,
        borderColor
    )
        assertEqual(name, nil, "anonymous tracker backdrop")
        assertEqual(width, nil, "tracker backdrop follows native width")
        assertEqual(height, nil, "tracker backdrop follows native height")
        assertEqual(backgroundColor, "background", "shared background token")
        assertEqual(borderColor, "border", "shared border token")
        backdropParent = parent
        backdropCreates = backdropCreates + 1
        return trackerBackdrop
    end,
    RegisterCallback = function(_, registeredCallback)
        callback = registeredCallback
    end,
    GetColorRGB = function(name, alpha)
        if name == "background" then
            return 0.1, 0.2, 0.3, alpha
        end
        assertEqual(name, "border", "shared border color lookup")
        return 0.4, 0.5, 0.6, alpha or 1
    end,
    SetFrameLevel = function(frame, relativeLevel)
        assertEqual(frame, trackerBackdrop, "tracker backdrop frame level")
        backdropRelativeLevel = relativeLevel
    end,
    SetFont = function()
        fontUpdates = fontUpdates + 1
    end,
}
local S = {
    RemoveTextures = function(region, hide)
        assertEqual(region, trackerNineSlice, "native tracker texture target")
        assertEqual(hide, true, "native tracker textures hidden")
        textureRemovals = textureRemovals + 1
    end,
}
local W = {
    config = {
        objectiveTracker = {
            enabled = true,
            backgroundAlpha = 0.73,
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
        Style = S,
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
    "tracker.NineSlice:ClearAllPoints(",
    "tracker.NineSlice:SetPoint(",
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
assertContains(objectiveSettings, '"objectiveTrackerBackground"',
    "Objective Tracker background controls must remain available")
assertContains(objectiveSettings, '"objectiveTrackerQuestAutomation"',
    "Objective Tracker quest automation controls must remain available")
assertNotContains(objectiveSettings, '"height"',
    "removed height control must not return")

local defaultsSource = readFile("Modules/UIWidgets/Defaults.lua")
local objectiveDefaults = defaultsSource:match(
    "objectiveTracker%s*=%s*{(.-)\n%s*},"
)
assertEqual(type(objectiveDefaults), "string",
    "Objective Tracker defaults block")
assertContains(objectiveDefaults, "backgroundAlpha =",
    "Objective Tracker background opacity default")
assertContains(objectiveDefaults, "autoAcceptQuests = false",
    "Objective Tracker auto-accept remains opt-in")
assertContains(objectiveDefaults, "autoTurnInQuests = false",
    "Objective Tracker auto-turn-in remains opt-in")
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

assertEqual(textureRemovals, 1,
    "native Objective Tracker textures replaced once")
assertEqual(backdropCreates, 1,
    "shared BFI Objective Tracker backdrop created once")
assertEqual(backdropParent, tracker,
    "shared backdrop inherits Objective Tracker visibility")
assertEqual(backdropAnchor, trackerNineSlice,
    "shared backdrop follows native content bounds")
assertEqual(backdropRelativeLevel, -1,
    "shared backdrop remains behind tracker content")
assertEqual(backdropColor[1], 0.1,
    "shared backdrop uses the BFI background color")
assertEqual(backdropColor[4], 0.73,
    "shared backdrop uses configured opacity")
assertEqual(backdropBorderColor[1], 0.4,
    "shared backdrop uses the BFI border color")
assertEqual(backdropBorderColor[4], 0.73,
    "configured opacity can fully hide the shared border")
W.config.objectiveTracker.backgroundAlpha = 0.42
callback(nil, "uiWidgets", "objectiveTracker")
assertEqual(textureRemovals, 1,
    "Objective Tracker native textures are not reprocessed")
assertEqual(backdropCreates, 1,
    "Objective Tracker shared backdrop remains idempotent")
assertEqual(backdropColor[4], 0.42,
    "Objective Tracker opacity updates without rebuilding the backdrop")
assertEqual(backdropBorderColor[4], 0.42,
    "Objective Tracker border opacity updates with its background")
W.config.objectiveTracker.backgroundAlpha = 0
callback(nil, "uiWidgets", "objectiveTracker")
assertEqual(backdropColor[4], 0,
    "zero opacity hides the Objective Tracker background")
assertEqual(backdropBorderColor[4], 0,
    "zero opacity hides the Objective Tracker border")
assertEqual(fontUpdates, 15, "visual font styling remains active")
assertEqual(tracker.IsInDefaultPosition, originalPositionCheck,
    "default-position method remains Blizzard-owned")
assertEqual(tracker.ignoreFramePositionManager, "blizzard",
    "frame-position-manager flag remains untouched")
assertEqual(tracker.isManagedFrame, "blizzard",
    "managed-frame flag remains untouched")
assertEqual(tracker.isRightManagedFrame, "blizzard",
    "right-managed-frame flag remains untouched")

print("objective_tracker_taint_boundary_test.lua: ok")
