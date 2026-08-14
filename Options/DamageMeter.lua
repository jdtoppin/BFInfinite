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
local automationPane
local appearancePane
local actionsPane
local statusText
local windowCount
local lockMeters
local alwaysShowPlayer
local windowTypeDropdowns = {}
local windowHeightSliders = {}
local mythicPlusTypeDropdowns = {}
local syncSessionChecks = {}
local autoCurrentOnCombatChecks = {}
local autoCurrentOnMythicPlusStartChecks = {}
local autoOverallOnMythicPlusCompleteChecks = {}
local CreateSlider

local CONTENT_WIDTH = 530
local CONTENT_HEIGHT = 1235
local SECTION_GAP = 12
local GENERAL_HEIGHT = 60
local GENERAL_STATUS_HEIGHT = 80
local CONTROL_WIDTH = 150
local WIDE_CONTROL_WIDTH = 240
local SLIDER_WIDTH = 140
local MIN_WINDOW_HEIGHT = 84
local MAX_WINDOW_HEIGHT = 520
local MIN_ROW_TEXT_SIZE = 8
local MAX_ROW_TEXT_SIZE = 14
local ROW_TEXT_VERTICAL_PADDING = 4
local MIN_HEADER_TEXT_SIZE = 8
local MAX_HEADER_TEXT_SIZE = 14
local HEADER_TEXT_VERTICAL_PADDING = 6

local function GetMeterTypeText(globalName, fallback)
    return _G[globalName] or L[fallback]
end

local METER_TYPE_ITEMS = {
    {
        text = GetMeterTypeText(
            "DAMAGE_METER_TYPE_DAMAGE_DONE",
            "Damage Done"
        ),
        value = "DamageDone",
    },
    {
        text = GetMeterTypeText("DAMAGE_METER_TYPE_DPS", "Damage Per Second"),
        value = "Dps",
    },
    {
        text = GetMeterTypeText(
            "DAMAGE_METER_TYPE_DAMAGE_TAKEN",
            "Damage Taken"
        ),
        value = "DamageTaken",
    },
    {
        text = GetMeterTypeText(
            "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN",
            "Avoidable Damage Taken"
        ),
        value = "AvoidableDamageTaken",
    },
    {
        text = GetMeterTypeText(
            "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN",
            "Enemy Damage Taken"
        ),
        value = "EnemyDamageTaken",
    },
    {
        text = GetMeterTypeText(
            "DAMAGE_METER_TYPE_HEALING_DONE",
            "Healing Done"
        ),
        value = "HealingDone",
    },
    {
        text = GetMeterTypeText("DAMAGE_METER_TYPE_HPS", "Healing Per Second"),
        value = "Hps",
    },
    {
        text = GetMeterTypeText("DAMAGE_METER_TYPE_ABSORBS", "Absorbs"),
        value = "Absorbs",
    },
    {
        text = GetMeterTypeText("DAMAGE_METER_TYPE_INTERRUPTS", "Interrupts"),
        value = "Interrupts",
    },
    {
        text = GetMeterTypeText("DAMAGE_METER_TYPE_DISPELS", "Dispels"),
        value = "Dispels",
    },
    {
        text = GetMeterTypeText("DAMAGE_METER_TYPE_DEATHS", "Deaths"),
        value = "Deaths",
    },
}

local NUMBER_MODE_ITEMS = {
    {text = L["Total"], value = "total"},
    {text = L["Per Second"], value = "perSecond"},
    {text = L["Total and Per Second"], value = "both"},
}

