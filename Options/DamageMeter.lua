---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

local damageMeterPanel
local scroll
local generalPane
local windowsPane
local appearancePane
local actionsPane
local statusText
local windowCount
local windowTypeDropdowns = {}

local CONTENT_WIDTH = 530
local CONTENT_HEIGHT = 720
local SECTION_GAP = 12
local GENERAL_HEIGHT = 60
local GENERAL_STATUS_HEIGHT = 80
local CONTROL_WIDTH = 150
local WIDE_CONTROL_WIDTH = 240
local SLIDER_WIDTH = 140

local METER_TYPE_ITEMS = {
    {text = L["Damage Done"], value = "DamageDone"},
    {text = L["Healing Done"], value = "HealingDone"},
    {text = L["Damage Taken"], value = "DamageTaken"},
}

local NUMBER_MODE_ITEMS = {
    {text = L["Total"], value = "total"},
    {text = L["Per Second"], value = "perSecond"},
    {text = L["Total and Per Second"], value = "both"},
}

local function SetPaneTips(pane, title, body)
    pane:SetTips(title, body)
    -- Titled panes place their tip button at the right edge. Point the tooltip
    -- back into the options frame instead of letting it grow off-screen.
    pane.tips:SetTipsPosition("BOTTOMRIGHT", 0, 0)
end

local function SetStatus(message, color)
    if not statusText then return end

    local hasMessage = type(message) == "string" and message ~= ""
    statusText:SetText(message or "")
    statusText:SetColor(color or "gray")
    statusText:SetShown(hasMessage)
    generalPane:SetHeight(
        hasMessage and GENERAL_STATUS_HEIGHT or GENERAL_HEIGHT
    )
end

local function RefreshDamageMeter()
    AF.Fire("BFI_UpdateModule", "damageMeter")
end

local function CreateDamageMeterPanel()
    damageMeterPanel = AF.CreateFrame(
        BFIOptionsFrame_ContentPane,
        "BFIOptionsFrame_DamageMeterPanel"
    )
    damageMeterPanel:SetAllPoints()

    scroll = AF.CreateScrollFrame(
        damageMeterPanel,
        nil,
        nil,
        nil,
        "none",
        "none"
    )
    AF.SetPoint(scroll, "TOPLEFT", damageMeterPanel, 15, -15)
    AF.SetPoint(scroll, "BOTTOMRIGHT", damageMeterPanel, -10, 15)
    scroll:SetScrollStep(50)
    scroll.scrollContent:SetWidth(CONTENT_WIDTH)
    scroll.scrollContent:SetHeight(CONTENT_HEIGHT)
end

local function CreateGeneralPane()
    generalPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["BFI Damage Meter"],
        CONTENT_WIDTH,
        GENERAL_HEIGHT
    )
    AF.SetPoint(generalPane, "TOPLEFT")
    SetPaneTips(
        generalPane,
        L["BFI Damage Meter"],
        L["BFI Damage Meter Tip"]
    )

    local enabled = AF.CreateCheckButton(
        generalPane,
        L["Enable BFI Damage Meter"]
    )
    AF.SetPoint(enabled, "TOPLEFT", generalPane, 15, -30)
    enabled:SetOnCheck(function(checked)
        DM.config.enabled = checked
        RefreshDamageMeter()
        generalPane.Load()
    end)

    local resetOnNewInstance = AF.CreateCheckButton(
        generalPane,
        L["Reset on New Instance"]
    )
    AF.SetPoint(
        resetOnNewInstance,
        "TOPLEFT",
        generalPane,
        280,
        -30
    )
    resetOnNewInstance:SetOnCheck(function(checked)
        local ok = DM.Native.SetResetOnNewInstance(checked)
        if ok then
            SetStatus()
        else
            SetStatus(L["Damage Meter CVar Failed"], "firebrick")
            resetOnNewInstance:SetChecked(
                DM.Native.GetResetOnNewInstance()
            )
        end
    end)

    statusText = AF.CreateFontString(generalPane, nil, "gray")
    AF.SetPoint(statusText, "TOPLEFT", generalPane, 15, -57)
    AF.SetPoint(statusText, "TOPRIGHT", generalPane, -15, -57)
    statusText:SetJustifyH("LEFT")

    function generalPane.Load()
        enabled:SetChecked(DM.config.enabled)
        resetOnNewInstance:SetChecked(
            DM.Native.GetResetOnNewInstance()
        )
        if DM.config.enabled and not DM.Data.IsAvailable() then
            SetStatus(
                L["Damage Meter Data Unavailable"],
                "yellow_text"
            )
        else
            SetStatus()
        end
    end
end

local function SetWindowControlState()
    local count = DM.config.windowCount
    for index, dropdown in ipairs(windowTypeDropdowns) do
        dropdown:SetEnabled(index <= count)
    end
