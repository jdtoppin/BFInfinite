---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local spellFrame

---------------------------------------------------------------------
-- icons
---------------------------------------------------------------------
local TALENT_BORDER_COLORS = {
    [TalentButtonUtil.BaseVisualState.RefundInvalid] = "red",
    [TalentButtonUtil.BaseVisualState.DisplayError] = "red",
    [TalentButtonUtil.BaseVisualState.Gated] = "disabled",
    [TalentButtonUtil.BaseVisualState.Selectable] = "lime",
    [TalentButtonUtil.BaseVisualState.Maxed] = "BFI",
    [TalentButtonUtil.BaseVisualState.Locked] = "disabled",
    [TalentButtonUtil.BaseVisualState.Disabled] = "disabled",
}

local function TalentTexture_SetShown(texture, shown)
    if shown then
        AF.TextureHide(texture)
    end
end

local function HideTalentTexture(texture)
    if not texture or texture._BFIHidden then return end

    texture._BFIHidden = true
    texture:Hide()
    hooksecurefunc(texture, "Show", AF.TextureHide)
    hooksecurefunc(texture, "SetShown", TalentTexture_SetShown)
end

local function UpdateTalentIconBorder(button, visualState)
    local color = TALENT_BORDER_COLORS[visualState] or "border"

    if button.BFICircleBorder then
        button.BFICircleBorder:SetColor(color)
        if button.BFIChoiceArrowLeft then
            button.BFIChoiceArrowLeft:SetColor(color)
            button.BFIChoiceArrowRight:SetColor(color)
        end
    elseif button.Icon.BFIBackdrop then
        button.Icon.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB(color))
    end
end

local function StyleChoiceTalentIcon(button)
    AF.ApplyCircularIconMask(button.IconMask)
    AF.ApplyCircularIconMask(button.DisabledOverlayMask)

    local iconSplitMask = button.IconSplitMask
    iconSplitMask:SetTexture(AF.GetPlainTexture())
    AF.ClearPoints(iconSplitMask)
    AF.SetPoint(iconSplitMask, "TOPLEFT", button.Icon)
    AF.SetPoint(iconSplitMask, "BOTTOM", button.Icon)

    local icon2Mask = button.Icon2Mask
    icon2Mask:SetTexture(AF.GetPlainTexture())
    icon2Mask:SetRotation(0)
    AF.ClearPoints(icon2Mask)
    AF.SetPoint(icon2Mask, "TOP", button.Icon2)
    AF.SetPoint(icon2Mask, "BOTTOMRIGHT", button.Icon2)
    button.BFIIcon2CircleMask = AF.CreateCircularMask(button.Icon2)

    local arrowLeft = AF.CreateTexture(button, AF.GetIcon("ArrowLeft2"), "border", "OVERLAY", 5)
    button.BFIChoiceArrowLeft = arrowLeft
    AF.SetSize(arrowLeft, 8, 8)
    AF.SetPoint(arrowLeft, "RIGHT", button.Icon, "LEFT", -1, 0)

    local arrowRight = AF.CreateTexture(button, AF.GetIcon("ArrowRight2"), "border", "OVERLAY", 5)
    button.BFIChoiceArrowRight = arrowRight
    AF.SetSize(arrowRight, 8, 8)
    AF.SetPoint(arrowRight, "LEFT", button.Icon, "RIGHT", 1, 0)
end

local function StyleTalentButton(button, forceCircle)
    if button._BFIIconStyled then return end
    button._BFIIconStyled = true

    S.StyleIcon(button.Icon)
    if button.Icon2 then
        S.StyleIcon(button.Icon2)
    end

    local isChoice = button.Icon2 ~= nil
    local isCircle = forceCircle or button.artSet.iconMask == "talents-node-circle-mask"
    if isChoice then
        StyleChoiceTalentIcon(button)
        button.BFICircleBorder = AF.CreateCircularIconBorder(button, button.Icon, "border", "OVERLAY", 4)
    elseif isCircle then
        AF.ApplyCircularIconMask(button.IconMask)
        AF.ApplyCircularIconMask(button.DisabledOverlayMask)
        button.BFICircleBorder = AF.CreateCircularIconBorder(button, button.Icon, "border", "OVERLAY", 4)
    elseif not button.artSet.iconMask then
        S.StyleSquareIcon(button.Icon, button.IconMask, true)
        S.StyleSquareIcon(button.DisabledOverlay, button.DisabledOverlayMask)
    else
        return
    end

    HideTalentTexture(button.Shadow)
    HideTalentTexture(button.StateBorder)
    HideTalentTexture(button.StateBorderHover)
    HideTalentTexture(button.BorderSheen)
    HideTalentTexture(button.SelectableGlow)

    hooksecurefunc(button, "UpdateStateBorder", UpdateTalentIconBorder)
    UpdateTalentIconBorder(button, button:GetVisualState())
