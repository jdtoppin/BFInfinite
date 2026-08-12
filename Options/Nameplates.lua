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

local PLATE_TYPE_GROUPS = {
    hostile = {
        "hostile_npc",
        "hostile_player",
    },
    friendly = {
        "friendly_npc",
        "friendly_player",
    },
}

local SEMANTIC_COLOR_CATEGORIES = {
    {key = "boss", label = "Boss"},
    {key = "lieutenant", label = "Lieutenant / Miniboss"},
    {key = "caster", label = "Caster"},
    {key = "default", label = "Default / Melee"},
}

local THREAT_STATE_COLOR_CATEGORIES = {
    {key = "warning", label = "Warning / Aggro"},
    {key = "transition", label = "Transition"},
    {key = "safe", label = "Safe"},
    {key = "offTank", label = "Off-Tank"},
}

local nameplatesPanel
local RefreshNameplatePreviews = AF.noop

local function UpdateNameplates()
    AF.Fire("BFI_UpdateModule", "nameplates")
    RefreshNameplatePreviews()
end

local function SetSharedHealthBarValue(key, value)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].healthBar[key] = value
    end
    UpdateNameplates()
end

local function GetSemanticColorConfig()
    return NP.config.hostile_npc.healthBar.semanticColor
end

local function SetSemanticColorEnabled(key, enabled)
    GetSemanticColorConfig()[key].enabled = enabled
    UpdateNameplates()
end

local function SetSemanticColor(key, r, g, b)
    AF.FillColorTable(
        GetSemanticColorConfig()[key].rgb,
        r,
        g,
        b
    )
    UpdateNameplates()
end

local function SetSharedCastValue(key, value)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].castBar[key] = value
    end
    UpdateNameplates()
end

local function SetSharedCastSectionValue(section, key, value)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].castBar[section][key] = value
    end
    UpdateNameplates()
end

local function GetSharedCastColorTables(key, section)
    local colors = {}
    for _, plateType in ipairs(PLATE_TYPES) do
        local castConfig = NP.config[plateType].castBar
        colors[#colors + 1] = section
            and castConfig[section][key]
            or castConfig[key]
    end
    return colors
end

local function SetSharedCastColor(
    key,
    section,
    r,
    g,
    b,
    a,
    preserveAlpha
)
    for _, color in ipairs(GetSharedCastColorTables(key, section)) do
        AF.FillColorTable(
            color,
            r,
            g,
            b,
            preserveAlpha and color[4] or a
        )
    end
    UpdateNameplates()
end

local function SetSharedCastFontValue(index, value)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].castBar.spellTargetText.font[index] = value
    end
    UpdateNameplates()
end

local function SetSharedCastArrayValue(
    section,
    key,
    index,
    value
)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].castBar[section][key][index] = value
    end
    UpdateNameplates()
end

local function SetSharedIndicatorEnabled(indicator, enabled)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType][indicator].enabled = enabled
    end
    UpdateNameplates()
end

local function SetSharedNamePlacement(placement)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType].nameText.placement = placement
    end
    UpdateNameplates()
end

local function SetHostileThreatValue(key, value)
    NP.config.hostile_npc.healthBar.threatGlow[key] = value
    UpdateNameplates()
end

local function SetHostileThreatColor(r, g, b)
    local color =
        NP.config.hostile_npc.healthBar.threatGlow.color
    AF.FillColorTable(color, r, g, b, color[4])
    UpdateNameplates()
end

local function GetThreatStateColorConfig()
    return NP.config.hostile_npc.healthBar.threatGlow.stateColors
end

local function SetThreatStateColorsEnabled(enabled)
    GetThreatStateColorConfig().enabled = enabled
    UpdateNameplates()
end

local function SetThreatStateColorEnabled(key, enabled)
    GetThreatStateColorConfig()[key].enabled = enabled
    UpdateNameplates()
end

local function SetThreatStateColor(key, r, g, b)
    AF.FillColorTable(
        GetThreatStateColorConfig()[key].rgb,
        r,
        g,
        b
    )
    UpdateNameplates()
end

local function SetScopeIndicatorEnabled(
    scope,
    indicator,
    enabled
)
    for _, plateType in ipairs(PLATE_TYPE_GROUPS[scope]) do
        NP.config[plateType][indicator].enabled = enabled
    end
    UpdateNameplates()
end

local function GetTargetStateConfig(scope, state)
    local plateTypes = PLATE_TYPE_GROUPS[scope]
    return NP.config[plateTypes[1]].targetIndicator[state]
end

local function SetTargetStateValue(
    scope,
    state,
    key,
    value
)
    for _, plateType in ipairs(PLATE_TYPE_GROUPS[scope]) do
        NP.config[plateType].targetIndicator[state][key] = value
    end
    UpdateNameplates()
end

local function SetTargetStateNestedValue(
    scope,
    state,
    section,
    key,
    value
)
    for _, plateType in ipairs(PLATE_TYPE_GROUPS[scope]) do
        NP.config[plateType].targetIndicator[state][section][key] =
            value
    end
    UpdateNameplates()
end

local function SetTargetStateColor(
    scope,
    state,
    section,
    r,
    g,
    b,
    a
)
    for _, plateType in ipairs(PLATE_TYPE_GROUPS[scope]) do
        local indicator = NP.config[plateType].targetIndicator
        local color = indicator[state][section].color
        AF.FillColorTable(color, r, g, b, a)
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
        local color =
            NP.config[plateType].debuffs.durationText.color.normal
        AF.FillColorTable(color, r, g, b, color[4])
    end
    UpdateNameplates()
end

local function PreviewColorTables(
    picker,
    colorTables,
    r,
    g,
    b,
    a,
    preserveAlpha
)
    -- AF clears picker ownership before restoring the widget on cancel. The
    -- dedicated cancel callback reloads every saved per-type value.
    if not AF.IsColorPickerOpen(picker) then
        return
    end

    local originals = {}
    for i, color in ipairs(colorTables) do
        originals[i] = {
            color[1],
            color[2],
            color[3],
            color[4],
        }
        local previewAlpha = a
        if preserveAlpha then
            previewAlpha = color[4]
        end
        AF.FillColorTable(
            color,
            r,
            g,
            b,
            previewAlpha
        )
    end

    -- Apply a live preview from a copied module configuration, then restore
    -- the saved tables. Confirmation persists the selected color separately.
    local success, result = pcall(UpdateNameplates)
    for i, color in ipairs(colorTables) do
        AF.FillColorTable(color, unpack(originals[i]))
    end

    if not success then
        error(result, 0)
    end
    return true
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

local function IsIndicatorEnabledForScope(scope, indicator)
    for _, plateType in ipairs(PLATE_TYPE_GROUPS[scope]) do
        if NP.config[plateType][indicator].enabled then
            return true
        end
    end
    return false
end

