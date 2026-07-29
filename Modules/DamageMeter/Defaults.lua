---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

local defaults = {
    enabled = false,
    windowCount = 3,
    windowTypes = {
        "DamageDone",
        "HealingDone",
        "DamageTaken",
    },
    width = 300,
    height = 220,
    headerHeight = 22,
    barHeight = 20,
    spacing = 2,
    padding = 4,
    texture = "AF",
    numberMode = "both",
    showSpecIcon = true,
    classColor = true,
    backgroundAlpha = 0.82,
    barAlpha = 0.9,
    accentHeader = true,
}

local validWindowTypes = {
    DamageDone = true,
    HealingDone = true,
    DamageTaken = true,
}

local validNumberModes = {
    total = true,
    perSecond = true,
    both = true,
}

local function CopyWindowTypes(source)
    local copy = {}
    for index = 1, 3 do
        copy[index] = source[index]
    end
    return copy
end

local function CopyDefaults()
    local copy = AF.Copy(defaults)
    copy.windowTypes = CopyWindowTypes(defaults.windowTypes)
    return copy
end

local function NormalizeNumber(value, default, minimum, maximum, integer)
    if type(value) ~= "number" then
        return default
    end

    value = math.max(minimum, math.min(maximum, value))
    if integer then
        value = math.floor(value + 0.5)
    end
    return value
end

local function NormalizeConfig(config)
    -- Legacy development builds stored transient CVar state in the profile.
    -- It must never survive profile copy, import, or export.
    config.nativeEnabledBeforeBFI = nil
    if type(config.enabled) ~= "boolean" then
        config.enabled = defaults.enabled
    end
    config.windowCount = NormalizeNumber(
        config.windowCount,
        defaults.windowCount,
        1,
        3,
        true
    )
    if type(config.windowTypes) ~= "table" then
        config.windowTypes = CopyWindowTypes(defaults.windowTypes)
    end
    for index = 1, 3 do
        if not validWindowTypes[config.windowTypes[index]] then
            config.windowTypes[index] = defaults.windowTypes[index]
        end
    end
    config.width = NormalizeNumber(
        config.width,
        defaults.width,
        220,
        520,
        true
    )
    config.height = NormalizeNumber(
        config.height,
        defaults.height,
        120,
        520,
        true
    )
    config.headerHeight = NormalizeNumber(
        config.headerHeight,
        defaults.headerHeight,
        18,
        36,
        true
    )
    config.barHeight = NormalizeNumber(
        config.barHeight,
        defaults.barHeight,
        14,
        36,
        true
    )
    config.spacing = NormalizeNumber(
        config.spacing,
        defaults.spacing,
        0,
        8,
        true
    )
    config.padding = NormalizeNumber(
        config.padding,
        defaults.padding,
        0,
        12,
        true
    )
    if type(config.texture) ~= "string" or config.texture == "" then
        config.texture = defaults.texture
    end
    if not validNumberModes[config.numberMode] then
        config.numberMode = defaults.numberMode
    end
    if type(config.showSpecIcon) ~= "boolean" then
        config.showSpecIcon = defaults.showSpecIcon
    end
    if type(config.classColor) ~= "boolean" then
        config.classColor = defaults.classColor
    end
    config.backgroundAlpha = NormalizeNumber(
        config.backgroundAlpha,
        defaults.backgroundAlpha,
        0,
        1
    )
    config.barAlpha = NormalizeNumber(
        config.barAlpha,
        defaults.barAlpha,
        0,
        1
    )
    if type(config.accentHeader) ~= "boolean" then
        config.accentHeader = defaults.accentHeader
    end
end

AF.RegisterCallback("BFI_UpdateProfile", function(_, profile)
    if type(profile.damageMeter) ~= "table" then
        profile.damageMeter = CopyDefaults()
    else
        for key, value in next, defaults do
            if profile.damageMeter[key] == nil then
                if type(value) == "table" then
                    profile.damageMeter[key] = CopyWindowTypes(value)
                else
                    profile.damageMeter[key] = value
                end
            end
        end
    end

    NormalizeConfig(profile.damageMeter)
    DM.config = profile.damageMeter
end)

function DM.GetDefaults()
    return CopyDefaults()
end

function DM.ResetToDefaults()
    wipe(DM.config)
    AF.Merge(DM.config, CopyDefaults())
    DM.config.windowTypes = CopyWindowTypes(defaults.windowTypes)
end
