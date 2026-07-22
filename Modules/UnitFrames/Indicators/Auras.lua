---@type BFI
local BFI = select(2, ...)
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local Auras_UpdateSize

---------------------------------------------------------------------
-- UpdateSize
---------------------------------------------------------------------
local function UpdateSize(self)
    if self.subFrameEnabled then
        Auras_UpdateSize(self, self.mainShown)
        Auras_UpdateSize(self.subFrame, self.subShown)
        if self.mainShown == 0 then
            AF.ClearPoints(self.subFrame)
            self.subFrame:SetPoint(self.anchor)
        else
            AF.LoadWidgetPosition(self.subFrame, self.subFramePosition, self)
        end
    else
        Auras_UpdateSize(self, self.numAuras)
    end
end

local function Auras_Update(self)
    self:SetUnit(self.root.effectiveUnit)
end

local function Auras_Enable(self)
    self:SetUnit(self.root.effectiveUnit)
    self:Show()
end

local function Auras_Disable(self)
    self:ClearUnit()
    self:Hide()
end

local function Auras_OnAurasUpdated(self, count)
    self.mainShown = count
    self.subShown = 0
    if self.subFrame then
        for _, aura in ipairs(self.subFrame.slots) do
            aura:ClearAura()
        end
    end
    UpdateSize(self)
end

---------------------------------------------------------------------
-- BFI_UpdateConfig
---------------------------------------------------------------------
AF.RegisterCallback("BFI_UpdateConfig", function(_, module)
    if module ~= "auras" then return end

    for _, frame in next, BFI.vars.unitButtons do
        if frame:IsVisible() then
            local buffs = UF.GetIndicator(frame, "buffs")
            if buffs and buffs.enabled then
                Auras_Update(buffs)
            end
            local debuffs = UF.GetIndicator(frame, "debuffs")
            if debuffs and debuffs.enabled then
                Auras_Update(debuffs)
            end
        end
    end
end, "low")

---------------------------------------------------------------------
-- config
---------------------------------------------------------------------
Auras_UpdateSize = function(self, numAuras)
    -- if not (self.width and self.height and self.orientation) then return end

    -- hide unused
    for i = numAuras + 1, self.numSlots do
        self.slots[i]:Hide()
    end

    -- set size
    local lines = ceil(numAuras / self.numPerLine)
    numAuras = min(numAuras, self.numPerLine)

    if self.isHorizontal then
        AF.SetGridSize(self, self.width, self.height, self.spacingX, self.spacingY, numAuras, lines)
    else
        AF.SetGridSize(self, self.width, self.height, self.spacingX, self.spacingY, lines, numAuras)
    end
end

local function Auras_SetSize(self, width, height)
    self.width = width
    self.height = height

    for i = 1, self.numSlots do
        AF.SetSize(self.slots[i], width, height)
    end
end

local function Auras_SetOrientation(self, orientation)
    self.orientation = orientation

    assert(self.anchor, "[indicator] position must be set before SetOrientation")

    self.isHorizontal = not strfind(orientation, "top")

    local point1, point2, x, y
    local newLinePoint2, newLineX, newLineY

    if orientation == "left_to_right" then
        if strfind(self.anchor, "^BOTTOM") then
            point1 = "BOTTOMLEFT"
            point2 = "BOTTOMRIGHT"
            newLinePoint2 = "TOPLEFT"
            y = 0
            newLineY = self.spacingY
        else
            point1 = "TOPLEFT"
            point2 = "TOPRIGHT"
            newLinePoint2 = "BOTTOMLEFT"
            y = 0
            newLineY = -self.spacingY
        end
        x = self.spacingX
        newLineX = 0

    elseif orientation == "right_to_left" then
        if strfind(self.anchor, "^BOTTOM") then
            point1 = "BOTTOMRIGHT"
            point2 = "BOTTOMLEFT"
            newLinePoint2 = "TOPRIGHT"
            y = 0
            newLineY = self.spacingY
        else
            point1 = "TOPRIGHT"
            point2 = "TOPLEFT"
            newLinePoint2 = "BOTTOMRIGHT"
            y = 0
            newLineY = -self.spacingY
        end
        x = -self.spacingX
        newLineX = 0

    elseif orientation == "top_to_bottom" then
        if strfind(self.anchor, "RIGHT$") then
            point1 = "TOPRIGHT"
            point2 = "BOTTOMRIGHT"
            newLinePoint2 = "TOPLEFT"
            x = 0
            newLineX = -self.spacingX
        else
            point1 = "TOPLEFT"
            point2 = "BOTTOMLEFT"
            newLinePoint2 = "TOPRIGHT"
            x = 0
            newLineX = self.spacingX
        end
        y = -self.spacingY
        newLineY = 0

    elseif orientation == "bottom_to_top" then
        if strfind(self.anchor, "RIGHT$") then
            point1 = "BOTTOMRIGHT"
            point2 = "TOPRIGHT"
            newLinePoint2 = "BOTTOMLEFT"
            x = 0
            newLineX = -self.spacingX
        else
            point1 = "BOTTOMLEFT"
            point2 = "TOPLEFT"
            newLinePoint2 = "BOTTOMRIGHT"
            x = 0
            newLineX = self.spacingX
        end
        y = self.spacingY
        newLineY = 0
    end

    for i = 1, self.numSlots do
        AF.ClearPoints(self.slots[i])
        if i == 1 then
            AF.SetPoint(self.slots[i], point1)
        elseif i % self.numPerLine == 1 then
            AF.SetPoint(self.slots[i], point1, self.slots[i-self.numPerLine], newLinePoint2, newLineX, newLineY)
        else
            AF.SetPoint(self.slots[i], point1, self.slots[i-1], point2, x, y)
        end
    end
