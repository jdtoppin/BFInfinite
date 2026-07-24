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
    self:SetTargetEmphasis(false)
    self:ClearUnit()
    self:Hide()
end

local function NameText_SetTargetEmphasis(self, enabled, config)
    local font = self.configuredFont
    if not font then return end

    if enabled and config and config.enabled then
        local shadow = config.shadow
        if shadow == nil then
            shadow = font[4]
        end

        AF.SetFont(
            self,
            font[1],
            math.max(1, font[2] + (config.sizeDelta or 0)),
            config.outline or font[3],
            shadow
        )
    else
        AF.SetFont(self, font[1], font[2], font[3], font[4])
    end
end

local function NameText_LoadConfig(self, config)
    self.configuredFont = {
        config.font[1],
        config.font[2],
        config.font[3],
        config.font[4],
    }
    self:SetTargetEmphasis(false)
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
    text.SetTargetEmphasis = NameText_SetTargetEmphasis
    text.LoadConfig = NameText_LoadConfig

    return text
end
