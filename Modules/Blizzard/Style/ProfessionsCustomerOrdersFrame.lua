---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local CustomerOrdersFrame
local hooksRegistered

-- Frame ownership and fields were verified against Gethe wow-ui-source live
-- commit 4383ced30106d51b27e3e86d1987f1552f0d259d (12.0.7.68887) and PTR
-- commit d3915c78aba77a7a9be76acbfa35c674bbb6abe9 (12.1.0.68914). The scoped
-- XML hierarchy is identical; the only scoped PTR Lua delta is the legacy
-- friend-system guard around the form's Add Friend menu entry.

local PROFESSION_ICON_QUALITY = {
    ["Professions-Slot-Frame"] = Enum.ItemQuality.Common,
    ["Professions-Slot-Frame-Green"] = Enum.ItemQuality.Uncommon,
    ["Professions-Slot-Frame-Blue"] = Enum.ItemQuality.Rare,
    ["Professions-Slot-Frame-Epic"] = Enum.ItemQuality.Epic,
    ["Professions-Slot-Frame-Legendary"] = Enum.ItemQuality.Legendary,
}

local function HideTexture(texture)
    if texture then
        texture:SetAlpha(0)
    end
end

local function IsInCustomerOrders(frame)
    while frame do
        if frame == CustomerOrdersFrame then
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

local function StylePanel(frame, color)
    if not frame or frame._BFICustomerOrdersPanelStyled then return end
    frame._BFICustomerOrdersPanelStyled = true

    S.RemoveNineSliceAndBackground(frame)
    HideTexture(frame.BackgroundNineSlice)
    HideTexture(frame.TopTileStreaks)
    S.CreateBackdrop(frame)
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB(color or "widget_dark"))
end

---------------------------------------------------------------------
-- icons
---------------------------------------------------------------------
local function StyleStandaloneIcon(icon, border, mask)
    if not icon then return end

    if not icon._BFICustomerOrdersStyled then
        icon._BFICustomerOrdersStyled = true
        S.StyleSquareIcon(icon, mask, true)
    end
    if border then
        S.StyleIconBorder(border, icon.BFIBackdrop)
    end
end

local function RefreshItemButtonTextures(button)
    local icon = button.Icon or button.icon or button.IconTexture
    if not icon or not icon.BFIBackdrop then return end

    local normalTexture = button.GetNormalTexture and button:GetNormalTexture()
    if normalTexture and normalTexture ~= icon then
        HideTexture(normalTexture)
    end

    local disabledTexture = button.GetDisabledTexture and button:GetDisabledTexture()
    if disabledTexture and disabledTexture ~= icon then
        HideTexture(disabledTexture)
    end

    local highlightTexture = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlightTexture then
        highlightTexture:SetAlpha(1)
        AF.SetOnePixelInside(highlightTexture, icon.BFIBackdrop)
        highlightTexture:SetColorTexture(AF.GetColorRGB("white", 0.2))
    end

    local pushedTexture = button.GetPushedTexture and button:GetPushedTexture()
    if pushedTexture then
        pushedTexture:SetAlpha(1)
        AF.SetOnePixelInside(pushedTexture, icon.BFIBackdrop)
        pushedTexture:SetColorTexture(AF.GetColorRGB("yellow", 0.2))
    end

    local checkedTexture = button.GetCheckedTexture and button:GetCheckedTexture()
    if checkedTexture then
        checkedTexture:SetAlpha(1)
        AF.SetOnePixelInside(checkedTexture, icon.BFIBackdrop)
        checkedTexture:SetColorTexture(AF.GetColorRGB("BFI", 0.25))
    end
end

local function RefreshRecraftInputSlot(button, item)
    HideTexture(button.BorderTexture)
    RefreshItemButtonTextures(button)

    if not button.BFIEmptyRecraftIcon then
        button.BFIEmptyRecraftIcon = button:CreateTexture(nil, "ARTWORK", nil, 1)
        button.BFIEmptyRecraftIcon:SetTexture(AF.GetIcon("Plus"))
        button.BFIEmptyRecraftIcon:SetVertexColor(AF.GetColorRGB("yellow_text"))
        AF.SetPoint(button.BFIEmptyRecraftIcon, "CENTER")
        AF.SetSize(button.BFIEmptyRecraftIcon, 16, 16)
        AF.AddToPixelUpdater_CustomGroup("BFIStyled", button.BFIEmptyRecraftIcon)
    end
    button.BFIEmptyRecraftIcon:SetShown(not item)
