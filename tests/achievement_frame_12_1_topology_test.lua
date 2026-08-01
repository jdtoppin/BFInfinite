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

local function setUpvalue(func, targetName, targetValue)
    local index = 1
    while true do
        local name = debug.getupvalue(func, index)
        if not name then
            error("missing upvalue: " .. targetName, 2)
        elseif name == targetName then
            debug.setupvalue(func, index, targetValue)
            return
        end
        index = index + 1
    end
end

local addonCallback
local AF = {}

function AF.RegisterAddonLoaded(addon, callback)
    assertEqual(addon, "Blizzard_AchievementUI", "addon callback owner")
    addonCallback = callback
end

local styledEditBoxes = {}
local styledDropdowns = {}
local S = {}

function S.StyleEditBox(box, offset)
    assertTrue(box ~= nil, "StyleEditBox must not receive nil")
    styledEditBoxes[#styledEditBoxes + 1] = {
        box = box,
        offset = offset,
    }
end

function S.StyleDropdownButton(dropdown)
    assertTrue(dropdown ~= nil, "StyleDropdownButton must not receive nil")
    styledDropdowns[#styledDropdowns + 1] = dropdown
end

local BFI = {
    funcs = {},
    modules = {
        Style = S,
    },
}

local environment = {
    AbstractFramework = AF,
    CRITERIA_TYPE_ACHIEVEMENT = 1,
    EVALUATION_TREE_FLAG_PROGRESS_BAR = 1,
    GetAchievementCriteriaInfo = function() end,
    GetAchievementNumCriteria = function() end,
    GetNumFilteredAchievements = function() end,
    PanelTemplates_SetTabEnabled = function() end,
    UnitClassBase = function() end,
    bit = {
        band = function() return 0 end,
    },
    debug = debug,
    ipairs = ipairs,
    next = next,
    select = select,
    tostring = tostring,
    type = type,
}
environment._G = environment

local chunk, loadError =
    loadfile("Modules/Blizzard/Style/AchievementFrame.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(addonCallback), "function", "Achievement addon callback")

local resolveSearchControls =
    findUpvalue(addonCallback, "ResolveSearchControls")
assertEqual(type(resolveSearchControls), "function", "12.1 search resolver")

local searchPreview = {}
local searchBox = {
    SearchPreviewContainer = searchPreview,
}
local dropdown = {}
local achievementFrame = {
    HeaderDetails = {
        Filters = {
            FilterDropdown = dropdown,
            SearchBox = searchBox,
        },
    },
}

local resolvedSearchBox, resolvedDropdown, resolvedPreview =
    resolveSearchControls(achievementFrame)
assertEqual(resolvedSearchBox, searchBox, "nested SearchBox")
assertEqual(resolvedDropdown, dropdown, "nested FilterDropdown")
assertEqual(resolvedPreview, searchPreview,
    "nested SearchPreviewContainer")

local styleAchievementFrame =
    findUpvalue(addonCallback, "StyleAchievementFrame")
local styleSearchControls =
    findUpvalue(styleAchievementFrame, "StyleSearchControls")
assertEqual(type(styleSearchControls), "function",
    "search-control styling closure")
setUpvalue(styleSearchControls, "searchBox", resolvedSearchBox)
setUpvalue(styleSearchControls, "filterDropdown", resolvedDropdown)
styleSearchControls()
assertEqual(#styledEditBoxes, 1, "SearchBox style calls")
assertEqual(styledEditBoxes[1].box, searchBox, "styled nested SearchBox")
assertEqual(styledEditBoxes[1].offset, -4, "SearchBox backdrop offset")
assertEqual(#styledDropdowns, 1, "FilterDropdown style calls")
assertEqual(styledDropdowns[1], dropdown, "styled nested FilterDropdown")

local missingSearchBox, missingDropdown = resolveSearchControls({})
assertEqual(missingSearchBox, nil, "missing 12.1 search hierarchy")
assertEqual(missingDropdown, nil, "missing 12.1 dropdown hierarchy")

environment.AchievementFrame = {}
environment.AchievementFrameTab2 = {}
addonCallback()

local sourceFile = assert(io.open(
    "Modules/Blizzard/Style/AchievementFrame.lua", "rb"
))
local source = sourceFile:read("*a")
sourceFile:close()

assertTrue(source:find(
    "frame.HeaderDetails", 1, true
) ~= nil, "12.1 HeaderDetails.Filters path")
assertTrue(source:find("achievementFrame.SearchBox", 1, true) == nil,
    "retired root SearchBox path")
assertTrue(source:find("achievementFrame.FilterDropdown", 1, true) == nil,
    "retired root FilterDropdown path")
assertTrue(source:find(
    "achievementFrame.SearchPreviewContainer", 1, true
) == nil, "retired root SearchPreviewContainer path")
assertTrue(source:find("AF.SetSize(searchBox", 1, true) == nil,
    "Blizzard owns SearchBox size")
assertTrue(source:find("AF.ClearPoints(searchBox)", 1, true) == nil,
    "Blizzard owns SearchBox anchors")
assertTrue(source:find("AF.SetSize(dropdown", 1, true) == nil,
    "Blizzard owns FilterDropdown size")
assertTrue(source:find("AF.ClearPoints(dropdown)", 1, true) == nil,
    "Blizzard owns FilterDropdown anchors")
assertTrue(source:find("SetMenuAnchor", 1, true) == nil,
    "Blizzard owns FilterDropdown menu anchoring")
assertTrue(source:find(
    "dropdown.displacedRegions = nil", 1, true
) == nil, "no redundant dropdown layout mutation")

print("achievement_frame_12_1_topology_test.lua: ok")
