---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
local NP = BFI.modules.Nameplates

local function HealthBar_Update(self)
    self:UpdateAll()
    self.threatIndicator:Refresh()
end

local function HealthBar_Enable(self)
    self:SetUnit(self.root.unit)
    self.threatIndicator:SetNativeUnitFrame(self.root.unitFrame)
    self:Show()
end

local function HealthBar_Disable(self)
    self.threatIndicator:Clear()
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

    local threatGlow = config.threatGlow or {}
    self.threatIndicator:Configure({
        -- Threat is meaningful only for hostile NPC plates. Player plates
        -- retain their configured reaction/class presentation.
        enabled = self.root.configKey == "hostile_npc"
            and threatGlow.enabled,
        border = threatGlow.border,
        glow = threatGlow.glow,
        bar = threatGlow.bar,
        style = threatGlow.style,
        thickness = threatGlow.borderSize,
        glowThickness = threatGlow.size,
        glowOutset = threatGlow.outset,
        alpha = threatGlow.alpha,
        borderAlpha = threatGlow.borderAlpha,
        glowAlpha = threatGlow.glowAlpha,
        barAlpha = threatGlow.barAlpha,
        name = threatGlow.name,
        nameAlpha = threatGlow.nameAlpha,
        combatOnly = threatGlow.combatOnly,
        instancesOnly = threatGlow.instancesOnly,
        tankOnly = threatGlow.tankOnly,
        useCustomColor = threatGlow.useCustomColor,
        color = threatGlow.useCustomColor
            and threatGlow.color
            or nil,
    })

    local semanticColor = config.semanticColor
    if self.root.configKey == "hostile_npc"
        and semanticColor
    then
        self:SetupFillColor({
            type = "nameplate_semantic",
            alpha = config.colorAlpha or 1,
            boss = semanticColor.boss,
            lieutenant = semanticColor.lieutenant,
            caster = semanticColor.caster,
            default = semanticColor.default,
        })
    else
        -- Players and friendly NPCs retain Blizzard's selection color.
        self:SetupFillColor({
            type = "selection_color",
            alpha = config.colorAlpha or 1,
        })
    end

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

    bar.threatIndicator =
        AF.CreateSecretNamePlateThreatIndicator(
            bar,
            name .. "ThreatIndicator"
        )

    bar.Update = HealthBar_Update
    bar.Enable = HealthBar_Enable
    bar.Disable = HealthBar_Disable
    bar.LoadConfig = HealthBar_LoadConfig

    return bar
end