end

local function StyleItemButton(button)
    if not button or button._BFICustomerOrdersItemStyled then return end

    local icon = button.Icon or button.icon or button.IconTexture
    if not icon then return end
    button._BFICustomerOrdersItemStyled = true

    StyleStandaloneIcon(icon, button.IconBorder or button.Border, button.CircleMask or button.IconMask)

    HideTexture(button.SlotBackground)
    HideTexture(button.CropFrame)
    HideTexture(button.ItemFrame)
    HideTexture(button.EmptyBackground)
    RefreshItemButtonTextures(button)
end

local function StyleReagentSlot(slot)
    if not slot then return end

    StyleItemButton(slot.Button)
    if slot.Checkbox then
        S.StyleCheckButton(slot.Checkbox)
    end
end

local function StyleRecraftSlot(slot)
    if not slot then return end

    HideTexture(slot.Background)
    StyleItemButton(slot.InputSlot)
    RefreshRecraftInputSlot(slot.InputSlot)
    StyleItemButton(slot.OutputSlot)
end

---------------------------------------------------------------------
-- table headers and rows
---------------------------------------------------------------------
local function StyleTableHeader(header)
    if not header or header._BFICustomerOrdersStyled then return end
    header._BFICustomerOrdersStyled = true

    HideTexture(header.Left)
    HideTexture(header.Middle)
    HideTexture(header.Right)
    S.CreateBackdrop(header)
    header.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))

    local highlight = header.GetHighlightTexture and header:GetHighlightTexture()
    if highlight then
        highlight:SetColorTexture(AF.GetColorRGB("white", 0.1))
        AF.SetOnePixelInside(highlight, header.BFIBackdrop)
    end
end

local function StyleTableHeaders(tableBuilder, container)
    if tableBuilder then
        for header in tableBuilder:EnumerateHeaders() do
            StyleTableHeader(header)
        end
    elseif container then
        for _, header in next, {container:GetChildren()} do
            StyleTableHeader(header)
        end
    end
end

local function UpdateItemCellQuality(row, cell)
    local option = row.option
    local itemID = option and option.itemID
    if not itemID or not cell.Icon or not cell.Icon.BFIBackdrop then return end
    local rowData = cell.rowData
    if not rowData or rowData.option ~= option then return end
    if cell._BFICustomerOrdersQualityRowData == rowData then return end

    cell._BFICustomerOrdersQualityRowData = rowData
    cell.Icon.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))

    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        if row.option ~= option or cell.rowData ~= rowData or rowData.option ~= option then return end

        local quality = item:GetItemQuality()
        if quality then
            cell.Icon.BFIBackdrop:SetBackdropBorderColor(AF.GetItemQualityColor(quality))
        end
    end)
end

local function StyleTableRow(row)
    if not row then return end

    if not row._BFICustomerOrdersStyled then
        row._BFICustomerOrdersStyled = true
        if row.HighlightTexture then
            row.HighlightTexture:SetColorTexture(AF.GetColorRGB("white", 0.1))
            row.HighlightTexture:SetAllPoints(row)
        end
    end

    if not row.cells then return end
    for _, cell in ipairs(row.cells) do
        if cell.Icon then
            StyleStandaloneIcon(cell.Icon, cell.IconBorder)
            UpdateItemCellQuality(row, cell)
        end
    end
end

local function UpdateTableRows(scrollBox)
    scrollBox:ForEachFrame(StyleTableRow)
end

local function WatchTableRows(scrollBox)
    if not scrollBox or scrollBox._BFICustomerOrdersRowsWatched then return end
    scrollBox._BFICustomerOrdersRowsWatched = true

    hooksecurefunc(scrollBox, "Update", UpdateTableRows)
    UpdateTableRows(scrollBox)
end

