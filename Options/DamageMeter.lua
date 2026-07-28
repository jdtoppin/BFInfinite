---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

local damageMeterPanel
local scroll
local meterPane
local displayPane
local layoutPane
local windowsPane
local appearancePane
local actionsPane
local combatRefreshFrame
local nativeSettingWidgets = {}
local nativeLayoutWidgets = {}
local statusText
local presetTip
local windowCount

local SETTING_ITEMS = {
    visibility = {
        {text = L["Always"], value = _G.Enum.DamageMeterVisibility.Always},
        {text = L["In Combat"], value = _G.Enum.DamageMeterVisibility.InCombat},
        {text = L["In Group"], value = _G.Enum.DamageMeterVisibility.InGroup},
        {text = L["Hidden"], value = _G.Enum.DamageMeterVisibility.Hidden},
    },
    style = {
        {text = L["Default"], value = _G.Enum.DamageMeterStyle.Default},
        {text = L["Bordered"], value = _G.Enum.DamageMeterStyle.Bordered},
        {text = L["Thin"], value = _G.Enum.DamageMeterStyle.Thin},
    },
    numbers = {
        {text = L["Minimal"], value = _G.Enum.DamageMeterNumbers.Minimal},
        {text = L["Compact"], value = _G.Enum.DamageMeterNumbers.Compact},
        {text = L["Complete"], value = _G.Enum.DamageMeterNumbers.Complete},
    },
}

local function SetStatus(message, color)
    if not statusText then return end

    statusText:SetText(message or "")
    statusText:SetColor(color or "gray")
end

local function GetErrorMessage(reason)
    if reason == "preset" then
        return L["Damage Meter Layout Requires Custom"], "firebrick"
    elseif reason == "combat" then
        return L["Damage Meter Combat Deferred"], "yellow_text"
    elseif reason == "edit_mode_active" or reason == "pending_changes" then
        return L["Open Blizzard Edit Mode"], "yellow_text"
    elseif reason == "cvar_write_failed" then
        return L["Damage Meter CVar Failed"], "firebrick"
    end
    return L["Damage Meter Loading"], "gray"
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
    scroll.scrollContent:SetWidth(530)
    scroll.scrollContent:SetHeight(805)
end

local function RegisterNativeSettingWidgets(...)
    for i = 1, select("#", ...) do
        nativeSettingWidgets[#nativeSettingWidgets + 1] = select(i, ...)
    end
end

local function RegisterNativeLayoutWidgets(...)
    for i = 1, select("#", ...) do
        nativeLayoutWidgets[#nativeLayoutWidgets + 1] = select(i, ...)
    end
end

local function HandleNativeResult(ok, reason)
    if ok then
        SetStatus()
        return true
    end

    local message, color = GetErrorMessage(reason)
    SetStatus(message, color)
    return false
end

local function CreateMeterPane()
    meterPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Native Meter"],
        530,
        105
    )
    AF.SetPoint(meterPane, "TOPLEFT")
    meterPane:SetTips(L["Damage Meter Native Tip"])

    local enabled = AF.CreateCheckButton(
        meterPane,
        L["Enable Damage Meter"]
    )
    AF.SetPoint(enabled, "TOPLEFT", meterPane, 15, -30)
    enabled:SetOnCheck(function(checked)
        local ok, reason = DM.Native.SetEnabled(checked)
        if not HandleNativeResult(ok, reason) then
            meterPane.Load()
            return
        end
        if checked then
            DM.EnsureNativeLoaded(function()
                if type(DM.ApplyDefaultPositionIfNeeded) == "function" then
                    DM.ApplyDefaultPositionIfNeeded()
                end
                AF.Fire("BFI_RefreshOptions", "damageMeter")
            end)
        end
    end)

    local resetOnNewInstance = AF.CreateCheckButton(
        meterPane,
        L["Reset on New Instance"]
    )
    AF.SetPoint(
        resetOnNewInstance,
        "TOPLEFT",
        meterPane,
        270,
        -30
    )
    resetOnNewInstance:SetOnCheck(function(checked)
        local ok, reason = DM.Native.SetResetOnNewInstance(checked)
        if not HandleNativeResult(ok, reason) then
            meterPane.Load()
        end
    end)

    statusText = AF.CreateFontString(meterPane, nil, "gray")
    AF.SetPoint(statusText, "TOPLEFT", meterPane, 15, -62)
    AF.SetPoint(statusText, "TOPRIGHT", meterPane, -15, -62)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(true)

    function meterPane.Load()
        enabled:SetChecked(DM.Native.GetEnabled())
        resetOnNewInstance:SetChecked(DM.Native.GetResetOnNewInstance())
    end
end

local function CreateSettingDropdown(parent, key, label, x, y)
    local dropdown = AF.CreateDropdown(parent, 105)
    dropdown:SetLabel(label)
    AF.SetPoint(dropdown, "TOPLEFT", parent, x, y)
    dropdown:SetItems(SETTING_ITEMS[key])
    RegisterNativeSettingWidgets(dropdown)
    return dropdown
end

local function CreateDisplayPane()
    displayPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Display"],
        255,
        205
    )
    AF.SetPoint(displayPane, "TOPLEFT", meterPane, "BOTTOMLEFT", 0, -20)
    displayPane:SetTips(L["Damage Meter Native Settings Read Only"])

    local visibility = CreateSettingDropdown(
        displayPane,
        "visibility",
        L["Visibility"],
        15,
        -45
    )
    local style = CreateSettingDropdown(
        displayPane,
        "style",
        L["Style"],
        135,
        -45
    )
    local numbers = CreateSettingDropdown(
        displayPane,
        "numbers",
        L["Number Format"],
        15,
        -100
    )

    local showSpecIcon = AF.CreateCheckButton(
        displayPane,
        L["Show Specialization Icons"]
    )
    AF.SetPoint(showSpecIcon, "TOPLEFT", displayPane, 15, -143)

    local showClassColor = AF.CreateCheckButton(
        displayPane,
        L["Use Class Colors"]
    )
    AF.SetPoint(showClassColor, "TOPLEFT", displayPane, 15, -174)

    RegisterNativeSettingWidgets(showSpecIcon, showClassColor)

    function displayPane.Load()
        local value

        value = DM.Native.GetSetting("visibility")
        if value ~= nil then visibility:SetSelectedValue(value) end

        value = DM.Native.GetSetting("style")
        if value ~= nil then style:SetSelectedValue(value) end

        value = DM.Native.GetSetting("numbers")
        if value ~= nil then numbers:SetSelectedValue(value) end

        value = DM.Native.GetSetting("showSpecIcon")
        if value ~= nil then showSpecIcon:SetChecked(value) end

        value = DM.Native.GetSetting("showClassColor")
        if value ~= nil then showClassColor:SetChecked(value) end
    end
