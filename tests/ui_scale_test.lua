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

local recommendedScale
local AF = {
    GetBestScale = function()
        return recommendedScale
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
}
environment._G = environment
setmetatable(environment, {__index = _G})

local chunk = assert(loadfile("Utils.lua"))
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local cases = {
    {label = "1080p", recommended = 0.71, expected = 0.71},
    {label = "1440p", recommended = 0.61, expected = 0.71},
    {label = "4K", recommended = 0.60, expected = 0.71},
    {label = "5K", recommended = 0.50, expected = 0.71},
    {label = "720p", recommended = 1.07, expected = 1.07},
}

for _, case in ipairs(cases) do
    recommendedScale = case.recommended
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
