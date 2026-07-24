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

local function CreateModulePane(parent)
    local pane = RegisterPane(AF.CreateTitledPane(parent, L["Cooldown Manager"], nil, 115))

    local enabled = AF.CreateCheckButton(pane, L["Enabled"])
    AF.SetPoint(enabled, "TOPLEFT", 15, -35)
    enabled:SetOnCheck(function(checked)
        CM.config.enabled = checked
        if checked then
            UpdateModule()
        else
            RequestReload()
        end
        AF.Fire("BFI_RefreshOptions", "cooldownManager")
    end)

    local skin = AF.CreateCheckButton(pane, L["Skin Cooldown Manager Icons"])
    AF.SetPoint(skin, "TOPLEFT", enabled, "BOTTOMLEFT", 0, -12)
    skin:SetOnCheck(function(checked)
        CM.config.skin = checked
        if checked then
            UpdateModule()
        else
            RequestReload()
        end
    end)

    local tip = AF.CreateFontString(
        pane,
        L["BFI changes presentation only. Blizzard still controls tracked abilities, cooldown data, and alerts."],
        "gray"
    )
    AF.SetPoint(tip, "TOPLEFT", enabled, 245, 2)
    AF.SetPoint(tip, "RIGHT", pane, -15, 0)
    tip:SetJustifyH("LEFT")
    tip:SetWordWrap(true)

    function pane.UpdateEnabled()
        skin:SetEnabled(CM.config.enabled)
    end

    function pane.Load()
        enabled:SetChecked(CM.config.enabled)
        skin:SetChecked(CM.config.skin)
        pane.UpdateEnabled()
    end

    return pane
end

local function CreateFontPane(parent, configKey, label)
    local pane = RegisterPane(AF.CreateTitledPane(parent, label, nil, 145))

    local font = AF.CreateDropdown(pane, 170)
    AF.SetPoint(font, "TOPLEFT", 15, -45)
    font:SetLabel(L["Font"])
    font:SetItems(AF.LSM_GetFontDropdownItems())
    font:SetOnSelect(function(value)
        CM.config[configKey].font[1] = value
        UpdateModule()
    end)

    local outline = AF.CreateDropdown(pane, 170)
    AF.SetPoint(outline, "TOPLEFT", font, 200, 0)
    outline:SetLabel(L["Outline"])
    outline:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    outline:SetOnSelect(function(value)
        CM.config[configKey].font[3] = value
        UpdateModule()
    end)

    local size = AF.CreateSlider(pane, L["Size"], 170, 5, 50, 1, nil, true)
    AF.SetPoint(size, "TOPLEFT", font, "BOTTOMLEFT", 0, -30)
    size:SetAfterValueChanged(function(value)
        CM.config[configKey].font[2] = value
        UpdateModule()
    end)

    local shadow = AF.CreateCheckButton(pane, L["Shadow"])
    AF.SetPoint(shadow, "LEFT", size, 200, 0)
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