end

local function CreateWindowTypeDropdown(parent, index, x, y)
    local dropdown = AF.CreateDropdown(parent, WIDE_CONTROL_WIDTH)
    dropdown:SetLabel(L["Meter %d Type"]:format(index))
    dropdown:SetItems(METER_TYPE_ITEMS)
    AF.SetPoint(dropdown, "TOPLEFT", parent, x, y)
    dropdown:SetOnSelect(function(value)
        DM.config.windowTypes[index] = value
        RefreshDamageMeter()
    end)
    windowTypeDropdowns[index] = dropdown
    return dropdown
end

local function CreateWindowsPane()
    windowsPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Meters"],
        CONTENT_WIDTH,
        165
    )
    AF.SetPoint(
        windowsPane,
        "TOPLEFT",
        generalPane,
        "BOTTOMLEFT",
        0,
        -SECTION_GAP
    )
    SetPaneTips(
        windowsPane,
        L["Meters"],
        L["BFI Damage Meter Windows Tip"]
    )

    windowCount = AF.CreateDropdown(windowsPane, CONTROL_WIDTH)
    windowCount:SetLabel(L["Window Count"])
    AF.SetPoint(windowCount, "TOPLEFT", windowsPane, 15, -50)
    windowCount:SetItems({
        {text = "1", value = 1},
        {text = "2", value = 2},
        {text = "3", value = 3},
    })
    windowCount:SetOnSelect(function(value)
        DM.config.windowCount = value
        SetWindowControlState()
        RefreshDamageMeter()
    end)

    CreateWindowTypeDropdown(windowsPane, 1, 190, -50)
    CreateWindowTypeDropdown(windowsPane, 2, 15, -115)
    CreateWindowTypeDropdown(windowsPane, 3, 280, -115)

    function windowsPane.Load()
        windowCount:SetSelectedValue(DM.config.windowCount)
        for index, dropdown in ipairs(windowTypeDropdowns) do
            dropdown:SetSelectedValue(DM.config.windowTypes[index])
        end
        SetWindowControlState()
    end
end

local function CreateSlider(
    parent,
    label,
    x,
    y,
    min,
    max,
    step,
    isPercentage
)
    local slider = AF.CreateSlider(
        parent,
        label,
        SLIDER_WIDTH,
        min,
        max,
        step,
        isPercentage,
        true
    )
    AF.SetPoint(slider, "TOPLEFT", parent, x, y)
    return slider
end

