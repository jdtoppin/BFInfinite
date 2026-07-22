---@type BFI
local BFI = select(2, ...)
---@class UnitFrames
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local function SetNormalStyle(self)
    self.bar:SetStatusBarColor(AF.GetColorRGB("cast_normal"))
    self.uninterruptible:Hide()
    self:SetBackdropBorderColor(AF.UnpackColor(self.borderColor))
    self.gap:SetColorTexture(AF.UnpackColor(self.borderColor))
end

local function SetInterruptibleStyle(self)
    local r, g, b, a = AF.GetColorRGB("cast_interruptible")
    self.bar:SetStatusBarColor(r, g, b, a)
    self.uninterruptible:Hide()

    if self.interruptibleColorBorder then
        self:SetBackdropBorderColor(r, g, b, a)
        self.gap:SetColorTexture(r, g, b, a)
    else
        self:SetBackdropBorderColor(AF.UnpackColor(self.borderColor))
        self.gap:SetColorTexture(AF.UnpackColor(self.borderColor))
    end
end

local function SetUninterruptibleStyle(self)
    local r, g, b, a = AF.GetColorRGB("cast_uninterruptible")
    self.bar:SetStatusBarColor(r, g, b, a)

    if self.showUninterruptibleTexture then
        self.uninterruptible:Show()
        if self.interruptibleColorBorder then
            r, g, b, a = AF.GetColorRGB("cast_uninterruptible_texture", 1)
        end
    else
        self.uninterruptible:Hide()
    end

    if self.interruptibleColorBorder then
        self:SetBackdropBorderColor(r, g, b, a)
        self.gap:SetColorTexture(r, g, b, a)
    else
        self:SetBackdropBorderColor(AF.UnpackColor(self.borderColor))
        self.gap:SetColorTexture(AF.UnpackColor(self.borderColor))
    end
end

local function UpdateInterruptibilityStyle(self)
    if not self.interruptibleCheckEnabled or self.interruptible == nil then
        SetNormalStyle(self)
    elseif self.interruptible then
        SetInterruptibleStyle(self)
    else
        SetUninterruptibleStyle(self)
    end
end

local function CastBar_OnCastStart(self, _, _, isNewCast)
    if isNewCast then
        self.interruptible = nil
    end
    self.status:Hide()
    self.bar:Show()
    UpdateInterruptibilityStyle(self)
end

local function CastBar_OnCastStop(self)
    self.interruptible = nil
    self.bar:Hide()
    self.status:Hide()
end

local function CastBar_OnInterruptibilityChanged(self, interruptible)
    -- UNIT_SPELLCAST_INTERRUPTIBLE and UNIT_SPELLCAST_NOT_INTERRUPTIBLE are
    -- not secret-conditional in Retail 12.0.7. The shared cast widget derives
    -- this boolean from the event name and never reads notInterruptible from
    -- UnitCastingInfo or UnitChannelInfo.
    self.interruptible = interruptible
    UpdateInterruptibilityStyle(self)
end

local function CastBar_Update(self)
    self:UpdateCurrentCast()
end

local function CastBar_Enable(self)
    self:SetUnit(self.root.effectiveUnit)
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

    -- Cast names may be secret. The shared widget forwards them directly to
    -- FontString:SetText, so length-based Lua truncation and interrupt-source
    -- replacement are intentionally not used here.
    self.showName = config.enabled
end

local function CastBar_SetupDurationText(self, config)
    self.durationText:SetShown(config.enabled)
    AF.SetFont(self.durationText, config.font)
    AF.LoadTextPosition(self.durationText, config.position)
    self.durationText:SetTextColor(AF.UnpackColor(config.color))

    -- The shared duration binding formats the opaque duration in native code.
    -- Lua never formats remaining time or appends the delay value.
    self.showDuration = config.enabled
end

local function CastBar_SetupIcon(self, show)
    if show then
        AF.SetPoint(self.bar, "TOPLEFT", self.gap, "TOPRIGHT")
        AF.SetPoint(self.status, "TOPLEFT", self.gap, "TOPRIGHT")
        self.icon:Show()
        self.gap:Show()
    else
        AF.SetPoint(self.bar, "TOPLEFT", 1, -1)
        AF.SetPoint(self.status, "TOPLEFT", 1, -1)
        self.icon:Hide()
        self.gap:Hide()
    end
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
    AF.ReSize(self.gap)
    AF.ReSize(self.spark)
    AF.RePoint(self.bar)
    AF.RePoint(self.status)
    AF.RePoint(self.icon)
    AF.RePoint(self.nameText)
    AF.RePoint(self.durationText)
end

