local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function mergeTable(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            mergeTable(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

local function copyTables(...)
    local copy = {}
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        if source then
            mergeTable(copy, source)
        end
    end
    return copy
end

local function loadPresets()
    local callbacks = {}
    local unitFrames = {}
    local translations = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
    local BFI = {
        L = translations,
        modules = {
            UnitFrames = unitFrames,
        },
    }
    local AF = {
        Copy = copyTables,
        GetColorTable = function(name, alpha)
            return {name = name, alpha = alpha}
        end,
        Merge = mergeTable,
        RegisterCallback = function(name, callback)
            callbacks[name] = callback
        end,
    }
    local environment = setmetatable({
        AbstractFramework = AF,
    }, {__index = _G})
    environment._G = environment

    local chunk, loadError = loadfile("Modules/UnitFrames/Presets.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return unitFrames, callbacks
end

local portraitFrameNames = {
    "party",
    "boss",
    "player",
    "target",
    "targettarget",
    "focus",
    "focustarget",
    "pet",
    "pettarget",
}

local function assertPortraitDefaults(config, message)
    local portraitCount = 0
    for frameName, frameConfig in pairs(config) do
        local indicators = type(frameConfig) == "table"
            and frameConfig.indicators
        local portrait = type(indicators) == "table"
            and indicators.portrait
        if portrait then
            portraitCount = portraitCount + 1
            assertEqual(
                portrait.style,
                "2d",
                message .. " " .. frameName .. " portrait style"
            )
        end
    end

    assertEqual(
        portraitCount,
        #portraitFrameNames,
        message .. " portrait-bearing frame count"
    )
    for _, frameName in ipairs(portraitFrameNames) do
        assertEqual(
            type(config[frameName].indicators.portrait),
            "table",
            message .. " " .. frameName .. " portrait config"
        )
    end
end

local UF, callbacks = loadPresets()
local updateProfile = callbacks.BFI_UpdateProfile
assertEqual(type(updateProfile), "function", "profile callback registration")

assertPortraitDefaults(UF.GetDefaults(), "default profile")

local presets = UF.GetPresets()
assertEqual(#presets, 2, "built-in preset count")
for _, preset in ipairs(presets) do
    assertPortraitDefaults(preset.get(), preset.id)
end

local newProfile = {}
updateProfile(nil, newProfile)
assertPortraitDefaults(newProfile.unitFrames, "new profile callback")
assertEqual(UF.config, newProfile.unitFrames, "new profile config identity")

local existingConfig = UF.GetDefaults()
existingConfig.player.indicators.portrait.style = "3d"
existingConfig.target.indicators.portrait.style = "class_icon"
local existingProfile = {
    unitFrames = existingConfig,
}
updateProfile(nil, existingProfile)
assertEqual(
    existingProfile.unitFrames,
    existingConfig,
    "existing profile config identity"
)
assertEqual(
    existingConfig.player.indicators.portrait.style,
    "3d",
    "explicit existing 3D portrait choice"
)
assertEqual(
    existingConfig.target.indicators.portrait.style,
    "class_icon",
    "explicit existing class-icon portrait choice"
)
assertEqual(UF.config, existingConfig, "existing profile runtime config identity")

assertPortraitDefaults(UF.GetDefaults(), "fresh defaults after existing profile")

print("unit frame portrait defaults tests passed")
