local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local updatePixels
local secretWidth = {}
local secretHeight = {}
local secretScale = {}
local F = {
    isValueNonSecret = function(value)
        return value ~= secretWidth
            and value ~= secretHeight
            and value ~= secretScale
    end,
}
local AF = {
    BuildOnUpdateExecutor = function(callback)
        updatePixels = callback
        return {
            Clear = function() end,
            Submit = function() end,
        }
    end,
    RegisterCallback = function() end,
}
local environment = {
    _G = false,
    AbstractFramework = AF,
    Enum = {ItemQuality = {}},
    hooksecurefunc = function() end,
    ipairs = ipairs,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
    setmetatable = setmetatable,
    string = string,
    table = table,
    type = type,
    unpack = unpack,
}
environment._G = environment

local BFI = {
    funcs = F,
    modules = {Style = {}},
}

local chunk, loadError = loadfile("Modules/Style/Style.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)
assertEqual(type(updatePixels), "function", "pixel updater callback")

local calls = 0
local function region(width, height, scale, scaleMustNotBeRead)
    return {
        GetSize = function()
            return width, height
        end,
        GetEffectiveScale = function()
            if scaleMustNotBeRead then
                error("scale must not be read after secret size", 2)
            end
            return scale
        end,
        UpdatePixels = function()
            calls = calls + 1
        end,
    }
end

updatePixels(nil, region(secretWidth, 14, 1, true), 0, 1)
assertEqual(calls, 0, "secret width skips pixel work")
updatePixels(nil, region(14, secretHeight, 1, true), 0, 1)
assertEqual(calls, 0, "secret height skips pixel work")
updatePixels(nil, region(14, 14, secretScale), 0, 1)
assertEqual(calls, 0, "secret scale skips pixel work")
updatePixels(nil, region(14, 14, 0), 0, 1)
assertEqual(calls, 0, "invalid scale skips pixel work")
updatePixels(nil, region(14, 14, 0.6), 0, 1)
assertEqual(calls, 1, "public geometry updates normally")

print("style_pixel_updater_secret_geometry_test.lua: ok")