---------------------------------------------------------------------
-- shared, globally pooled reagent icons
---------------------------------------------------------------------
local function SetTransientReagentStyle(button, styled)
    local icon = button.Icon or button.icon
    if not icon then return end

    if styled then
        if not button._BFICustomerOrdersTransientStyled then
            button._BFICustomerOrdersTransientStyled = true
            S.CreateBackdrop(icon, true, nil, 1)
        end

        icon:SetTexCoord(AF.GetDefaultTexCoord())
        icon.BFIBackdrop:Show()
        HideTexture(button.SlotBackground)

        local border = button.IconBorder or button.Border
        if border then
            border:SetAlpha(0)
            local quality = PROFESSION_ICON_QUALITY[border:GetAtlas()]
            if quality then
                icon.BFIBackdrop:SetBackdropBorderColor(AF.GetItemQualityColor(quality))
            else
                local r, g, b, a = border:GetVertexColor()
                if r == 1 and g == 1 and b == 1 then
                    r, g, b = AF.GetColorRGB("border")
                end
                icon.BFIBackdrop:SetBackdropBorderColor(r, g, b, a)
            end
        end
    elseif button._BFICustomerOrdersTransientStyled then
        icon:SetTexCoord(0, 1, 0, 1)
        icon.BFIBackdrop:Hide()
        if button.SlotBackground then
            button.SlotBackground:SetAlpha(1)
        end
        local border = button.IconBorder or button.Border
        if border then
            border:SetAlpha(1)
        end
    end
end

local function StyleHoveredReagentCell(cell)
    local styled = IsInCustomerOrders(cell)
    for _, button in next, {cell.ReagentsContainer:GetChildren()} do
        SetTransientReagentStyle(button, styled)
    end
end

---------------------------------------------------------------------
-- category navigation
---------------------------------------------------------------------
local function StyleCategoryButton(button)
    if not button._BFICustomerOrdersBackdropCreated then
        button._BFICustomerOrdersBackdropCreated = true
        S.CreateBackdrop(button)
        button.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
    end

    button.BFIBackdrop:SetShown(not button.isSpacer)
    HideTexture(button.NormalTexture)

    button.HighlightTexture:SetTexture(AF.GetPlainTexture())
    button.HighlightTexture:SetVertexColor(AF.GetColorRGB("white", 0.1))
    AF.SetOnePixelInside(button.HighlightTexture, button.BFIBackdrop)

    button.SelectedTexture:SetTexture(AF.GetPlainTexture())
    button.SelectedTexture:SetVertexColor(AF.GetColorRGB("BFI", 0.25))
    AF.SetOnePixelInside(button.SelectedTexture, button.BFIBackdrop)

    button.Lines:SetVertexColor(AF.GetColorRGB("darkgray"))
    button.SpacerLine:SetColorTexture(AF.GetColorRGB("border"))
    AF.SetHeight(button.SpacerLine, 1)
end

local function UpdateCategoryButtons(scrollBox)
    scrollBox:ForEachFrame(StyleCategoryButton)
end

local function StyleCategoryList(list)
    StylePanel(list)
    S.StyleScrollBar(list.ScrollBar)
    hooksecurefunc(list.ScrollBox, "Update", UpdateCategoryButtons)
    UpdateCategoryButtons(list.ScrollBox)
end

---------------------------------------------------------------------
-- browse and order lists
---------------------------------------------------------------------
local function StyleSemanticIconButton(button)
    if not button or button._BFICustomerOrdersSemanticStyled then return end
    button._BFICustomerOrdersSemanticStyled = true

    button:SetNormalTexture(AF.GetEmptyTexture())
    button:SetPushedTexture(AF.GetEmptyTexture())
    button:SetDisabledTexture(AF.GetEmptyTexture())

    local highlight = button:GetHighlightTexture()
    highlight:SetColorTexture(AF.GetColorRGB("white", 0.15))
    AF.SetOnePixelInside(highlight, button)

    S.CreateBackdrop(button)
    button.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))

    button:HookScript("OnEnter", function(self)
        if self:IsEnabled() then
            self.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_highlight"))
        end
    end)
    button:HookScript("OnLeave", function(self)
        self.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
    end)
end

local function StyleRecipeList(list)
    StylePanel(list)
    S.StyleScrollBar(list.ScrollBar)
    StyleTableHeaders(nil, list.HeaderContainer)
    WatchTableRows(list.ScrollBox)
end

