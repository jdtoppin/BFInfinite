---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
---@class Nameplates
local NP = BFI.modules.Nameplates

local builders = {
    {"healthBar", NP.CreateHealthBar},
    {"nameText", NP.CreateNameText},
    {"castBar", NP.CreateCastBar},
    {"debuffs", NP.CreateDebuffs},
    {"targetIndicator", NP.CreateTargetIndicator},
}

local allowedAnchors = {
    healthBar = {root = true},
    nameText = {root = true, healthBar = true},
    castBar = {root = true, healthBar = true},
    debuffs = {
        root = true,
        healthBar = true,
        nameText = true,
        castBar = true,
    },
    targetIndicator = {
        root = true,
        healthBar = true,
        nameText = true,
        castBar = true,
        debuffs = true,
    },
}

local allowedParents = {
    healthBar = {root = true},
    nameText = {root = true, healthBar = true},
    castBar = {root = true},
    debuffs = {root = true},
    targetIndicator = {root = true},
}

local function ResolveRegion(self, requested, allowed)
    if not requested
        or requested == "root"
        or not allowed[requested]
    then
        return self.root
    end

    local region = self.root.indicators[requested]
    if region == self then
        return self.root
    end
    return region or self.root
end

function NP.CreateIndicators(np)
    for _, builderInfo in ipairs(builders) do
        local indicatorName, builder = unpack(builderInfo)
        local indicator = builder(
            np,
            np:GetName() .. AF.UpperFirst(indicatorName)
        )
        indicator.indicatorName = indicatorName
        np.indicators[indicatorName] = indicator
    end
end

function NP.LoadIndicatorConfig(np, indicatorName, indicatorConfig)
    local indicator = np.indicators[indicatorName]
    if not indicator then return end

    if indicatorConfig then
        indicator:LoadConfig(indicatorConfig)
        indicator.enabled = indicatorConfig.enabled == true
    else
        indicator.enabled = false
    end

    if not indicator.enabled then
        indicator:Disable()
    end
end

function NP.SetupIndicators(np, config)
    for _, builderInfo in ipairs(builders) do
        local indicatorName = builderInfo[1]
        NP.LoadIndicatorConfig(
            np,
            indicatorName,
            config[indicatorName]
        )
    end
end

function NP.DisableIndicators(np)
    for _, indicator in next, np.indicators do
        indicator:Disable()
    end
end

function NP.UpdateIndicators(np)
    for _, indicator in next, np.indicators do
        if indicator.enabled then
            indicator:Update()
        end
    end
end

function NP.OnNameplateShow(np)
    for _, indicator in next, np.indicators do
        if indicator.enabled then
            indicator:Enable()
        end
    end
end

function NP.OnNameplateHide(np)
    NP.DisableIndicators(np)
end

function NP.LoadIndicatorPosition(self, position, anchorTo, parent)
    position = position or {"CENTER", "CENTER", 0, 0}

    -- Indicator-owned subregions (for example the cast icon background)
    -- intentionally anchor within their existing parent.
    if not self.root then
        AF.LoadWidgetPosition(self, position)
        return
    end

    local indicatorName = self.indicatorName
    local parentRegion = ResolveRegion(
        self,
        parent,
        allowedParents[indicatorName]
    )
    self:SetParent(parentRegion)

    local anchorRegion = ResolveRegion(
        self,
        anchorTo,
        allowedAnchors[indicatorName]
    )
    if self:GetObjectType() == "FontString" then
        AF.LoadTextPosition(self, position, anchorRegion)
    else
        AF.LoadWidgetPosition(self, position, anchorRegion)
    end
end

function NP.GetIndicator(frame, indicatorName, requireEnabled)
    if not frame or not frame.indicators then return end

    local indicator = frame.indicators[indicatorName]
    if indicator
        and (not requireEnabled or indicator.enabled)
    then
        return indicator
    end
end
