---@type BFI
local BFI = select(2, ...)
local T = BFI.modules.Tooltip
local L = BFI.L
---@type AbstractFramework
local AF = _G.AbstractFramework

local tooltipPanel
local behaviorPane, positionPane, healthBarPane

local function UpdateModule()
    AF.Fire("BFI_UpdateModule", "tooltip")
end

---------------------------------------------------------------------
-- panel
---------------------------------------------------------------------
local function CreateTooltipPanel()
    tooltipPanel = AF.CreateFrame(BFIOptionsFrame_ContentPane, "BFIOptionsFrame_TooltipPanel")
    tooltipPanel:SetAllPoints()
end

---------------------------------------------------------------------
-- behavior
---------------------------------------------------------------------
local function CreateBehaviorPane()
    behaviorPane = AF.CreateTitledPane(tooltipPanel, L["Behavior"], 250, 120)
    AF.SetPoint(behaviorPane, "TOPLEFT", tooltipPanel, 15, -15)

    local enabled = AF.CreateCheckButton(behaviorPane, L["Enable BFI Tooltip Controls"])
    AF.SetPoint(enabled, "TOPLEFT", behaviorPane, 10, -35)
    enabled:SetOnCheck(function(checked)
        T.config.enabled = checked
        tooltipPanel.UpdateWidgets()
        UpdateModule()
    end)

    local hideInCombat = AF.CreateCheckButton(behaviorPane, L["Hide Unit Tooltips in Combat"])
    AF.SetPoint(hideInCombat, "TOPLEFT", enabled, "BOTTOMLEFT", 0, -15)
    hideInCombat:SetTooltip(
        L["Hide Unit Tooltips in Combat"],
        L["Aura, item, and spell tooltips remain available"]
    )
    hideInCombat:SetOnCheck(function(checked)
        T.config.hideUnitTooltipsInCombat = checked
        UpdateModule()
    end)

    function behaviorPane.Load()
        enabled:SetChecked(T.config.enabled)
        hideInCombat:SetChecked(T.config.hideUnitTooltipsInCombat)
    end

    behaviorPane.enabled = enabled
    behaviorPane.hideInCombat = hideInCombat
end

---------------------------------------------------------------------
-- position
---------------------------------------------------------------------
local function CreatePositionPane()
    positionPane = AF.CreateTitledPane(tooltipPanel, L["Position"], 280, 260)
    AF.SetPoint(positionPane, "TOPLEFT", behaviorPane, "TOPRIGHT", 25, 0)

    local anchorMode = AF.CreateDropdown(positionPane, 220)
    AF.SetPoint(anchorMode, "TOPLEFT", positionPane, 10, -45)
    anchorMode:SetLabel(L["Anchored To"])
    anchorMode:SetItems({
        {text = L["Blizzard Default"], value = "default"},
        {text = L["BFI Anchor"], value = "fixed"},
        {text = L["Cursor"], value = "cursor"},
        {text = L["Cursor Left"], value = "cursor_left"},
        {text = L["Cursor Right"], value = "cursor_right"},
    })
    anchorMode:SetOnSelect(function(value)
        T.config.anchorMode = value
        tooltipPanel.UpdateWidgets()
        UpdateModule()
    end)

    local anchorPoint = AF.CreateDropdown(positionPane, 160)
    AF.SetPoint(anchorPoint, "TOPLEFT", anchorMode, "BOTTOMLEFT", 0, -35)
    anchorPoint:SetLabel(L["Anchor Point"])
    anchorPoint:SetItems(AF.GetDropdownItems_AnchorPoint(true))
    anchorPoint:SetOnSelect(function(value)
        T.config.anchorPoint = value
        UpdateModule()
    end)

    local fixedHint = AF.CreateFontString(
        positionPane,
        L["Use Edit Mode to move the BFI tooltip anchor"],
        "gray"
    )
    AF.SetPoint(fixedHint, "TOPLEFT", anchorPoint, "BOTTOMLEFT", 0, -12)

    local cursorX = AF.CreateSlider(positionPane, L["X Offset"], 100, -100, 100, 1, nil, true)
    AF.SetPoint(cursorX, "TOPLEFT", anchorPoint, "BOTTOMLEFT", 0, -55)
    cursorX:SetAfterValueChanged(function(value)
        T.config.cursorAnchor.x = value
        UpdateModule()
    end)

    local cursorY = AF.CreateSlider(positionPane, L["Y Offset"], 100, -100, 100, 1, nil, true)
    AF.SetPoint(cursorY, "TOPLEFT", cursorX, "TOPRIGHT", 30, 0)
    cursorY:SetAfterValueChanged(function(value)
        T.config.cursorAnchor.y = value
        UpdateModule()
    end)

    function positionPane.Load()
        anchorMode:SetSelectedValue(T.config.anchorMode)
        anchorPoint:SetSelectedValue(T.config.anchorPoint)
        cursorX:SetValue(T.config.cursorAnchor.x)
        cursorY:SetValue(T.config.cursorAnchor.y)
    end

    positionPane.anchorMode = anchorMode
    positionPane.anchorPoint = anchorPoint
    positionPane.fixedHint = fixedHint
    positionPane.cursorX = cursorX
    positionPane.cursorY = cursorY