local function StyleBrowsePage(page)
    local searchBar = page.SearchBar
    StyleSemanticIconButton(searchBar.FavoritesSearchButton)
    S.StyleEditBox(searchBar.SearchBox, -4)
    S.StyleButton(searchBar.SearchButton)
    S.StyleDropdownButton(searchBar.FilterDropdown)

    StyleCategoryList(page.CategoryList)
    StyleRecipeList(page.RecipeList)
    StyleTableHeaders(page.tableBuilder, page.RecipeList.HeaderContainer)
end

local function StyleRefreshButton(button)
    button:SetSize(24, 24)
    S.StyleIconButton(button, nil, 16, "yellow_text", "widget")
    button.BFIIcon:SetTexture(AF.GetIcon("Refresh_Round"), nil, nil, "TRILINEAR")
end

local function StyleOrderList(list, tableBuilder)
    StylePanel(list)
    S.StyleScrollBar(list.ScrollBar)
    StyleTableHeaders(tableBuilder, list.HeaderContainer)
    WatchTableRows(list.ScrollBox)
end

local function StyleMyOrdersPage(page)
    StyleRefreshButton(page.RefreshButton)
    StyleOrderList(page.OrderList, page.tableBuilder)
end

---------------------------------------------------------------------
-- order form
---------------------------------------------------------------------
local function StyleQualityDialog(dialog)
    if not dialog or dialog._BFICustomerOrdersStyled then return end
    dialog._BFICustomerOrdersStyled = true

    dialog:DisableDrawLayer("BACKGROUND")
    StylePanel(dialog, "background")
    S.StyleCloseButton(dialog.ClosePanelButton)
    StyleButtons(dialog.CancelButton, dialog.AcceptButton)

    for _, container in ipairs({dialog.Container1, dialog.Container2, dialog.Container3}) do
        StyleItemButton(container.Button)
        S.StyleEditBox(container.EditBox)
        S.StyleIconButton(container.EditBox.DecrementButton, AF.GetIcon("ArrowLeft2"), 12, nil, "widget")
        S.StyleIconButton(container.EditBox.IncrementButton, AF.GetIcon("ArrowRight2"), 12, nil, "widget")
    end
end

local function StyleNoteEditBox(note)
    if not note or note._BFICustomerOrdersStyled then return end
    note._BFICustomerOrdersStyled = true

    HideTexture(note.Border)
    S.CreateBackdrop(note)
    note.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
    S.StyleInputScrollFrame(note.ScrollingEditBox)
end

local function StyleMoneyInputBox(box)
    if not box or box._BFICustomerOrdersStyled then return end
    box._BFICustomerOrdersStyled = true

    HideTexture(box.Left)
    HideTexture(box.Middle)
    HideTexture(box.Right)
    S.CreateBackdrop(box)
    box.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
end

local function StyleViewListingsButton(button)
    S.StyleIconButton(button, "UI-CraftingOrderIcon-Up", 16, "yellow_text", "widget")
    hooksecurefunc(button, "SetHighlightAtlas", function(self)
        self:GetHighlightTexture():SetTexture(AF.GetEmptyTexture())
    end)
end

local function StyleCurrentListings(listings)
    if not listings or listings._BFICustomerOrdersStyled then return end
    listings._BFICustomerOrdersStyled = true

    StylePanel(listings, "background")
    if listings.TitleContainer then
        S.CreateBackdrop(listings.TitleContainer)
        listings.TitleContainer.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("header"))
        listings.TitleContainer.TitleText:ClearAllPoints()
        listings.TitleContainer.TitleText:SetPoint("CENTER", listings.TitleContainer)
    end

    S.StyleButton(listings.CloseButton)
    StyleOrderList(listings.OrderList, listings.tableBuilder)
end

local function StyleFormReagentSlots(form)
    for slot in form.reagentSlotPool:EnumerateActive() do
        StyleReagentSlot(slot)
    end
end

