---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
---@class Nameplates
local NP = BFI.modules.Nameplates

local function SetBorderColor(self, r, g, b, a)
    self:SetBackdropBorderColor(r, g, b, a)
    self.iconBG:SetVertexColor(r, g, b, a)
end

local function SetDefaultBorderColor(self)
    SetBorderColor(
        self,
        AF.UnpackColor(
            self.borderColor or AF.GetColorTable("border")
        )
    )
end

local function CastBar_OnCastStart(self)
    self.status:Hide()
    self.bar:Show()
    SetDefaultBorderColor(self)
end

local function CastBar_OnCastStop(self)
    self.bar:Hide()
    self.status:Hide()
    SetDefaultBorderColor(self)
end

local function CastBar_Update(self)
    self:UpdateCurrentCast()
end

local function CastBar_Enable(self)
    self:SetUnit(self.root.unit)
end

local function CastBar_Disable(self)
    self:ClearUnit()
end

local function CastBar_SetTexture(self, texture)
    texture = AF.LSM_GetBarTexture(texture)
    self.texture = texture
    self.bar:SetStatusBarTexture(texture)
    self.status:SetTexture(texture)
end

local function CastBar_SetupNameText(self, config)
    self.nameText:SetShown(config.enabled)
    AF.SetFont(self.nameText, config.font)
    AF.LoadTextPosition(self.nameText, config.position)
    self.nameText:SetTextColor(AF.UnpackColor(config.color))

    -- Secret cast names are forwarded directly to FontString:SetText by the
    -- shared widget. Lua truncation and interrupt-source replacement are not
    -- performed.
    self.showName = config.enabled
end

local function CastBar_SetupDurationText(self, config)
    self.durationText:SetShown(config.enabled)
    AF.SetFont(self.durationText, config.font)
    AF.LoadTextPosition(self.durationText, config.position)
    self.durationText:SetTextColor(AF.UnpackColor(config.color))
    self.showDuration = config.enabled
end

local function CastBar_SetupSpellTargetText(self, config)
    config = config or {}

    local enabled = config.enabled == true
    local font = config.font or {"BFI", 10, "outline", true}
    local position = config.position or {"TOP", "BOTTOM", 0, -1}
    local color = config.color or AF.GetColorTable("white")

    self.spellTargetTextRegion:SetShown(enabled)
    AF.SetFont(
        self.spellTargetTextRegion,
        font,
        config.fontSize,
        config.outline
    )
    AF.LoadTextPosition(self.spellTargetTextRegion, position)
    self.spellTargetTextRegion:SetTextColor(AF.UnpackColor(color))

    if enabled then
        self:SetSpellTargetText(self.spellTargetTextRegion)
    else
        self:SetSpellTargetText(nil)
    end
end

local function CastBar_SetupImportantGlow(self, config)
    config = config or {}

    local enabled = config.enabled == true
    local color = config.color or AF.GetColorTable("gold")
    self.importantGlowEnabled = enabled
    self.importantGlow:SetBackdropBorderColor(AF.UnpackColor(color))
    self.importantGlow:SetShown(enabled)
end

local function CastBar_SetupImportantIcon(self, config)
    config = config or {}

    local enabled = config.enabled == true
    self.importantIconEnabled = enabled
    self.importantIcon:SetShown(enabled)
    local size = config.size or 16
    AF.SetSize(self.importantIcon, size, size)
    AF.LoadWidgetPosition(
        self.importantIcon,
        config.position or {"LEFT", "RIGHT", 2, 0},
        self
    )
end

local function CastBar_UpdateImportantCastRegion(self)
    local enabled =
        self.importantGlowEnabled or self.importantIconEnabled
    -- AF applies Blizzard's possibly secret Important Cast result to this
    -- carrier. Its children use only ordinary profile visibility, allowing
    -- the glow and icon to coexist without inspecting the cast state in Lua.
    self:SetImportantCastRegion(
        enabled and self.importantCastCarrier or nil
    )
end

local function CastBar_SetupPlayerTargetHighlight(self, config)
    config = config or {}

    local enabled = config.enabled == true
    local color = config.color or AF.GetColorTable("white", 0.2)
    self.playerTargetOverlay:SetVertexColor(AF.UnpackColor(color))
    self.playerTargetOverlay:SetShown(enabled)

    if enabled then
        self:SetPlayerTargetRegion(self.playerTargetOverlay)
    else
        self:SetPlayerTargetRegion(nil)
    end
end

local function CastBar_SetupInterruptibility(self, config)
    local interruptibleCheck = config.interruptibleCheck or {}
    local normalColor = config.color or AF.GetColorTable("cast_normal")
    local interruptibleColor = config.interruptibleColor
        or AF.GetColorTable("cast_interruptible")
    local uninterruptibleColor = config.uninterruptibleColor
        or AF.GetColorTable("cast_uninterruptible")

    self.borderColor = config.borderColor or AF.GetColorTable("border")
    self.interruptibleCheckEnabled = interruptibleCheck.enabled ~= false

    if self.interruptibleCheckEnabled then
        self:SetInterruptibilityColors(
            normalColor,
            interruptibleColor,
            uninterruptibleColor
        )
    else
        self:SetInterruptibilityColors(
            normalColor,
            normalColor,
            normalColor
        )
    end

    SetDefaultBorderColor(self)
