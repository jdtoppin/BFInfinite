---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
local NP = BFI.modules.Nameplates

local function TargetIndicator_SetTargetState(
    self,
    isTarget,
    isFocus
)
    if isFocus then
        self.icon:SetTexture(
            AF.GetTexture(self.focusTexture, BFI.name)
        )
        self.icon:SetVertexColor(
            AF.UnpackColor(self.focusColor)
        )
        self:Show()
    elseif isTarget then
        self.icon:SetTexture(
            AF.GetTexture(self.targetTexture, BFI.name)
        )
        self.icon:SetVertexColor(
            AF.UnpackColor(self.targetColor)
        )
        self:Show()
    else
        self:Hide()
    end
end

local function TargetIndicator_Update()
    NP.UpdateTargetIndicators()
end

local function TargetIndicator_Enable(self)
    self:Update()
end

local function TargetIndicator_Disable(self)
    self:Hide()
end

local function TargetIndicator_LoadConfig(self, config)
    AF.SetFrameLevel(self, config.frameLevel, self.root)
    AF.SetSize(self, config.size, config.size)
    NP.LoadIndicatorPosition(
        self,
        config.position,
        config.anchorTo
    )

    self.targetTexture = config.target.texture
    self.targetColor = config.target.color
    self.focusTexture = config.focus.texture
    self.focusColor = config.focus.color
end

function NP.CreateTargetIndicator(parent, name)
    local frame = CreateFrame("Frame", name, parent)
    frame.root = parent
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon = icon
    icon:SetAllPoints()

    frame.SetTargetState = TargetIndicator_SetTargetState
    frame.Update = TargetIndicator_Update
    frame.Enable = TargetIndicator_Enable
    frame.Disable = TargetIndicator_Disable
    frame.LoadConfig = TargetIndicator_LoadConfig

    return frame
end
