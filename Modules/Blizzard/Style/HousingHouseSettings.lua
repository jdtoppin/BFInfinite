---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

-- House Settings
---------------------------------------------------------------------
local function StyleAccessOptions(options)
    S.StyleDropdownButton(options.AccessTypeDropdown)

    for _, option in ipairs(options.accessOptions) do
        S.StyleCheckButton(option.Checkbox, 15)
    end
end

local function StyleAbandonHouseDialog(dialog)
    if dialog._BFIHousingSettingsStyled then return end
    dialog._BFIHousingSettingsStyled = true

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
-- Interface/AddOns/Blizzard_HousingHouseSettings
AF.RegisterAddonLoaded("Blizzard_HousingHouseSettings", StyleHouseSettings)
