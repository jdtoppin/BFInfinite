---@type BFI
local BFI = select(2, ...)
---@class CooldownManager
local CM = BFI.modules.CooldownManager
---@type AbstractFramework
local AF = _G.AbstractFramework

local defaults = {
    enabled = false,
    positionVersion = 1,
    skin = true,
    cooldownText = {
        font = {"BFI", 14, "outline", false},
        color = AF.GetColorTable("white"),
    },
    countText = {
        font = {"BFI", 12, "outline", false},
        color = AF.GetColorTable("white"),
    },
    barText = {
        font = {"BFI", 12, "outline", false},
        color = AF.GetColorTable("white"),
    },
    viewers = {
        essential = {
            position = {"BOTTOM", 0, 310},
            center = true,
            orientation = "horizontal",
            direction = "right",
            iconLimit = 12,
            scale = 0.75,
            padding = 2,
            opacity = 1,
            visibility = "always",
            showTimer = true,
            showTooltips = true,
        },
        utility = {
            position = {"BOTTOM", 0, 240},
            center = true,
            orientation = "horizontal",
            direction = "right",
            iconLimit = 7,
            scale = 1,
            padding = 2,
            opacity = 1,
            visibility = "always",
            showTimer = true,
            showTooltips = true,
        },
        buffIcon = {
            position = {"BOTTOM", 0, 370},
            center = true,
            orientation = "horizontal",
            direction = "right",
            scale = 0.75,
            padding = 2,
            opacity = 1,
            visibility = "always",
            showTimer = true,
            showTooltips = true,
            hideWhenInactive = true,
        },
        buffBar = {
            position = {"BOTTOM", 420, 430},
            center = true,
            orientation = "vertical",
            direction = "left",
            scale = 0.8,
            padding = 2,
            opacity = 1,
            visibility = "always",
            showTimer = true,
            showTooltips = true,
            hideWhenInactive = true,
            barContent = "icon_and_name",
            barWidthScale = 1,
        },
    },
}

AF.RegisterCallback("BFI_UpdateProfile", function(_, profile)
    if not profile.cooldownManager then
        profile.cooldownManager = AF.Copy(defaults)
    end
    CM.config = profile.cooldownManager
end)

function CM.GetDefaults()
    return AF.Copy(defaults)
end

function CM.ResetToDefaults()
    wipe(CM.config)
    AF.Merge(CM.config, defaults)
end