end

local function CastBar_SetupUninterruptibleIcon(self, config)
    config = config or {}

    local enabled = config.enabled == true
    self.uninterruptibleIcon:SetShown(enabled)
    local size = config.size or 14
    AF.SetSize(self.uninterruptibleIcon, size, size)
    AF.LoadWidgetPosition(
        self.uninterruptibleIcon,
        config.position or {"CENTER", "CENTER", 0, 0},
        self.iconBG
    )
    -- Keep the X on AF's native boolean sink; never branch on the restricted
    -- notInterruptible result in BFI.
    self:SetUninterruptibleCastRegion(
        enabled and self.uninterruptibleCastCarrier or nil
    )
end

local function CastBar_SetupIcon(self, config)
    -- Keep the spell-icon geometry current even while its texture is hidden;
    -- the independently configurable uninterruptible X anchors to it.
    NP.LoadIndicatorPosition(self.iconBG, config.position)
    AF.SetSize(self.iconBG, config.width, config.height)

    if not config.enabled then
        self.icon:Hide()
        self.iconBG:Hide()
        return
    end

    self.icon:SetTexCoord(AF.Unpack8(AF.CalcTexCoordPreCrop(0.12, config.width / config.height)))
    self.iconBG:SetVertexColor(AF.UnpackColor(self.borderColor))

    self.icon:Show()
    self.iconBG:Show()
end

local function CastBar_SetupSpark(self, config)
    self.spark:SetShown(config.enabled)
    if not config.enabled then return end

    self.spark:ClearAllPoints()
    local fill = self.bar:GetStatusBarTexture()
    if config.height == 0 then
        if config.width == 1 then
            self.spark:SetPoint("TOPRIGHT", fill)
            self.spark:SetPoint("BOTTOMRIGHT", fill)
        else
            self.spark:SetPoint("TOP", fill, "TOPRIGHT")
            self.spark:SetPoint("BOTTOM", fill, "BOTTOMRIGHT")
        end
    else
        self.spark:SetPoint("CENTER", fill, "RIGHT")
        AF.SetHeight(self.spark, config.height)
    end

    AF.SetWidth(self.spark, config.width)
    if config.texture == "plain" then
        self.spark:SetTexture(AF.GetPlainTexture())
    else
        self.spark:SetTexture(AF.LSM_GetBarTexture(config.texture))
    end
    self.spark:SetVertexColor(AF.GetColorRGB("cast_spark"))
end

local function CastBar_UpdatePixels(self)
    AF.DefaultUpdatePixels(self)
    AF.ReSize(self.spark)
    AF.RePoint(self.bar)
    AF.RePoint(self.status)
    AF.RePoint(self.icon)
    AF.RePoint(self.iconBG)
    AF.RePoint(self.nameText)
    AF.RePoint(self.durationText)
    AF.RePoint(self.spellTargetTextRegion)
    AF.RePoint(self.playerTargetOverlay)
    AF.RePoint(self.importantGlow)
    AF.ReSize(self.importantIcon)
    AF.RePoint(self.importantIcon)
    AF.ReSize(self.uninterruptibleIcon)
    AF.RePoint(self.uninterruptibleIcon)
end

local function CastBar_LoadConfig(self, config)
    self.config = config

    AF.SetFrameLevel(self, config.frameLevel, self.root)
    AF.SetFrameLevel(self.importantCastCarrier, 3, self)
    AF.SetFrameLevel(
        self.importantGlow,
        0,
        self.importantCastCarrier
    )
    AF.SetFrameLevel(self.uninterruptibleCastCarrier, 4, self)
    NP.LoadIndicatorPosition(self, config.position, config.anchorTo)
    AF.SetSize(self, config.width, config.height)

    CastBar_SetTexture(self, config.texture)

    self:SetBackdropColor(AF.UnpackColor(config.bgColor))
    self:SetBackdropBorderColor(AF.UnpackColor(config.borderColor))

    CastBar_SetupInterruptibility(self, config)
    CastBar_SetupNameText(self, config.nameText)
    CastBar_SetupDurationText(self, config.durationText)
    CastBar_SetupSpellTargetText(self, config.spellTargetText)
    CastBar_SetupIcon(self, config.icon)
    CastBar_SetupSpark(self, config.spark)
    CastBar_SetupImportantGlow(self, config.importantGlow)
    CastBar_SetupImportantIcon(self, config.importantIcon)
    CastBar_UpdateImportantCastRegion(self)
    CastBar_SetupUninterruptibleIcon(
        self,
        config.uninterruptibleIcon
    )
    CastBar_SetupPlayerTargetHighlight(
        self,
        config.playerTargetHighlight
    )

    if self.unit then
        self:UpdateCurrentCast()
    end
end

