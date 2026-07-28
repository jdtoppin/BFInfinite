---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

local defaults = {
    enabled = false,
    accentHeader = true,
    barTexture = "AF",
    barBackgroundAlpha = 0.65,
}

local function NormalizeConfig(config)
    if type(config.enabled) ~= "boolean" then
        config.enabled = defaults.enabled
    end
    if type(config.accentHeader) ~= "boolean" then
        config.accentHeader = defaults.accentHeader
    end
    if type(config.barTexture) ~= "string" or config.barTexture == "" then
        config.barTexture = defaults.barTexture
    end

    local alpha = tonumber(config.barBackgroundAlpha)
    if alpha then
        config.barBackgroundAlpha = math.max(0, math.min(1, alpha))
    else
        config.barBackgroundAlpha = defaults.barBackgroundAlpha
    end
end

AF.RegisterCallback("BFI_UpdateProfile", function(_, profile)
    if type(profile.damageMeter) ~= "table" then
        profile.damageMeter = AF.Copy(defaults)
    else
        for key, value in next, defaults do
            if profile.damageMeter[key] == nil then
                profile.damageMeter[key] = value
            end
        end
    end

    NormalizeConfig(profile.damageMeter)
    DM.config = profile.damageMeter
end)

function DM.GetDefaults()
    return AF.Copy(defaults)
end

function DM.ResetToDefaults()
    wipe(DM.config)
    AF.Merge(DM.config, defaults)
end
