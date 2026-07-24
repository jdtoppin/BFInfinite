---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- House Finder
---------------------------------------------------------------------
local function UpdateNeighborhoodButton(button, selected)
    button.ButtonBackground:SetAlpha(0)
    button:GetHighlightTexture():SetAlpha(0)

    if selected == nil then
        selected = button.houseFinderFrame
            and button.houseFinderFrame.selectedNeighborhoodButton == button
    end

    if selected then
        button.BFIHousingCardBackground:SetColorTexture(AF.GetColorRGB("BFI", 0.25))
        button.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("BFI"))
    elseif button:IsMouseMotionFocus() then
        button.BFIHousingCardBackground:SetColorTexture(AF.GetColorRGB("BFI", 0.12))
        button.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("BFI"))
    else
        button.BFIHousingCardBackground:SetColorTexture(AF.GetColorRGB("widget"))
        button.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
    end
end

local function StyleNeighborhoodButton(button)
    if button._BFIHousingSupportStyled then
        UpdateNeighborhoodButton(button)
        return
    end
    button._BFIHousingSupportStyled = true

    -- Preserve the invite, party-sync, and guild-emblem regions. Only the
    -- Blizzard card and highlight atlases are replaced by BFI chrome.
    S.CreateBackdrop(button, true, nil, 1)
    button.BFIHousingCardBackground = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    button.BFIHousingCardBackground:SetAllPoints(button.BFIBackdrop)

    S.StyleIconButton(button.DeclineInviteButton, AF.GetIcon("Close"), 10, nil, "red")
    AF.SetSize(button.DeclineInviteButton, 16, 16)

    -- IgnoreNeighborhoodButton was added in 12.1.0.68914. The live
    -- 12.0.7.68887 template only has DeclineInviteButton.
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

local function StyleHouseFinder()
    local frame = _G.HouseFinderFrame
    if not frame then return end

    S.StyleTitledFrame(frame)

    local list = frame.NeighborhoodListFrame
    S.StyleScrollBar(list.ScrollFrame.ScrollBar)
    S.StyleScrollBar(list.BNetScrollFrame.ScrollBar)

    local searchBox = list.BNetFriendSearchBox
    S.StyleEditBox(searchBox)
    searchBox.LeftBorder:SetAlpha(0)
    searchBox.MiddleBorder:SetAlpha(0)
    searchBox.RightBorder:SetAlpha(0)
    S.StyleIconButton(searchBox.ClearButton, AF.GetIcon("Close"), 10, nil, "red")
    AF.SetSize(searchBox.ClearButton, 16, 16)

    local refreshButton = list.RefreshButton
    AF.SetSize(refreshButton, 24, 24)
    S.StyleIconButton(refreshButton, nil, 16, "yellow_text", "widget")
    refreshButton.BFIIcon:SetTexture(AF.GetIcon("Refresh_Round"), nil, nil, "TRILINEAR")

    local backButton = frame.PlotInfoFrame.BackButton
    S.StyleIconButton(backButton, AF.GetIcon("ArrowLeft2"), 16, nil, "widget")
    backButton.BFIIcon:ClearAllPoints()
    AF.SetPoint(backButton.BFIIcon, "LEFT", 7, 0)

    S.StyleButton(frame.PlotInfoFrame.VisitHouseButton)
    S.StyleDropdownButton(frame.GuildSubdivisionDropdown)

    StyleNeighborhoodPools(frame)
    hooksecurefunc(frame, "PopulateNeighborhoodList", StyleNeighborhoodPools)
    hooksecurefunc(frame, "PopulateBNetNeighborhoodList", StyleNeighborhoodPools)
end

---------------------------------------------------------------------
-- House Settings
---------------------------------------------------------------------
local function StyleAccessOptions(options)
    S.StyleDropdownButton(options.AccessTypeDropdown)

    for _, option in ipairs(options.accessOptions) do
        S.StyleCheckButton(option.Checkbox, 15)
    end
end

local function StyleAbandonHouseDialog(dialog)
    if dialog._BFIHousingSupportStyled then return end
    dialog._BFIHousingSupportStyled = true

    S.RemoveNineSliceAndBackground(dialog)
    S.CreateBackdrop(dialog, nil, nil, -1)

    local header = AF.CreateBorderedFrame(dialog, nil, nil, nil, "header", "border")
    dialog.BFIHeader = header
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    AF.SetHeight(header, 20)
    AF.SetFrameLevel(header, 1, dialog)
    AF.RemoveFromPixelUpdater(header)
    AF.AddToPixelUpdater_CustomGroup("BFIStyled", header)

    header.tex = AF.CreateGradientTexture(
        header,
        "HORIZONTAL",
        AF.GetColorTable("BFI", 0.4),
        AF.GetColorTable("BFI", 0),
        nil,
        "ARTWORK"
    )
    AF.SetOnePixelInside(header.tex, header)
    AF.RemoveFromPixelUpdater(header.tex)
    AF.AddToPixelUpdater_CustomGroup("BFIStyled", header.tex)

    dialog.HouseName:SetParent(header)
    dialog.HouseName:ClearAllPoints()
    dialog.HouseName:SetPoint("CENTER")

    S.StyleButton(dialog.ConfirmButton, "red")
    S.StyleButton(dialog.CancelButton)
    S.MakeMovable(dialog, header)
end

local function StyleHouseSettings()
    local frame = _G.HousingHouseSettingsFrame
    local dialog = _G.AbandonHouseConfirmationDialog
    if not frame or not dialog then return end

    -- This housing shell predates PortraitFrameTemplate but exposes the same
    -- title and close-button contract under Title rather than TitleText.
    frame.TitleText = frame.Title
    S.StyleTitledFrame(frame)
    frame.Title:SetParent(frame.BFIHeader)
    frame.Title:ClearAllPoints()
    frame.Title:SetPoint("CENTER")

    -- Keep the foliage and house identity art; replace only the generic
    -- container/header layers and divider with BFI shell chrome.
    frame.Spacer:SetColorTexture(AF.GetColorRGB("border", 0.65))

    S.StyleDropdownButton(frame.HouseOwnerDropdown)
    StyleAccessOptions(frame.PlotAccess)
    StyleAccessOptions(frame.HouseAccess)

    -- BlueprintExport is a third settings group introduced by PTR
    -- 12.1.0.68914 and is absent from live 12.0.7.68887.
    if frame.BlueprintExport then
        StyleAccessOptions(frame.BlueprintExport)
    end

    S.StyleButton(frame.IgnoreListButton)
    S.StyleButton(frame.SaveButton)
    S.StyleButton(frame.AbandonHouseButton, "red")

    StyleAbandonHouseDialog(dialog)
end

-- Exact source contracts:
-- live 12.0.7.68887, wow-ui-source 4383ced30106d51b27e3e86d1987f1552f0d259d
-- PTR  12.1.0.68914, wow-ui-source d3915c78aba77a7a9be76acbfa35c674bbb6abe9
-- Interface/AddOns/Blizzard_HousingHouseFinder
-- Interface/AddOns/Blizzard_HousingHouseSettings
AF.RegisterAddonLoaded("Blizzard_HousingHouseFinder", StyleHouseFinder)
AF.RegisterAddonLoaded("Blizzard_HousingHouseSettings", StyleHouseSettings)
