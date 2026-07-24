---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local ProfessionsFrame
local InspectRecipeFrame

-- Frame ownership and fields were verified against Gethe wow-ui-source
-- live commit 4383ced30106d51b27e3e86d1987f1552f0d259d and PTR commit
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9. The scoped XML hierarchy is
-- identical between those artifacts.

local TAB_ART_TEXTURES = {
    "Left",
    "Middle",
    "Right",
    "LeftActive",
    "MiddleActive",
    "RightActive",
    "LeftHighlight",
    "MiddleHighlight",
    "RightHighlight",
    "BottomBorderGlow",
}

local function HideTexture(texture)
    if texture then
        texture:SetAlpha(0)
    end
end

local function IsInScope(frame)
    while frame do
        if frame == ProfessionsFrame or frame == InspectRecipeFrame then
            return true
        end
        frame = frame:GetParent()
    end
    return false
end

local function StyleButtons(...)
    for i = 1, select("#", ...) do
        local button = select(i, ...)
        if button then
            S.StyleButton(button)
        end
    end
end

local function StyleInset(frame)
    if not frame or frame._BFIProfessionInsetStyled then return end
    frame._BFIProfessionInsetStyled = true

    S.RemoveNineSliceAndBackground(frame)
    HideTexture(frame.BackgroundNineSlice)
    S.CreateBackdrop(frame)
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("background"))
end

---------------------------------------------------------------------
-- icons
---------------------------------------------------------------------
local function StyleStandaloneIcon(icon, border, mask)
    if not icon then return end

    if not icon._BFIProfessionStyled then
        icon._BFIProfessionStyled = true
        S.StyleSquareIcon(icon, mask, true)
    end
    if border then
        S.StyleIconBorder(border, icon.BFIBackdrop)
    end
end

local function StyleItemButton(button)
    if not button or button._BFIProfessionItemStyled then return end

    local icon = button.Icon or button.icon or button.IconTexture
    if not icon then return end
    button._BFIProfessionItemStyled = true

    StyleStandaloneIcon(icon, button.IconBorder or button.Border, button.CircleMask or button.IconMask)

    HideTexture(button.SlotBackground)
    HideTexture(button.CropFrame)
    HideTexture(button.ItemFrame)

    local normalTexture = button.GetNormalTexture and button:GetNormalTexture()
    if normalTexture and normalTexture ~= icon then
        normalTexture:SetAlpha(0)
    end

    local disabledTexture = button.GetDisabledTexture and button:GetDisabledTexture()
    if disabledTexture and disabledTexture ~= icon then
        disabledTexture:SetAlpha(0)
    end

    local highlightTexture = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlightTexture then
        AF.SetOnePixelInside(highlightTexture, icon.BFIBackdrop)
        highlightTexture:SetColorTexture(AF.GetColorRGB("white", 0.2))
    end

    local pushedTexture = button.GetPushedTexture and button:GetPushedTexture()
    if pushedTexture then
        AF.SetOnePixelInside(pushedTexture, icon.BFIBackdrop)
        pushedTexture:SetColorTexture(AF.GetColorRGB("yellow", 0.2))
    end

    local checkedTexture = button.GetCheckedTexture and button:GetCheckedTexture()
    if checkedTexture then
        AF.SetOnePixelInside(checkedTexture, icon.BFIBackdrop)
        checkedTexture:SetColorTexture(AF.GetColorRGB("BFI", 0.25))
    end
end

local function StyleRecraftSlot(slot)
    if not slot then return end

    if not slot._BFIProfessionStyled then
        slot._BFIProfessionStyled = true
        StyleInset(slot)
    end

    StyleItemButton(slot.InputSlot)
    StyleItemButton(slot.OutputSlot)
end

---------------------------------------------------------------------
-- state-bearing tabs
---------------------------------------------------------------------
local function UpdateStateTab(tab, isSelected)
    tab.isSelected = isSelected
    tab.BFIBackdrop:SetBackdropColor(AF.UnpackColor(
        isSelected and tab._BFIProfessionHoverColor or tab._BFIProfessionColor
    ))
    tab.Text:SetPoint("CENTER", tab, "CENTER", 0, 0)
end