end

local function CreateNativeSlider(parent, key, label, x, y)
    local definition = DM.Native.GetSettingDefinition(key)
    local isPercentage = key == "transparency"
        or key == "backgroundTransparency"
        or key == "textSize"
    local slider = AF.CreateSlider(
        parent,
        label,
        105,
        definition.min,
        definition.max,
        definition.step,
        false,
        false
    )
    AF.SetPoint(slider, "TOPLEFT", parent, x, y)
    if isPercentage then
        slider.percentSign:Show()
    end
    RegisterNativeSettingWidgets(slider)
    return slider
end

local function CreateLayoutPane()
    layoutPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Layout"],
        255,
        330
    )
    AF.SetPoint(layoutPane, "TOPLEFT", displayPane, "TOPRIGHT", 20, 0)
    layoutPane:SetTips(L["Damage Meter Native Settings Read Only"])

    local widgets = {
        frameWidth = CreateNativeSlider(
            layoutPane, "frameWidth", L["Frame Width"], 15, -45
        ),
        frameHeight = CreateNativeSlider(
            layoutPane, "frameHeight", L["Frame Height"], 135, -45
        ),
        barHeight = CreateNativeSlider(
            layoutPane, "barHeight", L["Bar Height"], 15, -105
        ),
        padding = CreateNativeSlider(
            layoutPane, "padding", L["Padding"], 135, -105
        ),
        textSize = CreateNativeSlider(
            layoutPane, "textSize", L["Text Size"], 15, -165
        ),
        transparency = CreateNativeSlider(
            layoutPane, "transparency", L["Window Opacity"], 135, -165
        ),
        backgroundTransparency = CreateNativeSlider(
            layoutPane,
            "backgroundTransparency",
            L["Background Opacity"],
            15,
            -225
        ),
    }

    presetTip = AF.CreateFontString(layoutPane, nil, "firebrick")
    AF.SetPoint(presetTip, "TOPLEFT", layoutPane, 15, -272)
    AF.SetPoint(presetTip, "TOPRIGHT", layoutPane, -15, -272)
    presetTip:SetJustifyH("LEFT")
    presetTip:SetWordWrap(true)
    presetTip:SetColor("gray")
    presetTip:SetText(L["Damage Meter Native Settings Read Only"])

    function layoutPane.Load()
        for key, widget in next, widgets do
            local value = DM.Native.GetSetting(key)
            if value ~= nil then
                widget:SetValue(value)
            end
        end
    end
end

local function CreateWindowsPane()
    windowsPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Meters"],
        255,
        105
    )
    AF.SetPoint(windowsPane, "TOPLEFT", displayPane, "BOTTOMLEFT", 0, -20)
    windowsPane:SetTips(L["Damage Meter Windows Tip"])

    windowCount = AF.CreateDropdown(windowsPane, 105)
    windowCount:SetLabel(L["Window Count"])
    AF.SetPoint(windowCount, "TOPLEFT", windowsPane, 15, -45)
    windowCount:SetItems({
        {text = "1", value = 1},
        {text = "2", value = 2},
        {text = "3", value = 3},
    })
    RegisterNativeSettingWidgets(windowCount)

    function windowsPane.Load()
        local count = DM.Native.GetWindowCount()
        if count ~= nil then
            windowCount:SetSelectedValue(math.max(1, count))
        end
    end
