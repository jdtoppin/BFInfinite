---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local _G = _G

---------------------------------------------------------------------
-- shared
---------------------------------------------------------------------
local function StyleInset(frame, color, removeTextures)
    if not frame or frame._BFICollectionsInsetStyled then return end
    frame._BFICollectionsInsetStyled = true

    if removeTextures then
        S.RemoveTextures(frame, true)
    end
    S.RemoveNineSliceAndBackground(frame)
    S.CreateBackdrop(frame)
    if color then
        frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB(color))
    end
end

local function StyleCollectionBackground(frame)
    if not frame or frame._BFICollectionsBackgroundStyled then return end
    frame._BFICollectionsBackgroundStyled = true

    S.RemoveTextures(frame, true)
    S.RemoveNineSliceAndBackground(frame)
    S.CreateBackdrop(frame)
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_dark"))
end

local function StyleProgressBar(progressBar, color)
    if not progressBar then return end

    S.StyleStatusBar(progressBar)
    if color then
        progressBar:SetStatusBarColor(AF.GetColorRGB(color))
    end
end

local function StylePagingFrame(pagingFrame)
    if not pagingFrame then return end

    S.StyleIconButton(pagingFrame.PrevPageButton, AF.GetIcon("ArrowLeft2"), 16)
    S.StyleIconButton(pagingFrame.NextPageButton, AF.GetIcon("ArrowRight2"), 16)
end

local function StyleFilterDropdown(dropdown)
    if not dropdown then return end

    S.StyleFilterDropdownButton(dropdown)
end

local function StyleSquareIcon(icon, ...)
    if not icon then return end

    S.StyleIcon(icon, true)
    for i = 1, select("#", ...) do
        local border = select(i, ...)
        if border then
            S.StyleIconBorder(border, icon.BFIBackdrop)
        end
    end
end

local function StyleStateTexture(texture, backdrop, color, alpha)
    if not texture then return end

    texture:SetTexture(AF.GetPlainTexture())
    texture:SetVertexColor(AF.GetColorRGB(color, alpha))
    AF.SetOnePixelInside(texture, backdrop)
end

local function StyleCollectionRowSurface(button, background, selectedTexture, highlightTexture)
    if not button._BFICollectionsRowSurfaceStyled then
        button._BFICollectionsRowSurfaceStyled = true
        S.CreateBackdrop(button, true)
        StyleStateTexture(selectedTexture, button.BFIBackdrop, "BFI", 0.35)
        StyleStateTexture(highlightTexture, button.BFIBackdrop, "white", 0.2)
    end

    -- Mount initialization reapplies a white/red vertex color. Own the full
    -- color texture on every pooled refresh so Mounts, Pets, and Sets agree.
    if background then
        background:SetColorTexture(AF.GetColorRGB("widget_dark", 0.9))
        background:SetAlpha(1)
        AF.SetOnePixelInside(background, button.BFIBackdrop)
    end
end

