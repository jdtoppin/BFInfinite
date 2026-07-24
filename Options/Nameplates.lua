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

local function SetSharedIndicatorEnabled(indicator, enabled)
    for _, plateType in ipairs(PLATE_TYPES) do
        NP.config[plateType][indicator].enabled = enabled
    end
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
        {text = L["Colors"], value = "colors"},
        {text = L["Casts"], value = "casts"},
        {text = L["Target"], value = "target"},
        {text = L["Auras"], value = "auras"},
    })

    local generalPage = AF.CreateFrame(nameplatesPanel)
    AF.SetPoint(generalPage, "TOPLEFT", sectionSwitch, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(generalPage, "BOTTOMRIGHT", nameplatesPanel, -15, 15)

    local aurasPage = AF.CreateFrame(nameplatesPanel)
    AF.SetPoint(aurasPage, "TOPLEFT", sectionSwitch, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(aurasPage, "BOTTOMRIGHT", nameplatesPanel, -15, 15)

    local colorsPage = AF.CreateFrame(nameplatesPanel)
    AF.SetPoint(colorsPage, "TOPLEFT", sectionSwitch, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(colorsPage, "BOTTOMRIGHT", nameplatesPanel, -15, 15)

    local castsPage = AF.CreateFrame(nameplatesPanel)
    AF.SetPoint(castsPage, "TOPLEFT", sectionSwitch, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(castsPage, "BOTTOMRIGHT", nameplatesPanel, -15, 15)

    local targetPage = AF.CreateFrame(nameplatesPanel)
    AF.SetPoint(targetPage, "TOPLEFT", sectionSwitch, "BOTTOMLEFT", 0, -15)
    AF.SetPoint(targetPage, "BOTTOMRIGHT", nameplatesPanel, -15, 15)

    sectionSwitch:SetOnSelect(function(value)
        generalPage:SetShown(value == "general")
        colorsPage:SetShown(value == "colors")
        castsPage:SetShown(value == "casts")
        targetPage:SetShown(value == "target")
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
    -- hostile NPC semantic colors
    --------------------------------------------------
    local colorsPane = AF.CreateTitledPane(
        colorsPage,
        L["Dungeon Priority Colors"],
        nil,
        330
    )
    AF.SetPoint(colorsPane, "TOPLEFT", colorsPage)
    AF.SetPoint(colorsPane, "TOPRIGHT", colorsPage)

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

    local semanticColorWidgets = {}

    local function CreateSemanticColorRow(info, index)
        local key = info.key
        local enabledButton = AF.CreateCheckButton(
            colorsPane,
            L[info.label]
        )
        AF.SetPoint(
            enabledButton,
            "TOPLEFT",
            colorsPane,
            15,
            -125 - (index - 1) * 48
        )

        local picker = AF.CreateColorPicker(
            colorsPane,
            L["Color"]
        )
        AF.SetPoint(
            picker,
            "TOPLEFT",
            colorsPane,
            300,
            -125 - (index - 1) * 48
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
    end

    --------------------------------------------------
    -- cast appearance
    --------------------------------------------------
    local castsPane = AF.CreateTitledPane(
        castsPage,
        L["Cast Bar Appearance"],
        nil,
        470
    )
    AF.SetPoint(castsPane, "TOPLEFT", castsPage)
    AF.SetPoint(castsPane, "TOPRIGHT", castsPage)

    local castsNotice = AF.CreateFontString(
        castsPane,
        L["Cast settings apply to every nameplate. Important casts and player-targeted casts use Blizzard's secret-safe classifications; no custom spell or NPC lists are used."],
        "gray"
    )
    AF.SetPoint(castsNotice, "TOPLEFT", castsPane, 15, -30)
    AF.SetPoint(castsNotice, "TOPRIGHT", castsPane, -15, -30)
    castsNotice:SetJustifyH("LEFT")
    castsNotice:SetWordWrap(true)

    local UpdateCastWidgets

    local castWidth = AF.CreateSlider(
        castsPane,
        L["Width"],
        180,
        40,
        300,
        1,
        nil,
        true
    )
    AF.SetPoint(castWidth, "TOPLEFT", castsPane, 15, -85)
    castWidth:SetAfterValueChanged(function(value)
        SetSharedCastValue("width", value)
    end)

    local castHeight = AF.CreateSlider(
        castsPane,
        L["Height"],
        180,
        4,
        40,
        1,
        nil,
        true
    )
    AF.SetPoint(castHeight, "TOPLEFT", castsPane, 285, -85)
    castHeight:SetAfterValueChanged(function(value)
        SetSharedCastValue("height", value)
    end)

    local normalCastColor = AF.CreateColorPicker(
        castsPane,
        L["Normal"]
    )
    AF.SetPoint(normalCastColor, "TOPLEFT", castsPane, 15, -145)

    local interruptibleCastColor = AF.CreateColorPicker(
        castsPane,
        L["Interruptible"]
    )
    AF.SetPoint(
        interruptibleCastColor,
        "TOPLEFT",
        castsPane,
        200,
        -145
    )

    local uninterruptibleCastColor = AF.CreateColorPicker(
        castsPane,
        L["Uninterruptible"]
    )
    AF.SetPoint(
        uninterruptibleCastColor,
        "TOPLEFT",
        castsPane,
        385,
        -145
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
        castsPane,
        L["Color by Interruptibility"]
    )
    AF.SetPoint(interruptibility, "TOPLEFT", castsPane, 15, -195)
    interruptibility:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "interruptibleCheck",
            "enabled",
            checked
        )
        UpdateCastWidgets()
    end)

    local uninterruptibleTexture = AF.CreateCheckButton(
        castsPane,
        L["Uninterruptible Texture"]
    )
    AF.SetPoint(
        uninterruptibleTexture,
        "TOPLEFT",
        castsPane,
        285,
        -195
    )
    uninterruptibleTexture:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "interruptibleCheck",
            "showTexture",
            checked
        )
    end)

    local importantGlow = AF.CreateCheckButton(
        castsPane,
        L["Important Cast Glow"]
    )
    AF.SetPoint(importantGlow, "TOPLEFT", castsPane, 15, -235)
    importantGlow:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "importantGlow",
            "enabled",
            checked
        )
        UpdateCastWidgets()
    end)

    local importantGlowColor = AF.CreateColorPicker(
        castsPane,
        L["Glow Color"]
    )
    AF.SetPoint(
        importantGlowColor,
        "TOPLEFT",
        castsPane,
        285,
        -235
    )
    WireCastColorPicker(
        importantGlowColor,
        "color",
        "importantGlow",
        true
    )

    local playerTargetHighlight = AF.CreateCheckButton(
        castsPane,
        L["Player-target Cast Highlight"]
    )
    AF.SetPoint(
        playerTargetHighlight,
        "TOPLEFT",
        castsPane,
        15,
        -275
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
        castsPane,
        L["Highlight Color"],
        true
    )
    AF.SetPoint(
        playerTargetColor,
        "TOPLEFT",
        castsPane,
        285,
        -275
    )
    WireCastColorPicker(
        playerTargetColor,
        "color",
        "playerTargetHighlight",
        false
    )

    local castName = AF.CreateCheckButton(
        castsPane,
        L["Cast Name"]
    )
    AF.SetPoint(castName, "TOPLEFT", castsPane, 15, -315)
    castName:SetOnCheck(function(checked)
        SetSharedCastSectionValue("nameText", "enabled", checked)
    end)

    local castIcon = AF.CreateCheckButton(castsPane, L["Icon"])
    AF.SetPoint(castIcon, "TOPLEFT", castsPane, 200, -315)
    castIcon:SetOnCheck(function(checked)
        SetSharedCastSectionValue("icon", "enabled", checked)
    end)

    local castDuration = AF.CreateCheckButton(
        castsPane,
        L["Duration Text"]
    )
    AF.SetPoint(castDuration, "TOPLEFT", castsPane, 385, -315)
    castDuration:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "durationText",
            "enabled",
            checked
        )
    end)

    local spellTarget = AF.CreateCheckButton(
        castsPane,
        L["Spell Target Text"]
    )
    AF.SetPoint(spellTarget, "TOPLEFT", castsPane, 15, -355)
    spellTarget:SetOnCheck(function(checked)
        SetSharedCastSectionValue(
            "spellTargetText",
            "enabled",
            checked
        )
        UpdateCastWidgets()
    end)

    local spellTargetColor = AF.CreateColorPicker(
        castsPane,
        L["Text Color"]
    )
    AF.SetPoint(
        spellTargetColor,
        "TOPLEFT",
        castsPane,
        285,
        -355
    )
    WireCastColorPicker(
        spellTargetColor,
        "color",
        "spellTargetText",
        true
    )

    local spellTargetFont = AF.CreateDropdown(castsPane, 150)
    spellTargetFont:SetLabel(L["Font"])
    AF.SetPoint(spellTargetFont, "TOPLEFT", castsPane, 15, -405)
    spellTargetFont:SetItems(AF.LSM_GetFontDropdownItems())
    spellTargetFont:SetOnSelect(function(value)
        SetSharedCastFontValue(1, value)
    end)

    local spellTargetOutline = AF.CreateDropdown(castsPane, 150)
    spellTargetOutline:SetLabel(L["Outline"])
    AF.SetPoint(spellTargetOutline, "TOPLEFT", castsPane, 200, -405)
    spellTargetOutline:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    spellTargetOutline:SetOnSelect(function(value)
        SetSharedCastFontValue(3, value)
    end)

    local spellTargetSize = AF.CreateSlider(
        castsPane,
        L["Size"],
        150,
        5,
        30,
        1,
        nil,
        true
    )
    AF.SetPoint(spellTargetSize, "TOPLEFT", castsPane, 385, -405)
    spellTargetSize:SetAfterValueChanged(function(value)
        SetSharedCastFontValue(2, value)
    end)

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
        uninterruptibleTexture:SetChecked(checkConfig.showTexture)

        importantGlow:SetChecked(castConfig.importantGlow.enabled)
        if not AF.IsColorPickerOpen(importantGlowColor) then
            importantGlowColor:SetColor(
                castConfig.importantGlow.color
            )
        end

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
            uninterruptibleTexture
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
    end

    --------------------------------------------------
    -- target appearance
    --------------------------------------------------
    local targetPane = AF.CreateTitledPane(
        targetPage,
        L["Target Indicator"],
        nil,
        365
    )
    AF.SetPoint(targetPane, "TOPLEFT", targetPage)
    AF.SetPoint(targetPane, "TOPRIGHT", targetPage)

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
    AF.SetPoint(targetNotice, "TOPLEFT", targetPane, 150, -27)
    AF.SetPoint(targetNotice, "TOPRIGHT", targetPane, -15, -27)
    targetNotice:SetJustifyH("LEFT")
    targetNotice:SetWordWrap(true)

    local selectedTargetScope = "hostile"
    local selectedTargetState = "target"

    local targetScope = AF.CreateSwitch(targetPane, 250, 20)
    targetScope:SetLabel(L["Nameplate Group"])
    AF.SetPoint(targetScope, "TOPLEFT", targetPane, 15, -85)
    targetScope:SetLabels({
        {text = L["Hostile"], value = "hostile"},
        {text = L["Friendly"], value = "friendly"},
    })

    local targetState = AF.CreateSwitch(targetPane, 250, 20)
    targetState:SetLabel(L["Marker State"])
    AF.SetPoint(targetState, "TOPLEFT", targetPane, 300, -85)
    targetState:SetLabels({
        {text = L["Target"], value = "target"},
        {text = L["Focus"], value = "focus"},
    })

    local markerLayout = AF.CreateDropdown(targetPane, 220)
    markerLayout:SetLabel(L["Marker Layout"])
    AF.SetPoint(markerLayout, "TOPLEFT", targetPane, 15, -140)
    markerLayout:SetItems({
        {text = _G.NONE, value = "none"},
        {text = L["Top Arrow"], value = "top"},
        {text = L["Side Arrows"], value = "sides"},
    })

    local markerSize = AF.CreateSlider(
        targetPane,
        L["Marker Size"],
        180,
        8,
        80,
        1,
        nil,
        true
    )
    AF.SetPoint(markerSize, "TOPLEFT", targetPane, 300, -140)

    local sideArrowSize = AF.CreateSlider(
        targetPane,
        L["Side Arrow Size"],
        180,
        8,
        60,
        1,
        nil,
        true
    )
    AF.SetPoint(sideArrowSize, "TOPLEFT", targetPane, 15, -200)

    local arrowGap = AF.CreateSlider(
        targetPane,
        L["Arrow Gap"],
        180,
        0,
        30,
        1,
        nil,
        true
    )
    AF.SetPoint(arrowGap, "TOPLEFT", targetPane, 300, -200)

    local highlightHealthBar = AF.CreateCheckButton(
        targetPane,
        L["Highlight Health Bar"]
    )
    AF.SetPoint(
        highlightHealthBar,
        "TOPLEFT",
        targetPane,
        15,
        -245
    )

    local highlightColor = AF.CreateColorPicker(
        targetPane,
        L["Highlight Color"],
        true
    )
    AF.SetPoint(highlightColor, "TOPLEFT", targetPane, 300, -245)
    local targetColorPreviewed

    local emphasizeNameText = AF.CreateCheckButton(
        targetPane,
        L["Emphasize Name Text"]
    )
    AF.SetPoint(
        emphasizeNameText,
        "TOPLEFT",
        targetPane,
        15,
        -280
    )

    local nameSizeIncrease = AF.CreateSlider(
        targetPane,
        L["Name Size Increase"],
        150,
        0,
        8,
        1,
        nil,
        true
    )
    AF.SetPoint(
        nameSizeIncrease,
        "TOPLEFT",
        targetPane,
        15,
        -335
    )

    local nameOutline = AF.CreateDropdown(targetPane, 150)
    nameOutline:SetLabel(L["Outline"])
    AF.SetPoint(nameOutline, "TOPLEFT", targetPane, 200, -335)
    nameOutline:SetItems(AF.LSM_GetFontOutlineDropdownItems())

    local nameShadow = AF.CreateCheckButton(
        targetPane,
        L["Shadow"]
    )
    AF.SetPoint(nameShadow, "TOPLEFT", targetPane, 390, -317)

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
        arrowGap:SetValue(config.sideSpacing)
        highlightHealthBar:SetChecked(healthHighlight.enabled)
        if not AF.IsColorPickerOpen(highlightColor) then
            highlightColor:SetColor(healthHighlight.color)
        end
        emphasizeNameText:SetChecked(nameEmphasis.enabled)
        nameSizeIncrease:SetValue(nameEmphasis.sizeDelta)
        nameOutline:SetSelectedValue(nameEmphasis.outline)
        nameShadow:SetChecked(nameEmphasis.shadow)

        AF.SetEnabled(config.layout == "top", markerSize)
        AF.SetEnabled(
            config.layout == "sides",
            sideArrowSize,
            arrowGap
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

    arrowGap:SetAfterValueChanged(function(value)
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
        CancelCastColorPickers()
        AF.CancelColorPicker(highlightColor)
        AF.CancelColorPicker(normalColor)
    end

    local function HideNameplateColorPickers()
        HideSemanticColorPickers()
        HideCastColorPickers()
        AF.HideColorPicker(highlightColor)
        AF.HideColorPicker(normalColor)
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
        castBar:SetChecked(IsIndicatorEnabledForAnyPlateType("castBar"))
        debuffs:SetChecked(IsIndicatorEnabledForAnyPlateType("debuffs"))

        UpdateSemanticColorWidgets()
        UpdateCastWidgets()

        targetScope:SetSelectedValue(selectedTargetScope)
        targetState:SetSelectedValue(selectedTargetState)
        UpdateTargetWidgets()

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

    targetPage:HookOnHide(function()
        AF.CancelColorPicker(highlightColor)
    end)
    colorsPage:HookOnHide(CancelSemanticColorPickers)
    castsPage:HookOnHide(CancelCastColorPickers)
    aurasPage:HookOnHide(function()
        AF.CancelColorPicker(normalColor)
    end)
    nameplatesPanel:HookOnHide(CancelNameplateColorPickers)

    sectionSwitch:SetSelectedValue("general")
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