end

local function StyleSpellBookItem(item)
    local button = item.Button
    if not button._BFIIconStyled then
        button._BFIIconStyled = true
        S.CreateBackdrop(button, true, nil, 1)
        S.StyleIcon(button.Icon)
        button.BFICircleBorder = AF.CreateCircularIconBorder(button, button.Icon, "border", "OVERLAY", 5)
    end

    local isPassive = item.spellBookItemInfo.isPassive
    if isPassive then
        AF.ApplyCircularIconMask(button.IconMask)
    end
    button.IconMask:SetShown(isPassive)
    button.Border:Hide()
    button.BFIBackdrop:SetShown(not isPassive)
    button.BFICircleBorder:SetShown(isPassive)

    if isPassive then
        button.IconHighlight:SetAllPoints(button)
    else
        AF.SetOnePixelInside(button.IconHighlight, button.BFIBackdrop)
        button.IconHighlight:SetColorTexture(AF.GetColorRGB("white", 0.25))
    end
end

---------------------------------------------------------------------
-- SpecFrame
---------------------------------------------------------------------
local function StyleSpecFrame()
    local specFrame = spellFrame.SpecFrame
    S.RemoveBackground(specFrame)

    -- activate button
    for specContentFrame in specFrame.SpecContentFramePool:EnumerateActive() do
        S.StyleButton(specContentFrame.ActivateButton)
    end
end

---------------------------------------------------------------------
-- TalentsFrame
---------------------------------------------------------------------
local function StyleTalentsFrame()
    local talentsFrame = spellFrame.TalentsFrame
    -- S.RemoveBackground(talentsFrame)
    talentsFrame.BlackBG:SetAlpha(0)
    talentsFrame.BottomBar:SetAlpha(0)
    talentsFrame.Background:SetAlpha(0.5)

    S.StyleDropdownButton(talentsFrame.LoadSystem.Dropdown)
    S.StyleEditBox(talentsFrame.SearchBox, -4, -2, nil, 2)
    S.StyleButton(talentsFrame.ApplyButton, "BFI", "BFI")
    S.StyleButton(talentsFrame.InspectCopyButton, "BFI", "BFI")

    local searchPreview = talentsFrame.SearchPreviewContainer
    AF.ClearPoints(searchPreview)
    AF.SetPoint(searchPreview, "TOPLEFT", talentsFrame.SearchBox, "BOTTOMLEFT", -4, 1)
    AF.SetPoint(searchPreview, "TOPRIGHT", talentsFrame.SearchBox, "BOTTOMRIGHT", 0, 1)
    S.StyleSpellSearchPreviewContainer(searchPreview)

    -- Retail 12.0.7.68887 (Gethe wow-ui-source 4383ced): talent nodes are pooled and announce each acquisition.
    talentsFrame:RegisterCallback(TalentFrameBaseMixin.Event.TalentButtonAcquired, function(_, button)
        StyleTalentButton(button)
    end, talentsFrame)

    for button in talentsFrame:EnumerateAllTalentButtons() do
        StyleTalentButton(button)
    end

    hooksecurefunc(TalentSelectionChoiceFrameMixin, "SetSelectionOptions", function(selectionFrame)
        if selectionFrame:GetTalentFrame() ~= talentsFrame then return end

        for _, selectionButton in ipairs(selectionFrame.selectionFrameArray) do
            StyleTalentButton(selectionButton, true)
        end
    end)
end

