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
    assistedHighlight = true,
    cooldownText = {
        font = {"BFI", 14, "outline", false},
        color = AF.GetColorTable("white"),
        position = {"CENTER", "CENTER", 0, 0},
    },
    countText = {
        font = {"BFI", 12, "outline", false},
        color = AF.GetColorTable("white"),
    },
    hotkeyText = {
        font = {"BFI", 10, "outline", false},
        color = AF.GetColorTable("white"),
    },
    barText = {
        font = {"BFI", 12, "outline", false},
        color = AF.GetColorTable("white"),
    },
    durationText = {
        font = {"BFI", 12, "outline", false},
        color = AF.GetColorTable("white"),
        position = {"RIGHT", "RIGHT", -8, 0},
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
            showHotkeys = true,
            hotkeyPosition = {"TOPRIGHT", "TOPRIGHT", 0, 0},
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
            showHotkeys = true,
            hotkeyPosition = {"TOPRIGHT", "TOPRIGHT", 0, 0},
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
            showHotkeys = true,
            hotkeyPosition = {"TOPRIGHT", "TOPRIGHT", 0, 0},
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
            showHotkeys = true,
            hotkeyPosition = {"TOPRIGHT", "TOPRIGHT", 0, 0},
            barContent = "icon_and_name",
            barWidthScale = 1,
        },
    },
}

AF.RegisterCallback("BFI_UpdateProfile", function(_, profile)
    if not profile.cooldownManager then
        profile.cooldownManager = AF.Copy(defaults)
    else
        local config = profile.cooldownManager
        if config.assistedHighlight == nil then
            config.assistedHighlight = defaults.assistedHighlight
        end
        if type(config.cooldownText) ~= "table" then
            config.cooldownText = AF.Copy(defaults.cooldownText)
        elseif type(config.cooldownText.position) ~= "table" then
            config.cooldownText.position = AF.Copy(defaults.cooldownText.position)
        end
        if type(config.hotkeyText) ~= "table" then
            config.hotkeyText = AF.Copy(defaults.hotkeyText)
        end
        if type(config.durationText) ~= "table" then
            config.durationText = AF.Copy(defaults.durationText)
        elseif type(config.durationText.position) ~= "table" then
            config.durationText.position = AF.Copy(defaults.durationText.position)
        end
        if type(config.viewers) == "table" then
            for key, viewerDefaults in next, defaults.viewers do
                local viewerConfig = config.viewers[key]
                if type(viewerConfig) == "table" then
                    if viewerConfig.showHotkeys == nil then
                        viewerConfig.showHotkeys = viewerDefaults.showHotkeys
                    end
                    if type(viewerConfig.hotkeyPosition) ~= "table" then
                        viewerConfig.hotkeyPosition = AF.Copy(viewerDefaults.hotkeyPosition)
                    end
                end
            end
        end
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
