local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertFalse(value, message)
    if value then
        error(message or "expected a falsy value", 2)
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

local function readFile(path)
    local file, openError = io.open(path, "r")
    assertEqual(type(file), "userdata", openError or ("open " .. path))
    local contents = file:read("*a")
    file:close()
    return contents
end

local modulePath = "Modules/Blizzard/Style/CharacterFrame.lua"
local moduleSource = readFile(modulePath)
assertFalse(
    moduleSource:find("PAPERDOLL_STATCATEGORIES", 1, true),
    "Character styling must not access Blizzard's stat categories"
)
assertFalse(
    moduleSource:find("PaperDollFrame_UpdateStats", 1, true),
    "Character styling must not enumerate visibility-dependent stat rows"
)
assertFalse(
    moduleSource:find("EnumerateActive", 1, true),
    "Character styling must not enumerate active stat rows"
)
assertFalse(
    moduleSource:find("Background:IsShown", 1, true),
    "Character styling must not branch on stat-row visibility"
)
assertFalse(
    moduleSource:find("GetAverageItemLevel", 1, true),
    "Character styling must not query or reformat restricted stat values"
)
assertFalse(
    moduleSource:find("numericValue", 1, true),
    "Character styling must not inspect restricted stat values"
)

local callback
local fontUpdates = {}
local AF = {
    GetColorRGB = function(color, alpha)
        assertEqual(color, "darkgray", "stat background color")
        assertEqual(alpha, 0.1, "stat background alpha")
        return 0.2, 0.2, 0.2, alpha
    end,
    GetPlainTexture = function()
        return "plain"
    end,
    RegisterCallback = function(_, registeredCallback)
        callback = registeredCallback
    end,
    UpdateFont = function(fontString, font, size, flags)
        fontUpdates[#fontUpdates + 1] = {
            flags = flags,
            font = font,
            fontString = fontString,
            size = size,
        }
    end,
}

local function makeBackground()
    local background = {
        points = {},
    }

    function background:ClearAllPoints()
        self.clearCalls = (self.clearCalls or 0) + 1
        self.points = {}
    end

    function background:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end

    function background:SetTexture(texture)
        self.texture = texture
    end

    function background:SetVertexColor(...)
        self.vertexColor = {...}
    end

    return background
end

local itemLevelFrame = {
    Background = setmetatable({}, {
        __index = function()
            error("item-level background must remain untouched", 2)
        end,
    }),
    Label = {},
    Value = {},
}
local CharacterStatsPane = {
    ItemLevelFrame = itemLevelFrame,
}

local environment = {
    _G = false,
    AbstractFramework = AF,
    C_Reputation = {
        GetFactionParagonInfo = function() end,
        IsFactionParagon = function() end,
    },
    CharacterStatsPane = CharacterStatsPane,
    debug = debug,
    io = io,
    next = next,
    select = select,
    string = string,
    table = table,
    tostring = tostring,
    type = type,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local BFI = {
    modules = {
        Style = {},
    },
    vars = {
        blizzardFontSizeDelta = 3,
    },
}

local chunk, loadError = loadfile(modulePath)
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(callback), "function", "module callback")
local styleInsetRight = findUpvalue(callback, "StyleCharacterFrameInsetRight")
assertEqual(type(styleInsetRight), "function", "right inset style upvalue")
local styleStat = findUpvalue(styleInsetRight, "PaperDollFrame_StyleStat")
assertEqual(type(styleStat), "function", "stat presentation callback")

local regularFrame = {
    Background = makeBackground(),
    Label = {},
    Value = {},
}
local hostileValue = setmetatable({}, {
    __add = function()
        error("restricted value was added", 2)
    end,
    __div = function()
        error("restricted value was divided", 2)
    end,
    __index = function()
        error("restricted value was inspected", 2)
    end,
    __tostring = function()
        error("restricted value was formatted", 2)
    end,
})

styleStat(regularFrame, hostileValue, hostileValue, hostileValue, hostileValue)
assertEqual(regularFrame._BFIStatStyled, true, "regular stat styled marker")
assertEqual(regularFrame.Background.texture, "plain", "regular stat background texture")
assertEqual(#regularFrame.Background.vertexColor, 4, "regular stat background color")
assertEqual(regularFrame.Background.clearCalls, 1, "regular stat background reset")
assertEqual(#regularFrame.Background.points, 4, "regular stat background anchors")
assertEqual(#fontUpdates, 2, "regular stat font updates")
assertEqual(fontUpdates[1].fontString, regularFrame.Label, "regular stat label font")
assertEqual(fontUpdates[1].size, 15, "regular stat label size")
assertEqual(fontUpdates[2].fontString, regularFrame.Value, "regular stat value font")
assertEqual(fontUpdates[2].size, 15, "regular stat value size")

styleStat(regularFrame, hostileValue, hostileValue, hostileValue, hostileValue)
assertEqual(regularFrame.Background.clearCalls, 1, "regular stat style is idempotent")
assertEqual(#fontUpdates, 2, "regular stat fonts are not restyled")

styleStat(itemLevelFrame, hostileValue, hostileValue, hostileValue, hostileValue)
assertEqual(itemLevelFrame._BFIStatStyled, true, "item-level stat styled marker")
assertEqual(#fontUpdates, 3, "item-level font update")
assertEqual(fontUpdates[3].fontString, itemLevelFrame.Value, "item-level value font")
assertEqual(fontUpdates[3].size, 23, "item-level value size")

print("character_frame_unit_stats_safety_test.lua: ok")
