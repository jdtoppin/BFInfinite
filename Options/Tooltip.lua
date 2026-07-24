---@type BFI
local BFI = select(2, ...)
local F = BFI.funcs
local L = BFI.L
local T = BFI.modules.Tooltip
---@type AbstractFramework
local AF = _G.AbstractFramework

local LoadOptions

---------------------------------------------------------------------
-- panel
---------------------------------------------------------------------
local tooltipPanel

local function CreateTooltipPanel()
    tooltipPanel = AF.CreateFrame(BFIOptionsFrame_ContentPane, "BFIOptionsFrame_TooltipPanel")
    tooltipPanel:SetAllPoints()
end

---------------------------------------------------------------------
-- content pane
---------------------------------------------------------------------
local contentPane

local function BindButtonConfig(button)
    button.cfg = button.configKey and T.config[button.configKey] or T.config
end

local function CreateContentPane()
    contentPane = AF.CreateFrame(tooltipPanel)
    AF.SetPoint(contentPane, "TOPLEFT", 15, -15)
    AF.SetPoint(contentPane, "BOTTOMRIGHT", -15, 15)

    local list = AF.CreateScrollList(contentPane, nil, 0, 0, 28, 20, -1)
    contentPane.list = list
    list:SetPoint("TOPLEFT")
    AF.SetWidth(list, 150)
    list:SetupButtonGroup("BFI_transparent", LoadOptions, nil, nil, nil, function(button, data)
        button.configKey = data.configKey
        BindButtonConfig(button)
        button:SetTextColor(T.config.enabled and button.cfg.enabled and "white" or "disabled")
    end)
    list:SetData({
        {text = L["General"], id = "general"},
    })

    local scrollSettings = AF.CreateScrollFrame(contentPane, nil, nil, nil, "none", "none")
    contentPane.scrollSettings = scrollSettings
    scrollSettings.scrollBar:SetBackdropBorderColor(AF.GetColorRGB("border"))
    AF.SetPoint(scrollSettings, "TOPLEFT", list, "TOPRIGHT", 15, 0)
    AF.SetPoint(scrollSettings, "BOTTOM", list)
    AF.SetPoint(scrollSettings, "RIGHT")
    scrollSettings:SetScrollStep(50)
end

---------------------------------------------------------------------
-- load
---------------------------------------------------------------------
local selectedID = "general"

local function UpdateListColors()
    if not contentPane then return end

    for _, button in ipairs(contentPane.list:GetWidgets()) do
        BindButtonConfig(button)
        button:SetTextColor(T.config.enabled and button.cfg.enabled and "white" or "disabled")
    end
end

LoadOptions = function(button)
    selectedID = button.id
    BindButtonConfig(button)

    local scroll = contentPane.scrollSettings
    local options = F.GetTooltipOptions(scroll.scrollContent, button)
    local heights = {}
    local last

    for i, pane in ipairs(options) do
        pane.index = i

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
    end)

    C_Timer.After(0, function()
        for _, pane in ipairs(options) do
            pane.Load(button)
        end
    end)
end

local function ReloadSelected()
    for _, button in ipairs(contentPane.list:GetWidgets()) do
        if button.id == selectedID then
            LoadOptions(button)
            return
        end
    end
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which ~= "tooltip" or not contentPane then return end

    UpdateListColors()
    ReloadSelected()
end)

AF.RegisterCallback("BFI_UpdateTooltipOptionsList", UpdateListColors)

---------------------------------------------------------------------
-- show
---------------------------------------------------------------------
AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "tooltip" then
        if not tooltipPanel then
            CreateTooltipPanel()
            CreateContentPane()
            contentPane.list:Select(selectedID)
        else
            UpdateListColors()
            ReloadSelected()
        end
        tooltipPanel:Show()
    elseif tooltipPanel then
        tooltipPanel:Hide()
    end
end)
