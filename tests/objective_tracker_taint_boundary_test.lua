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
local trackerInDefaultPosition = true
local originalPositionCheck = function()
    return trackerInDefaultPosition
end
local trackerNineSlice = {}
local trackerHeader = {}
local trackerCollapsed = false
local firstModuleShown = true
local secondModuleShown = true
local thirdModuleShown = false
local trackerUpdateHook
local trackerHeightUpdateHook
local trackerMarkDirtyHook
local nextFrameCallbacks = {}
local pendingNativeDirtyUpdate

local function QueueNextFrame(queuedCallback)
    nextFrameCallbacks[#nextFrameCallbacks + 1] = queuedCallback
end

local function RunQueuedFrames()
    while #nextFrameCallbacks > 0 do
        local queued = table.remove(nextFrameCallbacks, 1)
        queued()
    end
end

local firstModule = {
    IsShown = function()
        return firstModuleShown
    end,
}
local secondModule = {
    IsShown = function()
        return secondModuleShown
    end,
}
local thirdModule = {
    IsShown = function()
        return thirdModuleShown
    end,
}
local tracker = {
    Header = trackerHeader,
    IsInDefaultPosition = originalPositionCheck,
    IsCollapsed = function()
        return trackerCollapsed
    end,
    ignoreFramePositionManager = "blizzard",
    isManagedFrame = "blizzard",
    isRightManagedFrame = "blizzard",
    modules = {
        firstModule,
        secondModule,
        thirdModule,
    },
    Update = forbiddenCall("ObjectiveTrackerFrame:Update"),
    UpdateHeight = forbiddenCall("ObjectiveTrackerFrame:UpdateHeight"),
    MarkDirty = function()
        if pendingNativeDirtyUpdate then
            QueueNextFrame(pendingNativeDirtyUpdate)
            pendingNativeDirtyUpdate = nil
        end
        if trackerMarkDirtyHook then
            trackerMarkDirtyHook()
        end
    end,
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
local backdropAnchors = {}
local backdropParent
local backdropColor
local backdropBorderColor
local dockFrameEvents = 0
local dockReservationCreates = 0
local dockReservationAnchors = {}
local trackerDockFrame = {
    ClearAllPoints = function()
        dockReservationAnchors = {}
    end,
    SetPoint = function(_, ...)
        dockReservationAnchors[#dockReservationAnchors + 1] = {...}
    end,
}
local trackerBackdrop = {
    ClearAllPoints = function()
        backdropAnchors = {}
    end,
    SetPoint = function(_, ...)
        backdropAnchors[#backdropAnchors + 1] = {...}
    end,
    SetBackdropColor = function(_, red, green, blue, alpha)
        backdropColor = {red, green, blue, alpha}
    end,
    SetBackdropBorderColor = function(_, red, green, blue, alpha)
        backdropBorderColor = {red, green, blue, alpha}
    end,
}
local AF = {
    CreateFrame = function(parent, name, width, height)
        assertEqual(parent, tracker, "Objective Tracker dock reservation parent")
        assertEqual(name, nil, "anonymous tracker dock reservation")
        assertEqual(width, nil, "tracker dock reservation has no owned size")
        assertEqual(height, nil, "tracker dock reservation has no owned size")
        dockReservationCreates = dockReservationCreates + 1
        return trackerDockFrame
    end,
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
    Fire = function(event)
        assertEqual(event, "BFI_ObjectiveTrackerDockFrameChanged",
            "Objective Tracker dock-frame callback")
        dockFrameEvents = dockFrameEvents + 1
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
    RunNextFrame = QueueNextFrame,
    debug = debug,
    hooksecurefunc = function(target, method, hook)
        assertEqual(target, tracker, "Objective Tracker update hook target")
        assertEqual(type(hook), "function", "Objective Tracker update hook")
        if method == "Update" then
            assertEqual(trackerUpdateHook, nil,
                "Objective Tracker update hooked once")
            trackerUpdateHook = hook
        elseif method == "UpdateHeight" then
            assertEqual(trackerHeightUpdateHook, nil,
                "Objective Tracker height update hooked once")
            trackerHeightUpdateHook = hook
        elseif method == "MarkDirty" then
            assertEqual(trackerMarkDirtyHook, nil,
                "Objective Tracker dirty update hooked once")
            trackerMarkDirtyHook = hook
        else
            error("unexpected Objective Tracker hook: " .. tostring(method), 2)
        end
    end,
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
    "tracker:SetHeight(",
    "tracker:SetSize(",
    "tracker:SetClipsChildren(",
    "tracker:SetParent(",
    "tracker.NineSlice:ClearAllPoints(",
    "tracker.NineSlice:SetPoint(",
    "module:GetContentsHeight(",
    "module:IsVisible(",
    "tracker.IsInDefaultPosition =",
    "tracker.editModeHeight =",
    "tracker.ignoreFramePositionManager =",
    "tracker.isManagedFrame =",
    "tracker.isRightManagedFrame =",
    "tracker.GetAvailableHeight =",
    "C_EditMode.SaveLayouts",
}
for _, pattern in ipairs(forbiddenOwnership) do
    assertNotContains(trackerSource, pattern,
        "Objective Tracker layout must remain Blizzard-owned")
end

local updateSource = trackerSource:match(
    "local function UpdateObjectiveTracker(.-)AF.RegisterCallback"
)
assertEqual(type(updateSource), "string",
    "Objective Tracker update callback source")
local observerAt = updateSource:find(
    "SetupTrackerLayoutObserver()",
    1,
    true
)
local disabledReturnAt = updateSource:find(
    "if not config.enabled then",
    1,
    true
)
assertEqual(type(observerAt), "number",
    "native layout observer remains installed")
assertEqual(type(disabledReturnAt), "number",
    "Objective Tracker disabled guard remains available")
assertEqual(observerAt < disabledReturnAt, true,
    "native layout observer also covers an unstyled tracker")
assertContains(
    trackerSource,
    'hooksecurefunc(tracker, "UpdateHeight", UpdateTrackerBackgroundLayout)',
    "native height changes refresh only the BFI dock reservation"
)
assertContains(
    trackerSource,
    'hooksecurefunc(tracker, "MarkDirty", QueueTrackerBackgroundLayout)',
    "deferred native module layouts refresh the BFI surface"
)

local optionsSource = readFile("Options/UIWidgets_Options.lua")
local objectiveSettings = optionsSource:match(
    "objectiveTracker%s*=%s*{(.-)\n%s*},"
)
assertEqual(type(objectiveSettings), "string",
    "Objective Tracker options block")
assertContains(objectiveSettings, '"objectiveTrackerBackground"',
    "Objective Tracker background controls must remain available")
assertContains(objectiveSettings, '"objectiveTrackerNativeHeight"',
    "Objective Tracker native height proxy must remain available")
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
assertEqual(type(trackerUpdateHook), "function",
    "shared backdrop follows native Objective Tracker updates")
assertEqual(type(trackerHeightUpdateHook), "function",
    "dock reservation follows native Objective Tracker height updates")
assertEqual(type(trackerMarkDirtyHook), "function",
    "shared backdrop follows deferred Objective Tracker layouts")
assertEqual(#backdropAnchors, 3,
    "shared backdrop uses explicit content bounds")
assertEqual(backdropAnchors[1][1], "TOPLEFT",
    "shared backdrop top-left point")
assertEqual(backdropAnchors[1][2], trackerHeader,
    "shared backdrop top-left follows the header")
assertEqual(backdropAnchors[1][3], "TOPLEFT",
    "shared backdrop top-left relative point")
assertEqual(backdropAnchors[1][4], -6,
    "shared backdrop removes the empty native left overhang")
assertEqual(backdropAnchors[1][5], 6,
    "shared backdrop moves above the header")
assertEqual(backdropAnchors[2][1], "TOPRIGHT",
    "shared backdrop top-right point")
assertEqual(backdropAnchors[2][2], trackerHeader,
    "shared backdrop top-right follows the header")
assertEqual(backdropAnchors[2][4], 6,
    "shared backdrop uses compact right padding")
assertEqual(backdropAnchors[2][5], 6,
    "shared backdrop top padding is symmetrical")
assertEqual(backdropAnchors[3][1], "BOTTOM",
    "shared backdrop bottom point")
assertEqual(backdropAnchors[3][2], secondModule,
    "shared backdrop follows the last shown objective module")
assertEqual(backdropAnchors[3][5], -16,
    "shared backdrop includes native and extra bottom padding")
assertEqual(backdropRelativeLevel, -1,
    "shared backdrop remains behind tracker content")
assertEqual(dockReservationCreates, 1,
    "separate Objective Tracker dock reservation created once")
assertEqual(W.objectiveTrackerDockFrame, trackerDockFrame,
    "separate reservation is published as the meter dock target")
assertEqual(#dockReservationAnchors, 2,
    "default tracker dock reservation uses compact surface bounds")
assertEqual(dockReservationAnchors[1][1], "TOPLEFT",
    "default dock reservation top-left point")
assertEqual(dockReservationAnchors[1][2], trackerBackdrop,
    "default dock reservation follows compact surface")
assertEqual(dockReservationAnchors[2][1], "BOTTOMRIGHT",
    "default dock reservation bottom-right point")
assertEqual(dockReservationAnchors[2][2], trackerBackdrop,
    "default dock reservation keeps compact surface bottom")
assertEqual(dockFrameEvents, 1,
    "meter docking refreshes when the tracker surface becomes ready")

secondModule.leftMargin = -20
trackerUpdateHook()
assertEqual(backdropAnchors[1][4], -6,
    "internal Scenario layout margin does not create blank left background")
secondModule.leftMargin = nil
trackerUpdateHook()
assertEqual(backdropAnchors[1][4], -6,
    "normal objectives return to the compact left edge")

secondModuleShown = false
trackerUpdateHook()
assertEqual(backdropAnchors[3][2], firstModule,
    "hidden last modules do not extend the shared backdrop")

local dockEventsBeforeFirstModuleCollapse = dockFrameEvents
pendingNativeDirtyUpdate = function()
    secondModuleShown = true
end
tracker:MarkDirty()
assertEqual(backdropAnchors[3][2], firstModule,
    "individual collapse waits for Blizzard's deferred layout")
assertEqual(#nextFrameCallbacks, 2,
    "native layout queues before the BFI surface refresh")
RunQueuedFrames()
assertEqual(backdropAnchors[3][2], secondModule,
    "collapsed headers retain the newly exposed module below")
assertEqual(dockFrameEvents, dockEventsBeforeFirstModuleCollapse + 1,
    "deferred layout reflows the meter dock reservation once")

local dockEventsBeforeSecondModuleCollapse = dockFrameEvents
pendingNativeDirtyUpdate = function()
    secondModuleShown = false
    thirdModuleShown = true
end
tracker:MarkDirty()
assertEqual(backdropAnchors[3][2], secondModule,
    "second collapse also waits for Blizzard's deferred layout")
RunQueuedFrames()
assertEqual(backdropAnchors[3][2], thirdModule,
    "later headers remain inside the shared backdrop after collapse")
assertEqual(dockFrameEvents, dockEventsBeforeSecondModuleCollapse + 1,
    "later deferred layout reflows the meter dock reservation once")

secondModuleShown = true
thirdModuleShown = false
trackerUpdateHook()

trackerCollapsed = true
trackerUpdateHook()
assertEqual(backdropAnchors[3][2], trackerHeader,
    "collapsed tracker background shrinks to the visible header")
assertEqual(backdropAnchors[3][5], -6,
    "collapsed tracker keeps only surface padding below the header")
assertEqual(backdropAnchors[1][4], -6,
    "collapsed tracker retains the compact left edge")

trackerCollapsed = false
secondModuleShown = true
thirdModuleShown = false
trackerUpdateHook()
assertEqual(backdropAnchors[3][2], secondModule,
    "expanded tracker background follows restored objective content")
assertEqual(backdropAnchors[3][5], -16,
    "expanded tracker restores objective bottom padding")
trackerInDefaultPosition = false
local dockEventsBeforeNativeHeight = dockFrameEvents
trackerHeightUpdateHook()
assertEqual(dockFrameEvents, dockEventsBeforeNativeHeight + 1,
    "native height updates reflow the docked meter lane")
assertEqual(backdropAnchors[3][2], secondModule,
    "custom native height leaves the visible background content-bound")
assertEqual(#dockReservationAnchors, 2,
    "custom tracker dock reservation uses native extent")
assertEqual(dockReservationAnchors[1][1], "TOPLEFT",
    "custom dock reservation top-left point")
assertEqual(dockReservationAnchors[1][2], tracker,
    "custom dock reservation follows native tracker top")
assertEqual(dockReservationAnchors[1][4], -6,
    "custom dock reservation includes the surface's left padding")
assertEqual(dockReservationAnchors[1][5], 0,
    "custom dock reservation retains the native top edge")
assertEqual(dockReservationAnchors[2][1], "BOTTOMRIGHT",
    "custom dock reservation bottom-right point")
assertEqual(dockReservationAnchors[2][2], tracker,
    "custom dock reservation follows native tracker height")
assertEqual(dockReservationAnchors[2][4], 6,
    "custom dock reservation includes the surface's right padding")
assertEqual(dockReservationAnchors[2][5], 0,
    "custom dock reservation retains the native bottom edge")
trackerCollapsed = true
trackerHeightUpdateHook()
assertEqual(dockReservationAnchors[1][2], trackerBackdrop,
    "collapsed custom tracker returns dock reservation to compact surface")
assertEqual(dockReservationAnchors[2][2], trackerBackdrop,
    "collapsed custom tracker does not reserve empty native height")
trackerCollapsed = false
trackerInDefaultPosition = true
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
