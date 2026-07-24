---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
local NP = BFI.modules.Nameplates

local function NameText_Update(self)
    self:UpdateName()
end

local function NameText_Enable(self)
    self:SetUnit(self.root.unit)
    self:Show()
end

local function NameText_Disable(self)
    self:ClearUnit()
    self:Hide()
end

local function NameText_LoadConfig(self, config)
    AF.SetFont(self, unpack(config.font))
    NP.LoadIndicatorPosition(
        self,
        config.position,
        config.anchorTo,
        config.parent
    )
    self:SetLength(config.length)

    if config.color.type == "custom_color" then
        self.color = {
            type = "custom_color",
            rgb = config.color.rgb,
        }
    else
        self.color = {type = "selection_color"}
    end
end

function NP.CreateNameText(parent, name)
    local text = AF.CreateSecretNameText(parent, name)
    text.root = parent
    text:Hide()

    text.Update = NameText_Update
    text.Enable = NameText_Enable
    text.Disable = NameText_Disable
    text.LoadConfig = NameText_LoadConfig

    return text
end