local function StyleLevelPlate(levelBackground, levelText, icon, color)
    if not levelBackground or not levelText or not icon then return end

    if not levelBackground._BFICollectionsLevelStyled then
        levelBackground._BFICollectionsLevelStyled = true
        S.CreateBackdrop(levelBackground, true, nil, 1)
    end

    levelBackground:SetTexture(AF.GetPlainTexture())
    levelBackground:SetVertexColor(AF.GetColorRGB(color or "widget"))
    AF.ClearPoints(levelBackground)
    AF.SetPoint(levelBackground, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    AF.SetSize(levelBackground, 29, 14)

    AF.ClearPoints(levelText)
    AF.SetPoint(levelText, "CENTER", levelBackground)
    levelBackground.BFIBackdrop:SetShown(levelBackground:IsShown())
end

local function StyleIconButtonStates(button, backdrop)
    if button._BFICollectionsStateStyled then return end
    button._BFICollectionsStateStyled = true

    StyleStateTexture(button.GetHighlightTexture and button:GetHighlightTexture(), backdrop, "highlight_add")
    StyleStateTexture(button.GetPushedTexture and button:GetPushedTexture(), backdrop, "yellow", 0.25)
    StyleStateTexture(button.GetCheckedTexture and button:GetCheckedTexture(), backdrop, "BFI", 0.25)
end

local function StyleLowercaseIconButton(button)
    if not button or button._BFICollectionsIconStyled then return end
    button._BFICollectionsIconStyled = true

    local icon = button.icon
    if not icon then return end

    StyleSquareIcon(icon, button.iconBorder, button.qualityBorder)
    StyleIconButtonStates(button, icon.BFIBackdrop)

    local name = button.GetName and button:GetName()
    local background = button.Background or (name and _G[name .. "Background"])
    if background then
        background:SetAlpha(0)
    end
    if button.selected then
        StyleStateTexture(button.selected, icon.BFIBackdrop, "BFI", 0.25)
    end
end

local function StylePanelSpellButton(button)
    if not button or button._BFICollectionsIconStyled then return end
    button._BFICollectionsIconStyled = true

    S.StyleSpellItemButton(button)
end

local function StyleCollectionSpellButton(button)
    if not button or button._BFICollectionsIconStyled then return end
    button._BFICollectionsIconStyled = true

    local icon = button.iconTexture
    if not icon then return end

    S.StyleIcon(icon, true)
    if button.iconTextureUncollected then
        S.StyleIcon(button.iconTextureUncollected)
    end

    if button.slotFrameCollected then
        S.StyleIconBorder(button.slotFrameCollected, icon.BFIBackdrop)
    end
    if button.slotFrameUncollected then
        S.StyleIconBorder(button.slotFrameUncollected, icon.BFIBackdrop)
    end
    StyleIconButtonStates(button, icon.BFIBackdrop)

    if button.slotFrameUncollectedInnerGlow then
        AF.SetOnePixelInside(button.slotFrameUncollectedInnerGlow, icon.BFIBackdrop)
    end
end

local function StyleCollectionListButton(button)
    if not button then return end

    -- Keep Blizzard's pooled Show/Hide and red unusable-state updates, but
    -- replace the rounded list atlases with flat square BFI state textures.
    StyleCollectionRowSurface(button, button.background, button.selectedTexture, button:GetHighlightTexture())

    local dragButton = button.DragButton or button.dragButton
    if not button._BFICollectionsRowStyled then
        button._BFICollectionsRowStyled = true
        StyleSquareIcon(button.icon, button.iconBorder)

        if dragButton then
            StyleStateTexture(dragButton.ActiveTexture, button.icon.BFIBackdrop, "BFI", 0.25)
            StyleStateTexture(dragButton:GetHighlightTexture(), button.icon.BFIBackdrop, "white", 0.25)
        end
    end

    if dragButton then
        StyleLevelPlate(dragButton.levelBG, dragButton.level, button.icon)
    end
end

local function StyleTabs(collectionsJournal)
    local tabs = {
        collectionsJournal.MountsTab,
        collectionsJournal.PetsTab,
        collectionsJournal.ToysTab,
        collectionsJournal.HeirloomsTab,
        collectionsJournal.WardrobeTab,
        collectionsJournal.WarbandScenesTab,
    }

    local previous
    for _, tab in ipairs(tabs) do
        S.StyleTab(tab)
        AF.ClearPoints(tab)
        if previous then
            AF.SetPoint(tab, "TOPLEFT", previous, "TOPRIGHT", 1, 0)
        else
            AF.SetPoint(tab, "TOPLEFT", collectionsJournal, "BOTTOMLEFT", 0, -1)
        end
        previous = tab
    end
end

---------------------------------------------------------------------
-- mounts
---------------------------------------------------------------------
local function StyleMountJournal()
    local frame = _G.MountJournal

    StyleInset(frame.LeftInset, "widget_dark")
    StyleInset(frame.RightInset, "widget_dark")
    StyleInset(frame.BottomLeftInset, "widget_dark", true)
    StyleInset(frame.MountCount, "widget", true)
    S.StyleEditBox(frame.searchBox, -4)
    StyleFilterDropdown(frame.FilterDropdown)
    S.StyleScrollBar(frame.ScrollBar)
    S.StyleButton(frame.MountButton, "BFI")

    StylePanelSpellButton(frame.SummonRandomFavoriteSpellFrame.Button)
    StylePanelSpellButton(frame.ToggleDynamicFlightFlyoutButton)

    local popup = frame.DynamicFlightFlyoutPopup
    StyleInset(popup, "widget")
    StylePanelSpellButton(popup.OpenDynamicFlightSkillTreeButton)
    StylePanelSpellButton(popup.DynamicFlightModeButton)
    S.StyleIcon(popup.DynamicFlightModeButton.texture)

    local slotButton = frame.BottomLeftInset.SlotButton
    StyleSquareIcon(slotButton.ItemIcon, slotButton.ItemBorder)
    S.RemoveTextures(slotButton.SlotBorder, true)
    StyleStateTexture(slotButton.SlotBorderOpen, slotButton.ItemIcon.BFIBackdrop, "BFI", 0.25)
    StyleStateTexture(slotButton:GetHighlightTexture(), slotButton.ItemIcon.BFIBackdrop, "white", 0.2)
    StyleStateTexture(slotButton:GetPushedTexture(), slotButton.ItemIcon.BFIBackdrop, "yellow", 0.2)
    for _, region in next, {slotButton:GetRegions()} do
        if region:IsObjectType("Texture") and region:GetAtlas() == "mountequipment-slot-background" then
            S.RemoveTextures(region, true)
        end
    end

    frame.MountDisplay.YesMountsTex:SetColorTexture(AF.GetColorRGB("widget"))
    frame.MountDisplay.NoMountsTex:SetColorTexture(AF.GetColorRGB("widget"))
    S.RemoveTextures(frame.MountDisplay.ShadowOverlay, true)
    S.StyleCheckButton(frame.MountDisplay.ModelScene.TogglePlayer)
    StyleSquareIcon(frame.MountDisplay.InfoButton.Icon)
    frame.ScrollBox:ForEachFrame(StyleCollectionListButton)
end

---------------------------------------------------------------------
-- pets
---------------------------------------------------------------------
local function StylePetLoadoutSlot(slot)
    if not slot then return end

    if not slot._BFICollectionsSlotStyled then
        slot._BFICollectionsSlotStyled = true

        S.CreateBackdrop(slot, true)
        S.RemoveTextures(slot.shadows, true)
        S.RemoveTextures(slot.helpFrame, true)
        local name = slot:GetName()
        S.RemoveTextures(name and _G[name .. "BG"], true)

        StyleSquareIcon(slot.icon, slot.iconBorder, slot.qualityBorder)
        StyleProgressBar(slot.healthFrame and slot.healthFrame.healthBar)
        StyleProgressBar(slot.xpBar)

        for i = 1, 3 do
            StyleLowercaseIconButton(slot["spell" .. i])
        end
    end

    StyleLevelPlate(slot.levelBG, slot.level, slot.icon)
end

local function StylePetLoadoutSlots()
    local loadout = _G.PetJournal.Loadout
    StylePetLoadoutSlot(loadout.Pet1)
    StylePetLoadoutSlot(loadout.Pet2)
    StylePetLoadoutSlot(loadout.Pet3)
end

local function StylePetCard(card)
    S.RemoveTextures(card)
    StyleSquareIcon(card.PetInfo.icon, card.PetInfo.qualityBorder)
    StyleLevelPlate(card.PetInfo.levelBG, card.PetInfo.level, card.PetInfo.icon)
    StyleProgressBar(card.HealthFrame.healthBar)
    StyleProgressBar(card.xpBar)

    for i = 1, 6 do
        StyleLowercaseIconButton(card["spell" .. i])
    end
end

local function StyleCollectionsInfoButton(button, collectionsJournal)
    if not button then return end

    S.StyleIconButton(button, AF.GetIcon("Info_Square"), 12, "gray", "gray_hover")
    AF.SetSize(button, 20, 20)
    button:SetHitRectInsets(0, 0, 0, 0)
    AF.ClearPoints(button)
    AF.SetPoint(button, "LEFT", collectionsJournal.BFIHeader, "LEFT", 2, 0)
    AF.SetFrameLevel(button, 1, collectionsJournal.BFIHeader)
end

local petHelpTipPositions = {
    UP = "TOP",
    DOWN = "BOTTOM",
    LEFT = "LEFT",
    RIGHT = "RIGHT",
}

local function GetActiveHelpTip(widget)
    local tip = widget and widget._helptip
    if tip and tip.widget == widget and tip:IsShown() then
        return tip
    end
end

local function GetActivePetJournalHelpTip(frame)
    for _, anchor in ipairs(frame._BFIPetJournalHelpAnchors or {}) do
        local tip = GetActiveHelpTip(anchor)
        if tip then return tip end
    end
end

local function HidePetJournalHelpTips(frame)
    local tip = GetActivePetJournalHelpTip(frame)
    if tip then
        -- AF only exposes a global hide API; close this tour without
        -- dismissing unrelated HelpTips owned by other modules.
        tip:Close()
    end

    local anchors = frame._BFIPetJournalHelpAnchors
    if anchors then
        for _, anchor in ipairs(anchors) do
            anchor:Hide()
        end
    end
end

local function HideAllPetJournalHelpTips(frame)
    HidePetJournalHelpTips(frame)

    local prompt = GetActiveHelpTip(frame.MainHelpButton)
    if prompt then
        prompt:Close()
    end
end

local function CreatePetJournalHelpTips(frame)
    local helpPlateInfo = _G.PetJournal_HelpPlate
    if not helpPlateInfo then return {} end

    local anchors = frame._BFIPetJournalHelpAnchors
    if not anchors then
        anchors = {}
        frame._BFIPetJournalHelpAnchors = anchors
    end

    local framePos = helpPlateInfo.FramePos or {}
    local tips = {}
    for _, helpInfo in ipairs(helpPlateInfo) do
        local buttonPos = helpInfo.ButtonPos
        local position = petHelpTipPositions[helpInfo.ToolTipDir]
        if buttonPos and position and helpInfo.ToolTipText then
            local index = #tips + 1
            local anchor = anchors[index]
            if not anchor then
                anchor = _G.CreateFrame("Frame", nil, frame)
                anchor:SetSize(46, 46)
                anchors[index] = anchor
            end

            anchor:ClearAllPoints()
            anchor:SetPoint(
                "TOPLEFT",
                frame,
                "TOPLEFT",
                (framePos.x or 0) + (buttonPos.x or 0),
                (framePos.y or 0) + (buttonPos.y or 0)
            )
            anchor:Show()

            tips[index] = {
                widget = anchor,
                position = position,
                text = helpInfo.ToolTipText,
                width = 220,
                closeHoldDuration = 0,
            }
        end
    end

    for i = #tips + 1, #anchors do
        anchors[i]:Hide()
    end
    return tips
end

local function HideNativePetJournalHelp()
    local helpPlate = _G.HelpPlate
    local helpPlateInfo = _G.PetJournal_HelpPlate
    if not helpPlate then return end

    if helpPlateInfo and helpPlate.IsShowingHelpInfo(helpPlateInfo) then
        helpPlate.Hide(false)
    end
    helpPlate.HideTooltip()
end

local function TogglePetJournalHelpTips(frame)
    local prompt = GetActiveHelpTip(frame.MainHelpButton)
    if prompt then
        prompt:Close()
    end

    if GetActivePetJournalHelpTip(frame) then
        HidePetJournalHelpTips(frame)
        return
    end

    -- Clear proxy anchors left behind when a player closes an intermediate
    -- step, then reopen the tour with the same click.
    HidePetJournalHelpTips(frame)
    HideNativePetJournalHelp()
    if _G.SetCVarBitfield and _G.LE_FRAME_TUTORIAL_PET_JOURNAL then
        _G.SetCVarBitfield("closedInfoFrames", _G.LE_FRAME_TUTORIAL_PET_JOURNAL, true)
    end
    if _G.CollectionsJournal_HideTabHelpTips then
        _G.CollectionsJournal_HideTabHelpTips()
    end

    local tips = CreatePetJournalHelpTips(frame)
    if #tips == 0 then return end

    AF.ShowHelpTipGroup(tips)
end

local function ReplacePetJournalTutorialPrompt(frame)
    local helpPlate = _G.HelpPlate
    local helpPlateInfo = _G.PetJournal_HelpPlate
    if not helpPlate or not helpPlateInfo then return end
    if not helpPlate.IsShowingTutorialTooltip(helpPlateInfo) then return end

    helpPlate.HideTooltip()
    local button = frame.MainHelpButton
    -- ShowTutorialTooltip leaves Blizzard's private tutorial mode active.
    -- Complete a non-rendered Show/Hide cycle before replacing the prompt.
    helpPlate.Show(helpPlateInfo, frame, button)
    helpPlate.Hide(false)
    AF.ShowHelpTip({
        widget = button,
        position = "RIGHT",
        text = button.mainHelpPlateButtonTooltipText or _G.MAIN_HELP_BUTTON_TOOLTIP,
        width = 220,
        glow = true,
        closeHoldDuration = 0,
    })
end

local function StylePetJournalHelpButton(frame)
    local button = frame.MainHelpButton
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    AF.SetTooltip(
        button,
        "BOTTOMLEFT",
        0,
        -2,
        button.mainHelpPlateButtonTooltipText or _G.MAIN_HELP_BUTTON_TOOLTIP
    )
    button:HookScript("OnEnter", function(self)
        if GetActiveHelpTip(self) then
            AF.HideTooltip()
        end
    end)
    button:SetScript("OnClick", function()
        AF.HideTooltip()
        TogglePetJournalHelpTips(frame)
    end)

    frame:HookScript("OnShow", ReplacePetJournalTutorialPrompt)
    frame:HookScript("OnHide", HideAllPetJournalHelpTips)
    if frame:IsShown() then
        ReplacePetJournalTutorialPrompt(frame)
    end
end

local function StylePetJournal(collectionsJournal)
    local frame = _G.PetJournal

    StyleInset(frame.LeftInset, "widget_dark")
    StyleInset(frame.PetCardInset, "widget_dark")
    StyleInset(frame.RightInset, "widget_dark")
    StyleInset(frame.PetCount, "widget", true)
    S.StyleEditBox(frame.searchBox, -4)
    StyleFilterDropdown(frame.FilterDropdown)
    S.StyleScrollBar(frame.ScrollBar)
    S.StyleButton(frame.FindBattleButton, "BFI")
    S.StyleButton(frame.SummonButton, "BFI")
    StyleCollectionsInfoButton(frame.MainHelpButton, collectionsJournal)
    StylePetJournalHelpButton(frame)

    StylePanelSpellButton(frame.HealPetSpellFrame.Button)
    StylePanelSpellButton(frame.SummonRandomPetSpellFrame.Button)

    S.RemoveTextures(frame.loadoutBorder, true)
    StylePetLoadoutSlots()
    StylePetCard(frame.PetCard)

    StyleCollectionBackground(frame.SpellSelect)
    StyleLowercaseIconButton(frame.SpellSelect.Spell1)
    StyleLowercaseIconButton(frame.SpellSelect.Spell2)

    frame.ScrollBox:ForEachFrame(StyleCollectionListButton)
end

---------------------------------------------------------------------
-- toys
---------------------------------------------------------------------
local function StyleToyBox()
    local frame = _G.ToyBox

    StyleProgressBar(frame.progressBar, "lime")
    S.StyleEditBox(frame.searchBox, -4)
    StyleFilterDropdown(frame.FilterDropdown)
    StyleCollectionBackground(frame.iconsFrame)
    StylePagingFrame(frame.PagingFrame)

    for i = 1, 18 do
        StyleCollectionSpellButton(frame.iconsFrame["spellButton" .. i])
    end
end

---------------------------------------------------------------------
-- heirlooms
---------------------------------------------------------------------
local function RefreshHeirloomLevel(button)
    local levelBackground = button.levelBackground
    if not levelBackground then return end

    local isMaxLevel = levelBackground:GetAtlas() == "collections-levelplate-gold"
    StyleLevelPlate(levelBackground, button.level, button.iconTexture, isMaxLevel and "yellow" or "widget")
end

local function StyleHeirloomButton(_, button)
    StyleCollectionSpellButton(button)
    RefreshHeirloomLevel(button)
end

local function StyleCollectionsRadio(frame)
    S.StyleMenuSelection(frame)
end

local function StyleCollectionsMenuHighlight(frame)
    local highlight = frame.highlight
    if not highlight then return end

    local hoverColor = AF.GetButtonHoverColor("BFI_transparent")
    highlight:SetColorTexture(AF.UnpackColor(hoverColor))
    highlight:SetBlendMode("BLEND")
end

local function StyleCollectionsRadioMenuDescriptions(parentDescription)
    for _, description in parentDescription:EnumerateElementDescriptions() do
        description:AddInitializer(StyleCollectionsMenuHighlight)
        if description:IsRadio() then
            description:AddInitializer(StyleCollectionsRadio)
        end
        StyleCollectionsRadioMenuDescriptions(description)
    end
end

local function StyleCollectionsRadioMenu(_, rootDescription)
    StyleCollectionsRadioMenuDescriptions(rootDescription)
end

local function StyleHeirloomClassRadioMenu(owner, rootDescription)
    if owner == _G.HeirloomsJournal.ClassDropdown then
        StyleCollectionsRadioMenu(owner, rootDescription)
    end
end

local collectionsRadioMenuTags = {
    "MENU_MOUNT_COLLECTION_FILTER",
    "MENU_PET_COLLECTION_FILTER",
    "MENU_TOYBOX_FILTER",
    "MENU_HEIRLOOMS_FILTER",
    "MENU_WARDROBE_FILTER",
    "MENU_WARDROBE_BASE_SETS_FILTER",
    "MENU_WARDROBE_CLASS",
    "MENU_WARDROBE_WEAPONS_FILTER",
    "MENU_WARDROBE_VARIANT_SETS",
}

local function RegisterCollectionsRadioMenus()
    for _, menuTag in ipairs(collectionsRadioMenuTags) do
        _G.Menu.ModifyMenu(menuTag, StyleCollectionsRadioMenu)
    end
    _G.Menu.ModifyMenu("MENU_CLASS_FILTER", StyleHeirloomClassRadioMenu)
end

local function StyleHeirlooms()
    local frame = _G.HeirloomsJournal

    StyleProgressBar(frame.progressBar, "lime")
    S.StyleEditBox(frame.SearchBox, -4)
    StyleFilterDropdown(frame.FilterDropdown)
    S.StyleDropdownButton(frame.ClassDropdown)
    StyleCollectionBackground(frame.iconsFrame)
    StylePagingFrame(frame.PagingFrame)

    for _, button in next, frame.heirloomEntryFrames do
        StyleHeirloomButton(nil, button)
    end
end

---------------------------------------------------------------------
-- appearances
---------------------------------------------------------------------
local function StyleWardrobeSlotButton(button)
    if button._BFICollectionsSlotStyled then return end
    button._BFICollectionsSlotStyled = true

    local icon = button.NormalTexture
    StyleSquareIcon(icon)
    StyleStateTexture(button.Highlight, icon.BFIBackdrop, "white", 0.25)
    StyleStateTexture(button.SelectedTexture, icon.BFIBackdrop, "BFI", 0.35)
end

local function StyleWardrobeSlotButtons(frame)
    local buttons = frame.SlotsFrame.Buttons
    if not buttons then return end

    for _, button in next, buttons do
        StyleWardrobeSlotButton(button)
    end
end

local function StyleWardrobeModel(model)
    if not model._BFICollectionsCardStyled then
        model._BFICollectionsCardStyled = true

        S.CreateBackdrop(model, true)
        for _, region in next, {model:GetRegions()} do
            if region:IsObjectType("Texture") and region:GetAtlas() == "transmog-wardrobe-border-highlighted" then
                StyleStateTexture(region, model.BFIBackdrop, "white", 0.2)
                break
            end
        end
        StyleStateTexture(model.DisabledOverlay, model.BFIBackdrop, "black", 0.55)
        StyleStateTexture(model.TransmogStateTexture, model.BFIBackdrop, "BFI", 0.35)
    end

    -- UpdateItems reapplies the native collected border atlas on every pass.
    S.RemoveTextures(model.Border, true)

    local visualInfo = model.visualInfo
    if not visualInfo then return end

    local color
    if not visualInfo.isCollected then
        color = "disabled"
    elseif not visualInfo.isUsable then
        color = "red"
    else
        color = "darkgray"
    end
    model.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB(color))