local function CastBar_LoadConfig(self, config)
    UF.LoadIndicatorPosition(self, config.position, config.anchorTo)
    AF.SetSize(self, config.width, config.height)
    AF.SetWidth(self.icon, config.height - 2)
    AF.SetFrameLevel(self, config.frameLevel, self.root)

    CastBar_SetTexture(self, config.texture)

    self:SetBackdropColor(AF.UnpackColor(config.bgColor))
    self:SetBackdropBorderColor(AF.UnpackColor(config.borderColor))
    self.gap:SetColorTexture(AF.UnpackColor(config.borderColor))
    self.uninterruptible:SetVertexColor(AF.GetColorRGB("cast_uninterruptible_texture"))

    CastBar_SetupNameText(self, config.nameText)
    CastBar_SetupDurationText(self, config.durationText)
    CastBar_SetupIcon(self, config.showIcon)
    CastBar_SetupSpark(self, config.spark)

    self.borderColor = config.borderColor
    self.interruptibleCheckEnabled = config.interruptibleCheck.enabled
    self.showUninterruptibleTexture = config.interruptibleCheck.showTexture
    self.interruptibleColorBorder = config.interruptibleCheck.colorBorder

    UpdateInterruptibilityStyle(self)
end

AF.RegisterCallback("BFI_UpdateConfig", function(_, module, group)
    if module ~= "colors" then return end
    if group and group ~= "casts" then return end

    for _, frame in next, BFI.vars.unitButtons do
        local castBar = UF.GetIndicator(frame, "castBar")
        if castBar then
            castBar.spark:SetVertexColor(AF.GetColorRGB("cast_spark"))
            castBar.uninterruptible:SetVertexColor(AF.GetColorRGB("cast_uninterruptible_texture"))
            UpdateInterruptibilityStyle(castBar)
        end
    end
end)

local function StartPreview(self)
    self:SetPreview("Shadow Bolt", 136197, 9, "cast")
end

local function CastBar_EnableConfigMode(self)
    self.Enable = CastBar_EnableConfigMode
    self.Update = AF.noop
    self:UnregisterAllEvents()

    self.previewElapsed = 0
    self:SetScript("OnUpdate", function(frame, elapsed)
        frame.previewElapsed = frame.previewElapsed + elapsed
        if frame.previewElapsed >= 9 then
            frame.previewElapsed = 0
            StartPreview(frame)
        end
    end)

    StartPreview(self)
    self:SetShown(self.enabled)
end

local function CastBar_DisableConfigMode(self)
    self.Enable = CastBar_Enable
    self.Update = CastBar_Update
    self:SetScript("OnUpdate", nil)
    self:StopCast()
end

function UF.CreateCastBar(parent, name)
    local frame = AF.CreateSecretCastBar(parent, name)
    AF.ApplyDefaultBackdrop(frame)
    frame.root = parent

    local icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon = icon
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    AF.SetPoint(icon, "TOPLEFT", 1, -1)
    AF.SetPoint(icon, "BOTTOMLEFT", 1, 1)

    local gap = frame:CreateTexture(nil, "BORDER")
    frame.gap = gap
    gap:SetPoint("TOPLEFT", icon, "TOPRIGHT")
    gap:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT")
    AF.SetWidth(gap, 1)

    local bar = CreateFrame("StatusBar", nil, frame)
    frame.bar = bar
    AF.SetOnePixelInside(bar, frame)
    AF.SetFrameLevel(bar, 1, frame)

    local status = frame:CreateTexture(nil, "OVERLAY")
    frame.status = status
    AF.SetOnePixelInside(status, frame)
    status:Hide()

    local spark = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    frame.spark = spark

    local uninterruptible = bar:CreateTexture(nil, "ARTWORK", nil, 4)
    frame.uninterruptible = uninterruptible
    uninterruptible:SetAllPoints()
    uninterruptible:SetTexture(AF.GetTexture("Uninterruptible1", BFI.name), "REPEAT", "REPEAT")
    uninterruptible:SetHorizTile(true)
    uninterruptible:SetVertTile(true)
    uninterruptible:Hide()

    local overlay = CreateFrame("Frame", nil, frame)
    frame.overlay = overlay
    overlay:SetAllPoints()
    AF.SetFrameLevel(overlay, 2, frame)

    local nameText = overlay:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
    frame.nameText = nameText

    local durationText = overlay:CreateFontString(nil, "OVERLAY", "AF_FONT_NORMAL")
    frame.durationText = durationText

    frame:SetStatusBar(bar)
    frame:SetNameText(nameText)
    frame:SetIcon(icon)
    frame:SetDurationText(durationText)

    frame.OnCastStart = CastBar_OnCastStart
    frame.OnCastStop = CastBar_OnCastStop
    frame.OnInterruptibilityChanged = CastBar_OnInterruptibilityChanged
    frame.Update = CastBar_Update
    frame.Enable = CastBar_Enable
    frame.Disable = CastBar_Disable
    frame.EnableConfigMode = CastBar_EnableConfigMode
    frame.DisableConfigMode = CastBar_DisableConfigMode
    frame.LoadConfig = CastBar_LoadConfig

    AF.AddToPixelUpdater_Auto(frame, CastBar_UpdatePixels)

    return frame
end
