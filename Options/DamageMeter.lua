---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

local damageMeterPanel
local appearancePane

local function RefreshDamageMeter()
    AF.Fire("BFI_UpdateModule", "damageMeter")
end

local function CreateDamageMeterPanel()
    damageMeterPanel = AF.CreateFrame(
        BFIOptionsFrame_ContentPane,
        "BFIOptionsFrame_DamageMeterPanel"
    )
    damageMeterPanel:SetAllPoints()
end

local function CreateAppearancePane()
    appearancePane = AF.CreateTitledPane(
        damageMeterPanel,
        L["Damage Meter"],
        350,
        260
    )
    AF.SetPoint(appearancePane, "TOPLEFT", damageMeterPanel, 15, -15)
    appearancePane:SetTips(L["Damage Meter Skin Tip"])

    local enabled = AF.CreateCheckButton(
        appearancePane,
        L["Apply BFI Damage Meter Skin"]
    )
    AF.SetPoint(enabled, "TOPLEFT", appearancePane, 15, -30)
    enabled:SetOnCheck(function(checked)
        DM.config.enabled = checked
        RefreshDamageMeter()
        appearancePane.Load()
    end)

    local accentHeader = AF.CreateCheckButton(
        appearancePane,
        L["Accent Header"]
    )
    AF.SetPoint(accentHeader, "TOPLEFT", enabled, "BOTTOMLEFT", 0, -18)
    accentHeader:SetOnCheck(function(checked)
        DM.config.accentHeader = checked
        RefreshDamageMeter()
    end)

    local barTexture = AF.CreateDropdown(appearancePane, 150)
    barTexture:SetLabel(L["Bar Texture"])
    AF.SetPoint(barTexture, "TOPLEFT", accentHeader, "BOTTOMLEFT", 0, -35)
    barTexture:SetItems(AF.LSM_GetBarTextureDropdownItems())
    barTexture:SetOnSelect(function(value)
        DM.config.barTexture = value
        RefreshDamageMeter()
    end)

    local barBackgroundAlpha = AF.CreateSlider(
        appearancePane,
        L["Bar Background Opacity"],
        150,
        0,
        1,
        0.05,
        true,
        true
    )
    AF.SetPoint(
        barBackgroundAlpha,
        "TOPLEFT",
        barTexture,
        "BOTTOMLEFT",
        0,
        -35
    )
    barBackgroundAlpha:SetAfterValueChanged(function(value)
        DM.config.barBackgroundAlpha = value
        RefreshDamageMeter()
    end)

    function appearancePane.Load()
        local config = DM.config
        enabled:SetChecked(config.enabled)
        accentHeader:SetChecked(config.accentHeader)
        barTexture:SetSelectedValue(config.barTexture)
        barBackgroundAlpha:SetValue(config.barBackgroundAlpha)

        AF.SetEnabled(
            config.enabled,
            accentHeader,
            barTexture,
            barBackgroundAlpha
        )
    end
end

local function CreateBlizzardControlsPane()
    local pane = AF.CreateTitledPane(
        damageMeterPanel,
        L["Blizzard Controls"],
        350,
        170
    )
    AF.SetPoint(pane, "TOPLEFT", appearancePane, "BOTTOMLEFT", 0, -15)

    local info = AF.CreateFontString(pane, L["Damage Meter Blizzard Controls Tip"])
    AF.SetPoint(info, "TOPLEFT", pane, 15, -30)
    AF.SetPoint(info, "TOPRIGHT", pane, -15, -30)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(true)

    local settingsButton = AF.CreateButton(
        pane,
        L["Open Blizzard Damage Meter Settings"],
        "BFI",
        250,
        25
    )
    AF.SetPoint(settingsButton, "TOPLEFT", info, "BOTTOMLEFT", 0, -15)
    settingsButton:SetOnClick(function()
        BFIOptionsFrame:Hide()
        _G.Settings.OpenToCategory(_G.Settings.ADVANCED_OPTIONS_CATEGORY_ID)
    end)

    local editModeButton = AF.CreateButton(
        pane,
        L["Open Blizzard Edit Mode"],
        "BFI",
        250,
        25
    )
    AF.SetPoint(editModeButton, "TOPLEFT", settingsButton, "BOTTOMLEFT", 0, -8)
    AF.ApplyCombatProtectionToWidget(editModeButton)
    editModeButton:SetOnClick(function()
        BFIOptionsFrame:Hide()
        if not _G.EditModeManagerFrame then
            _G.C_AddOns.LoadAddOn("Blizzard_EditMode")
        end
        if _G.EditModeManagerFrame then
            _G.ShowUIPanel(_G.EditModeManagerFrame)
        end
    end)
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "damageMeter" or not appearancePane then return end
    appearancePane.Load()
end)

AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "damageMeter" then
        if not damageMeterPanel then
            CreateDamageMeterPanel()
            CreateAppearancePane()
            CreateBlizzardControlsPane()
        end
        appearancePane.Load()
        damageMeterPanel:Show()
    elseif damageMeterPanel then
        damageMeterPanel:Hide()
    end
end)