local function StyleStateTab(tab)
    if not tab or tab._BFIProfessionStateTabStyled then return end
    tab._BFIProfessionStateTabStyled = true

    -- Do not use StyleTab here. Profession specialization tabs retain
    -- StateIcon/StateIconGlow, while crafting-order tabs retain their
    -- Glow animation.
    for _, key in ipairs(TAB_ART_TEXTURES) do
        HideTexture(tab[key])
    end

    tab._BFIProfessionColor = AF.GetButtonNormalColor("BFI_hover")
    tab._BFIProfessionHoverColor = AF.GetButtonHoverColor("BFI_hover")
    S.CreateBackdrop(tab)
    UpdateStateTab(tab, tab.isSelected)

    tab:HookScript("OnEnter", function(self)
        if not self.isSelected then
            self.BFIBackdrop:SetBackdropColor(AF.UnpackColor(self._BFIProfessionHoverColor))
        end
    end)
    tab:HookScript("OnLeave", function(self)
        UpdateStateTab(self, self.isSelected)
    end)
    hooksecurefunc(tab, "SetTabSelected", UpdateStateTab)
end

---------------------------------------------------------------------
-- recipe list
---------------------------------------------------------------------
local function StyleRecipeListElement(frame)
    if frame.CollapseIcon then
        if frame._BFIProfessionCategoryStyled then return end
        frame._BFIProfessionCategoryStyled = true

        HideTexture(frame.LeftPiece)
        HideTexture(frame.CenterPiece)
        HideTexture(frame.RightPiece)
        S.CreateBackdrop(frame)
        frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
        S.StyleStatusBar(frame.RankBar)
    elseif frame.SelectedOverlay then
        if frame._BFIProfessionRecipeStyled then return end
        frame._BFIProfessionRecipeStyled = true

        frame.SelectedOverlay:SetColorTexture(AF.GetColorRGB("BFI", 0.3))
        frame.SelectedOverlay:SetAllPoints(frame)
        frame.HighlightOverlay:SetColorTexture(AF.GetColorRGB("white", 0.08))
        frame.HighlightOverlay:SetAllPoints(frame)
    end
end

local function UpdateRecipeList(scrollBox)
    scrollBox:ForEachFrame(StyleRecipeListElement)
end

local function StyleRecipeList(recipeList)
    if not recipeList or recipeList._BFIProfessionStyled then return end
    recipeList._BFIProfessionStyled = true

    StyleInset(recipeList)
    HideTexture(recipeList.Background)
    HideTexture(recipeList.BackgroundNineSlice)
    S.StyleDropdownButton(recipeList.FilterDropdown)
    S.StyleEditBox(recipeList.SearchBox, -4)
    S.StyleScrollBar(recipeList.ScrollBar)

    hooksecurefunc(recipeList.ScrollBox, "Update", UpdateRecipeList)
    UpdateRecipeList(recipeList.ScrollBox)
end

---------------------------------------------------------------------
-- schematic form
---------------------------------------------------------------------
local function StyleCrafterDetails(details)
    if not details or details._BFIProfessionDetailsStyled then return end
    details._BFIProfessionDetailsStyled = true

    HideTexture(details.BackgroundTop)
    HideTexture(details.BackgroundBottom)
    HideTexture(details.BackgroundMiddle)
    HideTexture(details.BackgroundMinimized)

    S.CreateBackdrop(details)
    details.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_dark"))

    if details.Line then
        details.Line:SetColorTexture(AF.GetColorRGB("border"))
        AF.SetHeight(details.Line, 1)
    end
end

local function StyleQualityDialog(dialog)
    if not dialog or dialog._BFIProfessionStyled then return end
    dialog._BFIProfessionStyled = true

    StyleInset(dialog)
    S.StyleCloseButton(dialog.ClosePanelButton)
    StyleButtons(dialog.CancelButton, dialog.AcceptButton)

    for _, container in ipairs({dialog.Container1, dialog.Container2, dialog.Container3}) do
        StyleItemButton(container.Button)
        S.StyleEditBox(container.EditBox)
    end
end