local KEEP_CURRENT_TYPE = "__keepCurrentType"
local MYTHIC_PLUS_TYPE_ITEMS = {
    {text = L["Keep Current Type"], value = KEEP_CURRENT_TYPE},
}
for _, item in ipairs(METER_TYPE_ITEMS) do
    MYTHIC_PLUS_TYPE_ITEMS[#MYTHIC_PLUS_TYPE_ITEMS + 1] = item
end

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

local function GetMinimumWindowHeight(config)
    return math.max(
        MIN_WINDOW_HEIGHT,
        config.headerHeight + (config.padding * 2) + config.barHeight
    )
end

local function GetMaximumRowTextSize(config)
    return math.max(
        MIN_ROW_TEXT_SIZE,
        math.min(
            MAX_ROW_TEXT_SIZE,
            config.barHeight - ROW_TEXT_VERTICAL_PADDING
        )
    )
end

local function GetMaximumHeaderTextSize(config)
    return math.max(
        MIN_HEADER_TEXT_SIZE,
        math.min(
            MAX_HEADER_TEXT_SIZE,
            config.headerHeight - HEADER_TEXT_VERTICAL_PADDING
        )
    )
end

local function RefreshWindowHeightBounds()
    local config = DM.config
    local minimumWindowHeight = GetMinimumWindowHeight(config)

    for index, slider in ipairs(windowHeightSliders) do
        if config.windowHeights[index] < minimumWindowHeight then
            config.windowHeights[index] = minimumWindowHeight
        end
        slider:SetMinMaxValues(minimumWindowHeight, MAX_WINDOW_HEIGHT)
        slider:SetValue(config.windowHeights[index])
    end
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
        local enabled = index <= count
        dropdown:SetEnabled(enabled)
        windowHeightSliders[index]:SetEnabled(enabled)
        if mythicPlusTypeDropdowns[index] then
            mythicPlusTypeDropdowns[index]:SetEnabled(enabled)
            syncSessionChecks[index]:SetEnabled(enabled)
            autoCurrentOnCombatChecks[index]:SetEnabled(enabled)
            autoCurrentOnMythicPlusStartChecks[index]:SetEnabled(enabled)
            autoOverallOnMythicPlusCompleteChecks[index]:SetEnabled(enabled)
        end
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

local function CreateWindowHeightSlider(parent, index, x, y)
    local slider = CreateSlider(
        parent,
        L["Meter %d Height"]:format(index),
        x,
        y,
        MIN_WINDOW_HEIGHT,
        MAX_WINDOW_HEIGHT,
        1
    )
    slider:SetAfterValueChanged(function(value)
        DM.config.windowHeights[index] = value
        RefreshDamageMeter()
    end)
    windowHeightSliders[index] = slider
    return slider
end

local function CreateWindowsPane()
    windowsPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Meters"],
        CONTENT_WIDTH,
        275
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

    lockMeters = AF.CreateCheckButton(windowsPane, L["Lock Meters"])
    AF.SetPoint(lockMeters, "TOPLEFT", windowsPane, 190, -50)
    lockMeters:SetOnCheck(function(checked)
        DM.config.locked = checked
        RefreshDamageMeter()
    end)

    alwaysShowPlayer = AF.CreateCheckButton(
        windowsPane,
        L["Always Show Player"]
    )
    AF.SetPoint(alwaysShowPlayer, "TOPLEFT", windowsPane, 350, -50)
    alwaysShowPlayer:SetOnCheck(function(checked)
        DM.config.alwaysShowPlayer = checked
        RefreshDamageMeter()
    end)

    for index = 1, 3 do
        local y = -105 - ((index - 1) * 65)
        CreateWindowTypeDropdown(windowsPane, index, 15, y)
        CreateWindowHeightSlider(windowsPane, index, 280, y)
    end

    function windowsPane.Load()
        windowCount:SetSelectedValue(DM.config.windowCount)
        lockMeters:SetChecked(DM.config.locked)
        alwaysShowPlayer:SetChecked(DM.config.alwaysShowPlayer)
        RefreshWindowHeightBounds()
        for index, dropdown in ipairs(windowTypeDropdowns) do
            dropdown:SetSelectedValue(DM.config.windowTypes[index])
            windowHeightSliders[index]:SetValue(
                DM.config.windowHeights[index]
            )
        end
        SetWindowControlState()
    end
end

local function CreateAutomationPane()
    automationPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Sessions and Automation"],
        CONTENT_WIDTH,
        385
    )
    AF.SetPoint(
        automationPane,
        "TOPLEFT",
        windowsPane,
        "BOTTOMLEFT",
        0,
        -SECTION_GAP
    )
    SetPaneTips(
        automationPane,
        L["Sessions and Automation"],
        L["BFI Damage Meter Automation Tip"]
    )

    local resetOnMythicPlusStart = AF.CreateCheckButton(
        automationPane,
        L["Reset Data on Mythic+ Start"]
    )
    AF.SetPoint(
        resetOnMythicPlusStart,
        "TOPLEFT",
        automationPane,
        15,
        -32
    )
    resetOnMythicPlusStart:SetOnCheck(function(checked)
        DM.config.resetOnMythicPlusStart = checked
        RefreshDamageMeter()
    end)

    for index = 1, 3 do
        local y = -85 - ((index - 1) * 100)

        local mythicPlusType = AF.CreateDropdown(
            automationPane,
            WIDE_CONTROL_WIDTH
        )
        mythicPlusType:SetLabel(
            L["Meter %d Type on Mythic+ Start"]:format(index)
        )
        mythicPlusType:SetItems(MYTHIC_PLUS_TYPE_ITEMS)
        AF.SetPoint(mythicPlusType, "TOPLEFT", automationPane, 15, y)
        mythicPlusType:SetOnSelect(function(value)
            if value == KEEP_CURRENT_TYPE then
                DM.config.mythicPlusWindowTypes[index] = false
            else
                DM.config.mythicPlusWindowTypes[index] = value
            end
            RefreshDamageMeter()
        end)
        mythicPlusTypeDropdowns[index] = mythicPlusType

        local syncSessions = AF.CreateCheckButton(
            automationPane,
            L["Meter %d Sync Session Selection"]:format(index)
        )
        AF.SetPoint(syncSessions, "TOPLEFT", automationPane, 280, y)
        syncSessions:SetOnCheck(function(checked)
            DM.config.windowSyncSessions[index] = checked
            RefreshDamageMeter()
        end)
        syncSessionChecks[index] = syncSessions

        local autoCurrentOnCombat = AF.CreateCheckButton(
            automationPane,
            L["Meter %d Auto Current on Combat"]:format(index)
        )
        AF.SetPoint(
            autoCurrentOnCombat,
            "TOPLEFT",
            automationPane,
            280,
            y - 28
        )
        autoCurrentOnCombat:SetOnCheck(function(checked)
            DM.config.windowAutoCurrentOnCombat[index] = checked
            RefreshDamageMeter()
        end)
        autoCurrentOnCombatChecks[index] = autoCurrentOnCombat

        local autoCurrentOnMythicPlusStart = AF.CreateCheckButton(
            automationPane,
            L["Meter %d Current on Mythic+ Start"]:format(index)
        )
        AF.SetPoint(
            autoCurrentOnMythicPlusStart,
            "TOPLEFT",
            automationPane,
            15,
            y - 63
        )
        autoCurrentOnMythicPlusStart:SetOnCheck(function(checked)
            DM.config.windowAutoCurrentOnMythicPlusStart[index] = checked
            RefreshDamageMeter()
        end)
        autoCurrentOnMythicPlusStartChecks[index] =
            autoCurrentOnMythicPlusStart

        local autoOverallOnMythicPlusComplete = AF.CreateCheckButton(
            automationPane,
            L["Meter %d Overall on Mythic+ Complete"]:format(index)
        )
        AF.SetPoint(
            autoOverallOnMythicPlusComplete,
            "TOPLEFT",
            automationPane,
            280,
            y - 63
        )
        autoOverallOnMythicPlusComplete:SetOnCheck(function(checked)
            DM.config.windowAutoOverallOnMythicPlusComplete[index] =
                checked
            RefreshDamageMeter()
        end)
        autoOverallOnMythicPlusCompleteChecks[index] =
            autoOverallOnMythicPlusComplete
    end

    function automationPane.Load()
        local config = DM.config
        resetOnMythicPlusStart:SetChecked(config.resetOnMythicPlusStart)
        for index = 1, 3 do
            mythicPlusTypeDropdowns[index]:SetSelectedValue(
                config.mythicPlusWindowTypes[index] or KEEP_CURRENT_TYPE
            )
            syncSessionChecks[index]:SetChecked(
                config.windowSyncSessions[index]
            )
            autoCurrentOnCombatChecks[index]:SetChecked(
                config.windowAutoCurrentOnCombat[index]
            )
            autoCurrentOnMythicPlusStartChecks[index]:SetChecked(
                config.windowAutoCurrentOnMythicPlusStart[index]
            )
            autoOverallOnMythicPlusCompleteChecks[index]:SetChecked(
                config.windowAutoOverallOnMythicPlusComplete[index]
            )
        end
        SetWindowControlState()
    end
