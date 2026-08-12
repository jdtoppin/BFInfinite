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
local anchorPointItems = AF.GetDropdownItems_AnchorPoint()

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

    local function UpdateEnabledColor(checked)
        enabled.label:SetTextColor(AF.GetColorRGB(checked and "softlime" or "firebrick"))
    end

    enabled:SetOnCheck(function(checked)
        CM.config.enabled = checked
        UpdateEnabledColor(checked)
        UpdateModule()
        if not checked then
            RequestReload()
        end
        AF.Fire("BFI_RefreshOptions", "cooldownManager")
    end)

    function enabledPane.Load()
        UpdateEnabledColor(CM.config.enabled)
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

    local assistedPane = CreateOptionRow(parent, 55)
    panes[#panes + 1] = assistedPane

    local assistedHighlight = AF.CreateCheckButton(assistedPane, L["Show Assisted Highlight on Cooldown Icons"])
    AF.SetPoint(assistedHighlight, "TOPLEFT", 15, -8)
    assistedHighlight:SetOnCheck(function(checked)
        CM.config.assistedHighlight = checked
        UpdateModule()
    end)

    local assistedTip = AF.CreateFontString(
        assistedPane,
        L["Shows Blizzard's current recommendation on Essential and Utility cooldown icons. Follows the global Assisted Highlight setting."],
        "gray"
    )
    AF.SetPoint(assistedTip, "TOPLEFT", assistedHighlight, "BOTTOMLEFT", 0, -3)
    AF.SetPoint(assistedTip, "RIGHT", -15, 0)
    assistedTip:SetJustifyH("LEFT")
    assistedTip:SetWordWrap(true)

    function assistedPane.Load()
        assistedHighlight:SetChecked(CM.config.assistedHighlight)
        assistedHighlight:SetEnabled(CM.config.enabled)
    end

    local tipPane = CreateOptionRow(parent, 60)
    panes[#panes + 1] = tipPane

    local tip = AF.CreateFontString(
        tipPane,
        L["Use BFI Edit Mode to move and preview these layouts. BFI controls presentation and positioning; Blizzard controls tracked abilities, cooldown data, alerts, and inactive entries."],
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

local function CreateFontPane(parent, getConfig, label, withPosition)
    local pane = CreateOptionRow(parent, withPosition and 210 or 125)

    local title = AF.CreateFontString(pane, label, "BFI")
    AF.SetPoint(title, "TOPLEFT", 15, -10)

    local font = AF.CreateDropdown(pane, CONTROL_WIDTH)
    AF.SetPoint(font, "TOPLEFT", 15, -40)
    font:SetLabel(L["Font"])
    font:SetItems(AF.LSM_GetFontDropdownItems())
    font:SetOnSelect(function(value)
        getConfig().font[1] = value
        UpdateModule()
    end)

    local outline = AF.CreateDropdown(pane, CONTROL_WIDTH)
    AF.SetPoint(outline, "TOPLEFT", font, COLUMN_OFFSET, 0)
    outline:SetLabel(L["Outline"])
    outline:SetItems(AF.LSM_GetFontOutlineDropdownItems())
    outline:SetOnSelect(function(value)
        getConfig().font[3] = value
        UpdateModule()
    end)

    local size = AF.CreateSlider(pane, L["Size"], CONTROL_WIDTH, 5, 50, 1, nil, true)
    AF.SetPoint(size, "TOPLEFT", font, "BOTTOMLEFT", 0, -25)
    size:SetAfterValueChanged(function(value)
        getConfig().font[2] = value
        UpdateModule()
    end)

    local shadow = AF.CreateCheckButton(pane, L["Shadow"])
    AF.SetPoint(shadow, "LEFT", size, COLUMN_OFFSET, 0)
    shadow:SetOnCheck(function(checked)
        getConfig().font[4] = checked
        UpdateModule()
    end)

    local color = AF.CreateColorPicker(pane, L["Color"])
    AF.SetPoint(color, "LEFT", shadow, 115, 0)
    color:SetOnConfirm(function(r, g, b)
        SetConfigColor(getConfig().color, r, g, b)
        UpdateModule()
    end)

    local anchorPoint
    local relativePoint
    local xOffset
    local yOffset
    if withPosition then
        anchorPoint = AF.CreateDropdown(pane, CONTROL_WIDTH)
        AF.SetPoint(anchorPoint, "TOPLEFT", size, "BOTTOMLEFT", 0, -30)
        anchorPoint:SetLabel(L["Anchor Point"])
        anchorPoint:SetItems(anchorPointItems)
        anchorPoint:SetOnSelect(function(value)
            getConfig().position[1] = value
            UpdateModule()
        end)

        relativePoint = AF.CreateDropdown(pane, CONTROL_WIDTH)
        AF.SetPoint(relativePoint, "TOPLEFT", anchorPoint, COLUMN_OFFSET, 0)
        relativePoint:SetLabel(L["Relative Point"])
        relativePoint:SetItems(anchorPointItems)
        relativePoint:SetOnSelect(function(value)
            getConfig().position[2] = value
            UpdateModule()
        end)

        xOffset = AF.CreateSlider(pane, L["X Offset"], CONTROL_WIDTH, -100, 100, 0.5, nil, true)
        AF.SetPoint(xOffset, "TOPLEFT", anchorPoint, "BOTTOMLEFT", 0, -25)
        xOffset:SetAfterValueChanged(function(value)
            getConfig().position[3] = value
            UpdateModule()
        end)

        yOffset = AF.CreateSlider(pane, L["Y Offset"], CONTROL_WIDTH, -100, 100, 0.5, nil, true)
        AF.SetPoint(yOffset, "TOPLEFT", xOffset, COLUMN_OFFSET, 0)
        yOffset:SetAfterValueChanged(function(value)
            getConfig().position[4] = value
            UpdateModule()
        end)
    end

    function pane.UpdateEnabled()
        AF.SetEnabled(CM.config.enabled, font, outline, size, shadow, color)
        if withPosition then
            AF.SetEnabled(
                CM.config.enabled,
                anchorPoint,
                relativePoint,
                xOffset,
                yOffset
            )
        end
    end

    function pane.Load()
        local config = getConfig()
        font:SetSelectedValue(config.font[1])
        outline:SetSelectedValue(config.font[3])
        size:SetValue(config.font[2])
        shadow:SetChecked(config.font[4])
        color:SetColor(config.color)
        if withPosition then
            anchorPoint:SetSelectedValue(config.position[1])
            relativePoint:SetSelectedValue(config.position[2])
            xOffset:SetValue(config.position[3])
            yOffset:SetValue(config.position[4])
        end
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
    {text = L["Whenever Available"], value = "always"},
    {text = L["In Combat Only"], value = "combat"},
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
        textStyles = {
            {"cooldownText", L["Cooldown Text"], true},
            {"countText", L["Count Text"]},
            {"hotkeyText", L["Hot Key"]},
        },
    },
    utility = {
        label = L["Utility Cooldowns"],
        hasOrientation = true,
        hasIconLimit = true,
        textStyles = {
            {"cooldownText", L["Cooldown Text"], true},
            {"countText", L["Count Text"]},
            {"hotkeyText", L["Hot Key"]},
        },
    },
    buffIcon = {
        label = L["Buff Icons"],
        hasOrientation = true,
        textStyles = {
            {"cooldownText", L["Cooldown Text"], true},
            {"countText", L["Count Text"]},
            {"hotkeyText", L["Hot Key"]},
        },
    },
    buffBar = {
        label = L["Buff Bars"],
        hasBarSettings = true,
        textStyles = {
            {"barText", L["Bar Text"]},
            {"durationText", L["Duration Text"], true},
            {"countText", L["Count Text"]},
            {"hotkeyText", L["Hot Key"]},
        },
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
    visibility:SetLabel(L["BFI Visibility"])
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

    for _, styleInfo in ipairs(info.textStyles) do
        local configKey, label, withPosition = unpack(styleInfo)
        panes[#panes + 1] = CreateFontPane(
            parent,
            function()
                return CM.config.viewers[viewerKey][configKey]
            end,
            label,
            withPosition
        )
    end

    local hotkeyPane = CreateRow(130)
    local showHotkeys = AF.CreateCheckButton(hotkeyPane, L["Show Assigned Hotkeys"])
    AF.SetPoint(showHotkeys, "TOPLEFT", 15, -8)
    showHotkeys:SetOnCheck(function(checked)
        CM.config.viewers[viewerKey].showHotkeys = checked
        UpdateModule()
        hotkeyPane.UpdateEnabled()
    end)

    local anchorPoint = AF.CreateDropdown(hotkeyPane, CONTROL_WIDTH)
    AF.SetPoint(anchorPoint, "TOPLEFT", showHotkeys, "BOTTOMLEFT", 0, -28)
    anchorPoint:SetLabel(L["Anchor Point"])
    anchorPoint:SetItems(anchorPointItems)
    anchorPoint:SetOnSelect(function(value)
        CM.config.viewers[viewerKey].hotkeyPosition[1] = value
        UpdateModule()
    end)

    local relativePoint = AF.CreateDropdown(hotkeyPane, CONTROL_WIDTH)
    AF.SetPoint(relativePoint, "TOPLEFT", anchorPoint, COLUMN_OFFSET, 0)
    relativePoint:SetLabel(L["Relative Point"])
    relativePoint:SetItems(anchorPointItems)
    relativePoint:SetOnSelect(function(value)
        CM.config.viewers[viewerKey].hotkeyPosition[2] = value
        UpdateModule()
    end)

    local xOffset = AF.CreateSlider(hotkeyPane, L["X Offset"], CONTROL_WIDTH, -100, 100, 0.5, nil, true)
    AF.SetPoint(xOffset, "TOPLEFT", anchorPoint, "BOTTOMLEFT", 0, -25)
    xOffset:SetAfterValueChanged(function(value)
        CM.config.viewers[viewerKey].hotkeyPosition[3] = value
        UpdateModule()
    end)

    local yOffset = AF.CreateSlider(hotkeyPane, L["Y Offset"], CONTROL_WIDTH, -100, 100, 0.5, nil, true)
    AF.SetPoint(yOffset, "TOPLEFT", xOffset, COLUMN_OFFSET, 0)
    yOffset:SetAfterValueChanged(function(value)
        CM.config.viewers[viewerKey].hotkeyPosition[4] = value
        UpdateModule()
    end)

    function hotkeyPane.UpdateEnabled()
        local config = CM.config.viewers[viewerKey]
        showHotkeys:SetEnabled(CM.config.enabled)
        AF.SetEnabled(
            CM.config.enabled and config.showHotkeys,
            anchorPoint,
            relativePoint,
            xOffset,
            yOffset
        )
    end

    function hotkeyPane.Load()
        local config = CM.config.viewers[viewerKey]
        local position = config.hotkeyPosition
        showHotkeys:SetChecked(config.showHotkeys)
        anchorPoint:SetSelectedValue(position[1])
        relativePoint:SetSelectedValue(position[2])
        xOffset:SetValue(position[3])
        yOffset:SetValue(position[4])
        hotkeyPane.UpdateEnabled()
    end

    return panes
end

local function CreateOptionGroups(parent)
    if optionGroups.general then return end

    optionGroups.general = CreateModulePanes(parent)

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
