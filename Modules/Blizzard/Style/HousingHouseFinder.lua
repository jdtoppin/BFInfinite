---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- subdivision menu
---------------------------------------------------------------------
local function StyleSubdivisionRadio(frame)
    S.StyleMenuSelection(frame)
end

local function StyleSubdivisionMenuDescriptions(parentDescription)
    for _, description in parentDescription:EnumerateElementDescriptions() do
        if description:IsRadio() then
            description:AddInitializer(StyleSubdivisionRadio)
        end
        StyleSubdivisionMenuDescriptions(description)
    end
end

local function StyleSubdivisionMenu(dropdown)
    local rootDescription = dropdown:GetMenuDescription()
    if not rootDescription then return end

    StyleSubdivisionMenuDescriptions(rootDescription)
end

---------------------------------------------------------------------
-- neighborhood cards
---------------------------------------------------------------------
local function UpdateNeighborhoodButton(button, selected)
    button.ButtonBackground:SetAlpha(0)

    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetAlpha(0)
    end

    if selected == nil then
        selected = button.houseFinderFrame
            and button.houseFinderFrame.selectedNeighborhoodButton == button
    end

    if selected then
        button.BFIHouseFinderCardBackground:SetColorTexture(AF.GetColorRGB("BFI", 0.45))
    elseif button:IsMouseOver() then
        button.BFIHouseFinderCardBackground:SetColorTexture(AF.GetColorRGB("widget_highlight"))
    else
        button.BFIHouseFinderCardBackground:SetColorTexture(AF.GetColorRGB("widget"))
    end

    button.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
end

local function StyleNeighborhoodButton(button)
    if button._BFIHouseFinderStyled then
        UpdateNeighborhoodButton(button)
        return
    end
    button._BFIHouseFinderStyled = true

    -- Keep invite, party-sync, guild-emblem, and loading regions. Only the
    -- native card and selection atlases are replaced.
    S.CreateBackdrop(button, true, nil, 1)
    button.BFIHouseFinderCardBackground = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    button.BFIHouseFinderCardBackground:SetAllPoints(button.BFIBackdrop)

    S.StyleIconButton(button.DeclineInviteButton, AF.GetIcon("Close"), 10, nil, "red")
    AF.SetSize(button.DeclineInviteButton, 16, 16)

    -- IgnoreNeighborhoodButton was added in PTR 12.1.0.68914. The live
    -- 12.0.7.68887 template only exposes DeclineInviteButton.
    if button.IgnoreNeighborhoodButton then
        S.StyleIconButton(button.IgnoreNeighborhoodButton, AF.GetIcon("Close"), 10, nil, "red")
        AF.SetSize(button.IgnoreNeighborhoodButton, 16, 16)
    end

    button:HookScript("OnEnter", function(self)
        UpdateNeighborhoodButton(self)
    end)
    button:HookScript("OnLeave", function(self)
        UpdateNeighborhoodButton(self)
    end)
    hooksecurefunc(button, "Select", function(self)
        UpdateNeighborhoodButton(self, true)
    end)
    hooksecurefunc(button, "Deselect", function(self)
        UpdateNeighborhoodButton(self, false)
    end)

    UpdateNeighborhoodButton(button)
end

local function StyleNeighborhoodPools(frame)
    for button in frame.neighborhoodButtonPool:EnumerateActive() do
        StyleNeighborhoodButton(button)
    end

    for button in frame.bnetNeighborhoodButtonPool:EnumerateActive() do
        StyleNeighborhoodButton(button)
    end
end

---------------------------------------------------------------------
-- notification banner
---------------------------------------------------------------------
local function UpdateNotificationBanner(background, atlas)
    background:SetAlpha(0)

    local color = atlas == "housefinder-messaging-red" and "red" or "BFI"
    background.BFIHouseFinderFill:SetColorTexture(AF.GetColorRGB(color, 0.28))
    background.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
end

local function StyleNotificationBanner(banner)
    local background = banner.background
    S.CreateBackdrop(background, true)

    background.BFIHouseFinderFill = banner:CreateTexture(nil, "BACKGROUND")
    background.BFIHouseFinderFill:SetAllPoints(background)

    local atlas = background:GetAtlas()
    hooksecurefunc(background, "SetAtlas", UpdateNotificationBanner)
    UpdateNotificationBanner(background, atlas)
end

---------------------------------------------------------------------
-- plot information
---------------------------------------------------------------------
local function StylePlotTooltip(tooltip)
    if not tooltip then return end

    S.RemoveNineSliceAndBackground(tooltip)
    S.CreateBackdrop(tooltip, nil, nil, -1)
end