end

local function StyleWardrobeModels(frame)
    for _, model in ipairs(frame.Models) do
        StyleWardrobeModel(model)
    end
end

local function StyleWardrobeSetButton(button)
    StyleCollectionRowSurface(button, button.Background, button.SelectedTexture, button.HighlightTexture)

    if not button._BFICollectionsRowStyled then
        button._BFICollectionsRowStyled = true
        -- Preserve set progress, favorite, new, and unavailable visuals.
        StyleSquareIcon(button.IconFrame.Icon)
    end
end

local function StyleWardrobeSetItem(item)
    if not item._BFICollectionsIconStyled then
        item._BFICollectionsIconStyled = true
        StyleSquareIcon(item.Icon, item.IconBorder)
    end

    -- SetItemFrameQuality reapplies a pure-white vertex color whenever the
    -- pooled detail icon is refreshed. Keep the BFI outline neutral.
    item.Icon.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("darkgray"))
end

local function StyleWardrobeSetButtons(scrollBox)
    scrollBox:ForEachFrame(StyleWardrobeSetButton)
end

local function StyleWardrobeSetItems(frame)
    for item in frame.DetailsFrame.itemFramesPool:EnumerateActive() do
        StyleWardrobeSetItem(item)
    end
end

local function StyleWardrobeInfoButton(frame, collectionsJournal)
    local button = frame.InfoButton
    if not button then return end

    -- Blizzard's HelpTip can be globally suppressed. Use AF's transient hover
    -- tooltip while retaining all three localized shortcut strings.
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    StyleCollectionsInfoButton(button, collectionsJournal)
    AF.SetTooltip(
        button,
        "BOTTOMLEFT",
        0,
        -2,
        _G.WARDROBE_SHORTCUTS_TUTORIAL_1,
        _G.WARDROBE_SHORTCUTS_TUTORIAL_2,
        _G.WARDROBE_SHORTCUTS_TUTORIAL_3
    )
    button:HookScript("OnHide", function()
        if AF.Tooltip:GetOwner() == button then
            AF.HideTooltip()
        end
    end)