local function CreateAppearancePane()
    appearancePane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Appearance"],
        CONTENT_WIDTH,
        325
    )
    AF.SetPoint(
        appearancePane,
        "TOPLEFT",
        windowsPane,
        "BOTTOMLEFT",
        0,
        -SECTION_GAP
    )
    SetPaneTips(
        appearancePane,
        L["Appearance"],
        L["BFI Damage Meter Appearance Tip"]
    )

    local width = CreateSlider(
        appearancePane, L["Frame Width"], 15, -55, 220, 520, 1
    )
    width:SetAfterValueChanged(function(value)
        DM.config.width = value
        RefreshDamageMeter()
    end)

    local height = CreateSlider(
        appearancePane, L["Frame Height"], 190, -55, 120, 520, 1
    )
    height:SetAfterValueChanged(function(value)
        DM.config.height = value
        RefreshDamageMeter()
    end)

    local headerHeight = CreateSlider(
        appearancePane, L["Header Height"], 365, -55, 18, 36, 1
    )
    headerHeight:SetAfterValueChanged(function(value)
        DM.config.headerHeight = value
        RefreshDamageMeter()
    end)

    local barHeight = CreateSlider(
        appearancePane, L["Bar Height"], 15, -120, 14, 36, 1
    )
    barHeight:SetAfterValueChanged(function(value)
        DM.config.barHeight = value
        RefreshDamageMeter()
    end)

    local spacing = CreateSlider(
        appearancePane, L["Bar Spacing"], 190, -120, 0, 8, 1
    )
    spacing:SetAfterValueChanged(function(value)
        DM.config.spacing = value
        RefreshDamageMeter()
    end)

    local padding = CreateSlider(
        appearancePane, L["Padding"], 365, -120, 0, 12, 1
    )
    padding:SetAfterValueChanged(function(value)
        DM.config.padding = value
        RefreshDamageMeter()
    end)

    local backgroundAlpha = CreateSlider(
        appearancePane,
        L["Background Opacity"],
        15,
        -185,
        0,
        1,
        0.01,
        true
    )
    backgroundAlpha:SetAfterValueChanged(function(value)
        DM.config.backgroundAlpha = value
        RefreshDamageMeter()
    end)

    local barAlpha = CreateSlider(
        appearancePane,
        L["Bar Opacity"],
        190,
        -185,
        0,
        1,
        0.01,
        true
    )
    barAlpha:SetAfterValueChanged(function(value)
        DM.config.barAlpha = value
        RefreshDamageMeter()
    end)

    local texture = AF.CreateDropdown(
        appearancePane,
        CONTROL_WIDTH
    )
    texture:SetLabel(L["Bar Texture"])
    AF.SetPoint(texture, "TOPLEFT", appearancePane, 365, -185)
    texture:SetItems(AF.LSM_GetBarTextureDropdownItems())
    texture:SetOnSelect(function(value)
        DM.config.texture = value
        RefreshDamageMeter()
    end)

    local numberMode = AF.CreateDropdown(
        appearancePane,
        CONTROL_WIDTH
    )
    numberMode:SetLabel(L["Number Format"])
    AF.SetPoint(numberMode, "TOPLEFT", appearancePane, 15, -250)
    numberMode:SetItems(NUMBER_MODE_ITEMS)
    numberMode:SetOnSelect(function(value)
        DM.config.numberMode = value
        RefreshDamageMeter()
    end)

    local showSpecIcon = AF.CreateCheckButton(
        appearancePane,
        L["Show Specialization Icons"]
    )
    AF.SetPoint(showSpecIcon, "TOPLEFT", appearancePane, 190, -250)
    showSpecIcon:SetOnCheck(function(checked)
        DM.config.showSpecIcon = checked
        RefreshDamageMeter()
    end)

    local classColor = AF.CreateCheckButton(
        appearancePane,
        L["Use Class Colors"]
    )
    AF.SetPoint(classColor, "TOPLEFT", appearancePane, 380, -250)
    classColor:SetOnCheck(function(checked)
        DM.config.classColor = checked
        RefreshDamageMeter()
    end)

    local accentHeader = AF.CreateCheckButton(
        appearancePane,
        L["Accent Header"]
    )
    AF.SetPoint(accentHeader, "TOPLEFT", appearancePane, 15, -292)
    accentHeader:SetOnCheck(function(checked)
        DM.config.accentHeader = checked
        RefreshDamageMeter()
    end)

    function appearancePane.Load()
        local config = DM.config
        width:SetValue(config.width)
        height:SetValue(config.height)
        headerHeight:SetValue(config.headerHeight)
        barHeight:SetValue(config.barHeight)
        spacing:SetValue(config.spacing)
        padding:SetValue(config.padding)
        backgroundAlpha:SetValue(config.backgroundAlpha)
        barAlpha:SetValue(config.barAlpha)
        texture:SetSelectedValue(config.texture)
        numberMode:SetSelectedValue(config.numberMode)
        showSpecIcon:SetChecked(config.showSpecIcon)
        classColor:SetChecked(config.classColor)
        accentHeader:SetChecked(config.accentHeader)
    end
end

local function CreateActionsPane()
    actionsPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Damage Meter Actions"],
        CONTENT_WIDTH,
        100
    )
    AF.SetPoint(
        actionsPane,
        "TOPLEFT",
        appearancePane,
        "BOTTOMLEFT",
        0,
        -SECTION_GAP
    )

    local bottomRight = AF.CreateButton(
        actionsPane,
        L["Place Meters Bottom Right"],
        "BFI",
        245,
        25
    )
    AF.SetPoint(bottomRight, "TOPLEFT", actionsPane, 15, -42)
    bottomRight:SetOnClick(function()
        if DM.Renderer
            and type(DM.Renderer.ResetPosition) == "function" then
            DM.Renderer.ResetPosition()
        end
    end)

    local reset = AF.CreateButton(
        actionsPane,
        L["Reset Combat Data"],
        "red",
        245,
        25
    )
    AF.SetPoint(reset, "TOPLEFT", actionsPane, 270, -42)
    reset:SetOnClick(function()
        local dialog = AF.GetDialog(
            damageMeterPanel,
            L["Reset all Damage Meter combat data?"],
            300
        )
        AF.SetPoint(dialog, "TOP", damageMeterPanel, 0, -50)
        dialog:SetOnConfirm(function()
            DM.Data.Reset()
        end)
    end)
end

local function Load()
    if not DM.config then return end

    generalPane.Load()
    windowsPane.Load()
    appearancePane.Load()
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "damageMeter" or not damageMeterPanel then return end
    Load()
end)

AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "damageMeter" then
        if not damageMeterPanel then
            CreateDamageMeterPanel()
            CreateGeneralPane()
            CreateWindowsPane()
            CreateAppearancePane()
            CreateActionsPane()
        end
        Load()
        damageMeterPanel:Show()
    elseif damageMeterPanel then
        damageMeterPanel:Hide()
    end
end)
