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

local function SetSharedDebuffValue(key, value)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].debuffs[key] = value
    end
    UpdateNameplates()
end

local function SetSharedDebuffDurationValue(key, value)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].debuffs.durationText[key] = value
    end
    UpdateNameplates()
end

local function SetSharedDebuffDurationArrayValue(key, index, value)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].debuffs.durationText[key][index] = value
    end
    UpdateNameplates()
end

local function SetSharedDebuffDurationColor(r, g, b)
    for _, plateType in ipairs(PLATE_TYPES) do
        AF.FillColorTable(NP.config[plateType].debuffs.durationText.color.normal, r, g, b)
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

local function IsDebuffDurationEnabledForAnyPlateType()
    for _, plateType in ipairs(PLATE_TYPES) do
        if NP.config[plateType].debuffs.durationText.enabled then
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

    local sectionSwitch = AF.CreateSwitch(nameplatesPanel, nil, 20)
    AF.SetPoint(sectionSwitch, "TOPLEFT", modulePane, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(sectionSwitch, "TOPRIGHT", modulePane, "BOTTOMRIGHT", 0, -15)
    sectionSwitch:SetLabels({
        {text = L["General"], value = "general"},
        {text = L["Auras"], value = "auras"},
    })

    local generalPage = AF.CreateFrame(nameplatesPanel)
    AF.SetPoint(generalPage, "TOPLEFT", sectionSwitch, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(generalPage, "BOTTOMRIGHT", nameplatesPanel, -15, 15)

    local aurasPage = AF.CreateFrame(nameplatesPanel)
    AF.SetPoint(aurasPage, "TOPLEFT", sectionSwitch, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(aurasPage, "BOTTOMRIGHT", nameplatesPanel, -15, 15)

    sectionSwitch:SetOnSelect(function(value)
        generalPage:SetShown(value == "general")
        aurasPage:SetShown(value == "auras")
    end)

    --------------------------------------------------
    -- shared settings
    --------------------------------------------------
    local sharedPane = AF.CreateTitledPane(generalPage, L["Shared Nameplate Settings"], nil, 220)
    AF.SetPoint(sharedPane, "TOPLEFT", generalPage)
    AF.SetPoint(sharedPane, "TOPRIGHT", generalPage)

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
    local compatibilityPane = AF.CreateTitledPane(generalPage, L["Compatibility"], nil, 95, "sand")
    AF.SetPoint(compatibilityPane, "TOPLEFT", sharedPane, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(compatibilityPane, "TOPRIGHT", sharedPane, "BOTTOMRIGHT", 0, -15)

    local compatibilityNotice = AF.CreateFontString(compatibilityPane, L["Native special and quest widgets remain Blizzard-owned. Blizzard's click target expands to cover the BFI health bar. Changes made during combat may be deferred until combat ends."], "sand")
    AF.SetPoint(compatibilityNotice, "TOPLEFT", compatibilityPane, 15, -30)
    AF.SetPoint(compatibilityNotice, "TOPRIGHT", compatibilityPane, -15, -30)
    compatibilityNotice:SetJustifyH("LEFT")
    compatibilityNotice:SetWordWrap(true)

    --------------------------------------------------
    -- debuff aura appearance
    --------------------------------------------------
    local auraPane = AF.CreateTitledPane(aurasPage, L["debuffs"], nil, 365)
    AF.SetPoint(auraPane, "TOPLEFT", aurasPage)
    AF.SetPoint(auraPane, "TOPRIGHT", aurasPage)

    local auraNotice = AF.CreateFontString(auraPane, L["Debuff timer appearance changes apply to hostile and friendly NPC and player nameplates."], "gray")
    AF.SetPoint(auraNotice, "TOPLEFT", auraPane, 15, -30)
    AF.SetPoint(auraNotice, "TOPRIGHT", auraPane, -15, -30)
    auraNotice:SetJustifyH("LEFT")
    auraNotice:SetWordWrap(true)

    local cooldownStyle = AF.CreateDropdown(auraPane, 250)
    cooldownStyle:SetLabel(L["Cooldown Style"])
    AF.SetPoint(cooldownStyle, "TOPLEFT", auraPane, 15, -90)
    cooldownStyle:SetItems({
        {text = _G.NONE, value = "none"},
        {text = L["Vertical"], value = "vertical"},
        {text = L["Block Vertical"], value = "block_vertical"},
        {text = L["Clock"], value = "clock"},
        {text = L["Block Clock"], value = "block_clock"},
        {text = L["Clock (With Leading Edge)"], value = "clock_with_leading_edge"},
        {text = L["Block Clock (With Leading Edge)"], value = "block_clock_with_leading_edge"},
    })
    cooldownStyle:SetOnSelect(function(value)
        SetSharedDebuffValue("cooldownStyle", value)
    end)

    local durationEnabled = AF.CreateCheckButton(auraPane, L["Duration Text"])
    AF.SetPoint(durationEnabled, "TOPLEFT", auraPane, 300, -72)

    -- Retail 12.0.7's native DurationTextBinding cannot apply threshold
    -- colors without exposing restricted duration values to Lua. Keep the
    -- supported normal color here; 12.1 curve modes need a separate design.
    local normalColor = AF.CreateColorPicker(auraPane, L["Normal"])
    AF.SetPoint(normalColor, "TOPLEFT", auraPane, 300, -105)
    normalColor:SetOnChange(SetSharedDebuffDurationColor)

    local font = AF.CreateDropdown(auraPane, 150)
    font:SetLabel(L["Font"])
    AF.SetPoint(font, "TOPLEFT", auraPane, 15, -150)
    font:SetItems(AF.LSM_GetFontDropdownItems())
    font:SetOnSelect(function(value)
        SetSharedDebuffDurationArrayValue("font", 1, value)
    end)

    local outline = AF.CreateDropdown(auraPane, 150)
    outline:SetLabel(L["Outline"])
    AF.SetPoint(outline, "TOPLEFT", font, 185, 0)
    outline:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    outline:SetOnSelect(function(value)
        SetSharedDebuffDurationArrayValue("font", 3, value)
    end)

    local size = AF.CreateSlider(auraPane, L["Size"], 150, 5, 50, 1, nil, true)
    AF.SetPoint(size, "TOPLEFT", font, "BOTTOMLEFT", 0, -30)
    size:SetAfterValueChanged(function(value)
        SetSharedDebuffDurationArrayValue("font", 2, value)
    end)

    local shadow = AF.CreateCheckButton(auraPane, L["Shadow"])
    AF.SetPoint(shadow, "LEFT", size, 185, 0)
    shadow:SetOnCheck(function(checked)
        SetSharedDebuffDurationArrayValue("font", 4, checked)
    end)

    local anchorPoint = AF.CreateDropdown(auraPane, 150)
    anchorPoint:SetLabel(L["Anchor Point"])
    AF.SetPoint(anchorPoint, "TOPLEFT", size, "BOTTOMLEFT", 0, -40)
    anchorPoint:SetItems(AF.GetDropdownItems_AnchorPoint())
    anchorPoint:SetOnSelect(function(value)
        SetSharedDebuffDurationArrayValue("position", 1, value)
    end)

    local relativePoint = AF.CreateDropdown(auraPane, 150)
    relativePoint:SetLabel(L["Relative Point"])
    AF.SetPoint(relativePoint, "TOPLEFT", anchorPoint, 185, 0)
    relativePoint:SetItems(AF.GetDropdownItems_AnchorPoint())
    relativePoint:SetOnSelect(function(value)
        SetSharedDebuffDurationArrayValue("position", 2, value)
    end)

    local xOffset = AF.CreateSlider(auraPane, L["X Offset"], 150, -100, 100, 0.5, nil, true)
    AF.SetPoint(xOffset, "TOPLEFT", anchorPoint, "BOTTOMLEFT", 0, -25)
    xOffset:SetAfterValueChanged(function(value)
        SetSharedDebuffDurationArrayValue("position", 3, value)
    end)

    local yOffset = AF.CreateSlider(auraPane, L["Y Offset"], 150, -100, 100, 0.5, nil, true)
    AF.SetPoint(yOffset, "TOPLEFT", xOffset, 185, 0)
    yOffset:SetAfterValueChanged(function(value)
        SetSharedDebuffDurationArrayValue("position", 4, value)
    end)

    local function UpdateDurationWidgets()
        AF.SetEnabled(durationEnabled:GetChecked(), normalColor, font, outline, size, shadow,
            anchorPoint, relativePoint, xOffset, yOffset)
    end

    durationEnabled:SetOnCheck(function(checked)
        SetSharedDebuffDurationValue("enabled", checked)
        UpdateDurationWidgets()
    end)

    function nameplatesPanel.Load()
        local config = NP.config
        local durationConfig = config.hostile_npc.debuffs.durationText

        enabled:SetChecked(config.enabled)
        enabled:SetTextColor(config.enabled and "softlime" or "firebrick")
        width:SetValue(config.hostile_npc.healthBar.width)
        height:SetValue(config.hostile_npc.healthBar.height)
        nameText:SetChecked(IsIndicatorEnabledForAnyPlateType("nameText"))
        castBar:SetChecked(IsIndicatorEnabledForAnyPlateType("castBar"))
        debuffs:SetChecked(IsIndicatorEnabledForAnyPlateType("debuffs"))
        targetIndicator:SetChecked(IsIndicatorEnabledForAnyPlateType("targetIndicator"))

        cooldownStyle:SetSelectedValue(config.hostile_npc.debuffs.cooldownStyle)
        durationEnabled:SetChecked(IsDebuffDurationEnabledForAnyPlateType())
        normalColor:SetColor(durationConfig.color.normal)
        font:SetSelectedValue(durationConfig.font[1])
        outline:SetSelectedValue(durationConfig.font[3])
        size:SetValue(durationConfig.font[2])
        shadow:SetChecked(durationConfig.font[4])
        anchorPoint:SetSelectedValue(durationConfig.position[1])
        relativePoint:SetSelectedValue(durationConfig.position[2])
        xOffset:SetValue(durationConfig.position[3])
        yOffset:SetValue(durationConfig.position[4])
        UpdateDurationWidgets()
    end

    sectionSwitch:SetSelectedValue("general")
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