end

local function StyleWardrobe(collectionsJournal)
    local frame = _G.WardrobeCollectionFrame
    local itemsFrame = frame.ItemsCollectionFrame
    local setsFrame = frame.SetsCollectionFrame

    S.StyleTab(frame.ItemsTab)
    S.StyleTab(frame.SetsTab)
    AF.ClearPoints(frame.SetsTab)
    AF.SetPoint(frame.SetsTab, "TOPLEFT", frame.ItemsTab, "TOPRIGHT", 1, 0)

    S.StyleEditBox(frame.SearchBox, -4)
    StyleProgressBar(frame.SearchBox.ProgressFrame.ProgressBar, "BFI")
    StyleProgressBar(frame.progressBar, "lime")
    StyleFilterDropdown(frame.FilterButton)
    S.StyleDropdownButton(frame.ClassDropdown)
    StyleWardrobeInfoButton(frame, collectionsJournal)

    StyleCollectionBackground(itemsFrame)
    StylePagingFrame(itemsFrame.PagingFrame)
    S.StyleDropdownButton(itemsFrame.WeaponDropdown)
    StyleWardrobeSlotButtons(itemsFrame)
    hooksecurefunc(itemsFrame, "UpdateItems", StyleWardrobeModels)
    StyleWardrobeModels(itemsFrame)

    StyleInset(setsFrame.LeftInset, "widget_dark")
    StyleCollectionBackground(setsFrame.RightInset)
    S.StyleScrollBar(setsFrame.ListContainer.ScrollBar)
    S.StyleDropdownButton(setsFrame.DetailsFrame.VariantSetsDropdown)
    hooksecurefunc(setsFrame.ListContainer.ScrollBox, "Update", StyleWardrobeSetButtons)
    hooksecurefunc(setsFrame, "DisplaySet", StyleWardrobeSetItems)
    StyleWardrobeSetButtons(setsFrame.ListContainer.ScrollBox)
    StyleWardrobeSetItems(setsFrame)