---------------------------------------------------------------------
-- SpellBookFrame
---------------------------------------------------------------------
local function StyleSpellBookFrame()
    local spellBookFrame = spellFrame.SpellBookFrame
    S.RemoveBackground(spellBookFrame)
    spellBookFrame.TopBar:SetAlpha(0)

    -- tab
    local tabSystem = spellBookFrame.CategoryTabSystem
    S.StyleTabSystem(tabSystem, true)
    AF.ClearPoints(tabSystem)
    AF.SetPoint(tabSystem, "BOTTOMLEFT", spellBookFrame.PagedSpellsFrame, "TOPLEFT", 10, 10)

    -- search
    local searchBox = spellBookFrame.SearchBox
    S.StyleEditBox(searchBox, -4)
    AF.ClearPoints(searchBox)
    AF.SetPoint(searchBox, "BOTTOMLEFT", tabSystem, "BOTTOMRIGHT", 14, 0)
    AF.SetHeight(searchBox, 27)

    local searchPreview = spellBookFrame.SearchPreviewContainer
    AF.ClearPoints(searchPreview)
    AF.SetPoint(searchPreview, "TOPLEFT", searchBox, "BOTTOMLEFT", -4, -1)
    AF.SetPoint(searchPreview, "TOPRIGHT", searchBox, "BOTTOMRIGHT", 0, -1)
    S.StyleSpellSearchPreviewContainer(searchPreview)

    -- setting
    hooksecurefunc(spellBookFrame, "UpdateAttic", function()
        AF.ClearPoints(spellBookFrame.SettingsDropdown)
        AF.SetPoint(spellBookFrame.SettingsDropdown, "LEFT", searchBox, "RIGHT", 5, 0)
    end)

    -- assisted
    local assistedFrame = spellBookFrame.AssistedCombatRotationSpellFrame
    S.RemoveTextures(assistedFrame)
    AF.ClearPoints(assistedFrame)
    AF.SetPoint(assistedFrame, "BOTTOMRIGHT", spellBookFrame.PagedSpellsFrame, "TOPRIGHT", -10, 10)

    local button = assistedFrame.Button
    S.StyleSpellItemButton(button)
    button.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))

    -- Retail 12.0.7.68887 (Gethe wow-ui-source 4383ced): UpdateVisuals reapplies the active/passive icon masks.
    hooksecurefunc(SpellBookItemMixin, "UpdateVisuals", StyleSpellBookItem)
    spellBookFrame:ForEachDisplayedSpell(StyleSpellBookItem)

    -- page button
    local prevButton = spellBookFrame.PagedSpellsFrame.PagingControls.PrevPageButton
    S.StyleIconButton(prevButton, AF.GetIcon("ArrowLeft2"), 16)
    AF.SetSize(prevButton, 23, 23)

    local nextButton = spellBookFrame.PagedSpellsFrame.PagingControls.NextPageButton
    S.StyleButton(nextButton)
    S.StyleIconButton(nextButton, AF.GetIcon("ArrowRight2"), 16)
    AF.SetSize(nextButton, 23, 23)

    hooksecurefunc(spellBookFrame.PagedSpellsFrame.PagingControls, "LayoutChildren", function()
        local pageText = spellBookFrame.PagedSpellsFrame.PagingControls.PageText
        AF.ClearPoints(prevButton)
        AF.SetPoint(prevButton, "RIGHT", pageText, "LEFT", -7, 0)
        AF.ClearPoints(nextButton)
        AF.SetPoint(nextButton, "LEFT", pageText, "RIGHT", 7, 0)
    end)

    -- help
    spellBookFrame.HelpPlateButton:Hide()
end

local function StyleHeroTalentsSelectionDialog()
    local dialog = _G.HeroTalentsSelectionDialog
    S.StyleTitledFrame(dialog)

    -- activate button
    hooksecurefunc(dialog, "ShowDialog", function()
        for specContentFrame in dialog.SpecContentFramePool:EnumerateActive() do
            S.StyleButton(specContentFrame.ActivateButton)
            S.StyleButton(specContentFrame.ApplyChangesButton)
        end
    end)
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    spellFrame = _G.PlayerSpellsFrame

    S.StyleTitledFrame(spellFrame)
    S.StyleTabSystem(spellFrame.TabSystem)

    StyleSpecFrame()
    StyleTalentsFrame()
    StyleSpellBookFrame()
    StyleHeroTalentsSelectionDialog()
end
-- AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
AF.RegisterAddonLoaded("Blizzard_PlayerSpells", StyleBlizzard)
