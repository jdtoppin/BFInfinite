---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class Funcs
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

local commonModuleClasses = {
    "Enhancements",
    "Colors",
    "Auras",
}

local function HydrateCommonConfig(config)
    for _, moduleClassName in next, commonModuleClasses do
        local defaults = F.GetModuleDefaults(moduleClassName)
        if defaults then
            local moduleKey = F.GetModuleKey(moduleClassName)
            config[moduleKey] = F.MergeMissingDefaults(config[moduleKey], defaults)
        end
    end
end

local function HydrateProfile(profile)
    for _, moduleClassName in next, F.GetProfileModuleClassNames() do
        F.FixModule(profile, F.GetModuleKey(moduleClassName))
    end
end

local retiredHealthTextNumericFormats = {
    current_absorbs_sum = "current",
    current_absorbs_short_sum = "current_short",
}

local retiredHealthTextPercentFormats = {
    current_absorbs = "current",
    current_absorbs_decimal = "current_decimal",
    current_absorbs_sum = "current",
    current_absorbs_sum_decimal = "current_decimal",
}

local function MigrateRetiredHealthTextFormats(profile)
    if type(profile.unitFrames) ~= "table" then return end

    for _, frameConfig in next, profile.unitFrames do
        local indicators = type(frameConfig) == "table" and frameConfig.indicators
        local healthText = type(indicators) == "table" and indicators.healthText
        local format = type(healthText) == "table" and healthText.format
        if type(format) == "table" then
            format.numeric = retiredHealthTextNumericFormats[format.numeric] or format.numeric
            format.percent = retiredHealthTextPercentFormats[format.percent] or format.percent
        end
    end
end

---------------------------------------------------------------------
-- common revisions
---------------------------------------------------------------------
local commonRevisions = {
    -- {
    --     ver = 2,
    --     fn = function(config)
    --         -- do something for version 2
    --     end,
    -- },
    {
        ver = 4,
        fn = function(config)
            config.enhancements = F.MergeMissingDefaults(config.enhancements, BFI.modules.Enhancements.GetDefaults())
        end,
    }
}

function F.ReviseCommon()
    local revision = tonumber(BFIConfig.revision) or 0

    if revision < BFI.versionNum then
        for _, revise in ipairs(commonRevisions) do
            if revision < revise.ver then
                revise.fn(BFIConfig)
            end
        end
    end

    if revision > 0 and revision ~= BFI.versionNum then
        AF.ShowNotificationPopup(
            L["BFI has been updated to version %s\nClick here to view the changelog"]:format(AF.WrapTextInColor(BFI.version, "BFI")),
            27,
            "!" .. AF.GetIcon("BFI_64", BFI.name),
            nil, nil, "LEFT",
            F.ToggleChangelogsFrame
        )
    end

    HydrateCommonConfig(BFIConfig)
    BFIConfig.revision = BFI.versionNum
end

---------------------------------------------------------------------
-- profile revisions
---------------------------------------------------------------------
local profileRevisions = {
    -- {
    --     ver = 2,
    --     fn = function(profile)
    --         -- do something for version 2
    --     end,
    -- },
    {
        ver = 3,
        fn = function(profile)
            profile.chat = F.MergeMissingDefaults(profile.chat, BFI.modules.Chat.GetDefaults())
        end,
    },
    {
        ver = 4,
        fn = function(profile)
            profile.maps = F.MergeMissingDefaults(profile.maps, BFI.modules.Maps.GetDefaults())
        end,
    }
}

function F.ReviseProfile(profile, force)
    local revision = tonumber(profile.revision) or 0

    if revision < BFI.versionNum or force then
        for _, revise in ipairs(profileRevisions) do
            if revision < revise.ver then
                revise.fn(profile)
            end
        end
    end

    HydrateProfile(profile)
    MigrateRetiredHealthTextFormats(profile)
    profile.revision = BFI.versionNum
end
