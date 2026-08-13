---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
local NP = BFI.modules.Nameplates

local INSIDE_POSITION = {"CENTER", "CENTER", 0, 0}
local INSIDE_LENGTH = 0.9

local function ApplyConfiguredFont(region, font, enabled, config)
    if enabled and config and config.enabled then
        local shadow = config.shadow
        if shadow == nil then
            shadow = font[4]
        end

        AF.SetFont(
            region,
            font[1],
            math.max(1, font[2] + (config.sizeDelta or 0)),
            config.outline or font[3],
            shadow
        )
    else
        AF.SetFont(
            region,
            font[1],
            font[2],
            font[3],
            font[4]
        )
    end
end

local function NameText_Update(self)
    self:UpdateName()
    self.threatOverlay:UpdateName()
    self.threatIndicator:Refresh()
end

local function NameText_Enable(self)
    self:SetUnit(self.root.unit)
    self.threatOverlay:SetUnit(self.root.unit)
    self.threatOverlay:Show()
    self.threatIndicator:Refresh()
    self:Show()
end

local function NameText_Disable(self)
    self:SetTargetEmphasis(false)
    self.threatOverlay:ClearUnit()
    self.threatOverlay:Hide()
    self:ClearUnit()
    self:Hide()
end

local function NameText_SetTargetEmphasis(self, enabled, config)
    local font = self.configuredFont
    if not font then return end

    ApplyConfiguredFont(self, font, enabled, config)
    ApplyConfiguredFont(
        self.threatOverlay,
        font,
        enabled,
        config
    )
end

local function NameText_LoadConfig(self, config)
    self.configuredFont = {
        config.font[1],
        config.font[2],
        config.font[3],
        config.font[4],
    }
    self:SetTargetEmphasis(false)

    local position = config.position
    local anchorTo = config.anchorTo
    local parent = config.parent
    local length = config.length

    if config.placement == "inside" then
        position = INSIDE_POSITION
        anchorTo = "healthBar"
        length = INSIDE_LENGTH

        -- A friendly name-only plate keeps the text visible even though its
        -- health bar is disabled. When a bar is active, parent to it so the
        -- centered text draws above the status-bar texture.
        parent = NP.GetIndicator(self.root, "healthBar", true)
            and "healthBar"
            or "root"
    end

    NP.LoadIndicatorPosition(
        self,
        position,
        anchorTo,
        parent
    )
    self:SetLength(length)
    NP.LoadIndicatorPosition(
        self.threatOverlay,
        position,
        anchorTo,
        parent
    )
    self.threatOverlay:SetLength(length)
    ApplyConfiguredFont(
        self.threatOverlay,
        self.configuredFont,
        false
    )

    if config.color.type == "custom_color" then
        self.color = {
            type = "custom_color",
            rgb = config.color.rgb,
        }
    elseif config.color.type == "class_color" then
        self.color = {type = "class_color"}
    else
        self.color = {type = "selection_color"}
    end
end

function NP.CreateNameText(parent, name)
    local text = AF.CreateSecretNameText(parent, name)
    text.root = parent
    text:Hide()

    -- A dedicated duplicate keeps the configured name presentation intact
    -- underneath it. Its secret unit name remains inside AF's native text
    -- sink, while the threat carrier controls only color and visibility.
    local threatOverlay = AF.CreateSecretNameText(
        parent,
        name .. "ThreatOverlay"
    )
    threatOverlay.root = parent
    threatOverlay.indicatorName = "nameText"
    threatOverlay.UpdateColor = AF.noop
    threatOverlay:Hide()
    text.threatOverlay = threatOverlay

    local healthBar = parent.indicators.healthBar
    text.threatIndicator = healthBar.threatIndicator
    text.threatIndicator:SetNameOverlay(threatOverlay)

    text.Update = NameText_Update
    text.Enable = NameText_Enable
    text.Disable = NameText_Disable
    text.SetTargetEmphasis = NameText_SetTargetEmphasis
    text.LoadConfig = NameText_LoadConfig

    return text
end