end

local function Auras_SetNumPerLine(self, numPerLine)
    self.numPerLine = min(numPerLine, self.numSlots)
end

local function Auras_SetNumSlots(self, numSlots)
    self.numSlots = numSlots
    self:SetMaxCount(numSlots)

    for i = 1, numSlots do
        if not self.slots[i] then
            self.slots[i] = AF.CreateAura(self, true)
        end
    end

    -- hide if reduced
    for i = numSlots + 1, #self.slots do
        self.slots[i]:Hide()
    end
end

local function Auras_SetupAuras(self, config)
    for i = 1, self.numSlots do
        local aura = self.slots[i]
        aura.root = self.root
        aura:EnableTooltip(config.tooltip)
        -- aura:SetDesaturated(config.desaturated)
        aura:SetCooldownStyle(config.cooldownStyle)
        aura:SetupDurationText(config.durationText)
        aura:SetupStackText(config.stackText)
    end
end

local function Auras_UpdateSubFramePosition(self, orientation)
    local point1, newLinePoint2, newLineX, newLineY

    if orientation == "left_to_right" then
        if strfind(self.anchor, "^BOTTOM") then
            point1 = "BOTTOMLEFT"
            newLinePoint2 = "TOPLEFT"
            newLineY = self.spacingY
        else
            point1 = "TOPLEFT"
            newLinePoint2 = "BOTTOMLEFT"
            newLineY = -self.spacingY
        end
        newLineX = 0

    elseif orientation == "right_to_left" then
        if strfind(self.anchor, "^BOTTOM") then
            point1 = "BOTTOMRIGHT"
            newLinePoint2 = "TOPRIGHT"
            newLineY = self.spacingY
        else
            point1 = "TOPRIGHT"
            newLinePoint2 = "BOTTOMRIGHT"
            newLineY = -self.spacingY
        end
        newLineX = 0

    elseif orientation == "top_to_bottom" then
        if strfind(self.anchor, "RIGHT$") then
            point1 = "TOPRIGHT"
            newLinePoint2 = "TOPLEFT"
            newLineX = -self.spacingX
        else
            point1 = "TOPLEFT"
            newLinePoint2 = "TOPRIGHT"
            newLineX = self.spacingX
        end
        newLineY = 0

    elseif orientation == "bottom_to_top" then
        if strfind(self.anchor, "RIGHT$") then
            point1 = "BOTTOMRIGHT"
            newLinePoint2 = "BOTTOMLEFT"
            newLineX = -self.spacingX
        else
            point1 = "BOTTOMLEFT"
            newLinePoint2 = "BOTTOMRIGHT"
            newLineX = self.spacingX
        end
        newLineY = 0
    end

    self.subFramePosition = {point1, newLinePoint2, newLineX, newLineY}
    AF.SetPoint(self.subFrame, point1, self, newLinePoint2, newLineX, newLineY)
end

local function Auras_OnHide(self)
    for i = 1, self.numSlots do
        self.slots[i]:Hide()
    end

    if self.subFrameEnabled then
        for i = 1, self.numSlots do
            self.subFrame.slots[i]:Hide()
        end
    end
