---@type BFI
local BFI = select(2, ...)
local NP = BFI.modules.Nameplates
local A = BFI.modules.Auras
---@type AbstractFramework
local AF = _G.AbstractFramework

local Auras_UpdateSize, Auras_UpdateSiblings
local function Auras_Update(self)
    self:SetUnit(self.root.unit)
end

local function Auras_Enable(self)
    self:SetUnit(self.root.unit)
    self:Show()
end

local function Auras_Disable(self)
    self:ClearUnit()
    self:Hide()
end

local function Auras_OnAurasUpdated(self, count)
    Auras_UpdateSize(self, count)
    Auras_UpdateSiblings(self)
end

---------------------------------------------------------------------
-- BFI_UpdateConfig
---------------------------------------------------------------------
AF.RegisterCallback("BFI_UpdateConfig", function(_, module, which)
    if module ~= "auras" then return end

    if not which or which == "blacklist" or which == "priorities" then
        for _, frame in next, NP.created do
            if frame:IsVisible() then
                local buffs = NP.GetIndicator(frame, "buffs")
                if buffs and buffs.enabled then
                    Auras_Update(buffs)
                end
                local debuffs = NP.GetIndicator(frame, "debuffs")
                if debuffs and debuffs.enabled then
                    Auras_Update(debuffs)
                end
            end
        end
    end
end, "low")

---------------------------------------------------------------------
-- siblings
---------------------------------------------------------------------
local function Auras_AddSibling(self, sibling)
    if not self.siblings then
        self.siblings = {}
    end
    self.siblings[sibling] = true
end

local function Auras_RemoveSibling(self, sibling)
    if not self.siblings then
        return
    end
    self.siblings[sibling] = nil
end

function Auras_UpdateSiblings(self)
    if not self.siblings then
        return
    end
    for sibling in next, self.siblings do
        AF.ClearPoints(sibling)
        if self.numAuras == 0 then
            AF.SetPoint(sibling, sibling.position[1], self, sibling.position[2])
        else
            AF.SetPoint(sibling, sibling.position[1], self, sibling.position[2], sibling.position[3], sibling.position[4])
        end
    end
end

---------------------------------------------------------------------
-- config
---------------------------------------------------------------------
function Auras_UpdateSize(self, numAuras)
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

    Auras_UpdateSiblings(self)
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
        aura:EnableDispelColor(
            self.auraFilter == "HARMFUL"
            and config.auraTypeColor
            and config.auraTypeColor.debuffType
        )
        -- aura:SetDesaturated(config.desaturated)
        aura:SetCooldownStyle(config.cooldownStyle)
        aura:SetupDurationText(config.durationText)
        aura:SetupStackText(config.stackText)
    end
end

local function Auras_OnHide(self)
    for i = 1, self.numSlots do
        self.slots[i]:Hide()
    end
end

local function Auras_LoadConfig(self, config)
    AF.SetFrameLevel(self, config.frameLevel, self.root)
    NP.LoadIndicatorPosition(self, config.position, config.anchorTo)

    self.position = config.position -- for sibling update
    self.anchor = config.position[1]
    self.spacingX = config.spacingX
    self.spacingY = config.spacingY
    Auras_SetNumSlots(self, config.numTotal)
    Auras_SetSize(self, config.width, config.height)
    Auras_SetNumPerLine(self, config.numPerLine)
    Auras_SetOrientation(self, config.orientation)
    Auras_SetupAuras(self, config)
    Auras_UpdateSize(self, 0)

    if self.auraFilter == "HARMFUL|CROWD_CONTROL" then
        self:SetMatchFilters(nil)
    else
        self:SetMatchFilters(A.GetSecretSafeMatchFilters(self.auraFilter, config.filters))
    end

    -- Arbitrary spell blacklists and priorities remain unavailable for
    -- restricted auras. Supported categories use Blizzard's C-side filters.
end

local function Auras_UpdatePixels(self)
    AF.ReSize(self)
    AF.RePoint(self)
    for _, slot in next, self.slots do
        slot:UpdatePixels()
    end
end

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function CreateAuras(parent, name, auraFilter)
    local frame = AF.CreateSecretAuraList(parent, name, auraFilter)

    frame.root = parent
    frame.auraFilter = auraFilter
    frame.canHaveSibling = true

    -- scripts
    frame:SetScript("OnHide", Auras_OnHide)

    -- functions
    frame.Enable = Auras_Enable
    frame.Disable = Auras_Disable
    frame.Update = Auras_Update
    frame.LoadConfig = Auras_LoadConfig
    frame.AddSibling = Auras_AddSibling
    frame.RemoveSibling = Auras_RemoveSibling
    frame.UpdateSiblings = Auras_UpdateSiblings
    frame.OnAurasUpdated = Auras_OnAurasUpdated

    -- pixel perfect
    AF.AddToPixelUpdater_Auto(frame, Auras_UpdatePixels)

    return frame
end

function NP.CreateDebuffs(parent, name)
    return CreateAuras(parent, name, "HARMFUL")
end

function NP.CreateBuffs(parent, name)
    return CreateAuras(parent, name, "HELPFUL")
end

function NP.CreateCrowdControls(parent, name)
    return CreateAuras(parent, name, "HARMFUL|CROWD_CONTROL")
end
