local texturePath = assert(arg[1], "path to AbstractFramework Widgets/Texture.lua is required")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertNear(actual, expected, message)
    if math.abs(actual - expected) > 0.000001 then
        error(("%s: expected %.6f, got %.6f"):format(
            message or "values differ",
            expected,
            actual
        ), 2)
    end
end

local AF = {
    noop_true = function()
        return true
    end,
    Unpack8 = function(values)
        return unpack(values, 1, 8)
    end,
}

local environment = {
    C_Texture = {
        GetAtlasExists = function()
            return false
        end,
    },
}
setmetatable(environment, {__index = _G})

local chunk = assert(loadfile(texturePath))
setfenv(chunk, environment)
chunk("AbstractFramework", AF)

assertEqual(type(AF.ReCalcTexCoordForAura), "function",
    "loaded aura texcoord callback")

local coordinates
local aura = {
    icon = {
        SetTexCoord = function(_, ...)
            coordinates = {...}
        end,
    },
}

AF.ReCalcTexCoordForAura(aura, 200, 100)
assertEqual(#coordinates, 8, "texture coordinate count")

local expected = {0.12, 0.31, 0.12, 0.69, 0.88, 0.31, 0.88, 0.69}
for index, value in ipairs(expected) do
    assertNear(coordinates[index], value, "texture coordinate " .. index)
end

coordinates = nil
AF.ReCalcTexCoordForAura(aura, 0, 100)
assertEqual(coordinates, nil, "invalid dimensions leave the icon unchanged")

AF.ReCalcTexCoordForAura({}, 100, 100)

print("abstract_framework_texture_contract.lua: ok")
