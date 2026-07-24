---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class Nameplates
local NP = BFI.modules.Nameplates
---@type AbstractFramework
local AF = _G.AbstractFramework

local PLATE_TYPES = {
    "hostile_npc",
    "hostile_player",
    "friendly_npc",
    "friendly_player",
}

local nameplatesPanel

local function UpdateNameplates()
    AF.Fire("BFI_UpdateModule", "nameplates")
end

local function SetSharedHealthBarValue(key, value)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].healthBar[key] = value
    end
    UpdateNameplates()
end

local function SetSharedIndicatorEnabled(indicator, enabled)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType][indicator].enabled = enabled
    end
    UpdateNameplates()
end

-- Legacy profiles may still have per-type differences. Treat the shared
-- feature as active if any plate type currently uses it; changing the
-- checkbox intentionally normalizes all four types.
local function IsIndicatorEnabledForAnyPlateType(indicator)
    for _, plateType in ipairs(PLATE_TYPES) do
        if NP.config[plateType][indicator].enabled then
            return true
        end
    end
    return false
end

local function CreateNameplatesPanel()
    nameplatesPanel = AF.CreateFrame(BFIOptionsFrame_ContentPane, "BFIOptionsFrame_NameplatesPanel")
    nameplatesPanel:SetAllPoints()

    --------------------------------------------------
    -- module
    --------------------------------------------------
    local modulePane = AF.CreateTitledPane(nameplatesPanel, L["Nameplates"], nil, 100)
    AF.SetPoint(modulePane, "TOPLEFT", nameplatesPanel, 15, -15)
    AF.SetPoint(modulePane, "TOPRIGHT", nameplatesPanel, -15, -15)

    local enabled = AF.CreateCheckButton(modulePane, L["Enable BFI Nameplates"])
    AF.SetPoint(enabled, "TOPLEFT", modulePane, 15, -32)
    enabled:SetEnabled(NP.foundationAvailable)
    enabled:SetOnCheck(function(checked)
        NP.config.enabled = checked
        enabled:SetTextColor(checked and "softlime" or "firebrick")
        UpdateNameplates()
    end)

    local optInNotice = AF.CreateFontString(modulePane, L["BFI nameplates are opt-in and remain inactive until enabled."], "gray")
    AF.SetPoint(optInNotice, "TOPLEFT", modulePane, 15, -60)
    AF.SetPoint(optInNotice, "TOPRIGHT", modulePane, -15, -60)
    optInNotice:SetJustifyH("LEFT")
    optInNotice:SetWordWrap(true)

    --------------------------------------------------
    -- shared settings
    --------------------------------------------------
    local sharedPane = AF.CreateTitledPane(nameplatesPanel, L["Shared Nameplate Settings"], nil, 220)
    AF.SetPoint(sharedPane, "TOPLEFT", modulePane, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(sharedPane, "TOPRIGHT", modulePane, "BOTTOMRIGHT", 0, -15)

    local sharedNotice = AF.CreateFontString(sharedPane, L["Shared width, height, and feature changes apply to hostile and friendly NPC and player nameplates."], "gray")
    AF.SetPoint(sharedNotice, "TOPLEFT", sharedPane, 15, -30)
    AF.SetPoint(sharedNotice, "TOPRIGHT", sharedPane, -15, -30)
    sharedNotice:SetJustifyH("LEFT")
    sharedNotice:SetWordWrap(true)

    local width = AF.CreateSlider(sharedPane, L["Width"], 180, 40, 300, 1, nil, true)
    AF.SetPoint(width, "TOPLEFT", sharedPane, 15, -90)
    width:SetAfterValueChanged(function(value)
        SetSharedHealthBarValue("width", value)
    end)

    local height = AF.CreateSlider(sharedPane, L["Height"], 180, 4, 40, 1, nil, true)
    AF.SetPoint(height, "TOPLEFT", sharedPane, 285, -90)
    height:SetAfterValueChanged(function(value)
        SetSharedHealthBarValue("height", value)
    end)

    local nameText = AF.CreateCheckButton(sharedPane, L["Name"])
    AF.SetPoint(nameText, "TOPLEFT", sharedPane, 15, -150)
    nameText:SetOnCheck(function(checked)
        SetSharedIndicatorEnabled("nameText", checked)
    end)

    local castBar = AF.CreateCheckButton(sharedPane, L["castBar"])
    AF.SetPoint(castBar, "TOPLEFT", sharedPane, 285, -150)
    castBar:SetOnCheck(function(checked)
        SetSharedIndicatorEnabled("castBar", checked)
    end)

    local debuffs = AF.CreateCheckButton(sharedPane, L["debuffs"])
    AF.SetPoint(debuffs, "TOPLEFT", sharedPane, 15, -180)
    debuffs:SetOnCheck(function(checked)
        SetSharedIndicatorEnabled("debuffs", checked)
    end)

    local targetIndicator = AF.CreateCheckButton(sharedPane, L["Target Indicator"])
    AF.SetPoint(targetIndicator, "TOPLEFT", sharedPane, 285, -180)
    targetIndicator:SetOnCheck(function(checked)
        SetSharedIndicatorEnabled("targetIndicator", checked)
    end)

    --------------------------------------------------
    -- compatibility
    --------------------------------------------------
    local compatibilityPane = AF.CreateTitledPane(nameplatesPanel, L["Compatibility"], nil, 95, "sand")
    AF.SetPoint(compatibilityPane, "TOPLEFT", sharedPane, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(compatibilityPane, "TOPRIGHT", sharedPane, "BOTTOMRIGHT", 0, -15)

    local compatibilityNotice = AF.CreateFontString(compatibilityPane, L["Native special and quest widgets remain Blizzard-owned. Click targeting uses Blizzard's native region. Changes made during combat may be deferred until combat ends."], "sand")
    AF.SetPoint(compatibilityNotice, "TOPLEFT", compatibilityPane, 15, -30)
    AF.SetPoint(compatibilityNotice, "TOPRIGHT", compatibilityPane, -15, -30)
    compatibilityNotice:SetJustifyH("LEFT")
    compatibilityNotice:SetWordWrap(true)

    function nameplatesPanel.Load()
        local config = NP.config

        enabled:SetChecked(config.enabled)
        enabled:SetTextColor(config.enabled and "softlime" or "firebrick")
        width:SetValue(config.hostile_npc.healthBar.width)
        height:SetValue(config.hostile_npc.healthBar.height)
        nameText:SetChecked(IsIndicatorEnabledForAnyPlateType("nameText"))
        castBar:SetChecked(IsIndicatorEnabledForAnyPlateType("castBar"))
        debuffs:SetChecked(IsIndicatorEnabledForAnyPlateType("debuffs"))
        targetIndicator:SetChecked(IsIndicatorEnabledForAnyPlateType("targetIndicator"))
    end
end

---------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------
AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "nameplates" or not nameplatesPanel then return end
    nameplatesPanel.Load()
end)

AF.RegisterCallback("BFI_UpdateProfile", function()
    if nameplatesPanel and nameplatesPanel:IsShown() then
        nameplatesPanel.Load()
    end
end, "low")

---------------------------------------------------------------------
-- show
---------------------------------------------------------------------
AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "nameplates" then
        if not nameplatesPanel then
            CreateNameplatesPanel()
        end
        nameplatesPanel.Load()
        nameplatesPanel:Show()
    elseif nameplatesPanel then
        nameplatesPanel:Hide()
    end
end)