end

local function CreateAppearancePane()
    appearancePane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["BFI Appearance"],
        255,
        115
    )
    AF.SetPoint(appearancePane, "TOPLEFT", layoutPane, "BOTTOMLEFT", 0, -20)
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

    function appearancePane.Load()
        local config = DM.config
        enabled:SetChecked(config.enabled)
        accentHeader:SetChecked(config.accentHeader)

        AF.SetEnabled(config.enabled, accentHeader)
    end
end

local function OpenEditMode()
    BFIOptionsFrame:Hide()
    if not _G.EditModeManagerFrame then
        _G.C_AddOns.LoadAddOn("Blizzard_EditMode")
    end
    if _G.EditModeManagerFrame then
        _G.ShowUIPanel(_G.EditModeManagerFrame)
    end
end

local function CreateActionsPane()
    actionsPane = AF.CreateTitledPane(
        scroll.scrollContent,
        L["Damage Meter Actions"],
        530,
        100
    )
    AF.SetPoint(
        actionsPane,
        "TOPRIGHT",
        appearancePane,
        "BOTTOMRIGHT",
        0,
        -20
    )

    local bottomRight = AF.CreateButton(
        actionsPane,
        L["Place Meters Bottom Right"],
        "BFI",
        160,
        25
    )
    AF.SetPoint(bottomRight, "TOPLEFT", actionsPane, 15, -35)
    bottomRight:SetOnClick(function()
        if type(DM.ApplyBottomRightLayout) ~= "function" then return end

        local ok, reason = DM.ApplyBottomRightLayout()
        if ok then
            SetStatus(L["Damage Meter Layout Applied"], "softlime")
        else
            HandleNativeResult(ok, reason)
        end
    end)
    RegisterNativeLayoutWidgets(bottomRight)

    local editModeButton = AF.CreateButton(
        actionsPane,
        L["Open Blizzard Edit Mode"],
        "BFI",
        160,
        25
    )
    AF.SetPoint(editModeButton, "LEFT", bottomRight, "RIGHT", 10, 0)
    AF.ApplyCombatProtectionToWidget(editModeButton)
    editModeButton:SetOnClick(OpenEditMode)

    local reset = AF.CreateButton(
        actionsPane,
        L["Reset Combat Data"],
        "red",
        160,
        25
    )
    AF.SetPoint(reset, "LEFT", editModeButton, "RIGHT", 10, 0)
    AF.ApplyCombatProtectionToWidget(reset)
    reset:SetOnClick(function()
        local dialog = AF.GetDialog(
            damageMeterPanel,
            L["Reset all native Damage Meter combat data?"],
            300
        )
        AF.SetPoint(dialog, "TOP", damageMeterPanel, 0, -50)
        dialog:SetOnConfirm(function()
            DM.Data.Reset()
        end)
    end)
end

local function LoadNativeControls()
    if not meterPane then return end

    meterPane.Load()

    local _, settingError = DM.Native.GetSetting("style")
    local nativeReady = settingError == nil
    local canPersist, persistError = DM.Native.CanPersistLayout()
    local inCombat = _G.InCombatLockdown()

    if not combatRefreshFrame then
        combatRefreshFrame = _G.CreateFrame("Frame")
        combatRefreshFrame:SetScript("OnEvent", function()
            LoadNativeControls()
        end)
        combatRefreshFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatRefreshFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end

    AF.SetEnabled(false, unpack(nativeSettingWidgets))
    AF.SetEnabled(
        nativeReady and canPersist and not inCombat,
        unpack(nativeLayoutWidgets)
    )
    presetTip:SetShown(nativeReady)

    if nativeReady then
        displayPane.Load()
        layoutPane.Load()
        windowsPane.Load()
        if not canPersist then
            local message, color = GetErrorMessage(persistError)
            SetStatus(message, color)
        elseif inCombat then
            SetStatus(L["Damage Meter Combat Deferred"], "yellow_text")
        else
            SetStatus()
        end
    else
        SetStatus(L["Damage Meter Loading"], "gray")
    end
end

local function OnNativeReady()
    LoadNativeControls()
end

local function Load()
    meterPane.Load()
    appearancePane.Load()
    LoadNativeControls()

    DM.EnsureNativeLoaded(OnNativeReady)
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "damageMeter" or not damageMeterPanel then return end
    Load()
end)

AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "damageMeter" then
        if not damageMeterPanel then
            CreateDamageMeterPanel()
            CreateMeterPane()
            CreateDisplayPane()
            CreateLayoutPane()
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
