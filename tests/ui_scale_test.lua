local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local physicalWidth, physicalHeight
local AF = {
    GetPixelFactor = function()
        return 768 / physicalHeight
    end,
    RoundToDecimal = function(value, places)
        local multiplier = 10 ^ places
        return math.floor(value * multiplier + 0.5) / multiplier
    end,
    Clamp = function(value, minimum, maximum)
        return math.max(minimum, math.min(value, maximum))
    end,
}
local BFI = {
    L = setmetatable({}, {__index = function(_, key) return key end}),
    funcs = {},
    modules = {},
}
local environment = {
    _G = false,
    AbstractFramework = AF,
    GetPhysicalScreenSize = function()
        return physicalWidth, physicalHeight
    end,
}
environment._G = environment
setmetatable(environment, {__index = _G})

local chunk = assert(loadfile("Utils.lua"))
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local cases = {
    {label = "1080p reference", width = 1920, height = 1080, expected = 0.71},
    {label = "1440p", width = 2560, height = 1440, expected = 0.71},
    {label = "4K", width = 3840, height = 2160, expected = 0.71},
    {label = "5K", width = 5120, height = 2880, expected = 0.71},
    {label = "MacBook Air Retina backing", width = 2560, height = 1664, expected = 0.63},
    {label = "true 1280x832 display", width = 1280, height = 832, expected = 0.92},
    {label = "1440p ultrawide", width = 3440, height = 1440, expected = 0.71},
    {label = "high-density 4:3 comfort floor", width = 2048, height = 1536, expected = 0.63},
    {label = "720p pixel floor", width = 1280, height = 720, expected = 1.07},
}

for _, case in ipairs(cases) do
    physicalWidth, physicalHeight = case.width, case.height
    assertEqual(BFI.funcs.GetAutoUIScale(), case.expected, case.label .. " automatic scale")
end

local coreSource = readFile("Core.lua")
local optionsSource = readFile("Options/General.lua")
assert(coreSource:find("F.GetAutoUIScale()", 1, true),
    "new resolutions must use the BFI automatic scale")
assert(optionsSource:find("F.GetAutoUIScale()", 1, true),
    "the Auto Scale button must use the BFI automatic scale")
assert(not coreSource:find("AF.GetBestScale()", 1, true),
    "Core must not bypass the BFI automatic scale")
assert(not optionsSource:find("AF.GetBestScale()", 1, true),
    "General options must not bypass the BFI automatic scale")

print("ui_scale_test.lua: ok")