end

CreateSlider = function(
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
        340
    )
    AF.SetPoint(
        appearancePane,
        "TOPLEFT",
        automationPane,
        "BOTTOMLEFT",
        0,
        -SECTION_GAP
    )
    SetPaneTips(
        appearancePane,
        L["Appearance"],
        L["BFI Damage Meter Appearance Tip"]
    )

    local barTextSize
    local headerTextSize
    local function RefreshBarTextSizeBounds()
        if not barTextSize then return end

        local maximum = GetMaximumRowTextSize(DM.config)
        if DM.config.rowTextSize > maximum then
            DM.config.rowTextSize = maximum
        end
        barTextSize:SetMinMaxValues(MIN_ROW_TEXT_SIZE, maximum)
        barTextSize:SetValue(DM.config.rowTextSize)
    end

    local function RefreshHeaderTextSizeBounds()
        if not headerTextSize then return end

        local maximum = GetMaximumHeaderTextSize(DM.config)
        if DM.config.headerTextSize > maximum then
            DM.config.headerTextSize = maximum
        end
        headerTextSize:SetMinMaxValues(MIN_HEADER_TEXT_SIZE, maximum)
        headerTextSize:SetValue(DM.config.headerTextSize)
    end

    local width = CreateSlider(
        appearancePane, L["Frame Width"], 15, -55, 220, 520, 1
    )
    width:SetAfterValueChanged(function(value)
        DM.config.width = value
        RefreshDamageMeter()
    end)

    local headerHeight = CreateSlider(
        appearancePane, L["Header Height"], 190, -55, 18, 36, 1
    )
    headerHeight:SetAfterValueChanged(function(value)
        DM.config.headerHeight = value
        RefreshHeaderTextSizeBounds()
        RefreshWindowHeightBounds()
        RefreshDamageMeter()
    end)

    local barHeight = CreateSlider(
        appearancePane, L["Bar Height"], 365, -55, 14, 36, 1
    )
    barHeight:SetAfterValueChanged(function(value)
        DM.config.barHeight = value
        RefreshBarTextSizeBounds()
        RefreshWindowHeightBounds()
        RefreshDamageMeter()
    end)

    local spacing = CreateSlider(
        appearancePane, L["Bar Spacing"], 15, -120, 0, 8, 1
    )
    spacing:SetAfterValueChanged(function(value)
        DM.config.spacing = value
        RefreshDamageMeter()
    end)

    local padding = CreateSlider(
        appearancePane, L["Padding"], 190, -120, 0, 12, 1
    )
    padding:SetAfterValueChanged(function(value)
        DM.config.padding = value
        RefreshWindowHeightBounds()
        RefreshDamageMeter()
    end)

    local backgroundAlpha = CreateSlider(
        appearancePane,
        L["Background Opacity"],
        365,
        -120,
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
        15,
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
    AF.SetPoint(texture, "TOPLEFT", appearancePane, 190, -185)
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
    AF.SetPoint(numberMode, "TOPLEFT", appearancePane, 365, -185)
    numberMode:SetItems(NUMBER_MODE_ITEMS)
    numberMode:SetOnSelect(function(value)
        DM.config.numberMode = value
        RefreshDamageMeter()
    end)

    local showSpecIcon = AF.CreateCheckButton(
        appearancePane,
        L["Show Specialization Icons"]
    )
    AF.SetPoint(showSpecIcon, "TOPLEFT", appearancePane, 15, -250)
    showSpecIcon:SetOnCheck(function(checked)
        DM.config.showSpecIcon = checked
        RefreshDamageMeter()
    end)

    local classColor = AF.CreateCheckButton(
        appearancePane,
        L["Use Class Colors"]
    )
    AF.SetPoint(classColor, "TOPLEFT", appearancePane, 200, -250)
    classColor:SetOnCheck(function(checked)
        DM.config.classColor = checked
        RefreshDamageMeter()
    end)

    barTextSize = CreateSlider(
        appearancePane,
        L["Bar Text Size"],
        15,
        -305,
        MIN_ROW_TEXT_SIZE,
        GetMaximumRowTextSize(DM.config),
        1
    )
    barTextSize:SetAfterValueChanged(function(value)
        DM.config.rowTextSize = value
        RefreshDamageMeter()
    end)

    headerTextSize = CreateSlider(
        appearancePane,
        L["Header Text Size"],
        190,
        -305,
        MIN_HEADER_TEXT_SIZE,
        GetMaximumHeaderTextSize(DM.config),
        1
    )
    headerTextSize:SetAfterValueChanged(function(value)
        DM.config.headerTextSize = value
        RefreshDamageMeter()
    end)

    function appearancePane.Load()
        local config = DM.config
        width:SetValue(config.width)
        headerHeight:SetValue(config.headerHeight)
        barHeight:SetValue(config.barHeight)
        RefreshBarTextSizeBounds()
        RefreshHeaderTextSizeBounds()
        spacing:SetValue(config.spacing)
        padding:SetValue(config.padding)
        backgroundAlpha:SetValue(config.backgroundAlpha)
        barAlpha:SetValue(config.barAlpha)
        texture:SetSelectedValue(config.texture)
        numberMode:SetSelectedValue(config.numberMode)
        showSpecIcon:SetChecked(config.showSpecIcon)
        classColor:SetChecked(config.classColor)
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

    local placeMeters = AF.CreateButton(
        actionsPane,
        L["Place Meters Below Objective Tracker"],
        "BFI",
        245,
        25
    )
    AF.SetPoint(placeMeters, "TOPLEFT", actionsPane, 15, -42)
    placeMeters:SetOnClick(function()
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
    automationPane.Load()
    appearancePane.Load()
end

local function RefreshScrollLayout()
    local currentPanel = damageMeterPanel
    local currentScroll = scroll
    C_Timer.After(0, function()
        if currentPanel:IsShown() then
            AF.RePoint(currentScroll)
        end
    end)
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
            CreateAutomationPane()
            CreateAppearancePane()
            CreateActionsPane()
        end
        Load()
        damageMeterPanel:Show()
        RefreshScrollLayout()
    elseif damageMeterPanel then
        damageMeterPanel:Hide()
    end
end)
