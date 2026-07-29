---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
local NP = BFI.modules.Nameplates

local HALF_PI = math.pi / 2

local function TargetIndicator_ClearTargetState(self)
    self.targetVisual:Hide()
    self.focusVisual:Hide()

    if self.nameTextEmphasized then
        local nameText = NP.GetIndicator(self.root, "nameText")
        if nameText and nameText.SetTargetEmphasis then
            nameText:SetTargetEmphasis(false)
        end
    end

    self.nameTextEmphasized = nil
    self:Hide()
end

local function TargetIndicator_LoadStateVisual(
    self,
    visual,
    config
)
    local size = config.size or self.defaultSize
    local sideSize = config.sideSize or 22
    local sideSpacing = config.sideSpacing or 0
    local topSpacing = config.topSpacing
    if type(topSpacing) ~= "number" then
        topSpacing = self.defaultTopSpacing or 0
    end
    local layout = config.layout or "top"
    local texture = AF.GetTexture(config.texture, BFI.name)

    visual:Hide()
    visual:SetSize(size, size)
    visual:ClearAllPoints()
    visual:SetPoint("CENTER", self, "CENTER", 0, 0)

    for _, icon in next, visual.icons do
        icon:SetTexture(texture)
        icon:SetVertexColor(AF.UnpackColor(config.color))
    end

    visual.topIcon:SetSize(size, size)
    visual.topIcon:ClearAllPoints()
    visual.topIcon:SetPoint(
        "BOTTOM",
        self.anchorRegion,
        "TOP",
        0,
        topSpacing
    )
    visual.topIcon:SetShown(layout == "top")

    -- Use the already-resolved anchor region directly. Nameplate regions
    -- can be restricted, so prepare geometry during configuration with
    -- direct setters that do not read effective scale. Target/focus events
    -- only toggle preconfigured visuals.
    visual.leftIcon:SetSize(sideSize, sideSize)
    visual.leftIcon:ClearAllPoints()
    visual.leftIcon:SetPoint(
        "RIGHT",
        self.anchorRegion,
        "LEFT",
        -sideSpacing,
        0
    )
    visual.leftIcon:SetShown(layout == "sides")

    visual.rightIcon:SetSize(sideSize, sideSize)
    visual.rightIcon:ClearAllPoints()
    visual.rightIcon:SetPoint(
        "LEFT",
        self.anchorRegion,
        "RIGHT",
        sideSpacing,
        0
    )
    visual.rightIcon:SetShown(layout == "sides")

    local healthBar = NP.GetIndicator(self.root, "healthBar")
    local healthHighlight = config.healthBarHighlight
    if healthBar and healthHighlight then
        visual.healthBarHighlight:ClearAllPoints()
        visual.healthBarHighlight:SetPoint(
            "TOPLEFT",
            healthBar,
            "TOPLEFT",
            0,
            0
        )
        visual.healthBarHighlight:SetPoint(
            "BOTTOMRIGHT",
            healthBar,
            "BOTTOMRIGHT",
            0,
            0
        )
        visual.healthBarHighlight:SetColorTexture(
            AF.UnpackColor(healthHighlight.color)
        )
    end
    visual.healthBarHighlight:SetShown(
        healthBar ~= nil
            and healthBar.enabled
            and healthHighlight ~= nil
            and healthHighlight.enabled
    )

    visual.nameTextEmphasis = config.nameTextEmphasis
end

local function TargetIndicator_ApplyTargetState(self, visual)
    local nameEmphasis = visual.nameTextEmphasis
    local nameText = NP.GetIndicator(self.root, "nameText")
    if nameText
        and nameText.enabled
        and nameText.SetTargetEmphasis
        and nameEmphasis
        and nameEmphasis.enabled
    then
        nameText:SetTargetEmphasis(true, nameEmphasis)
        self.nameTextEmphasized = true
    end

    self:Show()
    visual:Show()
end

local function TargetIndicator_SetTargetState(
    self,
    isTarget,
    isFocus
)
    TargetIndicator_ClearTargetState(self)

    if isFocus then
        TargetIndicator_ApplyTargetState(
            self,
            self.focusVisual
        )
    elseif isTarget then
        TargetIndicator_ApplyTargetState(
            self,
            self.targetVisual
        )
    end
end

local function TargetIndicator_Update()
    NP.UpdateTargetIndicators()
end

local function TargetIndicator_Enable(self)
    self:Update()
end

local function TargetIndicator_Disable(self)
    TargetIndicator_ClearTargetState(self)
end

local function TargetIndicator_LoadConfig(self, config)
    TargetIndicator_ClearTargetState(self)

    AF.SetFrameLevel(self, config.frameLevel, self.root)
    self.defaultSize = config.size or 40
    local position = config.position
    self.defaultTopSpacing =
        type(position) == "table"
        and type(position[4]) == "number"
        and position[4]
        or 0
    AF.SetSize(self, self.defaultSize, self.defaultSize)
    self.anchorRegion = NP.LoadIndicatorPosition(
        self,
        config.position,
        config.anchorTo
    )

    TargetIndicator_LoadStateVisual(
        self,
        self.targetVisual,
        config.target
    )
    TargetIndicator_LoadStateVisual(
        self,
        self.focusVisual,
        config.focus
    )
end

local function CreateStateVisual(parent)
    local visual = CreateFrame("Frame", nil, parent)
    visual:Hide()

    local topIcon = visual:CreateTexture(nil, "ARTWORK")
    visual.topIcon = topIcon

    local leftIcon = visual:CreateTexture(nil, "ARTWORK")
    visual.leftIcon = leftIcon
    leftIcon:SetRotation(HALF_PI)
    leftIcon:Hide()

    local rightIcon = visual:CreateTexture(nil, "ARTWORK")
    visual.rightIcon = rightIcon
    rightIcon:SetRotation(-HALF_PI)
    rightIcon:Hide()

    visual.icons = {
        topIcon,
        leftIcon,
        rightIcon,
    }

    local healthBarHighlight = visual:CreateTexture(
        nil,
        "OVERLAY"
    )
    visual.healthBarHighlight = healthBarHighlight
    healthBarHighlight:SetBlendMode("ADD")
    healthBarHighlight:Hide()

    return visual
end

function NP.CreateTargetIndicator(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    frame.root = parent
    frame:Hide()

    frame.targetVisual = CreateStateVisual(frame)
    frame.focusVisual = CreateStateVisual(frame)

    frame.SetTargetState = TargetIndicator_SetTargetState
    frame.Update = TargetIndicator_Update
    frame.Enable = TargetIndicator_Enable
    frame.Disable = TargetIndicator_Disable
    frame.LoadConfig = TargetIndicator_LoadConfig

    return frame
end