end

local function Auras_LoadConfig(self, config)
    -- texplore(config)
    AF.SetFrameLevel(self, config.frameLevel, self.root)
    UF.LoadIndicatorPosition(self, config.position, config.anchorTo)

    self.anchor = config.position[1]
    self.spacingX = config.spacingX
    self.spacingY = config.spacingY
    self.isBlock = strfind(config.cooldownStyle, "^block")
    self.tooltipEnabled = config.tooltip.enabled

    Auras_SetNumSlots(self, config.numTotal)
    Auras_SetSize(self, config.width, config.height)
    Auras_SetNumPerLine(self, config.numPerLine)
    Auras_SetOrientation(self, config.orientation)
    Auras_SetupAuras(self, config)
    Auras_UpdateSize(self, 0)

    -- Spell/source/priority classification requires inspecting restricted
    -- AuraData. The shared list uses only the configured HELPFUL/HARMFUL filter
    -- and Blizzard's C-side default sorting, so the optional classified
    -- subframe is intentionally disabled.
    self.subFrameEnabled = false
    if self.subFrame then
        self.subFrame:Hide()
    end
end

local function Auras_UpdatePixels(self)
    AF.ReSize(self)
    AF.RePoint(self)
    for _, slot in next, self.slots do
        slot:UpdatePixels()
    end
    if self.subFrame then
        AF.ReSize(self.subFrame)
        AF.RePoint(self.subFrame)
        for _, slot in next, self.subFrame.slots do
            slot:UpdatePixels()
        end
    end
end

---------------------------------------------------------------------
-- config mode
---------------------------------------------------------------------
local function ConfigMode_RefreshAuras(self)
    local icon = self.auraFilter == "HELPFUL" and 135953 or 136071
    if self.isBlock then
        for i = 1, self.numSlots do
            self.slots[i]:SetCooldown(GetTime(), 15, i, icon, nil, nil, nil, AF.GetColorRGB("BFI"))
            self.slots[i]:EnableMouse(false)
        end
    else
        for i = 1, self.numSlots do
            self.slots[i]:SetCooldown(GetTime(), 15, i, icon)
            self.slots[i]:EnableMouse(false)
        end
    end
    Auras_UpdateSize(self, self.numSlots)
end

local function Auras_EnableConfigMode(self)
    self:UnregisterAllEvents()
    self.Enable = Auras_EnableConfigMode
    self.Update = AF.noop

    if self.enabled then
        if self.configModeTicker then
            self.configModeTicker:Cancel()
        end
        ConfigMode_RefreshAuras(self)
        self.configModeTicker = C_Timer.NewTicker(15, function()
            ConfigMode_RefreshAuras(self)
        end)
        self:Show()
    else
        if self.configModeTicker then
            self.configModeTicker:Cancel()
            self.configModeTicker = nil
        end
        self:Hide()
    end
end

local function Auras_DisableConfigMode(self)
    self.Enable = Auras_Enable
    self.Update = Auras_Update

    if self.configModeTicker then
        self.configModeTicker:Cancel()
        self.configModeTicker = nil
    end

    if self.tooltipEnabled then
        for i = 1, self.numSlots do
            self.slots[i]:EnableMouse(true)
        end
    end
end

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
function UF.CreateAuras(parent, name, auraFilter, hasSubFrame)
    local frame = AF.CreateSecretAuraList(parent, name, auraFilter)

    frame.root = parent
    frame.auraFilter = auraFilter

    -- subFrame
    if hasSubFrame then
        frame.subFrame = CreateFrame("Frame", nil, frame)
        frame.subFrame.root = parent
        frame.subFrame.slots = {}
    end

    frame.mainShown = 0
    frame.subShown = 0

    -- scripts
    frame:SetScript("OnHide", Auras_OnHide)

    -- functions
    frame.Enable = Auras_Enable
    frame.Disable = Auras_Disable
    frame.Update = Auras_Update
    frame.EnableConfigMode = Auras_EnableConfigMode
    frame.DisableConfigMode = Auras_DisableConfigMode
    frame.LoadConfig = Auras_LoadConfig
    frame.OnAurasUpdated = Auras_OnAurasUpdated

    -- pixel perfect
    AF.AddToPixelUpdater_Auto(frame, Auras_UpdatePixels)

    return frame
end
