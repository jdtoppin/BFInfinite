---@type BFI
local BFI = select(2, ...)
---@class Funcs
local F = BFI.funcs
local L = BFI.L
local T = BFI.modules.Tooltip
---@type AbstractFramework
local AF = _G.AbstractFramework

local created = {}
local builder = {}
local options = {}

local settings = {
    general = {
        "customBehavior",
        "position",
        "healthBar",
    },
}

local function UpdateModule()
    AF.Fire("BFI_UpdateModule", "tooltip")
end

local function UpdateGeneralWidgets()
    local enabled = T.config.enabled
    local behavior = created.customBehavior
    local position = created.position
    local healthBar = created.healthBar
    if not (behavior and position and healthBar) then return end

    local anchorMode = T.config.anchorMode
    local fixed = enabled and anchorMode == "fixed"
    local cursorWithOffsets = enabled and (anchorMode == "cursor_left" or anchorMode == "cursor_right")

    AF.SetEnabled(enabled, behavior.hideInCombat, position.anchorMode, healthBar.enabled)
    AF.SetEnabled(fixed, position.anchorPoint)
    position.fixedHint:SetShown(fixed)
    AF.SetEnabled(cursorWithOffsets, position.cursorX, position.cursorY)
    AF.SetEnabled(enabled and T.config.healthBar.enabled, healthBar.height)
end

---------------------------------------------------------------------
-- custom behavior
---------------------------------------------------------------------
builder.customBehavior = function(parent)
    if created.customBehavior then return created.customBehavior end

    local pane = AF.CreateTitledPane(parent, L["Custom Tooltip Behavior"], nil, 120)
    created.customBehavior = pane

    local enabled = AF.CreateCheckButton(pane, L["Apply BFI Tooltip Settings"])
    AF.SetPoint(enabled, "TOPLEFT", pane, 10, -35)
    enabled:SetOnCheck(function(checked)
        pane.t.cfg.enabled = checked
        AF.Fire("BFI_UpdateTooltipOptionsList")
        UpdateGeneralWidgets()
        UpdateModule()
    end)

    local enabledTips = AF.CreateTipsButton(pane)
    AF.SetPoint(enabledTips, "LEFT", enabled.label, "RIGHT", 5, 0)
    enabledTips:SetTips(
        L["Apply BFI Tooltip Settings"],
        L["Controls global positioning, unit-tooltip combat visibility, the native health bar, and optional tooltip extras. BFI's visual tooltip skin and widget-specific tooltip settings are separate"]
    )

    local hideInCombat = AF.CreateCheckButton(pane, L["Hide Unit Tooltips in Combat"])
    AF.SetPoint(hideInCombat, "TOPLEFT", enabled, "BOTTOMLEFT", 0, -15)
    hideInCombat:SetOnCheck(function(checked)
        pane.t.cfg.hideUnitTooltipsInCombat = checked
        UpdateModule()
    end)

    local combatTips = AF.CreateTipsButton(pane)
    AF.SetPoint(combatTips, "LEFT", hideInCombat.label, "RIGHT", 5, 0)
    combatTips:SetTips(
        L["Hide Unit Tooltips in Combat"],
        L["Only unit tooltips are hidden. Aura, item, and spell tooltips remain available"]
    )

    function pane.Load(t)
        pane.t = t
        enabled:SetChecked(t.cfg.enabled)
        hideInCombat:SetChecked(t.cfg.hideUnitTooltipsInCombat)
        UpdateGeneralWidgets()
    end

    pane.hideInCombat = hideInCombat
    return pane
end

