---@type BFI
local BFI = select(2, ...)
local B = BFI.modules.Bags
local L = BFI.L
---@type AbstractFramework
local AF = _G.AbstractFramework

local bagsPanel
local appearancePane

local function RefreshBags()
    AF.Fire("BFI_UpdateModule", "bags")
end

local function CreateBagsPanel()
    bagsPanel = AF.CreateFrame(BFIOptionsFrame_ContentPane, "BFIOptionsFrame_BagsPanel")
    bagsPanel:SetAllPoints()
end

local function CreateAppearancePane()
    appearancePane = AF.CreateTitledPane(bagsPanel, L["Bags"], 350, 360)
    AF.SetPoint(appearancePane, "TOPLEFT", bagsPanel, 15, -15)
    appearancePane:SetTips(
        L["Bags Performance Tip"]
    )

    local enabled = AF.CreateCheckButton(appearancePane, L["Enabled"])
    AF.SetPoint(enabled, "TOPLEFT", appearancePane, 15, -30)

    local function UpdateEnabledColor(checked)
        enabled.label:SetTextColor(AF.GetColorRGB(checked and "softlime" or "firebrick"))
    end

    enabled:SetOnCheck(function(checked)
        B.config.enabled = checked
        UpdateEnabledColor(checked)
        RefreshBags()
        appearancePane.Load()
        if not checked then
            local dialog = AF.GetDialog(bagsPanel, L["A UI reload is required\nDo it now?"])
            AF.SetPoint(dialog, "TOP", 0, -50)
            dialog:SetOnConfirm(ReloadUI)
        end
    end)

    local showBagSlots = AF.CreateCheckButton(appearancePane, L["Show Bags"])
    AF.SetPoint(showBagSlots, "TOPLEFT", enabled, "BOTTOMLEFT", 0, -18)
    showBagSlots:SetOnCheck(function(checked)
        B.config.showBagSlots = checked
        B.Refresh()
    end)

    local showBlizzardBagBar = AF.CreateCheckButton(appearancePane, L["Show Blizzard Bag Bar"])
    AF.SetPoint(showBlizzardBagBar, "TOPLEFT", showBagSlots, "BOTTOMLEFT", 0, -18)
    showBlizzardBagBar:SetOnCheck(function(checked)
        B.config.showBlizzardBagBar = checked
        B.Refresh()
    end)

    local viewMode = AF.CreateDropdown(appearancePane, 165)
    viewMode:SetLabel(L["Bag View"])
    AF.SetPoint(viewMode, "TOPLEFT", showBlizzardBagBar, "BOTTOMLEFT", 0, -35)
    viewMode:SetItems({
        {text = L["Combined View"], value = "combined"},
        {text = L["Categories View"], value = "categories"},
        {text = L["Individual Bags View"], value = "individual"},
    })
    viewMode:SetOnSelect(function(value)
        B.config.viewMode = value
        B.Refresh()
    end)

    local showItemLevel = AF.CreateCheckButton(appearancePane, L["Show Item Level"])
    AF.SetPoint(showItemLevel, "TOPLEFT", viewMode, "BOTTOMLEFT", 0, -18)
    showItemLevel:SetOnCheck(function(checked)
        B.config.showItemLevel = checked
        B.Refresh()
    end)

    local columns = AF.CreateSlider(appearancePane, L["Preferred Columns"], 150, 10, 16, 1, nil, true)
    AF.SetPoint(columns, "TOPLEFT", showItemLevel, "BOTTOMLEFT", 0, -45)
    columns:SetAfterValueChanged(function(value)
        B.config.columns = value
        B.Refresh()
    end)

    local spacing = AF.CreateSlider(appearancePane, L["Slot Spacing"], 150, 1, 8, 1, nil, true)
    AF.SetPoint(spacing, "TOPLEFT", columns, "BOTTOMLEFT", 0, -45)
    spacing:SetAfterValueChanged(function(value)
        B.config.spacing = value
        B.Refresh()
    end)

    function appearancePane.Load()
        local config = B.config
        UpdateEnabledColor(config.enabled)
        enabled:SetChecked(config.enabled)
        showBagSlots:SetChecked(config.showBagSlots)
        showBlizzardBagBar:SetChecked(config.showBlizzardBagBar)
        viewMode:SetSelectedValue(config.viewMode)
        showItemLevel:SetChecked(config.showItemLevel)
        columns:SetValue(config.columns)
        spacing:SetValue(config.spacing)

        showBagSlots:SetEnabled(config.enabled)
        showBlizzardBagBar:SetEnabled(config.enabled)
        viewMode:SetEnabled(config.enabled)
        showItemLevel:SetEnabled(config.enabled)
        columns:SetEnabled(config.enabled)
        spacing:SetEnabled(config.enabled)
    end
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "bags" or not bagsPanel then return end
    appearancePane.Load()
end)

AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "bags" then
        if not bagsPanel then
            CreateBagsPanel()
            CreateAppearancePane()
        end
        appearancePane.Load()
        bagsPanel:Show()
    elseif bagsPanel then
        bagsPanel:Hide()
    end
end)