local function IsHealthBarEnabledForScope(scope)
    return IsIndicatorEnabledForScope(scope, "healthBar")
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

    local contentPane = AF.CreateFrame(nameplatesPanel)
    AF.SetPoint(contentPane, "TOPLEFT", nameplatesPanel, 15, -15)
    AF.SetPoint(contentPane, "BOTTOMRIGHT", nameplatesPanel, -15, 15)

    local sectionOrder = {
        "general",
        "colors",
        "casts",
        "target",
        "threat",
        "auras",
    }
    local sectionPanes = {
        general = {},
        colors = {},
        casts = {},
        target = {},
        threat = {},
        auras = {},
    }
    local sectionCleanup = {}

    local sectionList = AF.CreateScrollList(
        contentPane,
        nil,
        0,
        0,
        28,
        20,
        -1
    )
    sectionList:SetPoint("TOPLEFT")
    AF.SetWidth(sectionList, 150)

    local scrollSettings = AF.CreateScrollFrame(
        contentPane,
        nil,
        nil,
        nil,
        "none",
        "none"
    )
    scrollSettings.scrollBar:SetBackdropBorderColor(
        AF.GetColorRGB("border")
    )
    AF.SetPoint(
        scrollSettings,
        "TOPLEFT",
        sectionList,
        "TOPRIGHT",
        15,
        0
    )
    AF.SetPoint(scrollSettings, "BOTTOM", sectionList)
    AF.SetPoint(scrollSettings, "RIGHT")
    scrollSettings:SetScrollStep(50)
    AF.ApplyCombatProtectionToFrame(
        scrollSettings.scrollContent,
        0,
        0,
        0,
        0
    )

    local function CreateSectionPane(
        section,
        title,
        height,
        titleColor
    )
        local pane = AF.CreateBorderedFrame(
            scrollSettings.scrollContent,
            nil,
            nil,
            height
        )
        pane:Hide()
        sectionPanes[section][#sectionPanes[section] + 1] = pane

        if title then
            local paneTitle = AF.CreateFontString(
                pane,
                title,
                titleColor or "BFI"
            )
            AF.SetPoint(paneTitle, "TOPLEFT", pane, 15, -10)
        end

        return pane
    end

    local selectedSection
    local function ShowSection(button)
        if selectedSection and sectionCleanup[selectedSection] then
            sectionCleanup[selectedSection]()
        end

        for _, section in ipairs(sectionOrder) do
            for _, pane in ipairs(sectionPanes[section]) do
                pane:Hide()
                AF.ClearPoints(pane)
            end
        end

        selectedSection = button.id
        local panes = sectionPanes[selectedSection]
        local heights = {}
        local last
        for _, pane in ipairs(panes) do
            if last then
                AF.SetPoint(
                    pane,
                    "TOPLEFT",
                    last,
                    "BOTTOMLEFT",
                    0,
                    -10
                )
            else
                AF.SetPoint(
                    pane,
                    "TOPLEFT",
                    scrollSettings.scrollContent
                )
            end
            AF.SetPoint(
                pane,
                "RIGHT",
                scrollSettings.scrollContent
            )
            pane:Show()
            heights[#heights + 1] = pane._height or 0
            last = pane
        end

        scrollSettings:SetContentHeights(heights, 10)
        C_Timer.After(0, function()
            AF.RePoint(scrollSettings)
        end)
        RefreshNameplatePreviews()
    end

    local sectionItems = {
        {text = L["General"], value = "general"},
        {text = L["Colors"], value = "colors"},
        {text = L["Casts"], value = "casts"},
        {text = L["Target"], value = "target"},
        {text = L["Threat"], value = "threat"},
        {text = L["Auras"], value = "auras"},
    }
    local sectionButtons = {}
    for _, item in ipairs(sectionItems) do
        local button = AF.CreateButton(
            sectionList,
            item.text,
            "BFI_transparent",
            nil,
            nil,
            nil,
            "none",
            ""
        )
        button.id = item.value
        button:EnablePushEffect(false)
        button:SetTextJustifyH("LEFT")
        sectionButtons[#sectionButtons + 1] = button
    end
    sectionList:SetWidgets(sectionButtons)
    AF.CreateButtonGroup(sectionButtons, ShowSection)

    --------------------------------------------------
    -- module
    --------------------------------------------------
    local modulePane = CreateSectionPane(
        "general",
        L["Nameplates"],
        100
    )

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
    local sharedPane = CreateSectionPane(
        "general",
        L["Shared Nameplate Settings"],
        255
    )

    local sharedNotice = AF.CreateFontString(sharedPane, L["Shared width, height, and feature changes apply to hostile and friendly NPC and player nameplates."], "gray")
    AF.SetPoint(sharedNotice, "TOPLEFT", sharedPane, 15, -30)
    AF.SetPoint(sharedNotice, "TOPRIGHT", sharedPane, -15, -30)
    sharedNotice:SetJustifyH("LEFT")
    sharedNotice:SetWordWrap(true)

    local width = AF.CreateSlider(
        sharedPane,
        L["Width"],
        165,
        40,
        300,
        1,
        nil,
        true
    )
    AF.SetPoint(width, "TOPLEFT", sharedPane, 15, -105)
    width:SetAfterValueChanged(function(value)
        SetSharedHealthBarValue("width", value)
    end)

    local height = AF.CreateSlider(
        sharedPane,
        L["Height"],
        165,
        4,
        40,
        1,
        nil,
        true
    )
    AF.SetPoint(height, "TOPLEFT", sharedPane, 200, -105)
    height:SetAfterValueChanged(function(value)
        SetSharedHealthBarValue("height", value)
    end)

    local nameText = AF.CreateCheckButton(sharedPane, L["Name"])
    AF.SetPoint(nameText, "TOPLEFT", sharedPane, 15, -165)
    nameText:SetOnCheck(function(checked)
        SetSharedIndicatorEnabled("nameText", checked)
    end)

    local castBar = AF.CreateCheckButton(sharedPane, L["castBar"])
    AF.SetPoint(castBar, "TOPLEFT", sharedPane, 200, -165)
    castBar:SetOnCheck(function(checked)
        SetSharedIndicatorEnabled("castBar", checked)
    end)

    local debuffs = AF.CreateCheckButton(sharedPane, L["debuffs"])
    AF.SetPoint(debuffs, "TOPLEFT", sharedPane, 15, -200)
    debuffs:SetOnCheck(function(checked)
        SetSharedIndicatorEnabled("debuffs", checked)
    end)

    local namePlacement = AF.CreateDropdown(sharedPane, 165)
    namePlacement:SetLabel(L["Name Placement"])
    AF.SetPoint(namePlacement, "TOPLEFT", sharedPane, 200, -215)
    namePlacement:SetItems({
        {text = L["Outside Health Bar"], value = "outside"},
        {text = L["Inside Health Bar"], value = "inside"},
    })
    namePlacement:SetOnSelect(function(value)
        SetSharedNamePlacement(value)
    end)

    --------------------------------------------------
    -- compatibility
    --------------------------------------------------
    local compatibilityPane = CreateSectionPane(
        "general",
        L["Compatibility"],
        150,
        "sand"
    )

    local compatibilityNotice = AF.CreateFontString(
        compatibilityPane,
        L["Native special and quest widgets remain Blizzard-owned. When a BFI health bar is visible, its protected click target matches the bar exactly: inside text shares the target and outside text is visual-only. Name-only plates use a bounded bar-width target because restricted name text cannot be measured. Changes made during combat may be deferred until combat ends."],
        "sand"
    )
    AF.SetPoint(compatibilityNotice, "TOPLEFT", compatibilityPane, 15, -30)
    AF.SetPoint(compatibilityNotice, "TOPRIGHT", compatibilityPane, -15, -30)
    compatibilityNotice:SetJustifyH("LEFT")
    compatibilityNotice:SetWordWrap(true)

    --------------------------------------------------
    -- threat
    --------------------------------------------------
    local threatPane = CreateSectionPane(
        "threat",
        L["Threat Colors"],
        165
    )

    local threatNotice = AF.CreateFontString(
        threatPane,
        L["Threat colors apply only to hostile NPC nameplates. BFI classifies the public qualitative states for your role and can distinguish another tank holding the unit. Whenever Retail restricts a query, AbstractFramework falls back to Blizzard's native carrier without inspecting the protected value."],
        "gray"
    )
    AF.SetPoint(threatNotice, "TOPLEFT", threatPane, 15, -30)
    AF.SetPoint(threatNotice, "TOPRIGHT", threatPane, -15, -30)
    threatNotice:SetJustifyH("LEFT")
    threatNotice:SetWordWrap(true)

    local threatPreviewPane = CreateSectionPane(
        "threat",
        L["Quick Reference"],
        300
    )
    local threatPreview =
        NP.CreateThreatOptionsPreview(threatPreviewPane)

    local UpdateThreatWidgets
    local CancelThreatColorPickers
    local threatPresentationPane = CreateSectionPane(
        "threat",
        L["Presentation"],
        145
    )
    local threatGeometryPane = CreateSectionPane(
        "threat",
        L["Border + Glow"],
        145
    )
    local threatOpacityPane = CreateSectionPane(
        "threat",
        L["Opacity"],
        145
    )
    local threatFallbackPane = CreateSectionPane(
        "threat",
        L["Native / Restricted Fallback"],
        125
    )
    local threatStateColorPane = CreateSectionPane(
        "threat",
        L["Role-Aware State Colors"],
        310
    )
    local threatScopePane = CreateSectionPane(
        "threat",
        L["Scope"],
        125
    )

    local threatEnabled = AF.CreateCheckButton(
        threatPresentationPane,
        L["Enable Threat Colors"]
    )
    AF.SetPoint(
        threatEnabled,
        "TOPLEFT",
        threatPresentationPane,
        15,
        -45
    )
    threatEnabled:SetOnCheck(function(checked)
        if not checked and CancelThreatColorPickers then
            CancelThreatColorPickers()
        end
        SetHostileThreatValue("enabled", checked)
        UpdateThreatWidgets()
    end)

    local threatBorder = AF.CreateCheckButton(
        threatPresentationPane,
        L["Border"]
    )
    AF.SetPoint(
        threatBorder,
        "TOPLEFT",
        threatPresentationPane,
        15,
        -80
    )
    threatBorder:SetOnCheck(function(checked)
        SetHostileThreatValue("border", checked)
        UpdateThreatWidgets()
    end)

    local threatGlow = AF.CreateCheckButton(
        threatPresentationPane,
        L["Glow"]
    )
    AF.SetPoint(
        threatGlow,
        "TOPLEFT",
        threatPresentationPane,
        200,
        -80
    )
    threatGlow:SetOnCheck(function(checked)
        SetHostileThreatValue("glow", checked)
        UpdateThreatWidgets()
    end)

    local threatBar = AF.CreateCheckButton(
        threatPresentationPane,
        L["Full-Bar Overlay"]
    )
    AF.SetPoint(
        threatBar,
        "TOPLEFT",
        threatPresentationPane,
        15,
        -115
    )
    threatBar:SetOnCheck(function(checked)
        SetHostileThreatValue("bar", checked)
        UpdateThreatWidgets()
    end)

    local threatName = AF.CreateCheckButton(
        threatPresentationPane,
        L["Name Text"]
    )
    AF.SetPoint(
        threatName,
        "TOPLEFT",
        threatPresentationPane,
        200,
        -115
    )
    threatName:SetOnCheck(function(checked)
        SetHostileThreatValue("name", checked)
        UpdateThreatWidgets()
    end)

    local threatBorderSize = AF.CreateSlider(
        threatGeometryPane,
        L["Border Thickness"],
        165,
        1,
        12,
        1,
        nil,
        true
    )
    AF.SetPoint(
        threatBorderSize,
        "TOPLEFT",
        threatGeometryPane,
        15,
        -50
    )
    threatBorderSize:SetAfterValueChanged(function(value)
        SetHostileThreatValue("borderSize", value)
    end)

    local threatGlowSize = AF.CreateSlider(
        threatGeometryPane,
        L["Glow Thickness"],
        165,
        1,
        16,
        1,
        nil,
        true
    )
    AF.SetPoint(
        threatGlowSize,
        "TOPLEFT",
        threatGeometryPane,
        200,
        -50
    )
    threatGlowSize:SetAfterValueChanged(function(value)
        SetHostileThreatValue("size", value)
    end)

    local threatOutset = AF.CreateSlider(
        threatGeometryPane,
        L["Glow Outset"],
        165,
        0,
        16,
        1,
        nil,
        true
    )
    AF.SetPoint(
        threatOutset,
        "TOPLEFT",
        threatGeometryPane,
        15,
        -110
    )
    threatOutset:SetAfterValueChanged(function(value)
        SetHostileThreatValue("outset", value)
    end)

    local threatBorderAlpha = AF.CreateSlider(
        threatOpacityPane,
        L["Border Opacity"],
        165,
        0.1,
        1,
        0.05,
        true,
        true
    )
    AF.SetPoint(
        threatBorderAlpha,
        "TOPLEFT",
        threatOpacityPane,
        15,
        -50
    )
    threatBorderAlpha:SetAfterValueChanged(function(value)
        SetHostileThreatValue("borderAlpha", value)
    end)

    local threatGlowAlpha = AF.CreateSlider(
        threatOpacityPane,
        L["Glow Opacity"],
        165,
        0.1,
        1,
        0.05,
        true,
        true
    )
    AF.SetPoint(
        threatGlowAlpha,
        "TOPLEFT",
        threatOpacityPane,
        200,
        -50
    )
    threatGlowAlpha:SetAfterValueChanged(function(value)
        SetHostileThreatValue("glowAlpha", value)
    end)

    local threatBarAlpha = AF.CreateSlider(
        threatOpacityPane,
        L["Bar Overlay Opacity"],
        165,
        0.1,
        1,
        0.05,
        true,
        true
    )
    AF.SetPoint(
        threatBarAlpha,
        "TOPLEFT",
        threatOpacityPane,
        15,
        -110
    )
    threatBarAlpha:SetAfterValueChanged(function(value)
        SetHostileThreatValue("barAlpha", value)
    end)

    local threatNameAlpha = AF.CreateSlider(
        threatOpacityPane,
        L["Name Opacity"],
        165,
        0.1,
        1,
        0.05,
        true,
        true
    )
    AF.SetPoint(
        threatNameAlpha,
        "TOPLEFT",
        threatOpacityPane,
        200,
        -110
    )
    threatNameAlpha:SetAfterValueChanged(function(value)
        SetHostileThreatValue("nameAlpha", value)
    end)

    local threatUseCustomColor = AF.CreateCheckButton(
        threatFallbackPane,
        L["Use Custom Fallback Color"]
    )
    AF.SetPoint(
        threatUseCustomColor,
        "TOPLEFT",
        threatFallbackPane,
        15,
        -45
    )

    local threatColor = AF.CreateColorPicker(
        threatFallbackPane,
        L["Fallback Color"]
    )
    AF.SetPoint(
        threatColor,
        "TOPLEFT",
        threatFallbackPane,
        200,
        -45
    )

    local threatColorNotice = AF.CreateFontString(
        threatFallbackPane,
        L["Used when role-aware classification is unavailable or disabled. Blizzard's native signal controls visibility."],
        "gray"
    )
    AF.SetPoint(
        threatColorNotice,
        "TOPLEFT",
        threatFallbackPane,
        15,
        -75
    )
    AF.SetPoint(
        threatColorNotice,
        "TOPRIGHT",
        threatFallbackPane,
        -15,
        -75
    )
    threatColorNotice:SetJustifyH("LEFT")
    threatColorNotice:SetWordWrap(true)

    local threatColorPreviewed
    threatUseCustomColor:SetOnCheck(function(checked)
        AF.CancelColorPicker(threatColor)
        SetHostileThreatValue("useCustomColor", checked)
        UpdateThreatWidgets()
    end)
    threatColor:SetOnChange(function(r, g, b, a)
        local color =
            NP.config.hostile_npc.healthBar.threatGlow.color
        threatColorPreviewed = PreviewColorTables(
            threatColor,
            {color},
            r,
            g,
            b,
            a,
            true
        ) or threatColorPreviewed
    end)
    threatColor:SetOnConfirm(function(r, g, b)
        SetHostileThreatColor(r, g, b)
        threatColorPreviewed = nil
    end)
    threatColor:SetOnAccept(function()
        if threatColorPreviewed then
            UpdateNameplates()
            threatColorPreviewed = nil
        end
    end)
    local function ResetThreatColorPreview()
        threatColorPreviewed = nil
        UpdateNameplates()
    end
    threatColor:SetOnCancel(ResetThreatColorPreview)
    threatColor:SetOnDiscard(ResetThreatColorPreview)

    local threatStateWidgets = {}
    local threatStateColorsEnabled = AF.CreateCheckButton(
        threatStateColorPane,
        L["Use Role-Aware State Colors"]
    )
    AF.SetPoint(
        threatStateColorsEnabled,
        "TOPLEFT",
        threatStateColorPane,
        15,
        -45
    )

    local threatStateNotice = AF.CreateFontString(
        threatStateColorPane,
        L["Tank: Safe means you hold aggro; Off-Tank means another tank or group pet does. Damage / Healing: Safe means you do not have aggro. Transition marks intermediate threat."],
        "gray"
    )
    AF.SetPoint(
        threatStateNotice,
        "TOPLEFT",
        threatStateColorPane,
        15,
        -75
    )
    AF.SetPoint(
        threatStateNotice,
        "TOPRIGHT",
        threatStateColorPane,
        -15,
        -75
    )
    threatStateNotice:SetJustifyH("LEFT")
    threatStateNotice:SetWordWrap(true)

    local function CreateThreatStateColorRow(info, index)
        local key = info.key
        local y = -130 - (index - 1) * 45
        local enabledButton = AF.CreateCheckButton(
            threatStateColorPane,
            L[info.label]
        )
        AF.SetPoint(
            enabledButton,
            "TOPLEFT",
            threatStateColorPane,
            15,
            y
        )

        local picker = AF.CreateColorPicker(
            threatStateColorPane,
            L["Color"]
        )
        AF.SetPoint(
            picker,
            "TOPLEFT",
            threatStateColorPane,
            200,
            y
        )

        local colorPreviewed
        enabledButton:SetOnCheck(function(checked)
            AF.CancelColorPicker(picker)
            SetThreatStateColorEnabled(key, checked)
            UpdateThreatWidgets()
        end)
        picker:SetOnChange(function(r, g, b, a)
            local color = GetThreatStateColorConfig()[key].rgb
            colorPreviewed = PreviewColorTables(
                picker,
                {color},
                r,
                g,
                b,
                a,
                true
            ) or colorPreviewed
        end)
        picker:SetOnConfirm(function(r, g, b)
            SetThreatStateColor(key, r, g, b)
            colorPreviewed = nil
        end)
        picker:SetOnAccept(function()
            if colorPreviewed then
                UpdateNameplates()
                colorPreviewed = nil
            end
        end)

        local function ResetStateColorPreview()
            colorPreviewed = nil
            UpdateNameplates()
        end
        picker:SetOnCancel(ResetStateColorPreview)
        picker:SetOnDiscard(ResetStateColorPreview)

        threatStateWidgets[#threatStateWidgets + 1] = {
            key = key,
            enabledButton = enabledButton,
            picker = picker,
        }
    end

    for index, info in ipairs(THREAT_STATE_COLOR_CATEGORIES) do
        CreateThreatStateColorRow(info, index)
    end

    threatStateColorsEnabled:SetOnCheck(function(checked)
        for _, widgets in ipairs(threatStateWidgets) do
            AF.CancelColorPicker(widgets.picker)
        end
        SetThreatStateColorsEnabled(checked)
        UpdateThreatWidgets()
    end)

    CancelThreatColorPickers = function()
        AF.CancelColorPicker(threatColor)
        for _, widgets in ipairs(threatStateWidgets) do
            AF.CancelColorPicker(widgets.picker)
        end
    end

    local threatCombatOnly = AF.CreateCheckButton(
        threatScopePane,
        L["Combat Only"]
    )
    AF.SetPoint(
        threatCombatOnly,
        "TOPLEFT",
        threatScopePane,
        15,
        -45
    )
    threatCombatOnly:SetOnCheck(function(checked)
        SetHostileThreatValue("combatOnly", checked)
    end)

    local threatInstancesOnly = AF.CreateCheckButton(
        threatScopePane,
        L["Instances Only"]
    )
    AF.SetPoint(
        threatInstancesOnly,
        "TOPLEFT",
        threatScopePane,
        200,
        -45
    )
    threatInstancesOnly:SetOnCheck(function(checked)
        SetHostileThreatValue("instancesOnly", checked)
    end)

    local threatTankOnly = AF.CreateCheckButton(
        threatScopePane,
        L["Tank Role Only"]
    )
    AF.SetPoint(
        threatTankOnly,
        "TOPLEFT",
        threatScopePane,
        15,
        -80
    )
    threatTankOnly:SetOnCheck(function(checked)
        SetHostileThreatValue("tankOnly", checked)
    end)

    UpdateThreatWidgets = function()
        local config =
            NP.config.hostile_npc.healthBar.threatGlow
        local stateColors = config.stateColors

        threatEnabled:SetChecked(config.enabled)
        threatBorder:SetChecked(config.border)
        threatGlow:SetChecked(config.glow)
        threatBar:SetChecked(config.bar)
        threatName:SetChecked(config.name)
        threatBorderSize:SetValue(config.borderSize)
        threatGlowSize:SetValue(config.size)
        threatOutset:SetValue(config.outset)
        threatBorderAlpha:SetValue(config.borderAlpha)
        threatGlowAlpha:SetValue(config.glowAlpha)
        threatBarAlpha:SetValue(config.barAlpha)
        threatNameAlpha:SetValue(config.nameAlpha)
        threatUseCustomColor:SetChecked(config.useCustomColor)
        if not AF.IsColorPickerOpen(threatColor) then
            threatColor:SetColor(config.color)
        end
        threatStateColorsEnabled:SetChecked(stateColors.enabled)
        for _, widgets in ipairs(threatStateWidgets) do
            local state = stateColors[widgets.key]
            widgets.enabledButton:SetChecked(state.enabled)
            if not AF.IsColorPickerOpen(widgets.picker) then
                widgets.picker:SetColor(state.rgb)
            end
            AF.SetEnabled(
                config.enabled and stateColors.enabled,
                widgets.enabledButton
            )
            AF.SetEnabled(
                config.enabled
                    and stateColors.enabled
                    and state.enabled,
                widgets.picker
            )
        end
        threatCombatOnly:SetChecked(config.combatOnly)
        threatInstancesOnly:SetChecked(config.instancesOnly)
        threatTankOnly:SetChecked(config.tankOnly)

        AF.SetEnabled(
            config.enabled,
            threatBorder,
            threatGlow,
            threatBar,
            threatName,
            threatUseCustomColor,
            threatStateColorsEnabled,
            threatCombatOnly,
            threatInstancesOnly,
            threatTankOnly
        )
        AF.SetEnabled(
            config.enabled and config.border,
            threatBorderSize,
            threatBorderAlpha
        )
        AF.SetEnabled(
            config.enabled and config.glow,
            threatGlowSize,
            threatOutset,
            threatGlowAlpha
        )
        AF.SetEnabled(
            config.enabled and config.bar,
            threatBarAlpha
        )
        AF.SetEnabled(
            config.enabled and config.name,
            threatNameAlpha
        )
        AF.SetEnabled(
            config.enabled and config.useCustomColor,
            threatColor
        )

        threatPreview:Refresh(
            NP.config.hostile_npc.healthBar,
            NP.config.hostile_npc.nameText.enabled
        )
    end

    --------------------------------------------------
    -- hostile NPC semantic colors
    --------------------------------------------------
    local colorsPane = CreateSectionPane(
        "colors",
        L["Dungeon Priority Colors"],
        190
    )

    local colorsNotice = AF.CreateFontString(
        colorsPane,
        L["These colors apply only to hostile NPC health bars. No NPC names or IDs are used."],
        "gray"
    )
    AF.SetPoint(colorsNotice, "TOPLEFT", colorsPane, 15, -30)
    AF.SetPoint(colorsNotice, "TOPRIGHT", colorsPane, -15, -30)
    colorsNotice:SetJustifyH("LEFT")
    colorsNotice:SetWordWrap(true)

    local fallbackNotice = AF.CreateFontString(
        colorsPane,
        L["Priority: Boss > Lieutenant / Miniboss > Caster > Default / Melee. Disabled or unavailable categories fall through; Blizzard's selection color is the final fallback."],
        "sand"
    )
    AF.SetPoint(
        fallbackNotice,
        "TOPLEFT",
        colorsNotice,
        "BOTTOMLEFT",
        0,
        -8
    )
    AF.SetPoint(
        fallbackNotice,
        "TOPRIGHT",
        colorsNotice,
        "BOTTOMRIGHT",
        0,
        -8
    )
    fallbackNotice:SetJustifyH("LEFT")
    fallbackNotice:SetWordWrap(true)

    local semanticPreviewPane = CreateSectionPane(
        "colors",
        L["Quick Reference"],
        195
    )
    local semanticPreview =
        NP.CreateSemanticColorOptionsPreview(
            semanticPreviewPane
        )

    local colorSettingsPane = CreateSectionPane(
        "colors",
        L["Colors"],
        225
    )
    local semanticColorWidgets = {}

    local function CreateSemanticColorRow(info, index)
        local key = info.key
        local enabledButton = AF.CreateCheckButton(
            colorSettingsPane,
            L[info.label]
        )
        AF.SetPoint(
            enabledButton,
            "TOPLEFT",
            colorSettingsPane,
            15,
            -45 - (index - 1) * 45
        )

        local picker = AF.CreateColorPicker(
            colorSettingsPane,
            L["Color"]
        )
        AF.SetPoint(
            picker,
            "TOPLEFT",
            colorSettingsPane,
            200,
            -45 - (index - 1) * 45
        )

        local colorPreviewed

        enabledButton:SetOnCheck(function(checked)
            AF.CancelColorPicker(picker)
            SetSemanticColorEnabled(key, checked)
            AF.SetEnabled(checked, picker)
        end)

        picker:SetOnChange(function(r, g, b, a)
            local color = GetSemanticColorConfig()[key].rgb
            colorPreviewed = PreviewColorTables(
                picker,
                {color},
                r,
                g,
                b,
                a,
                true
            ) or colorPreviewed
        end)
        picker:SetOnConfirm(function(r, g, b)
            SetSemanticColor(key, r, g, b)
            colorPreviewed = nil
        end)
        picker:SetOnAccept(function()
            if colorPreviewed then
                UpdateNameplates()
                colorPreviewed = nil
            end
        end)

        local function ResetColorPreview()
            colorPreviewed = nil
            UpdateNameplates()
        end
        picker:SetOnCancel(ResetColorPreview)
        picker:SetOnDiscard(ResetColorPreview)

        semanticColorWidgets[#semanticColorWidgets + 1] = {
            key = key,
            enabledButton = enabledButton,
            picker = picker,
        }
    end

    for index, info in ipairs(SEMANTIC_COLOR_CATEGORIES) do
        CreateSemanticColorRow(info, index)
    end

    local function UpdateSemanticColorWidgets()
        local semanticColor = GetSemanticColorConfig()
        for _, widgets in ipairs(semanticColorWidgets) do
            local category = semanticColor[widgets.key]
            widgets.enabledButton:SetChecked(category.enabled)
            if not AF.IsColorPickerOpen(widgets.picker) then
                widgets.picker:SetColor(category.rgb)
            end
            AF.SetEnabled(category.enabled, widgets.picker)
        end

        semanticPreview:Refresh(
            NP.config.hostile_npc.healthBar
        )
    end

    --------------------------------------------------
    -- cast appearance
    --------------------------------------------------
    local castsPane = CreateSectionPane(
        "casts",
        L["Cast Bar Appearance"],
        170
    )

    local castsNotice = AF.CreateFontString(
        castsPane,
        L["Cast settings apply to every nameplate. Important, not-kickable, and player-targeted indicators use Blizzard secret-safe classifications. Interrupt readiness tracks your primary known interrupt; no enemy spell or NPC lists are used."],
        "gray"
    )
    AF.SetPoint(castsNotice, "TOPLEFT", castsPane, 15, -30)
    AF.SetPoint(castsNotice, "TOPRIGHT", castsPane, -15, -30)
    castsNotice:SetJustifyH("LEFT")
    castsNotice:SetWordWrap(true)

    local castPreviewPane = CreateSectionPane(
        "casts",
        L["Quick Reference"],
        330
    )
    local castPreview =
        NP.CreateCastOptionsPreview(castPreviewPane)

    local UpdateCastWidgets
    local castBasePane = CreateSectionPane(
        "casts",
        L["Size"] .. " / " .. L["Colors"],
        185
    )
    local castInterruptibilityPane = CreateSectionPane(
        "casts",
        L["Color by Interruptibility"],
        105
    )
    local interruptReadyTickPane = CreateSectionPane(
        "casts",
        L["Interrupt Ready Tick"],
        130
    )
    local castHighlightsPane = CreateSectionPane(
        "casts",
        L["Glow"] .. " / " .. L["Highlight Color"],
        140
    )
    local uninterruptibleIconPane = CreateSectionPane(
        "casts",
        L["Not Kickable X"],
        250
    )
    local importantIconPane = CreateSectionPane(
        "casts",
        L["Important Cast Icon"],
        250
    )
    local castContentPane = CreateSectionPane(
        "casts",
        L["Cast Name"],
        90
    )
    local spellTargetPane = CreateSectionPane(
        "casts",
        L["Spell Target Text"],
        185
    )

    local castWidth = AF.CreateSlider(
        castBasePane,
        L["Width"],
        165,
        40,
        300,
        1,
        nil,
        true
    )
    AF.SetPoint(castWidth, "TOPLEFT", castBasePane, 15, -50)
    castWidth:SetAfterValueChanged(function(value)
        SetSharedCastValue("width", value)
    end)

    local castHeight = AF.CreateSlider(
        castBasePane,
        L["Height"],
        165,
        4,
        40,
        1,
        nil,
        true
    )
    AF.SetPoint(castHeight, "TOPLEFT", castBasePane, 200, -50)
    castHeight:SetAfterValueChanged(function(value)
        SetSharedCastValue("height", value)
    end)

    local normalCastColor = AF.CreateColorPicker(
        castBasePane,
        L["Kick Cooling Down / No Kick"]
    )
    AF.SetPoint(
        normalCastColor,
        "TOPLEFT",
        castBasePane,
        15,
        -110
    )

    local interruptibleCastColor = AF.CreateColorPicker(
        castBasePane,
        L["Kick Ready"]
    )
    AF.SetPoint(
        interruptibleCastColor,
        "TOPLEFT",
        castBasePane,
        15,
        -155
    )

    local uninterruptibleCastColor = AF.CreateColorPicker(
        castBasePane,
        L["Not Kickable"]
    )
    AF.SetPoint(
        uninterruptibleCastColor,
        "TOPLEFT",
        castBasePane,
        200,
        -155
    )

    local castColorPickers = {}
    local castColorPreviewed = {}

    local function WireCastColorPicker(
        picker,
        key,
        section,
        preserveAlpha
    )
        castColorPickers[#castColorPickers + 1] = picker

        picker:SetOnChange(function(r, g, b, a)
            castColorPreviewed[picker] = PreviewColorTables(
                picker,
                GetSharedCastColorTables(key, section),
                r,
                g,
                b,
                a,
                preserveAlpha
            ) or castColorPreviewed[picker]
        end)
        picker:SetOnConfirm(function(r, g, b, a)
            SetSharedCastColor(
                key,
                section,
                r,
                g,
                b,
                a,
                preserveAlpha
            )
            castColorPreviewed[picker] = nil
        end)
        picker:SetOnAccept(function()
            if castColorPreviewed[picker] then
                UpdateNameplates()
                castColorPreviewed[picker] = nil
            end
        end)

        local function ResetCastColorPreview()
            castColorPreviewed[picker] = nil
            UpdateNameplates()
        end
        picker:SetOnCancel(ResetCastColorPreview)
        picker:SetOnDiscard(ResetCastColorPreview)
    end

    WireCastColorPicker(
        normalCastColor,
        "color",
        nil,
        true
    )
    WireCastColorPicker(
        interruptibleCastColor,
        "interruptibleColor",
        nil,
        true
    )
    WireCastColorPicker(
        uninterruptibleCastColor,
        "uninterruptibleColor",
        nil,
        true
    )

    local interruptibility = AF.CreateCheckButton(
        castInterruptibilityPane,
        L["Color by Interruptibility"]
    )
    AF.SetPoint(
        interruptibility,
        "TOPLEFT",
        castInterruptibilityPane,
        15,
        -40
    )
    interruptibility:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "interruptibleCheck",
            "enabled",
            checked
        )
        UpdateCastWidgets()
    end)

    local interruptReadiness = AF.CreateCheckButton(
        castInterruptibilityPane,
        L["Use My Interrupt Cooldown"]
    )
    AF.SetPoint(
        interruptReadiness,
        "TOPLEFT",
        castInterruptibilityPane,
        15,
        -70
    )
    interruptReadiness:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "interruptibleCheck",
            "requireUsable",
            checked
        )
        UpdateCastWidgets()
    end)

    local interruptReadyTickHelp = AF.CreateFontString(
        interruptReadyTickPane,
        L["Shows where your primary interrupt becomes ready. The tick is clipped when that happens after the cast ends."],
        "gray"
    )
    AF.SetPoint(
        interruptReadyTickHelp,
        "TOPLEFT",
        interruptReadyTickPane,
        15,
        -30
    )
    AF.SetPoint(
        interruptReadyTickHelp,
        "TOPRIGHT",
        interruptReadyTickPane,
        -15,
        -30
    )
    interruptReadyTickHelp:SetJustifyH("LEFT")
    interruptReadyTickHelp:SetWordWrap(true)

    local interruptReadyTick = AF.CreateCheckButton(
        interruptReadyTickPane,
        L["Enable"]
    )
    AF.SetPoint(
        interruptReadyTick,
        "TOPLEFT",
        interruptReadyTickHelp,
        "BOTTOMLEFT",
        0,
        -12
    )
    interruptReadyTick:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "interruptReadyTick",
            "enabled",
            checked
        )
        UpdateCastWidgets()
    end)

    local interruptReadyTickColor = AF.CreateColorPicker(
        interruptReadyTickPane,
        L["Tick Color"]
    )
    AF.SetPoint(
        interruptReadyTickColor,
        "TOPLEFT",
        interruptReadyTickHelp,
        "BOTTOMLEFT",
        185,
        -12
    )
    WireCastColorPicker(
        interruptReadyTickColor,
        "color",
        "interruptReadyTick",
        true
    )

    local importantGlow = AF.CreateCheckButton(
        castHighlightsPane,
        L["Important Cast Glow"]
    )
    AF.SetPoint(
        importantGlow,
        "TOPLEFT",
        castHighlightsPane,
        15,
        -40
    )
    importantGlow:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "importantGlow",
            "enabled",
            checked
        )
        UpdateCastWidgets()
    end)

    local importantGlowColor = AF.CreateColorPicker(
        castHighlightsPane,
        L["Glow Color"]
    )
    AF.SetPoint(
        importantGlowColor,
        "TOPLEFT",
        castHighlightsPane,
        220,
        -40
    )
    WireCastColorPicker(
        importantGlowColor,
        "color",
        "importantGlow",
        true
    )

    local function CreateCastStateIconWidgets(
        pane,
        section,
        positionHelp
    )
        local help = AF.CreateFontString(
            pane,
            positionHelp,
            "gray"
        )
        AF.SetPoint(help, "TOPLEFT", pane, 15, -30)
        AF.SetPoint(help, "TOPRIGHT", pane, -15, -30)
        help:SetJustifyH("LEFT")
        help:SetWordWrap(true)

        local enableIcon = AF.CreateCheckButton(
            pane,
            L["Enable"]
        )
        AF.SetPoint(
            enableIcon,
            "TOPLEFT",
            help,
            "BOTTOMLEFT",
            0,
            -12
        )
        enableIcon:SetOnCheck(function(checked)
            SetSharedCastSectionValue(
                section,
                "enabled",
                checked
            )
            UpdateCastWidgets()
        end)

        local size = AF.CreateSlider(
            pane,
            L["Size"],
            165,
            6,
            40,
            1,
            nil,
            true
        )
        AF.SetPoint(
            size,
            "TOPLEFT",
            help,
            "BOTTOMLEFT",
            185,
            -17
        )
        size:SetAfterValueChanged(function(value)
            SetSharedCastSectionValue(section, "size", value)
        end)

        local anchorPoint = AF.CreateDropdown(pane, 165)
        anchorPoint:SetLabel(L["Anchor Point"])
        AF.SetPoint(
            anchorPoint,
            "TOPLEFT",
            help,
            "BOTTOMLEFT",
            0,
            -72
        )
        anchorPoint:SetItems(AF.GetDropdownItems_AnchorPoint())
        anchorPoint:SetOnSelect(function(value)
            SetSharedCastArrayValue(
                section,
                "position",
                1,
                value
            )
        end)

        local relativePoint = AF.CreateDropdown(pane, 165)
        relativePoint:SetLabel(L["Relative Point"])
        AF.SetPoint(
            relativePoint,
            "TOPLEFT",
            help,
            "BOTTOMLEFT",
            185,
            -72
        )
        relativePoint:SetItems(
            AF.GetDropdownItems_AnchorPoint()
        )
        relativePoint:SetOnSelect(function(value)
            SetSharedCastArrayValue(
                section,
                "position",
                2,
                value
            )
        end)

        local xOffset = AF.CreateSlider(
            pane,
            L["X Offset"],
            165,
            -100,
            100,
            0.5,
            nil,
            true
        )
        AF.SetPoint(
            xOffset,
            "TOPLEFT",
            help,
            "BOTTOMLEFT",
            0,
            -132
        )
        xOffset:SetAfterValueChanged(function(value)
            SetSharedCastArrayValue(
                section,
                "position",
                3,
                value
            )
        end)

        local yOffset = AF.CreateSlider(
            pane,
            L["Y Offset"],
            165,
            -100,
            100,
            0.5,
            nil,
            true
        )
        AF.SetPoint(
            yOffset,
            "TOPLEFT",
            help,
            "BOTTOMLEFT",
            185,
            -132
        )
        yOffset:SetAfterValueChanged(function(value)
            SetSharedCastArrayValue(
                section,
                "position",
                4,
                value
            )
        end)

        return {
            enabled = enableIcon,
            size = size,
            anchorPoint = anchorPoint,
            relativePoint = relativePoint,
            xOffset = xOffset,
            yOffset = yOffset,
        }
    end

    local uninterruptibleIconWidgets =
        CreateCastStateIconWidgets(
            uninterruptibleIconPane,
            "uninterruptibleIcon",
            L["X means a normal kick cannot interrupt the cast; stops may still work."]
        )
    local importantIconWidgets =
        CreateCastStateIconWidgets(
            importantIconPane,
            "importantIcon",
            L["On dual-state casts, X uses this slot; the important glow remains."]
        )

    local playerTargetHighlight = AF.CreateCheckButton(
        castHighlightsPane,
        L["Player-target Cast Highlight"]
    )
    AF.SetPoint(
        playerTargetHighlight,
        "TOPLEFT",
        castHighlightsPane,
        15,
        -75
    )
    playerTargetHighlight:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "playerTargetHighlight",
            "enabled",
            checked
        )
        UpdateCastWidgets()
    end)

    local playerTargetColor = AF.CreateColorPicker(
        castHighlightsPane,
        L["Highlight Color"],
        true
    )
    AF.SetPoint(
        playerTargetColor,
        "TOPLEFT",
        castHighlightsPane,
        15,
        -105
    )
    WireCastColorPicker(
        playerTargetColor,
        "color",
        "playerTargetHighlight",
        false
    )

    local castName = AF.CreateCheckButton(
        castContentPane,
        L["Cast Name"]
    )
    AF.SetPoint(castName, "TOPLEFT", castContentPane, 15, -40)
    castName:SetOnCheck(function(checked)
        SetSharedCastSectionValue("nameText", "enabled", checked)
    end)

    local castIcon = AF.CreateCheckButton(
        castContentPane,
        L["Icon"]
    )
    AF.SetPoint(castIcon, "TOPLEFT", castContentPane, 200, -40)
    castIcon:SetOnCheck(function(checked)
        SetSharedCastSectionValue("icon", "enabled", checked)
    end)

    local castDuration = AF.CreateCheckButton(
        castContentPane,
        L["Duration Text"]
    )
    AF.SetPoint(
        castDuration,
        "TOPLEFT",
        castContentPane,
        15,
        -70
    )
    castDuration:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "durationText",
            "enabled",
            checked
        )
    end)

    local spellTarget = AF.CreateCheckButton(
        spellTargetPane,
        L["Spell Target Text"]
    )
    AF.SetPoint(
        spellTarget,
        "TOPLEFT",
        spellTargetPane,
        15,
        -40
    )
    spellTarget:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "spellTargetText",
            "enabled",
            checked
        )
        UpdateCastWidgets()
    end)

    local spellTargetColor = AF.CreateColorPicker(
        spellTargetPane,
        L["Text Color"]
    )
    AF.SetPoint(
        spellTargetColor,
        "TOPLEFT",
        spellTargetPane,
        200,
        -40
    )
    WireCastColorPicker(
        spellTargetColor,
        "color",
        "spellTargetText",
        true
    )

    local spellTargetFont = AF.CreateDropdown(spellTargetPane, 165)
    spellTargetFont:SetLabel(L["Font"])
    AF.SetPoint(
        spellTargetFont,
        "TOPLEFT",
        spellTargetPane,
        15,
        -95
    )
    spellTargetFont:SetItems(AF.LSM_GetFontDropdownItems())
    spellTargetFont:SetOnSelect(function(value)
        SetSharedCastFontValue(1, value)
    end)

    local spellTargetOutline = AF.CreateDropdown(
        spellTargetPane,
        165
    )
    spellTargetOutline:SetLabel(L["Outline"])
    AF.SetPoint(
        spellTargetOutline,
        "TOPLEFT",
        spellTargetPane,
        200,
        -95
    )
    spellTargetOutline:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    spellTargetOutline:SetOnSelect(function(value)
        SetSharedCastFontValue(3, value)
    end)

    local spellTargetSize = AF.CreateSlider(
        spellTargetPane,
        L["Size"],
        165,
        5,
        30,
        1,
        nil,
        true
    )
    AF.SetPoint(
        spellTargetSize,
        "TOPLEFT",
        spellTargetPane,
        15,
        -150
    )
    spellTargetSize:SetAfterValueChanged(function(value)
        SetSharedCastFontValue(2, value)
    end)

    local function UpdateCastStateIconWidgets(widgets, config)
        local position = config.position
        widgets.enabled:SetChecked(config.enabled)
        widgets.size:SetValue(config.size)
        widgets.anchorPoint:SetSelectedValue(position[1])
        widgets.relativePoint:SetSelectedValue(position[2])
        widgets.xOffset:SetValue(position[3])
        widgets.yOffset:SetValue(position[4])
        AF.SetEnabled(
            config.enabled,
            widgets.size,
            widgets.anchorPoint,
            widgets.relativePoint,
            widgets.xOffset,
            widgets.yOffset
        )
    end

    UpdateCastWidgets = function()
        local castConfig = NP.config.hostile_npc.castBar
        local checkConfig = castConfig.interruptibleCheck
        local targetConfig = castConfig.spellTargetText

        castWidth:SetValue(castConfig.width)
        castHeight:SetValue(castConfig.height)
        if not AF.IsColorPickerOpen(normalCastColor) then
            normalCastColor:SetColor(castConfig.color)
        end
        if not AF.IsColorPickerOpen(interruptibleCastColor) then
            interruptibleCastColor:SetColor(
                castConfig.interruptibleColor
            )
        end
        if not AF.IsColorPickerOpen(uninterruptibleCastColor) then
            uninterruptibleCastColor:SetColor(
                castConfig.uninterruptibleColor
            )
        end

        interruptibility:SetChecked(checkConfig.enabled)
        interruptReadiness:SetChecked(
            checkConfig.requireUsable
        )
        interruptReadyTick:SetChecked(
            castConfig.interruptReadyTick.enabled
        )
        if not AF.IsColorPickerOpen(
            interruptReadyTickColor
        ) then
            interruptReadyTickColor:SetColor(
                castConfig.interruptReadyTick.color
            )
        end
        UpdateCastStateIconWidgets(
            uninterruptibleIconWidgets,
            castConfig.uninterruptibleIcon
        )

        importantGlow:SetChecked(castConfig.importantGlow.enabled)
        if not AF.IsColorPickerOpen(importantGlowColor) then
            importantGlowColor:SetColor(
                castConfig.importantGlow.color
            )
        end
        UpdateCastStateIconWidgets(
            importantIconWidgets,
            castConfig.importantIcon
        )

        playerTargetHighlight:SetChecked(
            castConfig.playerTargetHighlight.enabled
        )
        if not AF.IsColorPickerOpen(playerTargetColor) then
            playerTargetColor:SetColor(
                castConfig.playerTargetHighlight.color
            )
        end

        castName:SetChecked(castConfig.nameText.enabled)
        castIcon:SetChecked(castConfig.icon.enabled)
        castDuration:SetChecked(castConfig.durationText.enabled)
        spellTarget:SetChecked(targetConfig.enabled)
        if not AF.IsColorPickerOpen(spellTargetColor) then
            spellTargetColor:SetColor(targetConfig.color)
        end
        spellTargetFont:SetSelectedValue(targetConfig.font[1])
        spellTargetOutline:SetSelectedValue(targetConfig.font[3])
        spellTargetSize:SetValue(targetConfig.font[2])

        AF.SetEnabled(
            checkConfig.enabled,
            interruptibleCastColor,
            uninterruptibleCastColor,
            interruptReadiness
        )
        AF.SetEnabled(
            castConfig.interruptReadyTick.enabled,
            interruptReadyTickColor
        )
        AF.SetEnabled(
            castConfig.importantGlow.enabled,
            importantGlowColor
        )
        AF.SetEnabled(
            castConfig.playerTargetHighlight.enabled,
            playerTargetColor
        )
        AF.SetEnabled(
            targetConfig.enabled,
            spellTargetColor,
            spellTargetFont,
            spellTargetOutline,
            spellTargetSize
        )

        castPreview:Refresh(
            castConfig,
            IsIndicatorEnabledForAnyPlateType("castBar")
        )
    end

    --------------------------------------------------
    -- target appearance
    --------------------------------------------------
    local targetPane = CreateSectionPane(
        "target",
        L["Target Indicator"],
        160
    )

    local targetIndicator = AF.CreateCheckButton(
        targetPane,
        L["Enable"]
    )
    AF.SetPoint(targetIndicator, "TOPLEFT", targetPane, 15, -30)

    local targetNotice = AF.CreateFontString(
        targetPane,
        L["Target marker changes apply to NPC and player nameplates in the selected group."],
        "gray"
    )
    AF.SetPoint(targetNotice, "TOPLEFT", targetPane, 110, -30)
    AF.SetPoint(targetNotice, "TOPRIGHT", targetPane, -15, -27)
    targetNotice:SetJustifyH("LEFT")
    targetNotice:SetWordWrap(true)

    local selectedTargetScope = "hostile"
    local selectedTargetState = "target"

    local targetScope = AF.CreateSwitch(targetPane, 165, 20)
    targetScope:SetLabel(L["Nameplate Group"])
    AF.SetPoint(targetScope, "TOPLEFT", targetPane, 15, -110)
    targetScope:SetLabels({
        {text = L["Hostile"], value = "hostile"},
        {text = L["Friendly"], value = "friendly"},
    })

    local targetState = AF.CreateSwitch(targetPane, 165, 20)
    targetState:SetLabel(L["Marker State"])
    AF.SetPoint(targetState, "TOPLEFT", targetPane, 200, -110)
    targetState:SetLabels({
        {text = L["Target"], value = "target"},
        {text = L["Focus"], value = "focus"},
    })

    local targetPreviewPane = CreateSectionPane(
        "target",
        L["Quick Reference"],
        245
    )
    local targetPreview =
        NP.CreateTargetOptionsPreview(targetPreviewPane)

    local markerPane = CreateSectionPane(
        "target",
        L["Marker Layout"],
        205
    )
    local healthHighlightPane = CreateSectionPane(
        "target",
        L["Highlight Health Bar"],
        80
    )
    local nameEmphasisPane = CreateSectionPane(
        "target",
        L["Emphasize Name Text"],
        145
    )

    local markerLayout = AF.CreateDropdown(markerPane, 165)
    markerLayout:SetLabel(L["Marker Layout"])
    AF.SetPoint(markerLayout, "TOPLEFT", markerPane, 15, -50)
    markerLayout:SetItems({
        {text = _G.NONE, value = "none"},
        {text = L["Top Arrow"], value = "top"},
        {text = L["Side Arrows"], value = "sides"},
    })

    local markerSize = AF.CreateSlider(
        markerPane,
        L["Marker Size"],
        165,
        8,
        80,
        1,
        nil,
        true
    )
    AF.SetPoint(markerSize, "TOPLEFT", markerPane, 15, -110)

    local sideArrowSize = AF.CreateSlider(
        markerPane,
        L["Side Arrow Size"],
        165,
        8,
        60,
        1,
        nil,
        true
    )
    AF.SetPoint(
        sideArrowSize,
        "TOPLEFT",
        markerPane,
        15,
        -170
    )

    local topArrowGap = AF.CreateSlider(
        markerPane,
        L["Top Arrow Gap"],
        165,
        0,
        30,
        1,
        nil,
        true
    )
    AF.SetPoint(
        topArrowGap,
        "TOPLEFT",
        markerPane,
        200,
        -110
    )

    local sideArrowGap = AF.CreateSlider(
        markerPane,
        L["Side Arrow Gap"],
        165,
        0,
        30,
        1,
        nil,
        true
    )
    AF.SetPoint(
        sideArrowGap,
        "TOPLEFT",
        markerPane,
        200,
        -170
    )

    local highlightHealthBar = AF.CreateCheckButton(
        healthHighlightPane,
        L["Highlight Health Bar"]
    )
    AF.SetPoint(
        highlightHealthBar,
        "TOPLEFT",
        healthHighlightPane,
        15,
        -45
    )

    local highlightColor = AF.CreateColorPicker(
        healthHighlightPane,
        L["Highlight Color"],
        true
    )
    AF.SetPoint(
        highlightColor,
        "TOPLEFT",
        healthHighlightPane,
        200,
        -45
    )
    local targetColorPreviewed

    local emphasizeNameText = AF.CreateCheckButton(
        nameEmphasisPane,
        L["Emphasize Name Text"]
    )
    AF.SetPoint(
        emphasizeNameText,
        "TOPLEFT",
        nameEmphasisPane,
        15,
        -40
    )

    local nameSizeIncrease = AF.CreateSlider(
        nameEmphasisPane,
        L["Name Size Increase"],
        165,
        0,
        8,
        1,
        nil,
        true
    )
    AF.SetPoint(
        nameSizeIncrease,
        "TOPLEFT",
        nameEmphasisPane,
        15,
        -95
    )

    local nameOutline = AF.CreateDropdown(nameEmphasisPane, 165)
    nameOutline:SetLabel(L["Outline"])
    AF.SetPoint(
        nameOutline,
        "TOPLEFT",
        nameEmphasisPane,
        200,
        -95
    )
    nameOutline:SetItems(AF.LSM_GetFontOutlineDropdownItems())

    local nameShadow = AF.CreateCheckButton(
        nameEmphasisPane,
        L["Shadow"]
    )
    AF.SetPoint(
        nameShadow,
        "TOPLEFT",
        nameEmphasisPane,
        15,
        -130
    )

    local function UpdateTargetPreview(
        config,
        healthBarEnabled,
        nameTextEnabled
    )
        local plateType =
            PLATE_TYPE_GROUPS[selectedTargetScope][1]
        targetPreview:Refresh(
            NP.config[plateType],
            config,
            selectedTargetScope == "hostile"
                and L["Hostile"]
                or L["Friendly"],
            selectedTargetState == "target"
                and L["Target"]
                or L["Focus"],
            IsIndicatorEnabledForScope(
                selectedTargetScope,
                "targetIndicator"
            ),
            healthBarEnabled,
            nameTextEnabled
        )
    end

    local function UpdateTargetWidgets()
        local config = GetTargetStateConfig(
            selectedTargetScope,
            selectedTargetState
        )
        local healthHighlight = config.healthBarHighlight
        local nameEmphasis = config.nameTextEmphasis
        local healthBarEnabled = IsHealthBarEnabledForScope(
            selectedTargetScope
        )
        local nameTextEnabled = IsIndicatorEnabledForScope(
            selectedTargetScope,
            "nameText"
        )

        targetIndicator:SetChecked(
            IsIndicatorEnabledForScope(
                selectedTargetScope,
                "targetIndicator"
            )
        )
        markerLayout:SetSelectedValue(config.layout)
        markerSize:SetValue(config.size)
        sideArrowSize:SetValue(config.sideSize)
        topArrowGap:SetValue(config.topSpacing or 0)
        sideArrowGap:SetValue(config.sideSpacing or 0)
        highlightHealthBar:SetChecked(healthHighlight.enabled)
        if not AF.IsColorPickerOpen(highlightColor) then
            highlightColor:SetColor(healthHighlight.color)
        end
        emphasizeNameText:SetChecked(nameEmphasis.enabled)
        nameSizeIncrease:SetValue(nameEmphasis.sizeDelta)
        nameOutline:SetSelectedValue(nameEmphasis.outline)
        nameShadow:SetChecked(nameEmphasis.shadow)

        AF.SetEnabled(
            config.layout == "top",
            markerSize,
            topArrowGap
        )
        AF.SetEnabled(
            config.layout == "sides",
            sideArrowSize,
            sideArrowGap
        )
        AF.SetEnabled(healthBarEnabled, highlightHealthBar)
        AF.SetEnabled(
            healthBarEnabled and healthHighlight.enabled,
            highlightColor
        )
        AF.SetEnabled(nameTextEnabled, emphasizeNameText)
        AF.SetEnabled(
            nameTextEnabled and nameEmphasis.enabled,
            nameSizeIncrease,
            nameOutline,
            nameShadow
        )

        UpdateTargetPreview(
            config,
            healthBarEnabled,
            nameTextEnabled
        )
    end

    local function CancelTargetColorPicker()
        AF.CancelColorPicker(highlightColor)
    end

    targetIndicator:SetOnCheck(function(checked)
        SetScopeIndicatorEnabled(
            selectedTargetScope,
            "targetIndicator",
            checked
        )
    end)

    targetScope:SetOnSelect(function(value)
        CancelTargetColorPicker()
        selectedTargetScope = value
        UpdateTargetWidgets()
    end)

    targetState:SetOnSelect(function(value)
        CancelTargetColorPicker()
        selectedTargetState = value
        UpdateTargetWidgets()
    end)

    markerLayout:SetOnSelect(function(value)
        SetTargetStateValue(
            selectedTargetScope,
            selectedTargetState,
            "layout",
            value
        )
        UpdateTargetWidgets()
    end)

    markerSize:SetAfterValueChanged(function(value)
        SetTargetStateValue(
            selectedTargetScope,
            selectedTargetState,
            "size",
            value
        )
    end)

    sideArrowSize:SetAfterValueChanged(function(value)
        SetTargetStateValue(
            selectedTargetScope,
            selectedTargetState,
            "sideSize",
            value
        )
    end)

    topArrowGap:SetAfterValueChanged(function(value)
        SetTargetStateValue(
            selectedTargetScope,
            selectedTargetState,
            "topSpacing",
            value
        )
    end)

    sideArrowGap:SetAfterValueChanged(function(value)
        SetTargetStateValue(
            selectedTargetScope,
            selectedTargetState,
            "sideSpacing",
            value
        )
    end)

    highlightHealthBar:SetOnCheck(function(checked)
        SetTargetStateNestedValue(
            selectedTargetScope,
            selectedTargetState,
            "healthBarHighlight",
            "enabled",
            checked
        )
        UpdateTargetWidgets()
    end)

    highlightColor:SetOnChange(function(r, g, b, a)
        local colors = {}
        for _, plateType in ipairs(
            PLATE_TYPE_GROUPS[selectedTargetScope]
        ) do
            local stateConfig =
                NP.config[plateType].targetIndicator[
                    selectedTargetState
                ]
            colors[#colors + 1] =
                stateConfig.healthBarHighlight.color
        end
        targetColorPreviewed = PreviewColorTables(
            highlightColor,
            colors,
            r,
            g,
            b,
            a
        ) or targetColorPreviewed
    end)
    highlightColor:SetOnConfirm(function(r, g, b, a)
        SetTargetStateColor(
            selectedTargetScope,
            selectedTargetState,
            "healthBarHighlight",
            r,
            g,
            b,
            a
        )
        targetColorPreviewed = nil
    end)
    highlightColor:SetOnAccept(function()
        if targetColorPreviewed then
            UpdateNameplates()
            targetColorPreviewed = nil
        end
    end)
    local function ResetTargetColorPreview()
        targetColorPreviewed = nil
        UpdateNameplates()
    end
    highlightColor:SetOnCancel(ResetTargetColorPreview)
    highlightColor:SetOnDiscard(ResetTargetColorPreview)

    emphasizeNameText:SetOnCheck(function(checked)
        SetTargetStateNestedValue(
            selectedTargetScope,
            selectedTargetState,
            "nameTextEmphasis",
            "enabled",
            checked
        )
        UpdateTargetWidgets()
    end)

    nameSizeIncrease:SetAfterValueChanged(function(value)
        SetTargetStateNestedValue(
            selectedTargetScope,
            selectedTargetState,
            "nameTextEmphasis",
            "sizeDelta",
            value
        )
    end)

    nameOutline:SetOnSelect(function(value)
        SetTargetStateNestedValue(
            selectedTargetScope,
            selectedTargetState,
            "nameTextEmphasis",
            "outline",
            value
        )
    end)

    nameShadow:SetOnCheck(function(checked)
        SetTargetStateNestedValue(
            selectedTargetScope,
            selectedTargetState,
            "nameTextEmphasis",
            "shadow",
            checked
        )
    end)

    --------------------------------------------------
    -- debuff aura appearance
    --------------------------------------------------
    local auraPane = CreateSectionPane(
        "auras",
        L["debuffs"],
        105
    )

    local auraNotice = AF.CreateFontString(auraPane, L["Debuff timer appearance changes apply to hostile and friendly NPC and player nameplates."], "gray")
    AF.SetPoint(auraNotice, "TOPLEFT", auraPane, 15, -30)
    AF.SetPoint(auraNotice, "TOPRIGHT", auraPane, -15, -30)
    auraNotice:SetJustifyH("LEFT")
    auraNotice:SetWordWrap(true)

    local auraPreviewPane = CreateSectionPane(
        "auras",
        L["Quick Reference"],
        205
    )
    local auraPreview =
        NP.CreateAuraOptionsPreview(auraPreviewPane)

    local cooldownPane = CreateSectionPane(
        "auras",
        L["Cooldown Style"],
        80
    )
    local durationPane = CreateSectionPane(
        "auras",
        L["Duration Text"],
        80
    )
    local durationTextPane = CreateSectionPane(
        "auras",
        L["Text"],
        145
    )
    local durationPositionPane = CreateSectionPane(
        "auras",
        L["Position"],
        145
    )

    local cooldownStyle = AF.CreateDropdown(cooldownPane, 350)
    cooldownStyle:SetLabel(L["Cooldown Style"])
    AF.SetPoint(
        cooldownStyle,
        "TOPLEFT",
        cooldownPane,
        15,
        -50
    )
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

    local durationEnabled = AF.CreateCheckButton(
        durationPane,
        L["Duration Text"]
    )
    AF.SetPoint(
        durationEnabled,
        "TOPLEFT",
        durationPane,
        15,
        -45
    )

    -- Retail 12.0.7's native DurationTextBinding cannot apply threshold
    -- colors without exposing restricted duration values to Lua. Keep the
    -- supported normal color here; 12.1 curve modes need a separate design.
    local normalColor = AF.CreateColorPicker(
        durationPane,
        L["Normal"]
    )
    AF.SetPoint(
        normalColor,
        "TOPLEFT",
        durationPane,
        200,
        -45
    )
    local durationColorPreviewed
    normalColor:SetOnChange(function(r, g, b, a)
        local colors = {}
        for _, plateType in ipairs(PLATE_TYPES) do
            colors[#colors + 1] =
                NP.config[plateType].debuffs.durationText.color.normal
        end
        durationColorPreviewed = PreviewColorTables(
            normalColor,
            colors,
            r,
            g,
            b,
            a,
            true
        ) or durationColorPreviewed
    end)
    normalColor:SetOnConfirm(function(r, g, b)
        SetSharedDebuffDurationColor(r, g, b)
        durationColorPreviewed = nil
    end)
    normalColor:SetOnAccept(function()
        if durationColorPreviewed then
            UpdateNameplates()
            durationColorPreviewed = nil
        end
    end)
    local function ResetDurationColorPreview()
        durationColorPreviewed = nil
        UpdateNameplates()
    end
    normalColor:SetOnCancel(ResetDurationColorPreview)
    normalColor:SetOnDiscard(ResetDurationColorPreview)

    local font = AF.CreateDropdown(durationTextPane, 165)
    font:SetLabel(L["Font"])
    AF.SetPoint(font, "TOPLEFT", durationTextPane, 15, -50)
    font:SetItems(AF.LSM_GetFontDropdownItems())
    font:SetOnSelect(function(value)
        SetSharedDebuffDurationArrayValue("font", 1, value)
    end)

    local outline = AF.CreateDropdown(durationTextPane, 165)
    outline:SetLabel(L["Outline"])
    AF.SetPoint(
        outline,
        "TOPLEFT",
        durationTextPane,
        200,
        -50
    )
    outline:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    outline:SetOnSelect(function(value)
        SetSharedDebuffDurationArrayValue("font", 3, value)
    end)

    local size = AF.CreateSlider(
        durationTextPane,
        L["Size"],
        165,
        5,
        50,
        1,
        nil,
        true
    )
    AF.SetPoint(size, "TOPLEFT", durationTextPane, 15, -110)
    size:SetAfterValueChanged(function(value)
        SetSharedDebuffDurationArrayValue("font", 2, value)
    end)

    local shadow = AF.CreateCheckButton(
        durationTextPane,
        L["Shadow"]
    )
    AF.SetPoint(
        shadow,
        "TOPLEFT",
        durationTextPane,
        200,
        -95
    )
    shadow:SetOnCheck(function(checked)
        SetSharedDebuffDurationArrayValue("font", 4, checked)
    end)

    local anchorPoint = AF.CreateDropdown(
        durationPositionPane,
        165
    )
    anchorPoint:SetLabel(L["Anchor Point"])
    AF.SetPoint(
        anchorPoint,
        "TOPLEFT",
        durationPositionPane,
        15,
        -50
    )
    anchorPoint:SetItems(AF.GetDropdownItems_AnchorPoint())
    anchorPoint:SetOnSelect(function(value)
        SetSharedDebuffDurationArrayValue("position", 1, value)
    end)

    local relativePoint = AF.CreateDropdown(
        durationPositionPane,
        165
    )
    relativePoint:SetLabel(L["Relative Point"])
    AF.SetPoint(
        relativePoint,
        "TOPLEFT",
        durationPositionPane,
        200,
        -50
    )
    relativePoint:SetItems(AF.GetDropdownItems_AnchorPoint())
    relativePoint:SetOnSelect(function(value)
        SetSharedDebuffDurationArrayValue("position", 2, value)
    end)

    local xOffset = AF.CreateSlider(
        durationPositionPane,
        L["X Offset"],
        165,
        -100,
        100,
        0.5,
        nil,
        true
    )
    AF.SetPoint(
        xOffset,
        "TOPLEFT",
        durationPositionPane,
        15,
        -110
    )
    xOffset:SetAfterValueChanged(function(value)
        SetSharedDebuffDurationArrayValue("position", 3, value)
    end)

    local yOffset = AF.CreateSlider(
        durationPositionPane,
        L["Y Offset"],
        165,
        -100,
        100,
        0.5,
        nil,
        true
    )
    AF.SetPoint(
        yOffset,
        "TOPLEFT",
        durationPositionPane,
        200,
        -110
    )
    yOffset:SetAfterValueChanged(function(value)
        SetSharedDebuffDurationArrayValue("position", 4, value)
    end)

    local function UpdateDurationWidgets()
        AF.SetEnabled(durationEnabled:GetChecked(), normalColor, font, outline, size, shadow,
            anchorPoint, relativePoint, xOffset, yOffset)
        auraPreview:Refresh(
            NP.config.hostile_npc,
            IsIndicatorEnabledForAnyPlateType("debuffs"),
            IsDebuffDurationEnabledForAnyPlateType()
        )
    end

    durationEnabled:SetOnCheck(function(checked)
        SetSharedDebuffDurationValue("enabled", checked)
        UpdateDurationWidgets()
    end)

    local function CancelSemanticColorPickers()
        for _, widgets in ipairs(semanticColorWidgets) do
            AF.CancelColorPicker(widgets.picker)
        end
    end

    local function HideSemanticColorPickers()
        for _, widgets in ipairs(semanticColorWidgets) do
            AF.HideColorPicker(widgets.picker)
        end
    end

    local function HideThreatStateColorPickers()
        for _, widgets in ipairs(threatStateWidgets) do
            AF.HideColorPicker(widgets.picker)
        end
    end

    local function CancelCastColorPickers()
        for _, picker in ipairs(castColorPickers) do
            AF.CancelColorPicker(picker)
        end
    end

    local function HideCastColorPickers()
        for _, picker in ipairs(castColorPickers) do
            AF.HideColorPicker(picker)
        end
    end

    local function CancelNameplateColorPickers()
        CancelSemanticColorPickers()
        CancelThreatColorPickers()
        CancelCastColorPickers()
        AF.CancelColorPicker(highlightColor)
        AF.CancelColorPicker(normalColor)
    end

    local function HideNameplateColorPickers()
        HideSemanticColorPickers()
        HideThreatStateColorPickers()
        HideCastColorPickers()
        AF.HideColorPicker(threatColor)
        AF.HideColorPicker(highlightColor)
        AF.HideColorPicker(normalColor)
    end

    RefreshNameplatePreviews = function()
        if not nameplatesPanel then return end

        semanticPreview:Refresh(
            NP.config.hostile_npc.healthBar
        )
        castPreview:Refresh(
            NP.config.hostile_npc.castBar,
            IsIndicatorEnabledForAnyPlateType("castBar")
        )
        threatPreview:Refresh(
            NP.config.hostile_npc.healthBar,
            NP.config.hostile_npc.nameText.enabled
        )

        local targetConfig = GetTargetStateConfig(
            selectedTargetScope,
            selectedTargetState
        )
        UpdateTargetPreview(
            targetConfig,
            IsHealthBarEnabledForScope(
                selectedTargetScope
            ),
            IsIndicatorEnabledForScope(
                selectedTargetScope,
                "nameText"
            )
        )

        auraPreview:Refresh(
            NP.config.hostile_npc,
            IsIndicatorEnabledForAnyPlateType("debuffs"),
            IsDebuffDurationEnabledForAnyPlateType()
        )
    end

    function nameplatesPanel.Load(discardColorPreview)
        if discardColorPreview then
            -- A reset/profile load has already replaced NP.config. Discard
            -- the old live-edit session; its discard handler reloads the
            -- current table without writing the old color into it.
            HideNameplateColorPickers()
        else
            CancelNameplateColorPickers()
        end

        local config = NP.config
        local durationConfig = config.hostile_npc.debuffs.durationText

        enabled:SetChecked(config.enabled)
        enabled:SetTextColor(config.enabled and "softlime" or "firebrick")
        width:SetValue(config.hostile_npc.healthBar.width)
        height:SetValue(config.hostile_npc.healthBar.height)
        nameText:SetChecked(IsIndicatorEnabledForAnyPlateType("nameText"))
        namePlacement:SetSelectedValue(
            config.hostile_npc.nameText.placement or "outside"
        )
        castBar:SetChecked(IsIndicatorEnabledForAnyPlateType("castBar"))
        debuffs:SetChecked(IsIndicatorEnabledForAnyPlateType("debuffs"))

        UpdateSemanticColorWidgets()
        UpdateCastWidgets()

        targetScope:SetSelectedValue(selectedTargetScope)
        targetState:SetSelectedValue(selectedTargetState)
        UpdateTargetWidgets()
        UpdateThreatWidgets()

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

    -- Restore an in-progress preview while NP.config still references the
    -- outgoing profile. The module's medium-priority profile callback then
    -- swaps in the new profile before the low-priority options reload.
    AF.RegisterCallback("BFI_UpdateProfile", function()
        CancelNameplateColorPickers()
    end, "high")

    sectionCleanup.target = function()
        AF.CancelColorPicker(highlightColor)
    end
    sectionCleanup.colors = CancelSemanticColorPickers
    sectionCleanup.casts = CancelCastColorPickers
    sectionCleanup.threat = CancelThreatColorPickers
    sectionCleanup.auras = function()
        AF.CancelColorPicker(normalColor)
        auraPreview:Stop()
    end
    nameplatesPanel:HookOnHide(CancelNameplateColorPickers)
    nameplatesPanel:HookOnHide(function()
        auraPreview:Stop()
    end)
    nameplatesPanel:HookOnShow(RefreshNameplatePreviews)

    sectionButtons[1]:SilentClick()
end

---------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------
AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "nameplates" or not nameplatesPanel then return end
    nameplatesPanel.Load(true)
end)

AF.RegisterCallback("BFI_UpdateProfile", function()
    if nameplatesPanel and nameplatesPanel:IsShown() then
        nameplatesPanel.Load(true)
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
