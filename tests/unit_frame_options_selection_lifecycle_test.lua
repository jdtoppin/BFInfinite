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

local function getUpvalue(func, expectedName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(func, index)
        if not name then return end
        if name == expectedName then
            return value, index
        end
        index = index + 1
    end
end

local function setUpvalue(func, expectedName, value)
    local _, index = getUpvalue(func, expectedName)
    assertTrue(index, "missing upvalue: " .. expectedName)
    debug.setupvalue(func, index, value)
end

local callbacks = {}
local scheduled = {}
local events = {}
local sharedOptions = {}

local function newPane(selection, index)
    local pane = {
        _height = 20 + index,
        id = selection .. index,
        shown = true,
    }

    function pane:Hide()
        self.shown = false
        events[#events + 1] = "hide:" .. self.id
    end

    function pane.Load(info)
        pane.loadedWith = info.id
        events[#events + 1] = "load:" .. pane.id
    end

    function pane:Show()
        self.shown = true
        events[#events + 1] = "show:" .. self.id
    end

    return pane
end

local cachedPanes = {
    newPane("shared", 1),
    newPane("shared", 2),
}

local F = {}
function F.GetUnitFrameOptions()
    for index in pairs(sharedOptions) do
        sharedOptions[index] = nil
    end

    for index, pane in ipairs(cachedPanes) do
        sharedOptions[index] = pane
    end
    return sharedOptions
end

local AF = {}
function AF.CreateObjectPool()
    return {}
end

function AF.RegisterCallback(event, callback)
    callbacks[event] = callback
end

function AF.RePoint()
    events[#events + 1] = "repoint"
end

function AF.SetPoint()
end

local BFI = {
    funcs = F,
    L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    }),
    modules = {
        UnitFrames = {},
    },
}

local environment = {
    _G = false,
    AbstractFramework = AF,
    C_Timer = {
        After = function(_, callback)
            scheduled[#scheduled + 1] = callback
        end,
    },
    debug = debug,
    error = error,
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    select = select,
    setmetatable = setmetatable,
    string = string,
    table = table,
    tinsert = table.insert,
    tostring = tostring,
    type = type,
}
environment._G = environment
setmetatable(environment, {
    __index = function(_, key)
        error("unexpected UnitFrames global: " .. tostring(key), 2)
    end,
})

local chunk, loadError = loadfile("Options/UnitFrames.lua")
assertTrue(chunk, loadError)
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local refresh = callbacks.BFI_RefreshOptions
assertTrue(refresh, "unit frame refresh callback")
local loadList = getUpvalue(refresh, "LoadList")
assertTrue(loadList, "LoadList upvalue")
local loadOptions = getUpvalue(loadList, "ListItem_LoadOptions")
assertTrue(loadOptions, "ListItem_LoadOptions upvalue")

local scroll = {
    scrollContent = {},
}
function scroll:SetContentHeights(heights, spacing)
    self.heights = heights
    self.spacing = spacing
end

setUpvalue(loadOptions, "frameOptionsPane", {
    scrollSettings = scroll,
})

loadOptions({id = "buffs"})
assertEqual(#scheduled, 1, "Buffs deferred pass count")
assertEqual(cachedPanes[1].loadedWith, "buffs",
    "Buffs first pane loaded synchronously")
assertEqual(cachedPanes[2].loadedWith, "buffs",
    "Buffs second pane loaded synchronously")

loadOptions({id = "debuffs"})
assertEqual(#scheduled, 2, "Debuffs deferred pass count")
assertEqual(cachedPanes[1].loadedWith, "debuffs",
    "Debuffs first pane loaded synchronously")
assertEqual(cachedPanes[2].loadedWith, "debuffs",
    "Debuffs second pane loaded synchronously")

local eventsBeforeOldPass = #events
scheduled[1]()
assertEqual(#events, eventsBeforeOldPass,
    "obsolete Buffs pass is ignored")
assertEqual(cachedPanes[1].loadedWith, "debuffs",
    "obsolete pass does not rebind cached pane")

scheduled[2]()
assertEqual(cachedPanes[1].loadedWith, "debuffs",
    "latest pass preserves Debuffs first pane")
assertEqual(cachedPanes[2].loadedWith, "debuffs",
    "latest pass preserves Debuffs second pane")
assertEqual(events[#events], "repoint",
    "latest pass repoints after loading")

print("unit frame options selection lifecycle tests passed")