local function StyleSchematicForm(form)
    if not form or not IsInScope(form) then return end

    if not form._BFIProfessionStyled then
        form._BFIProfessionStyled = true

        StyleInset(form)
        HideTexture(form.Background)
        HideTexture(form.MinimalBackground)

        StyleItemButton(form.OutputIcon)
        S.StyleStatusBar(form.RecipeLevelBar)
        S.StyleDropdownButton(form.RecipeLevelDropdown)
        S.StyleCheckButton(form.TrackRecipeCheckbox)
        S.StyleCheckButton(form.AllocateBestQualityCheckbox)
        StyleItemButton(form.Concentrate and form.Concentrate.ConcentrateToggleButton)
        StyleCrafterDetails(form.Details)
        StyleQualityDialog(form.QualityDialog)
        StyleRecraftSlot(form.recraftSlot)
    end

    for _, slot in ipairs(form:GetSlots()) do
        StyleItemButton(slot.Button)
        if slot.Checkbox then
            S.StyleCheckButton(slot.Checkbox)
        end
    end

    if form.salvageSlot then
        StyleItemButton(form.salvageSlot.Button)
    end
    if form.enchantSlot then
        StyleItemButton(form.enchantSlot.Button)
    end
end

---------------------------------------------------------------------
-- rank bar
---------------------------------------------------------------------
local function StyleProfessionExpansionRadio(frame)
    local selectBox = frame.leftTexture1
    if not selectBox then return end

    local layer, subLevel = selectBox:GetDrawLayer()
    local border = frame:AttachTexture()
    border:SetDrawLayer(layer, subLevel - 1)
    border:SetColorTexture(AF.GetColorRGB("border"))
    AF.SetSize(border, 15, 15)
    AF.SetPoint(border, "CENTER", selectBox)

    selectBox:SetColorTexture(AF.GetColorRGB("widget"))
    AF.SetSize(selectBox, 13, 13)

    local selected = frame.leftTexture2
    if selected then
        selected:SetColorTexture(AF.GetColorRGB("BFI", 0.7))
        AF.ClearPoints(selected)
        AF.SetPoint(selected, "CENTER", selectBox)
        AF.SetSize(selected, 7, 7)
    end
end

local function StyleProfessionExpansionMenu(_, rootDescription)
    for _, description in rootDescription:EnumerateElementDescriptions() do
        if description:IsRadio() then
            description:AddInitializer(StyleProfessionExpansionRadio)
        end
    end
end

local function StyleRankBar(rankBar)
    if not rankBar or rankBar._BFIProfessionStyled then return end
    rankBar._BFIProfessionStyled = true

    HideTexture(rankBar.Background)
    HideTexture(rankBar.Border)
    S.CreateBackdrop(rankBar)
    rankBar.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_dark"))

    S.StyleDropdownButton(rankBar.ExpansionDropdownButton)
    HideTexture(rankBar.ExpansionDropdownButton.Texture)
end

---------------------------------------------------------------------
-- crafting output log
---------------------------------------------------------------------
local function StyleOutputLogElement(element)
    if not element or not IsInScope(element) then return end

    if not element._BFIProfessionStyled then
        element._BFIProfessionStyled = true

        local itemContainer = element.ItemContainer
        HideTexture(itemContainer.NameFrame)
        HideTexture(itemContainer.BorderFrame)
        itemContainer.HighlightNameFrame:SetColorTexture(AF.GetColorRGB("white", 0.12))
        itemContainer.PushedNameFrame:SetColorTexture(AF.GetColorRGB("yellow", 0.15))
        S.CreateBackdrop(itemContainer)
        itemContainer.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))

        StyleItemButton(itemContainer.Item)
        StyleItemButton(element.Multicraft.Item)
    end

    for button in element.itemButtonPool:EnumerateActive() do
        StyleItemButton(button)
    end
end

local function UpdateOutputLog(scrollBox)
    scrollBox:ForEachFrame(StyleOutputLogElement)
end

local function StyleOutputLog(log)
    if not log or log._BFIProfessionStyled then return end
    log._BFIProfessionStyled = true

    S.RemoveNineSliceAndBackground(log)
    S.CreateBackdrop(log)
    if log.CloseButton then
        S.StyleCloseButton(log.CloseButton)
    end
    if log.ScrollBar then
        S.StyleScrollBar(log.ScrollBar)
    end

    hooksecurefunc(log.ScrollBox, "Update", UpdateOutputLog)
    UpdateOutputLog(log.ScrollBox)
end

---------------------------------------------------------------------
-- crafting page
---------------------------------------------------------------------
local function StyleSearchResult(button)
    if button._BFIProfessionStyled then return end
    button._BFIProfessionStyled = true

    HideTexture(button.IconFrame)
    StyleStandaloneIcon(button.Icon)
    S.CreateBackdrop(button)
    button.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))

    local normalTexture = button:GetNormalTexture()
    local pushedTexture = button:GetPushedTexture()
    local highlightTexture = button:GetHighlightTexture()
    HideTexture(normalTexture)
    HideTexture(pushedTexture)
    if highlightTexture then
        highlightTexture:SetColorTexture(AF.GetColorRGB("white", 0.1))
        highlightTexture:SetAllPoints(button.BFIBackdrop)
    end