end

---------------------------------------------------------------------
-- health bar
---------------------------------------------------------------------
local function CreateHealthBarPane()
    healthBarPane = AF.CreateTitledPane(tooltipPanel, L["Native Health Bar"], 250, 130)
    AF.SetPoint(healthBarPane, "TOPLEFT", behaviorPane, "BOTTOMLEFT", 0, -25)

    local enabled = AF.CreateCheckButton(healthBarPane, L["Show Health Bar"])
    AF.SetPoint(enabled, "TOPLEFT", healthBarPane, 10, -35)
    enabled:SetOnCheck(function(checked)
        T.config.healthBar.enabled = checked
        tooltipPanel.UpdateWidgets()
        UpdateModule()
    end)

    local height = AF.CreateSlider(healthBarPane, L["Height"], 150, 1, 20, 1, nil, true)
    AF.SetPoint(height, "TOPLEFT", enabled, "BOTTOMLEFT", 0, -35)
    height:SetAfterValueChanged(function(value)
        T.config.healthBar.height = value
        UpdateModule()
    end)

    function healthBarPane.Load()
        enabled:SetChecked(T.config.healthBar.enabled)
        height:SetValue(T.config.healthBar.height)
    end

    healthBarPane.enabled = enabled
    healthBarPane.height = height
end

---------------------------------------------------------------------
-- state
---------------------------------------------------------------------
local function UpdateWidgets()
    local enabled = T.config.enabled
    local anchorMode = T.config.anchorMode
    local fixed = enabled and anchorMode == "fixed"
    local cursorWithOffsets = enabled and (anchorMode == "cursor_left" or anchorMode == "cursor_right")

    AF.SetEnabled(enabled, behaviorPane.hideInCombat, positionPane.anchorMode, healthBarPane.enabled)
    AF.SetEnabled(fixed, positionPane.anchorPoint)
    positionPane.fixedHint:SetShown(fixed)
    AF.SetEnabled(cursorWithOffsets, positionPane.cursorX, positionPane.cursorY)
    AF.SetEnabled(enabled and T.config.healthBar.enabled, healthBarPane.height)
end

local function LoadOptions()
    behaviorPane.Load()
    positionPane.Load()
    healthBarPane.Load()
    UpdateWidgets()
end

---------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------
AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "tooltip" or not tooltipPanel then return end
    LoadOptions()
end)

---------------------------------------------------------------------
-- show
---------------------------------------------------------------------
AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "tooltip" then
        if not tooltipPanel then
            CreateTooltipPanel()
            CreateBehaviorPane()
            CreatePositionPane()
            CreateHealthBarPane()
            tooltipPanel.UpdateWidgets = UpdateWidgets
        end
        LoadOptions()
        tooltipPanel:Show()
    elseif tooltipPanel then
        tooltipPanel:Hide()
    end
end)
