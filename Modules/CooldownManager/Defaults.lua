---@type BFI
local BFI = select(2, ...)
---@class CooldownManager
local CM = BFI.modules.CooldownManager
---@type AbstractFramework
local AF = _G.AbstractFramework

local function CreateTextStyle(size, position)
    local style = {
        font = {"BFI", size, "outline", false},
        color = AF.GetColorTable("white"),
    }
    if position then
        style.position = position
    end
    return style
end

local defaults = {
    enabled = false,
    positionVersion = 1,
    skin = true,
    assistedHighlight = true,
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
            cooldownText = CreateTextStyle(
                20,
                {"CENTER", "CENTER", 0, 0}
            ),
            countText = CreateTextStyle(13),
            hotkeyText = CreateTextStyle(13),
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
            cooldownText = CreateTextStyle(
                12,
                {"CENTER", "CENTER", 0, 0}
            ),
            countText = CreateTextStyle(10),
            hotkeyText = CreateTextStyle(10),
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
            cooldownText = CreateTextStyle(
                16,
                {"CENTER", "CENTER", 0, 0}
            ),
            countText = CreateTextStyle(13),
            hotkeyText = CreateTextStyle(13),
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
            countText = CreateTextStyle(13),
            hotkeyText = CreateTextStyle(13),
            barText = CreateTextStyle(14),
            durationText = CreateTextStyle(
                14,
                {"RIGHT", "RIGHT", -8, 0}
            ),
        },
    },
}

local viewerStyleKeys = {
    essential = {
        cooldownText = true,
        countText = true,
        hotkeyText = true,
    },
    utility = {
        cooldownText = true,
        countText = true,
        hotkeyText = true,
    },
    buffIcon = {
        cooldownText = true,
        countText = true,
        hotkeyText = true,
    },
    buffBar = {
        countText = true,
        hotkeyText = true,
        barText = true,
        durationText = true,
    },
}

local function CopyConfigValue(value)
    if type(value) == "table" then
        return AF.Copy(value)
    end
    return value
end

local fontValueTypes = {"string", "number", "string", "boolean"}
local colorValueTypes = {"number", "number", "number", "number"}
local positionValueTypes = {"string", "string", "number", "number"}
local anchorPoints = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local function FillArray(config, fallback, valueTypes)
    if type(config) ~= "table" then
        return AF.Copy(fallback)
    end
    for index = 1, #fallback do
        if type(config[index]) ~= valueTypes[index] then
            config[index] = fallback[index]
        end
    end
    return config
end

local function RepairAnchorPosition(position, fallback)
    position = FillArray(position, fallback, positionValueTypes)
    if not anchorPoints[position[1]] then
        position[1] = fallback[1]
    end
    if not anchorPoints[position[2]] then
        position[2] = fallback[2]
    end
    return position
end

local function RepairTextStyle(style, fallback)
    if type(style) ~= "table" then
        return AF.Copy(fallback)
    end
    style.font = FillArray(style.font, fallback.font, fontValueTypes)
    style.color = FillArray(style.color, fallback.color, colorValueTypes)
    if style.font[2] <= 0 then
        style.font[2] = fallback.font[2]
    end
    if fallback.position then
        style.position = RepairAnchorPosition(
            style.position,
            fallback.position
        )
    end
    return style
end

AF.RegisterCallback("BFI_UpdateProfile", function(_, profile)
    if type(profile.cooldownManager) ~= "table" then
        profile.cooldownManager = AF.Copy(defaults)
    else
        local config = profile.cooldownManager
        if config.assistedHighlight == nil then
            config.assistedHighlight = defaults.assistedHighlight
        end
        if type(config.viewers) ~= "table" then
            config.viewers = {}
        end
        for viewerKey, viewerDefaults in next, defaults.viewers do
            local viewerConfig = config.viewers[viewerKey]
            if type(viewerConfig) ~= "table" then
                viewerConfig = {}
                config.viewers[viewerKey] = viewerConfig
            end
            local styleKeys = viewerStyleKeys[viewerKey]
            for configKey, defaultValue in next, viewerDefaults do
                if viewerConfig[configKey] == nil then
                    local legacyStyle = styleKeys[configKey]
                        and config[configKey]
                    if type(legacyStyle) == "table" then
                        viewerConfig[configKey] = AF.Copy(legacyStyle)
                    else
                        viewerConfig[configKey] = CopyConfigValue(defaultValue)
                    end
                end
                if styleKeys[configKey] then
                    viewerConfig[configKey] = RepairTextStyle(
                        viewerConfig[configKey],
                        defaultValue
                    )
                elseif configKey == "hotkeyPosition" then
                    viewerConfig[configKey] = RepairAnchorPosition(
                        viewerConfig[configKey],
                        defaultValue
                    )
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