end

local function UpdateSearchResults(scrollBox)
    scrollBox:ForEachFrame(StyleSearchResult)
end

local function StyleGuildCrafterButton(button)
    S.StyleButton(button, "gray_hover")
end

local function UpdateGuildCrafters(scrollBox)
    scrollBox:ForEachFrame(StyleGuildCrafterButton)
end

local function StyleCraftingPage(page)
    StyleRecipeList(page.RecipeList)
    StyleSchematicForm(page.SchematicForm)

    StyleButtons(page.CreateButton, page.CreateAllButton, page.ViewGuildCraftersButton)
    S.StyleEditBox(page.CreateMultipleInputBox)
    S.StyleEditBox(page.MinimizedSearchBox, -4)
    S.StyleDropdownButton(page.LinkButton)
    StyleRankBar(page.RankBar)

    local searchResults = page.MinimizedSearchResults
    StyleInset(searchResults)
    StyleInset(searchResults.Inset)
    HideTexture(searchResults.TopTileStreaks)
    searchResults.PortraitContainer:SetAlpha(0)
    S.StyleCloseButton(searchResults.CloseButton)
    S.StyleScrollBar(searchResults.ScrollBar)
    hooksecurefunc(searchResults.ScrollBox, "Update", UpdateSearchResults)
    UpdateSearchResults(searchResults.ScrollBox)

    for _, slot in ipairs(page.InventorySlots) do
        StyleItemButton(slot)
    end

    if page.GuildFrame and page.GuildFrame.Container then
        StyleInset(page.GuildFrame)
        local guildContainer = page.GuildFrame.Container
        StyleInset(guildContainer)
        S.StyleScrollBar(guildContainer.ScrollBar)
        hooksecurefunc(guildContainer.ScrollBox, "Update", UpdateGuildCrafters)
        UpdateGuildCrafters(guildContainer.ScrollBox)
    end

    StyleOutputLog(page.CraftingOutputLog)
end

---------------------------------------------------------------------
-- specializations page
---------------------------------------------------------------------
local function StyleSpecializationTabs(page)
    for tab in page.tabsPool:EnumerateActive() do
        StyleStateTab(tab)
    end
end

local function StyleSpecializationsPage(page)
    StyleButtons(
        page.ApplyButton,
        page.UnlockTabButton,
        page.ViewTreeButton,
        page.BackToPreviewButton,
        page.ViewPreviewButton,
        page.BackToFullTreeButton,
        page.DetailedView.SpendPointsButton,
        page.DetailedView.UnlockPathButton
    )
    S.StyleIconButton(page.UndoButton, "talents-button-undo", 16)
    S.RemoveTextures(page.PanelFooter, true)

    StyleSpecializationTabs(page)
end

---------------------------------------------------------------------
-- crafting orders page
---------------------------------------------------------------------
local function StyleOrderListElement(button)
    if button._BFIProfessionStyled then return end
    button._BFIProfessionStyled = true

    if button.HighlightTexture then
        button.HighlightTexture:SetColorTexture(AF.GetColorRGB("BFI", 0.18))
    end

    for _, cell in ipairs({button:GetChildren()}) do
        StyleStandaloneIcon(cell.Icon, cell.IconBorder)
        if cell.ReagentsContainer then
            for _, reagentButton in ipairs({cell.ReagentsContainer:GetChildren()}) do
                StyleItemButton(reagentButton)
            end
        end
    end
end

local function UpdateOrderList(scrollBox)
    scrollBox:ForEachFrame(StyleOrderListElement)
end

local function StyleNoteEditBox(noteEditBox)
    if not noteEditBox then return end

    HideTexture(noteEditBox.Border)
    S.StyleInputScrollFrame(noteEditBox.ScrollingEditBox)
end

