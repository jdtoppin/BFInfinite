---@type BFI
local BFI = select(2, ...)
---@class Bags
local B = BFI.modules.Bags
---@type AbstractFramework
local AF = _G.AbstractFramework

local defaults = {
    enabled = true,
    position = {"BOTTOMRIGHT", -35, 110},
    categories = false,
    showBagSlots = true,
    columns = 12,
    spacing = 4,
}

local function NormalizeConfig(config)
    if type(config.enabled) ~= "boolean" then config.enabled = defaults.enabled end
    if type(config.categories) ~= "boolean" then config.categories = defaults.categories end
    if type(config.showBagSlots) ~= "boolean" then config.showBagSlots = defaults.showBagSlots end

    local columns = tonumber(config.columns)
    config.columns = columns and math.max(10, math.min(16, math.floor(columns + 0.5))) or defaults.columns

    local spacing = tonumber(config.spacing)
    config.spacing = spacing and math.max(1, math.min(8, math.floor(spacing + 0.5))) or defaults.spacing

    local position = config.position
    if type(position) ~= "table"
        or type(position[1]) ~= "string"
        or type(position[2]) ~= "number"
        or type(position[3]) ~= "number" then
        config.position = AF.Copy(defaults.position)
    end
end

AF.RegisterCallback("BFI_UpdateProfile", function(_, profile)
    if type(profile.bags) ~= "table" then
        profile.bags = AF.Copy(defaults)
    end
    NormalizeConfig(profile.bags)
    B.config = profile.bags
end)

function B.GetDefaults()
    return AF.Copy(defaults)
end

function B.ResetToDefaults()
    wipe(B.config)
    AF.Merge(B.config, defaults)
end