local function CreateViewerPane(parent, viewerKey)
    local info = viewerInfo[viewerKey]
    local pane = RegisterPane(AF.CreateTitledPane(parent, info.label, nil, info.hasBarSettings and 455 or 390))
    local widgets = {}

    local function AddWidget(widget)
        widgets[#widgets + 1] = widget
        return widget
    end

    local center = AddWidget(AF.CreateCheckButton(pane, L["Center Incomplete Lines"]))
    AF.SetPoint(center, "TOPLEFT", 15, -35)
    center:SetOnCheck(function(checked)
        CM.config.viewers[viewerKey].center = checked
        UpdateModule()
    end)

    local orientation
    if info.hasOrientation then
        orientation = AddWidget(AF.CreateDropdown(pane, 180))
        AF.SetPoint(orientation, "TOPLEFT", center, "BOTTOMLEFT", 0, -35)
        orientation:SetLabel(L["Orientation"])
        orientation:SetItems(orientationItems)
        orientation:SetOnSelect(function(value)
            CM.config.viewers[viewerKey].orientation = value
            UpdateModule()
        end)
    end

    local direction = AddWidget(AF.CreateDropdown(pane, 180))
    if orientation then
        AF.SetPoint(direction, "TOPLEFT", orientation, 210, 0)
    else
        AF.SetPoint(direction, "TOPLEFT", center, "BOTTOMLEFT", 0, -35)
    end
    direction:SetLabel(L["Growth Direction"])
    direction:SetItems(directionItems)
    direction:SetOnSelect(function(value)
        CM.config.viewers[viewerKey].direction = value
        UpdateModule()
    end)

    local firstRow = orientation or direction
    local iconLimit
    if info.hasIconLimit then
        iconLimit = AddWidget(AF.CreateSlider(pane, L["Icons Per Line"], 180, 1, 20, 1, nil, true))
        AF.SetPoint(iconLimit, "TOPLEFT", firstRow, "BOTTOMLEFT", 0, -35)
        iconLimit:SetAfterValueChanged(function(value)
            CM.config.viewers[viewerKey].iconLimit = value
            UpdateModule()
        end)
    end

    local scale = AddWidget(AF.CreateSlider(pane, L["Icon Scale"], 180, 0.5, 2, 0.05, true, true))
    if iconLimit then
        AF.SetPoint(scale, "TOPLEFT", iconLimit, 210, 0)
    else
        AF.SetPoint(scale, "TOPLEFT", firstRow, "BOTTOMLEFT", 0, -35)
    end
    scale:SetAfterValueChanged(function(value)
        CM.config.viewers[viewerKey].scale = value
        UpdateModule()
    end)

    local secondRow = iconLimit or scale
    local padding = AddWidget(AF.CreateSlider(pane, L["Spacing"], 180, 0, 14, 1, nil, true))
    AF.SetPoint(padding, "TOPLEFT", secondRow, "BOTTOMLEFT", 0, -35)
    padding:SetAfterValueChanged(function(value)
        CM.config.viewers[viewerKey].padding = value
        UpdateModule()
    end)

    local opacity = AddWidget(AF.CreateSlider(pane, L["Opacity"], 180, 0.5, 1, 0.05, true, true))
    AF.SetPoint(opacity, "TOPLEFT", padding, 210, 0)
    opacity:SetAfterValueChanged(function(value)
        CM.config.viewers[viewerKey].opacity = value
        UpdateModule()
    end)

    local visibility = AddWidget(AF.CreateDropdown(pane, 180))
    AF.SetPoint(visibility, "TOPLEFT", padding, "BOTTOMLEFT", 0, -35)
    visibility:SetLabel(L["Visibility"])
    visibility:SetItems(visibilityItems)
    visibility:SetOnSelect(function(value)
        CM.config.viewers[viewerKey].visibility = value
        UpdateModule()
    end)

    local showTimer = AddWidget(AF.CreateCheckButton(pane, L["Show Cooldown Timers"]))
    AF.SetPoint(showTimer, "TOPLEFT", visibility, 210, 3)
    showTimer:SetOnCheck(function(checked)
        CM.config.viewers[viewerKey].showTimer = checked
        UpdateModule()
    end)

    local showTooltips = AddWidget(AF.CreateCheckButton(pane, L["Show Tooltips"]))
    AF.SetPoint(showTooltips, "TOPLEFT", showTimer, "BOTTOMLEFT", 0, -12)
    showTooltips:SetOnCheck(function(checked)
        CM.config.viewers[viewerKey].showTooltips = checked
        UpdateModule()
    end)

    local hideWhenInactive
    if info.hasHideWhenInactive then
        hideWhenInactive = AddWidget(AF.CreateCheckButton(pane, L["Hide When Inactive"]))
        AF.SetPoint(hideWhenInactive, "TOPLEFT", visibility, "BOTTOMLEFT", 0, -20)
        hideWhenInactive:SetOnCheck(function(checked)
            CM.config.viewers[viewerKey].hideWhenInactive = checked
            UpdateModule()
        end)
    end

    local barContent
    local barWidthScale
    if info.hasBarSettings then
        local anchor = hideWhenInactive or visibility

        barContent = AddWidget(AF.CreateDropdown(pane, 180))
        AF.SetPoint(barContent, "TOPLEFT", anchor, "BOTTOMLEFT", 0, -35)
        barContent:SetLabel(L["Bar Content"])
        barContent:SetItems(barContentItems)
        barContent:SetOnSelect(function(value)
            CM.config.viewers[viewerKey].barContent = value
            UpdateModule()
        end)

        barWidthScale = AddWidget(AF.CreateSlider(pane, L["Bar Width Scale"], 180, 0.5, 2, 0.05, true, true))
        AF.SetPoint(barWidthScale, "TOPLEFT", barContent, 210, 0)
        barWidthScale:SetAfterValueChanged(function(value)
            CM.config.viewers[viewerKey].barWidthScale = value
            UpdateModule()
        end)
    end

    function pane.UpdateEnabled()
        AF.SetEnabled(CM.config.enabled, unpack(widgets))
    end

    function pane.Load()
        local config = CM.config.viewers[viewerKey]
        center:SetChecked(config.center)
        if orientation then
            orientation:SetSelectedValue(config.orientation)
        end
        direction:SetSelectedValue(config.direction)
        if iconLimit then
            iconLimit:SetValue(config.iconLimit)
        end
        scale:SetValue(config.scale)
        padding:SetValue(config.padding)
        opacity:SetValue(config.opacity)
        visibility:SetSelectedValue(config.visibility)
        showTimer:SetChecked(config.showTimer)
        showTooltips:SetChecked(config.showTooltips)
        if hideWhenInactive then
            hideWhenInactive:SetChecked(config.hideWhenInactive)
        end
        if barContent then
            barContent:SetSelectedValue(config.barContent)
            barWidthScale:SetValue(config.barWidthScale)
        end
        pane.UpdateEnabled()
    end

    return pane
end

local function CreateOptionGroups(parent)
    if optionGroups.general then return end

    optionGroups.general = {
        CreateModulePane(parent),
        CreateFontPane(parent, "cooldownText", L["Cooldown Text"]),
        CreateFontPane(parent, "countText", L["Count Text"]),
        CreateFontPane(parent, "barText", L["Bar Text"]),
    }

    for key in next, viewerInfo do
        optionGroups[key] = {CreateViewerPane(parent, key)}
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