local function StyleOrderView(view)
    local orderInfo = view.OrderInfo
    StyleInset(orderInfo)
    StyleButtons(
        orderInfo.BackButton,
        orderInfo.StartOrderButton,
        orderInfo.DeclineOrderButton,
        orderInfo.ReleaseOrderButton
    )
    S.StyleDropdownButton(orderInfo.SocialDropdown)

    HideTexture(orderInfo.NoteBox.Background.Border)
    StyleInset(orderInfo.NoteBox)
    HideTexture(orderInfo.NPCRewardsFrame.Background)
    StyleInset(orderInfo.NPCRewardsFrame)
    for _, rewardItem in ipairs(orderInfo.NPCRewardsFrame.RewardItems) do
        StyleItemButton(rewardItem)
    end

    local orderDetails = view.OrderDetails
    StyleInset(orderDetails)
    StyleSchematicForm(orderDetails.SchematicForm)
    StyleItemButton(orderDetails.FulfillmentForm.ItemIcon)
    StyleRecraftSlot(orderDetails.FulfillmentForm.RecraftSlot)
    StyleNoteEditBox(orderDetails.FulfillmentForm.NoteEditBox)

    StyleRankBar(view.RankBar)
    StyleButtons(
        view.CreateButton,
        view.CompleteOrderButton,
        view.StartRecraftButton,
        view.StopRecraftButton
    )

    local declineDialog = view.DeclineOrderDialog
    StyleInset(declineDialog)
    StyleNoteEditBox(declineDialog.NoteEditBox)
    StyleButtons(declineDialog.CancelButton, declineDialog.ConfirmButton)
    StyleOutputLog(view.CraftingOutputLog)
end

local function StyleOrdersPage(page)
    local browse = page.BrowseFrame
    StyleRecipeList(browse.RecipeList)
    S.StyleIconButton(browse.FavoritesSearchButton, "auctionhouse-icon-favorite", 16)
    S.StyleButton(browse.SearchButton)
    S.StyleIconButton(browse.BackButton, AF.GetIcon("ArrowLeft2"), 16)

    for _, tab in ipairs(browse.orderTypeTabs) do
        StyleStateTab(tab)
    end

    local orderList = browse.OrderList
    StyleInset(orderList)
    S.StyleScrollBar(orderList.ScrollBar)
    hooksecurefunc(orderList.ScrollBox, "Update", UpdateOrderList)
    UpdateOrderList(orderList.ScrollBox)

    HideTexture(browse.OrdersRemainingDisplay.Background)
    StyleInset(browse.OrdersRemainingDisplay)
    StyleOrderView(page.OrderView)
end

---------------------------------------------------------------------
-- shells
---------------------------------------------------------------------
local function StyleMaximizeMinimize(frame)
    local maximizeMinimize = frame.MaximizeMinimize
    if not maximizeMinimize then return end

    S.StyleMaximizeButton(maximizeMinimize.MaximizeButton)
    S.StyleMinimizeButton(maximizeMinimize.MinimizeButton)
    maximizeMinimize:ClearAllPoints()
    maximizeMinimize:SetPoint("TOPRIGHT", frame.CloseButton, "TOPLEFT", 1, 0)
    AF.SetSize(maximizeMinimize, 27, 20)
    AF.SetFrameLevel(maximizeMinimize, 1, frame.BFIHeader)
end

local function StyleBlizzard()
    ProfessionsFrame = _G.ProfessionsFrame
    InspectRecipeFrame = _G.InspectRecipeFrame
    if not ProfessionsFrame or not InspectRecipeFrame then return end

    S.StyleTitledFrame(ProfessionsFrame)
    StyleMaximizeMinimize(ProfessionsFrame)
    S.StyleTabSystem(ProfessionsFrame.TabSystem)

    StyleCraftingPage(ProfessionsFrame.CraftingPage)
    StyleSpecializationsPage(ProfessionsFrame.SpecPage)
    StyleOrdersPage(ProfessionsFrame.OrdersPage)

    S.StyleTitledFrame(InspectRecipeFrame)
    StyleSchematicForm(InspectRecipeFrame.SchematicForm)

    hooksecurefunc(ProfessionsRecipeSchematicFormMixin, "Init", StyleSchematicForm)
    hooksecurefunc(ProfessionsSpecFrameMixin, "InitializeTabs", StyleSpecializationTabs)
    hooksecurefunc(ProfessionsCraftingOutputLogElementMixin, "Init", StyleOutputLogElement)
    _G.Menu.ModifyMenu("MENU_PROFESSIONS_RANK_BAR", StyleProfessionExpansionMenu)
end
AF.RegisterAddonLoaded("Blizzard_Professions", StyleBlizzard)