---------------------------------------------------------------------
-- position
---------------------------------------------------------------------
builder.position = function(parent)
    if created.position then return created.position end

    local pane = AF.CreateTitledPane(parent, L["Position"], nil, 260)
    created.position = pane

    local anchorMode = AF.CreateDropdown(pane, 220)
    AF.SetPoint(anchorMode, "TOPLEFT", pane, 10, -45)
    anchorMode:SetLabel(L["Default Tooltip Position"])
    anchorMode:SetItems({
        {text = L["Blizzard Default"], value = "default"},
        {text = L["BFI Anchor"], value = "fixed"},
        {text = L["Cursor"], value = "cursor"},
        {text = L["Cursor Left"], value = "cursor_left"},
        {text = L["Cursor Right"], value = "cursor_right"},
    })
    anchorMode:SetOnSelect(function(value)
        pane.t.cfg.anchorMode = value
        UpdateGeneralWidgets()
        UpdateModule()
    end)

    local anchorModeTips = AF.CreateTipsButton(pane)
    AF.SetPoint(anchorModeTips, "LEFT", anchorMode.label, "RIGHT", 5, 0)
    anchorModeTips:SetTips(
        L["Default Tooltip Position"],
        L["Applies to world tooltips, Blizzard tooltips that use the default position, and BFI widgets whose own Relative To setting is Default. Explicit Button, Unit Frame, Icon, or Group positions override it"]
    )

    local anchorPoint = AF.CreateDropdown(pane, 160)
    AF.SetPoint(anchorPoint, "TOPLEFT", anchorMode, "BOTTOMLEFT", 0, -35)
    anchorPoint:SetLabel(L["Anchor Point"])
    anchorPoint:SetItems(AF.GetDropdownItems_AnchorPoint(true))
    anchorPoint:SetOnSelect(function(value)
        pane.t.cfg.anchorPoint = value
        UpdateModule()
    end)

    local fixedHint = AF.CreateFontString(
        pane,
        L["Use Edit Mode to move the BFI tooltip anchor"],
        "gray"
    )
    AF.SetPoint(fixedHint, "TOPLEFT", anchorPoint, "BOTTOMLEFT", 0, -12)

    local cursorX = AF.CreateSlider(pane, L["X Offset"], 100, -100, 100, 1, nil, true)
    AF.SetPoint(cursorX, "TOPLEFT", anchorPoint, "BOTTOMLEFT", 0, -55)
    cursorX:SetAfterValueChanged(function(value)
        pane.t.cfg.cursorAnchor.x = value
        UpdateModule()
    end)

    local cursorY = AF.CreateSlider(pane, L["Y Offset"], 100, -100, 100, 1, nil, true)
    AF.SetPoint(cursorY, "TOPLEFT", cursorX, "TOPRIGHT", 30, 0)
    cursorY:SetAfterValueChanged(function(value)
        pane.t.cfg.cursorAnchor.y = value
        UpdateModule()
    end)

    function pane.Load(t)
        pane.t = t
        anchorMode:SetSelectedValue(t.cfg.anchorMode)
        anchorPoint:SetSelectedValue(t.cfg.anchorPoint)
        cursorX:SetValue(t.cfg.cursorAnchor.x)
        cursorY:SetValue(t.cfg.cursorAnchor.y)
        UpdateGeneralWidgets()
    end

    pane.anchorMode = anchorMode
    pane.anchorPoint = anchorPoint
    pane.fixedHint = fixedHint
    pane.cursorX = cursorX
    pane.cursorY = cursorY
    return pane
end

---------------------------------------------------------------------
-- health bar
---------------------------------------------------------------------
builder.healthBar = function(parent)
    if created.healthBar then return created.healthBar end

    local pane = AF.CreateTitledPane(parent, L["Native Health Bar"], nil, 130)
    created.healthBar = pane

    local enabled = AF.CreateCheckButton(pane, L["Show Health Bar"])
    AF.SetPoint(enabled, "TOPLEFT", pane, 10, -35)
    enabled:SetOnCheck(function(checked)
        pane.t.cfg.healthBar.enabled = checked
        UpdateGeneralWidgets()
        UpdateModule()
    end)

    local height = AF.CreateSlider(pane, L["Height"], 150, 1, 20, 1, nil, true)
    AF.SetPoint(height, "TOPLEFT", enabled, "BOTTOMLEFT", 0, -35)
    height:SetAfterValueChanged(function(value)
        pane.t.cfg.healthBar.height = value
        UpdateModule()
    end)

    function pane.Load(t)
        pane.t = t
        enabled:SetChecked(t.cfg.healthBar.enabled)
        height:SetValue(t.cfg.healthBar.height)
        UpdateGeneralWidgets()
    end

    pane.enabled = enabled
    pane.height = height
    return pane
end

---------------------------------------------------------------------
-- get
---------------------------------------------------------------------
function F.GetTooltipOptions(parent, info)
    for _, pane in pairs(created) do
        pane:Hide()
        AF.ClearPoints(pane)
    end

    wipe(options)
    local setting = settings[info.id]
    if not setting then return options end

    for _, option in ipairs(setting) do
        local pane = builder[option](parent)
        options[#options + 1] = pane
        pane:Show()
    end

    return options
end