AF.RegisterCallback("BFI_UpdateConfig", function(_, module, group)
    if module ~= "colors" then return end
    if not NP.config.enabled then return end
    if group and group ~= "casts" then return end

    for _, frame in next, NP.created do
        local castBar = NP.GetIndicator(frame, "castBar")
        if castBar then
            castBar.spark:SetVertexColor(AF.GetColorRGB("cast_spark"))
            CastBar_SetupImportantGlow(
                castBar,
                castBar.config and castBar.config.importantGlow
            )
            CastBar_UpdateImportantCastRegion(castBar)
            CastBar_SetupPlayerTargetHighlight(
                castBar,
                castBar.config
                    and castBar.config.playerTargetHighlight
            )
            CastBar_SetupInterruptibility(
                castBar,
                castBar.config or {}
            )
            if castBar.unit then
                castBar:UpdateCurrentCast()
            end
        end
    end
end)

function NP.CreateCastBar(parent, name)
    local frame = AF.CreateSecretCastBar(parent, name)
    AF.ApplyDefaultBackdrop(frame)
    frame.root = parent

    local status = frame:CreateTexture(nil, "OVERLAY")
    frame.status = status
    AF.SetOnePixelInside(status, frame)
    status:Hide()

    local iconBG = frame:CreateTexture(nil, "BORDER")
    frame.iconBG = iconBG
    iconBG:SetTexture(AF.GetPlainTexture())

    local icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon = icon
    AF.SetPoint(icon, "TOPLEFT", iconBG, 1, -1)
    AF.SetPoint(icon, "BOTTOMRIGHT", iconBG, -1, 1)

    local bar = CreateFrame("StatusBar", nil, frame)
    frame.bar = bar
    AF.SetOnePixelInside(bar, frame)
    AF.SetFrameLevel(bar, 1, frame)

    local spark = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    frame.spark = spark

    local overlay = CreateFrame("Frame", nil, frame)
    frame.overlay = overlay
    overlay:SetAllPoints()
    AF.SetFrameLevel(overlay, 2, frame)

    local playerTargetOverlay =
        overlay:CreateTexture(nil, "BACKGROUND")
    frame.playerTargetOverlay = playerTargetOverlay
    AF.SetOnePixelInside(playerTargetOverlay, overlay)
    playerTargetOverlay:SetTexture(
        AF.GetTexture("Square_Soft_Edge")
    )
    playerTargetOverlay:SetBlendMode("ADD")
    playerTargetOverlay:SetAlpha(0)

    local nameText = overlay:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
    frame.nameText = nameText

    local durationText = overlay:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
    frame.durationText = durationText

    local spellTargetTextRegion =
        overlay:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
    frame.spellTargetTextRegion = spellTargetTextRegion

    local importantCastCarrier =
        CreateFrame("Frame", nil, frame)
    frame.importantCastCarrier = importantCastCarrier
    importantCastCarrier:SetAllPoints()
    importantCastCarrier:EnableMouse(false)
    importantCastCarrier:SetAlpha(0)
    AF.SetFrameLevel(importantCastCarrier, 3, frame)

    local importantGlow =
        AF.CreateGlow(importantCastCarrier, "gold", 3)
    frame.importantGlow = importantGlow
    importantGlow:EnableMouse(false)
    importantGlow:SetBorderBlendMode("ADD")
    importantGlow:Hide()
    AF.SetFrameLevel(importantGlow, 0, importantCastCarrier)

    local importantIcon = importantCastCarrier:CreateTexture(
        nil,
        "OVERLAY",
        nil,
        1
    )
    frame.importantIcon = importantIcon
    importantIcon:SetTexture(AF.GetIcon("Fluent_Notice"))
    importantIcon:Hide()

    local uninterruptibleCastCarrier =
        CreateFrame("Frame", nil, frame)
    frame.uninterruptibleCastCarrier =
        uninterruptibleCastCarrier
    uninterruptibleCastCarrier:SetAllPoints()
    uninterruptibleCastCarrier:EnableMouse(false)
    uninterruptibleCastCarrier:SetAlpha(0)
    AF.SetFrameLevel(uninterruptibleCastCarrier, 4, frame)

    local uninterruptibleIcon =
        uninterruptibleCastCarrier:CreateTexture(
            nil,
            "OVERLAY"
        )
    frame.uninterruptibleIcon = uninterruptibleIcon
    uninterruptibleIcon:SetTexture(AF.GetIcon("Close"))
    uninterruptibleIcon:Hide()

    frame:SetStatusBar(bar)
    frame:SetNameText(nameText)
    frame:SetIcon(icon)
    frame:SetDurationText(durationText)

    frame.OnCastStart = CastBar_OnCastStart
    frame.OnCastStop = CastBar_OnCastStop
    frame.Update = CastBar_Update
    frame.Enable = CastBar_Enable
    frame.Disable = CastBar_Disable
    frame.LoadConfig = CastBar_LoadConfig

    AF.AddToPixelUpdater_Auto(frame, CastBar_UpdatePixels)

    return frame
end