local function StylePlotInfo(frame)
    frame.PlotTitleBG:SetAlpha(0)
    frame.VisitButtonBG:SetAlpha(0)
    frame.VisitDescriptionBG:SetAlpha(0)
    frame.TopRightFiligree:SetAlpha(0)
    frame.BottomLeftFiligree:SetAlpha(0)
    frame.BottomRightFiligree:SetAlpha(0)

    -- The scenic neighborhood image remains visible through its native mask;
    -- this BFI-owned anchor replaces only the wood/filigree pane border.
    local pane = CreateFrame("Frame", nil, frame)
    AF.SetPoint(pane, "TOPLEFT", frame.Mask)
    AF.SetPoint(pane, "BOTTOMRIGHT", frame.Mask)
    S.CreateBackdrop(pane, true, nil, 1)
    frame.BFIHouseFinderPane = pane

    local backButton = frame.BackButton
    S.StyleIconButton(backButton, AF.GetIcon("ArrowLeft2"), 16, nil, "widget")
    AF.ClearPoints(backButton.BFIIcon)
    AF.SetPoint(backButton.BFIIcon, "LEFT", 7, 0)

    S.StyleButton(frame.VisitHouseButton)
end

---------------------------------------------------------------------
-- House Finder
---------------------------------------------------------------------
local function StyleHouseFinder()
    local frame = _G.HouseFinderFrame
    if not frame then return end

    S.StyleTitledFrame(frame)

    local list = frame.NeighborhoodListFrame
    list.NeighborhoodListBG:SetAlpha(0)
    list.NeighborhoodTitleBG:SetAlpha(0)
    list.ListBottomGradient.BottomGradient:SetAlpha(0)
    S.CreateBackdrop(list)
    list.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("background"))

    S.StyleScrollBar(list.ScrollFrame.ScrollBar)
    S.StyleScrollBar(list.BNetScrollFrame.ScrollBar)

    local searchBox = list.BNetFriendSearchBox
    S.StyleEditBox(searchBox)
    searchBox.LeftBorder:SetAlpha(0)
    searchBox.MiddleBorder:SetAlpha(0)
    searchBox.RightBorder:SetAlpha(0)
    S.StyleIconButton(searchBox.ClearButton, AF.GetIcon("Close"), 10, nil, "red")
    AF.SetSize(searchBox.ClearButton, 16, 16)
    -- Preserve the 165px autocomplete field while fitting both controls into
    -- the 256px list header: 55 + 165 + 5 + 24 + 7.
    AF.ClearPoints(searchBox)
    AF.SetPoint(searchBox, "TOPLEFT", list, 55, -12)

    local refreshButton = list.RefreshButton
    AF.SetSize(refreshButton, 24, 24)
    S.StyleIconButton(refreshButton, AF.GetIcon("Refresh_Round"), 16, "yellow_text", "widget")
    AF.ClearPoints(refreshButton)
    AF.SetPoint(refreshButton, "LEFT", searchBox, "RIGHT", 5, 0)

    local mapCanvas = frame.HouseFinderMapCanvasFrame
    mapCanvas.ScrollContainer.Child.TiledBackground:SetAlpha(0)

    frame.WoodBorderFrame.Border:SetAlpha(0)
    S.CreateBackdrop(frame.WoodBorderFrame, true)

    StyleNotificationBanner(frame.HouseFinderNotificationBanner)
    local subdivisionDropdown = frame.GuildSubdivisionDropdown
    S.StyleDropdownButton(subdivisionDropdown)
    hooksecurefunc(subdivisionDropdown, "GenerateMenu", StyleSubdivisionMenu)
    StyleSubdivisionMenu(subdivisionDropdown)

    StylePlotInfo(frame.PlotInfoFrame)
    StylePlotTooltip(frame.SelectedPlotTooltip)
    StylePlotTooltip(_G.HouseFinderHighlightedPlotTooltip)

    -- Init is shared by both live/PTR pools and runs after Blizzard resets a
    -- recycled card, so native atlases cannot leak back in on later results.
    hooksecurefunc(_G.HouseFinderNeighborhoodButtonMixin, "Init", StyleNeighborhoodButton)
    StyleNeighborhoodPools(frame)
end

-- Exact source contracts:
-- live 12.0.7.68887, wow-ui-source 4383ced30106d51b27e3e86d1987f1552f0d259d
-- PTR  12.1.0.68914, wow-ui-source d3915c78aba77a7a9be76acbfa35c674bbb6abe9
-- Interface/AddOns/Blizzard_HousingHouseFinder
AF.RegisterAddonLoaded("Blizzard_HousingHouseFinder", StyleHouseFinder)
