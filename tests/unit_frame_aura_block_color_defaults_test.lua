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

local function mergeCopy(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            local child = {}
            target[key] = child
            mergeCopy(child, value)
        else
            target[key] = value
        end
    end
    return target
end

local AF = {}
local UF = {}
local F = {}
local BFI = {
    L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    }),
    funcs = F,
    modules = {
        UnitFrames = UF,
    },
    versionNum = 4,
}

function AF.Copy(...)
    local copy = {}
    for index = 1, select("#", ...) do
        mergeCopy(copy, select(index, ...))
    end
    return copy
end

function AF.GetColorTable()
    return {1, 1, 1, 1}
end

function AF.IsBlank(value)
    return value == nil or value == ""
end

function AF.LowerFirst(value)
    return value:sub(1, 1):lower() .. value:sub(2)
end

function AF.Merge(target, source)
    return mergeCopy(target, source)
end

function AF.RegisterCallback()
end

function AF.UpperFirst(value)
    return value:sub(1, 1):upper() .. value:sub(2)
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    GetCVar = function()
        return nil
    end,
    assert = assert,
    error = error,
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    select = select,
    setmetatable = setmetatable,
    string = string,
    table = table,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    wipe = function(value)
        for key in pairs(value) do
            value[key] = nil
        end
    end,
}
environment._G = environment
setmetatable(environment, {
    __index = function(_, key)
        error(
            "unexpected block-color defaults global: "
                .. tostring(key),
            2
        )
    end,
})

local function loadModule(path)
    local chunk, loadError = loadfile(path)
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
end

loadModule("Utils.lua")
loadModule("Modules/UnitFrames/Presets.lua")

local function assertBlockColor(color, message)
    assertEqual(type(color), "table", message .. " type")
    for index, value in ipairs({0.5, 0.5, 0.5, 1}) do
        assertEqual(color[index], value, message .. " " .. index)
    end
end

local function assertPresetColors(preset, message)
    local count = 0
    local seen = {}

    for owner, frameConfig in pairs(preset) do
        local indicators = type(frameConfig) == "table"
            and frameConfig.indicators
        if type(indicators) == "table" then
            for _, indicatorID in ipairs({"buffs", "debuffs"}) do
                local config = indicators[indicatorID]
                if type(config) == "table" then
                    count = count + 1
                    assertBlockColor(
                        config.blockColor,
                        message .. " " .. owner .. " " .. indicatorID
                    )
                    assertTrue(
                        not seen[config.blockColor],
                        message .. " shared color table "
                            .. owner .. " " .. indicatorID
                    )
                    seen[config.blockColor] = true
                end
            end
        end
    end

    assertEqual(count, 20, message .. " aura indicator count")
end

local defaults = UF.GetDefaults()
local secondDefaults = UF.GetDefaults()
local secondPreset = UF.GetPreset("default2")
assertPresetColors(defaults, "default 1")
assertPresetColors(secondDefaults, "second default 1 copy")
assertPresetColors(secondPreset, "default 2")

defaults.player.indicators.buffs.blockColor[1] = 0.1
assertEqual(
    secondDefaults.player.indicators.buffs.blockColor[1],
    0.5,
    "separate default copies"
)

for _, moduleClassName in ipairs(F.GetProfileModuleClassNames()) do
    if not BFI.modules[moduleClassName] then
        BFI.modules[moduleClassName] = {
            GetDefaults = function()
                return {}
            end,
        }
    end
end
for _, moduleClassName in ipairs({
    "Enhancements",
    "Colors",
    "Auras",
}) do
    if not BFI.modules[moduleClassName] then
        BFI.modules[moduleClassName] = {
            GetDefaults = function()
                return {}
            end,
        }
    end
end
loadModule("Revise.lua")

local oldProfile = {
    revision = BFI.versionNum,
    unitFrames = {
        player = {
            indicators = {
                buffs = {
                    cooldownStyle = "block_clock",
                },
            },
        },
    },
}
F.ReviseProfile(oldProfile)
assertEqual(
    oldProfile.unitFrames.player.indicators.buffs.cooldownStyle,
    "block_clock",
    "profile hydration preserves saved style"
)
assertBlockColor(
    oldProfile.unitFrames.player.indicators.buffs.blockColor,
    "profile hydration block color"
)
assertTrue(
    oldProfile.unitFrames.player.indicators.buffs.blockColor
        ~= secondDefaults.player.indicators.buffs.blockColor,
    "profile hydration color table isolation"
)

local savedSpellColor = {0.9, 0.8, 0.7, 0.6}
environment.BFIConfig = {
    revision = BFI.versionNum,
    auras = {
        colors = {
            [12345] = savedSpellColor,
        },
    },
}
F.ReviseCommon()
assertEqual(
    environment.BFIConfig.auras.colors[12345],
    savedSpellColor,
    "disabled global spell-color data preserved"
)

print("unit_frame_aura_block_color_defaults_test.lua: ok")
