---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local CM = BFI.modules.CooldownManager
---@type AbstractFramework
local AF = _G.AbstractFramework

local ReloadUI = _G.ReloadUI

local panel
local contentPane
local selectedID = "general"
local allPanes = {}
local optionGroups = {}
local CONTROL_WIDTH = 150
local COLUMN_OFFSET = 185

local function UpdateModule()
    AF.Fire("BFI_UpdateModule", "cooldownManager")
end

local function RequestReload()
    local dialog = AF.GetDialog(panel, L["A UI reload is required\nDo it now?"])
    AF.SetPoint(dialog, "TOP", 0, -50)
    dialog:SetOnConfirm(ReloadUI)
end

local function RegisterPane(pane)
    allPanes[#allPanes + 1] = pane
    return pane
end

local function SetConfigColor(config, r, g, b)
    config[1] = r
    config[2] = g
    config[3] = b
end

local function CreateOptionRow(parent, height)
    return RegisterPane(AF.CreateBorderedFrame(parent, nil, nil, height))
end

local function CreateModulePanes(parent)
    local panes = {}

    local enabledPane = CreateOptionRow(parent, 30)
    panes[#panes + 1] = enabledPane

    local enabled = AF.CreateCheckButton(enabledPane, L["Enabled"])
    AF.SetPoint(enabled, "LEFT", 15, 0)
    enabled:SetOnCheck(function(checked)
        CM.config.enabled = checked
        UpdateModule()
        if not checked then
            RequestReload()
        end
        AF.Fire("BFI_RefreshOptions", "cooldownManager")
    end)

    function enabledPane.Load()
        enabled:SetChecked(CM.config.enabled)
    end

    local skinPane = CreateOptionRow(parent, 30)
    panes[#panes + 1] = skinPane

    local skin = AF.CreateCheckButton(skinPane, L["Skin Cooldown Manager Icons"])
    AF.SetPoint(skin, "LEFT", 15, 0)
    skin:SetOnCheck(function(checked)
        CM.config.skin = checked
        if checked then
            UpdateModule()
        else
            RequestReload()
        end
    end)

    function skinPane.Load()
        skin:SetChecked(CM.config.skin)
        skin:SetEnabled(CM.config.enabled)
    end

    local tipPane = CreateOptionRow(parent, 45)
    panes[#panes + 1] = tipPane

    local tip = AF.CreateFontString(
        tipPane,
        L["BFI changes presentation only. Blizzard still controls tracked abilities, cooldown data, and alerts."],
        "gray"
    )
    AF.SetPoint(tip, "TOPLEFT", 15, -8)
    AF.SetPoint(tip, "BOTTOMRIGHT", -15, 8)
    tip:SetJustifyH("LEFT")
    tip:SetJustifyV("MIDDLE")
    tip:SetWordWrap(true)

    function tipPane.Load()
    end

    return panes
end

local function CreateFontPane(parent, configKey, label)
    local pane = CreateOptionRow(parent, 125)

    local title = AF.CreateFontString(pane, label, "BFI")
    AF.SetPoint(title, "TOPLEFT", 15, -10)

    local font = AF.CreateDropdown(pane, CONTROL_WIDTH)
    AF.SetPoint(font, "TOPLEFT", 15, -40)
    font:SetLabel(L["Font"])
    font:SetItems(AF.LSM_GetFontDropdownItems())
    font:SetOnSelect(function(value)
        CM.config[configKey].font[1] = value
        UpdateModule()
    end)

    local outline = AF.CreateDropdown(pane, CONTROL_WIDTH)
    AF.SetPoint(outline, "TOPLEFT", font, COLUMN_OFFSET, 0)
    outline:SetLabel(L["Outline"])
    outline:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    outline:SetOnSelect(function(value)
        CM.config[configKey].font[3] = value
        UpdateModule()
    end)

    local size = AF.CreateSlider(pane, L["Size"], CONTROL_WIDTH, 5, 50, 1, nil, true)
    AF.SetPoint(size, "TOPLEFT", font, "BOTTOMLEFT", 0, -25)
    size:SetAfterValueChanged(function(value)
        CM.config[configKey].font[2] = value
        UpdateModule()
    end)

    local shadow = AF.CreateCheckButton(pane, L["Shadow"])
    AF.SetPoint(shadow, "LEFT", size, COLUMN_OFFSET, 0)
    shadow:SetOnCheck(function(checked)
        CM.config[configKey].font[4] = checked
        UpdateModule()
    end)

    local color = AF.CreateColorPicker(pane, L["Color"])
    AF.SetPoint(color, "LEFT", shadow, 115, 0)
    color:SetOnConfirm(function(r, g, b)
        SetConfigColor(CM.config[configKey].color, r, g, b)
        UpdateModule()
    end)

    function pane.UpdateEnabled()
        AF.SetEnabled(CM.config.enabled, font, outline, size, shadow, color)
    end

    function pane.Load()
        local config = CM.config[configKey]
        font:SetSelectedValue(config.font[1])
        outline:SetSelectedValue(config.font[3])
        size:SetValue(config.font[2])
        shadow:SetChecked(config.font[4])
        color:SetColor(config.color)
        pane.UpdateEnabled()
    end

    return pane
end

local orientationItems = {
    {text = L["Horizontal"], value = "horizontal"},
    {text = L["Vertical"], value = "vertical"},
}

local directionItems = {
    {text = L["Left / Down"], value = "left"},
    {text = L["Right / Up"], value = "right"},
}

local visibilityItems = {
    {text = L["Always"], value = "always"},
    {text = L["In Combat"], value = "combat"},
    {text = L["Hidden"], value = "hidden"},
}

local barContentItems = {
    {text = L["Icon and Name"], value = "icon_and_name"},
    {text = L["Icon Only"], value = "icon_only"},
    {text = L["Name Only"], value = "name_only"},
}

local viewerInfo = {
    essential = {
        label = L["Essential Cooldowns"],
        hasOrientation = true,
        hasIconLimit = true,
    },
    utility = {
        label = L["Utility Cooldowns"],
        hasOrientation = true,
        hasIconLimit = true,
    },
    buffIcon = {
        label = L["Buff Icons"],
        hasOrientation = true,
        hasHideWhenInactive = true,
    },
    buffBar = {
        label = L["Buff Bars"],
        hasHideWhenInactive = true,
        hasBarSettings = true,
    },
}

local function CreateViewerPanes(parent, viewerKey)
    local info = viewerInfo[viewerKey]
    local panes = {}

    local function CreateRow(height)
        local pane = CreateOptionRow(parent, height)
        panes[#panes + 1] = pane
        return pane
    end

    local function SetRowLifecycle(pane, widgets, load)
        function pane.UpdateEnabled()
            AF.SetEnabled(CM.config.enabled, unpack(widgets))
        end

        function pane.Load()
            load(CM.config.viewers[viewerKey])
            pane.UpdateEnabled()
        end
    end

    local centerPane = CreateRow(30)
    local center = AF.CreateCheckButton(centerPane, L["Center Incomplete Lines"])
    AF.SetPoint(center, "LEFT", 15, 0)
    center:SetOnCheck(function(checked)
        CM.config.viewers[viewerKey].center = checked
        UpdateModule()
    end)
    SetRowLifecycle(centerPane, {center}, function(config)
        center:SetChecked(config.center)
    end)

    local layoutPane = CreateRow(55)
    local layoutWidgets = {}
    local orientation
    if info.hasOrientation then
        orientation = AF.CreateDropdown(layoutPane, CONTROL_WIDTH)
        layoutWidgets[#layoutWidgets + 1] = orientation
        AF.SetPoint(orientation, "TOPLEFT", 15, -25)
        orientation:SetLabel(L["Orientation"])
        orientation:SetItems(orientationItems)
        orientation:SetOnSelect(function(value)
            CM.config.viewers[viewerKey].orientation = value
            UpdateModule()
        end)
    end

    local direction = AF.CreateDropdown(layoutPane, CONTROL_WIDTH)
    layoutWidgets[#layoutWidgets + 1] = direction
    if orientation then
        AF.SetPoint(direction, "TOPLEFT", orientation, COLUMN_OFFSET, 0)
    else
        AF.SetPoint(direction, "TOPLEFT", 15, -25)
    end
    direction:SetLabel(L["Growth Direction"])
    direction:SetItems(directionItems)
    direction:SetOnSelect(function(value)
        CM.config.viewers[viewerKey].direction = value
        UpdateModule()
    end)
    SetRowLifecycle(layoutPane, layoutWidgets, function(config)
        if orientation then
            orientation:SetSelectedValue(config.orientation)
        end
        direction:SetSelectedValue(config.direction)
    end)

    local scalePane = CreateRow(55)
    local scaleWidgets = {}
    local iconLimit
    if info.hasIconLimit then
        iconLimit = AF.CreateSlider(scalePane, L["Icons Per Line"], CONTROL_WIDTH, 1, 20, 1, nil, true)
        scaleWidgets[#scaleWidgets + 1] = iconLimit
        AF.SetPoint(iconLimit, "TOPLEFT", 15, -25)
        iconLimit:SetAfterValueChanged(function(value)
            CM.config.viewers[viewerKey].iconLimit = value
            UpdateModule()
        end)
    end

    local scale = AF.CreateSlider(scalePane, L["Icon Scale"], CONTROL_WIDTH, 0.5, 2, 0.05, true, true)
    scaleWidgets[#scaleWidgets + 1] = scale
    if iconLimit then
        AF.SetPoint(scale, "TOPLEFT", iconLimit, COLUMN_OFFSET, 0)
    else
        AF.SetPoint(scale, "TOPLEFT", 15, -25)
    end
    scale:SetAfterValueChanged(function(value)
        CM.config.viewers[viewerKey].scale = value
        UpdateModule()
    end)
    SetRowLifecycle(scalePane, scaleWidgets, function(config)
        if iconLimit then
            iconLimit:SetValue(config.iconLimit)
        end
        scale:SetValue(config.scale)
    end)

    local appearancePane = CreateRow(55)
    local padding = AF.CreateSlider(appearancePane, L["Spacing"], CONTROL_WIDTH, 0, 14, 1, nil, true)
    AF.SetPoint(padding, "TOPLEFT", 15, -25)
    padding:SetAfterValueChanged(function(value)
        CM.config.viewers[viewerKey].padding = value
        UpdateModule()
    end)

    local opacity = AF.CreateSlider(appearancePane, L["Opacity"], CONTROL_WIDTH, 0.5, 1, 0.05, true, true)
    AF.SetPoint(opacity, "TOPLEFT", padding, COLUMN_OFFSET, 0)
    opacity:SetAfterValueChanged(function(value)
        CM.config.viewers[viewerKey].opacity = value
        UpdateModule()
    end)
    SetRowLifecycle(appearancePane, {padding, opacity}, function(config)
        padding:SetValue(config.padding)
        opacity:SetValue(config.opacity)
    end)

    local visibilityPane = CreateRow(75)
    local visibility = AF.CreateDropdown(visibilityPane, CONTROL_WIDTH)
    AF.SetPoint(visibility, "TOPLEFT", 15, -25)
    visibility:SetLabel(L["Visibility"])
    visibility:SetItems(visibilityItems)
    visibility:SetOnSelect(function(value)
        CM.config.viewers[viewerKey].visibility = value
        UpdateModule()
    end)

    local showTimer = AF.CreateCheckButton(visibilityPane, L["Show Cooldown Timers"])
    AF.SetPoint(showTimer, "TOPLEFT", visibility, COLUMN_OFFSET, 3)
    showTimer:SetOnCheck(function(checked)
        CM.config.viewers[viewerKey].showTimer = checked
        UpdateModule()
    end)

    local showTooltips = AF.CreateCheckButton(visibilityPane, L["Show Tooltips"])
    AF.SetPoint(showTooltips, "TOPLEFT", showTimer, "BOTTOMLEFT", 0, -12)
    showTooltips:SetOnCheck(function(checked)
        CM.config.viewers[viewerKey].showTooltips = checked
        UpdateModule()
    end)
    SetRowLifecycle(visibilityPane, {visibility, showTimer, showTooltips}, function(config)
        visibility:SetSelectedValue(config.visibility)
        showTimer:SetChecked(config.showTimer)
        showTooltips:SetChecked(config.showTooltips)
    end)

    if info.hasHideWhenInactive then
        local inactivePane = CreateRow(30)
        local hideWhenInactive = AF.CreateCheckButton(inactivePane, L["Hide When Inactive"])
        AF.SetPoint(hideWhenInactive, "LEFT", 15, 0)
        hideWhenInactive:SetOnCheck(function(checked)
            CM.config.viewers[viewerKey].hideWhenInactive = checked
            UpdateModule()
        end)
        SetRowLifecycle(inactivePane, {hideWhenInactive}, function(config)
            hideWhenInactive:SetChecked(config.hideWhenInactive)
        end)
    end

    if info.hasBarSettings then
        local barPane = CreateRow(55)
        local barContent = AF.CreateDropdown(barPane, CONTROL_WIDTH)
        AF.SetPoint(barContent, "TOPLEFT", 15, -25)
        barContent:SetLabel(L["Bar Content"])
        barContent:SetItems(barContentItems)
        barContent:SetOnSelect(function(value)
            CM.config.viewers[viewerKey].barContent = value
            UpdateModule()
        end)

        local barWidthScale = AF.CreateSlider(barPane, L["Bar Width Scale"], CONTROL_WIDTH, 0.5, 2, 0.05, true, true)
        AF.SetPoint(barWidthScale, "TOPLEFT", barContent, COLUMN_OFFSET, 0)
        barWidthScale:SetAfterValueChanged(function(value)
            CM.config.viewers[viewerKey].barWidthScale = value
            UpdateModule()
        end)
        SetRowLifecycle(barPane, {barContent, barWidthScale}, function(config)
            barContent:SetSelectedValue(config.barContent)
            barWidthScale:SetValue(config.barWidthScale)
        end)
    end

    return panes
end

local function CreateOptionGroups(parent)
    if optionGroups.general then return end

    optionGroups.general = CreateModulePanes(parent)
    optionGroups.general[#optionGroups.general + 1] = CreateFontPane(parent, "cooldownText", L["Cooldown Text"])
    optionGroups.general[#optionGroups.general + 1] = CreateFontPane(parent, "countText", L["Count Text"])
    optionGroups.general[#optionGroups.general + 1] = CreateFontPane(parent, "barText", L["Bar Text"])

    for key in next, viewerInfo do
        optionGroups[key] = CreateViewerPanes(parent, key)
    end
end

local function GetOptions(id)
    for _, pane in ipairs(allPanes) do
        pane:Hide()
        AF.ClearPoints(pane)
    end

    local options = optionGroups[id] or {}
    for _, pane in ipairs(options) do
        pane:Show()
    end
    return options
end

local LoadOptions

local function UpdateListColors()
    if not contentPane or not CM.config then return end
    for _, button in ipairs(contentPane.list:GetWidgets()) do
        button:SetTextColor(CM.config.enabled and "white" or "disabled")
    end
end

LoadOptions = function(button)
    selectedID = button.id

    local scroll = contentPane.scrollSettings
    local options = GetOptions(selectedID)
    local heights = {}
    local last

    for _, pane in ipairs(options) do
        if last then
            AF.SetPoint(pane, "TOPLEFT", last, "BOTTOMLEFT", 0, -10)
        else
            AF.SetPoint(pane, "TOPLEFT", scroll.scrollContent)
        end
        AF.SetPoint(pane, "RIGHT", scroll.scrollContent)
        last = pane
        heights[#heights + 1] = pane._height or tostring(pane:GetHeight())
    end

    scroll:SetContentHeights(heights, 10)
    C_Timer.After(0, function()
        AF.RePoint(scroll)
        for _, pane in ipairs(options) do
            pane.Load()
        end
    end)
end

local function ReloadSelected()
    if not contentPane then return end
    for _, button in ipairs(contentPane.list:GetWidgets()) do
        if button.id == selectedID then
            LoadOptions(button)
            return
        end
    end
end

local function CreatePanel()
    panel = AF.CreateFrame(BFIOptionsFrame_ContentPane, "BFIOptionsFrame_CooldownManagerPanel")
    panel:SetAllPoints()

    contentPane = AF.CreateFrame(panel)
    AF.SetPoint(contentPane, "TOPLEFT", 15, -15)
    AF.SetPoint(contentPane, "BOTTOMRIGHT", -15, 15)

    local list = AF.CreateScrollList(contentPane, nil, 0, 0, 28, 20, -1)
    contentPane.list = list
    list:SetPoint("TOPLEFT")
    AF.SetWidth(list, 150)
    list:SetupButtonGroup("BFI_transparent", LoadOptions)
    list:SetData({
        {text = L["General"], id = "general"},
        {text = viewerInfo.essential.label, id = "essential"},
        {text = viewerInfo.utility.label, id = "utility"},
        {text = viewerInfo.buffIcon.label, id = "buffIcon"},
        {text = viewerInfo.buffBar.label, id = "buffBar"},
    })

    local scrollSettings = AF.CreateScrollFrame(contentPane, nil, nil, nil, "none", "none")
    contentPane.scrollSettings = scrollSettings
    scrollSettings.scrollBar:SetBackdropBorderColor(AF.GetColorRGB("border"))
    AF.SetPoint(scrollSettings, "TOPLEFT", list, "TOPRIGHT", 15, 0)
    AF.SetPoint(scrollSettings, "BOTTOM", list)
    AF.SetPoint(scrollSettings, "RIGHT")
    scrollSettings:SetScrollStep(50)

    CreateOptionGroups(scrollSettings.scrollContent)
    UpdateListColors()
    list:Select(selectedID)
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "cooldownManager" or not contentPane then return end
    UpdateListColors()
    ReloadSelected()
end)

AF.RegisterCallback("BFI_UpdateProfile", function()
    if not contentPane then return end
    UpdateListColors()
    ReloadSelected()
end, "low")

AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "cooldownManager" then
        if not panel then
            CreatePanel()
        else
            UpdateListColors()
            ReloadSelected()
        end
        panel:Show()
    elseif panel then
        panel:Hide()
    end
end)