end

---------------------------------------------------------------------
-- warband scenes
---------------------------------------------------------------------
local function StyleWarbandSceneEntry(entry)
    if not entry._BFICollectionsCardStyled then
        entry._BFICollectionsCardStyled = true

        S.CreateBackdrop(entry, true)
        S.RemoveTextures(entry.Border, true)
        StyleStateTexture(entry.HighlightTexture, entry.BFIBackdrop, "white", 0.2)

        entry.NameBackground:SetTexture(AF.GetPlainTexture())
        entry.NameBackground:SetVertexColor(AF.GetColorRGB("widget_dark", 0.9))
        AF.ClearPoints(entry.NameBackground)
        AF.SetPoint(entry.NameBackground, "BOTTOMLEFT", entry.BFIBackdrop, "BOTTOMLEFT", 1, 1)
        AF.SetPoint(entry.NameBackground, "BOTTOMRIGHT", entry.BFIBackdrop, "BOTTOMRIGHT", -1, 1)
        AF.SetHeight(entry.NameBackground, 34)
    end

    -- Init resets the atlas to its native size for every pooled card.
    AF.ClearPoints(entry.Icon)
    AF.SetOnePixelInside(entry.Icon, entry.BFIBackdrop)
end

local function StyleWarbandScenes()
    local frame = _G.WarbandSceneJournal
    local icons = frame.IconsFrame.Icons

    StyleCollectionBackground(frame.IconsFrame)
    S.StyleCheckButton(icons.Controls.ShowOwned.Checkbox)
    StylePagingFrame(icons.Controls.PagingControls)
    hooksecurefunc(icons, "DisplayViewsForCurrentPage", function(self)
        self:ForEachFrame(StyleWarbandSceneEntry)
    end)
    icons:ForEachFrame(StyleWarbandSceneEntry)
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    local collectionsJournal = _G.CollectionsJournal
    if not collectionsJournal then return end
    if collectionsJournal._BFICollectionsJournalStyled then return end
    collectionsJournal._BFICollectionsJournalStyled = true

    -- Frame keys and mixin update points verified in Retail 12.0.7.68887
    -- (Gethe wow-ui-source 4383ced30106d51b27e3e86d1987f1552f0d259d)
    -- and PTR 12.1.0.68914
    -- (Gethe wow-ui-source d3915c78aba77a7a9be76acbfa35c674bbb6abe9).
    -- The Collections XML surface is stable between those pinned artifacts.
    hooksecurefunc("MountJournal_InitMountButton", StyleCollectionListButton)
    hooksecurefunc("PetJournal_InitPetButton", StyleCollectionListButton)
    hooksecurefunc("PetJournal_UpdatePetLoadOut", StylePetLoadoutSlots)
    hooksecurefunc("PetJournal_UpdatePetCard", StylePetCard)
    hooksecurefunc("ToySpellButton_UpdateButton", StyleCollectionSpellButton)
    hooksecurefunc(_G.HeirloomsJournal, "UpdateButton", StyleHeirloomButton)
    hooksecurefunc(_G.WardrobeCollectionFrame.ItemsCollectionFrame, "CreateSlotButtons", StyleWardrobeSlotButtons)
    hooksecurefunc(_G.WardrobeSetsScrollFrameButtonMixin, "Init", StyleWardrobeSetButton)
    hooksecurefunc(_G.WardrobeSetsDetailsItemMixin, "OnShow", StyleWardrobeSetItem)
    hooksecurefunc(_G.WardrobeSetsCollectionMixin, "SetItemFrameQuality", function(_, item)
        StyleWardrobeSetItem(item)
    end)
    hooksecurefunc(_G.WarbandSceneEntryMixin, "Init", StyleWarbandSceneEntry)

    S.StyleTitledFrame(collectionsJournal)
    StyleTabs(collectionsJournal)
    StyleMountJournal()
    StylePetJournal(collectionsJournal)
    StyleToyBox()
    StyleHeirlooms()
    StyleWardrobe(collectionsJournal)
    StyleWarbandScenes()
    RegisterCollectionsRadioMenus()
end

AF.RegisterAddonLoaded("Blizzard_Collections", StyleBlizzard)