local function StyleOrderForm(form)
    StylePanel(form.LeftPanelBackground, "background")
    StylePanel(form.RightPanelBackground, "background")

    HideTexture(form.RecipeHeader)
    S.CreateBackdrop(form.RecipeHeader)
    form.RecipeHeader.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))

    S.StyleButton(form.BackButton)
    StyleItemButton(form.OutputIcon)
    StyleRecraftSlot(form.RecraftSlot)

    S.StyleDropdownButton(form.MinimumQuality.Dropdown)
    S.StyleDropdownButton(form.OrderRecipientDropdown)
    S.StyleEditBox(form.OrderRecipientTarget)
    S.StyleDropdownButton(form.OrderRecipientDisplay.SocialDropdown)

    StyleFormReagentSlots(form)

    local payment = form.PaymentContainer
    StyleNoteEditBox(payment.NoteEditBox)
    StyleMoneyInputBox(payment.TipMoneyInputFrame.GoldBox)
    StyleMoneyInputBox(payment.TipMoneyInputFrame.SilverBox)
    StyleMoneyInputBox(payment.TipMoneyInputFrame.CopperBox)
    StyleViewListingsButton(payment.ViewListingsButton)
    S.StyleDropdownButton(payment.DurationDropdown)
    StyleButtons(payment.ListOrderButton, payment.CancelOrderButton)

    S.StyleCheckButton(form.TrackRecipeCheckbox.Checkbox)
    S.StyleCheckButton(form.AllocateBestQualityCheckbox)
    StyleQualityDialog(form.QualityDialog)
    StyleCurrentListings(form.CurrentListings)
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function RegisterHooks()
    if hooksRegistered then return end
    hooksRegistered = true

    hooksecurefunc(ProfessionsCustomerOrdersCategoryButtonMixin, "Init", StyleCategoryButton)
    hooksecurefunc(ProfessionsCustomerOrdersRecipeListElementMixin, "Init", StyleTableRow)
    hooksecurefunc(ProfessionsCustomerOrderListElementMixin, "Init", StyleTableRow)
    hooksecurefunc(ProfessionsCustomerListingsElementMixin, "Init", StyleTableRow)
    hooksecurefunc(ProfessionsCustomerOrdersBrowsePageMixin, "SetupTable", function(page)
        StyleTableHeaders(page.tableBuilder, page.RecipeList.HeaderContainer)
        UpdateTableRows(page.RecipeList.ScrollBox)
    end)
    hooksecurefunc(ProfessionsCustomerOrderFormMixin, "UpdateReagentSlots", StyleFormReagentSlots)
    hooksecurefunc(ProfessionsRecraftInputSlotMixin, "Init", function(button, item)
        if not IsInCustomerOrders(button) then return end
        RefreshRecraftInputSlot(button, item)
    end)
    hooksecurefunc(ProfessionsCrafterTableCellReagentsMixin, "OnEnter", StyleHoveredReagentCell)
end

local function StyleBlizzard()
    CustomerOrdersFrame = _G.ProfessionsCustomerOrdersFrame
    if not CustomerOrdersFrame then return end

    RegisterHooks()
    S.StyleTitledFrame(CustomerOrdersFrame)

    CustomerOrdersFrame.MoneyFrameInset:SetAlpha(0)
    S.RemoveTextures(CustomerOrdersFrame.MoneyFrameBorder)
    S.CreateBackdrop(CustomerOrdersFrame.MoneyFrameBorder)
    CustomerOrdersFrame.MoneyFrameBorder.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))

    S.StyleTab(CustomerOrdersFrame.BrowseTab)
    S.StyleTab(CustomerOrdersFrame.OrdersTab)
    AF.ClearPoints(CustomerOrdersFrame.BrowseTab)
    AF.SetPoint(CustomerOrdersFrame.BrowseTab, "TOPLEFT", CustomerOrdersFrame, "BOTTOMLEFT", 0, -1)
    AF.ClearPoints(CustomerOrdersFrame.OrdersTab)
    AF.SetPoint(
        CustomerOrdersFrame.OrdersTab,
        "TOPLEFT",
        CustomerOrdersFrame.BrowseTab,
        "TOPRIGHT",
        1,
        0
    )

    StyleBrowsePage(CustomerOrdersFrame.BrowseOrders)
    StyleMyOrdersPage(CustomerOrdersFrame.MyOrdersPage)
    StyleOrderForm(CustomerOrdersFrame.Form)
end
AF.RegisterAddonLoaded("Blizzard_ProfessionsCustomerOrders", StyleBlizzard)
