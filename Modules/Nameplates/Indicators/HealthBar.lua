---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
local NP = BFI.modules.Nameplates

local function HealthBar_Update(self)
    self:UpdateAll()
end

local function HealthBar_Enable(self)
    self:SetUnit(self.root.unit)
    self:Show()
end

local function HealthBar_Disable(self)
    self:ClearUnit()
    self:Hide()
end

local function HealthBar_LoadConfig(self, config)
    AF.SetFrameLevel(self, config.frameLevel, self.root)
    NP.LoadIndicatorPosition(
        self,
        config.position,
        config.anchorTo
    )
    AF.SetSize(self, config.width, config.height)

    self:LSM_SetTexture(config.texture)
    self:SetBackgroundColor(AF.UnpackColor(config.bgColor))
    self:SetBorderColor(AF.UnpackColor(config.borderColor))

    self:SetupFillColor({
        type = "selection_color",
        alpha = config.colorAlpha or 1,
    })

    if config.lossColor.useDarkerForground then
        self:SetupUnfillColor({
            type = "selection_dark",
            alpha = config.lossColor.alpha,
        })
    else
        self:SetupUnfillColor({
            type = "custom_color",
            gradient = "disabled",
            rgb = config.lossColor.rgb,
            alpha = config.lossColor.alpha,
        })
    end

    self:EnableMouseoverHighlight(
        config.mouseoverHighlight.enabled
    )
    self:SetMouseoverHighlightColor(
        AF.UnpackColor(config.mouseoverHighlight.color)
    )

    self:EnableHealPrediction(false)
    self:EnableHealAbsorb(false)
    self:EnableDispelHighlight(false)

    self:EnableDamageAbsorb(config.shield.enabled)
    self:SetDamageAbsorbColor(
        AF.UnpackColor(config.shield.color)
    )
    self:SetupDamageAbsorb_NormalStyle(
        config.shield.reverseFill,
        false
    )
end

function NP.CreateHealthBar(parent, name)
    local bar = AF.CreateSecretHealthBar(parent, name)
    bar.root = parent
    bar:Hide()

    bar.Update = HealthBar_Update
    bar.Enable = HealthBar_Enable
    bar.Disable = HealthBar_Disable
    bar.LoadConfig = HealthBar_LoadConfig

    return bar
end
