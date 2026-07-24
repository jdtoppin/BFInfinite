---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- shared control visuals
---------------------------------------------------------------------
local function CreateSquareElement(frame)
    if frame._BFIHousingSquare then return end
    frame._BFIHousingSquare = true

    S.CreateBackdrop(frame, true)

    local background = AF.CreateTexture(frame, nil, "widget", "BACKGROUND", -8)
    frame.BFIHousingBackground = background
    background:SetAllPoints()
end

local function UpdateActionButton(button)
    local color
    if not button:IsEnabled() then
        color = "widget_dark"
    elseif button:IsMouseMotionFocus() then
        color = "widget_highlight"
    else
        color = "widget"
    end

    button.BFIHousingBackground:SetVertexColor(AF.GetColorRGB(color))
end

local function StyleActionButton(button)
    if not button or button._BFIHousingActionStyled then return end
    button._BFIHousingActionStyled = true

    CreateSquareElement(button)
    button:HookScript("OnShow", UpdateActionButton)
    button:HookScript("OnEnter", UpdateActionButton)
    button:HookScript("OnLeave", UpdateActionButton)
    button:HookScript("OnEnable", UpdateActionButton)
    button:HookScript("OnDisable", UpdateActionButton)
    UpdateActionButton(button)
end

---------------------------------------------------------------------
-- side tabs
---------------------------------------------------------------------
local function StyleSideTabs(frame)
    for i, tab in ipairs(frame.TabButtons) do
        S.StyleSideTab(tab)

        -- Both 12.0.7's HousingDashboardSideTabTemplate and 12.1's
        -- LargeSideTabButtonTemplate expose Icon and SetChecked. Calling
        -- SetChecked after styling restores the appropriate identity atlas.
        local checked = frame.activeTab and frame.activeTab.tabButton == tab
        tab:SetChecked(checked)

        AF.ClearPoints(tab)
        if i == 1 then
            AF.SetPoint(tab, "TOPLEFT", frame, "TOPRIGHT", 4, -28)
        else
            AF.SetPoint(tab, "TOPLEFT", frame.TabButtons[i - 1], "BOTTOMLEFT", 0, -1)
        end
    end
end

---------------------------------------------------------------------
-- catalog
---------------------------------------------------------------------
local function UpdateCatalogEntry(frame, isPressed)
    local color
    if not frame:IsEnabled() then
        color = "widget_dark"
    elseif isPressed or frame.isSelected then
        color = "BFI"
    elseif frame:IsMouseMotionFocus() then
        color = "widget_highlight"
    else
        color = "widget"
    end

    local alpha = frame.isSelected and 0.45 or 0.8
    frame.BFIHousingBackground:SetVertexColor(AF.GetColorRGB(color, alpha))
    frame.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB(frame.isSelected and "BFI" or "border"))
end

local function StyleCatalogEntry(frame)
    if frame._BFIHousingCatalogStyled then return end
    frame._BFIHousingCatalogStyled = true

    CreateSquareElement(frame)

    -- Keep the decor icon/model, special-room markers, quantities, and dye
    -- state. Only the ornamental card chrome is replaced.
    frame.Background:SetAlpha(0)
    frame.HoverBackground:SetAlpha(0)

    hooksecurefunc(frame, "UpdateVisuals", UpdateCatalogEntry)
    hooksecurefunc(frame, "UpdateBackground", UpdateCatalogEntry)
    frame:HookScript("OnEnter", function(self)
        UpdateCatalogEntry(self)
    end)
    frame:HookScript("OnLeave", function(self)
        UpdateCatalogEntry(self)
    end)
    frame:HookScript("OnEnable", UpdateCatalogEntry)
    frame:HookScript("OnDisable", UpdateCatalogEntry)
    UpdateCatalogEntry(frame)
end

local function StyleVisibleCatalogEntries(scrollBox)
    scrollBox:ForEachFrame(StyleCatalogEntry)
end

local function UpdateCatalogCategory(frame)
    local color
    if not frame:IsEnabled() then
        color = "widget_dark"
    elseif frame.isActive then
        color = "BFI"
    elseif frame:IsMouseMotionFocus() then
        color = "widget_highlight"
    else
        color = "widget"
    end

    local alpha = frame.isActive and 0.45 or 0.8
    frame.BFIHousingBackground:SetVertexColor(AF.GetColorRGB(color, alpha))
    frame.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB(frame.isActive and "BFI" or "border"))
end

local function StyleCatalogCategory(frame)
    if frame._BFIHousingCategoryStyled then return end
    frame._BFIHousingCategoryStyled = true

    CreateSquareElement(frame)
    frame:HookScript("OnEnter", UpdateCatalogCategory)
    frame:HookScript("OnLeave", UpdateCatalogCategory)
    frame:HookScript("OnEnable", UpdateCatalogCategory)
    frame:HookScript("OnDisable", UpdateCatalogCategory)
    if frame.UpdateVisuals then
        hooksecurefunc(frame, "UpdateVisuals", UpdateCatalogCategory)
    end
    UpdateCatalogCategory(frame)
end

local function StyleCatalogCategories(categories)
    StyleActionButton(categories.BackButton)
    StyleCatalogCategory(categories.AllSubcategoriesStandIn)

    for frame in categories.categoryPool:EnumerateActive() do
        StyleCatalogCategory(frame)
    end
    for frame in categories.subcategoryPool:EnumerateActive() do
        StyleCatalogCategory(frame)
    end
end

local function StyleCatalog(catalog)
    S.StyleDropdownButton(catalog.Filters.FilterDropdown)
    catalog.Filters.FilterDropdown.displacedRegions = nil
    S.StyleEditBox(catalog.SearchBox, -4)

    local categories = catalog.Categories
    StyleCatalogCategories(categories)
    hooksecurefunc(categories, "DisplayTopLevelCategories", StyleCatalogCategories)
    hooksecurefunc(categories, "DisplaySubcategoriesUnderCategory", StyleCatalogCategories)

    local options = catalog.OptionsContainer
    S.StyleScrollBar(options.ScrollBar)
    hooksecurefunc(options.ScrollBox, "Update", StyleVisibleCatalogEntries)
    StyleVisibleCatalogEntries(options.ScrollBox)

    local preview = catalog.PreviewFrame
    S.StyleIconButton(preview.VariantLeftButton, AF.GetIcon("ArrowLeft2"), 16)
    S.StyleIconButton(preview.VariantRightButton, AF.GetIcon("ArrowRight2"), 16)
    AF.SetSize(preview.VariantLeftButton, 27, 27)
    AF.SetSize(preview.VariantRightButton, 27, 27)
end

---------------------------------------------------------------------
-- house info
---------------------------------------------------------------------
local function StyleHouseInfoTabs(content)
    if not content.tabsInitialized or content._BFIHousingTabsStyled then return end
    content._BFIHousingTabsStyled = true
    S.StyleTabSystem(content.TabSystem, true)
end

local function StyleInitiatives(initiatives)
    local initiativeSet = initiatives.InitiativeSetFrame
    local tasks = initiativeSet.InitiativeTasks
    local activity = initiativeSet.InitiativeActivity

    S.StyleScrollBar(tasks.ScrollBar)
    S.StyleScrollBar(activity.ScrollBar)

    local switcher = initiativeSet.InitiativeActiveNeighborhoodSwitcher
    S.StyleButton(switcher.SwitchActiveNeighborhoodBtn)
end

local function StyleHouseInfo(houseInfo)
    if houseInfo.HouseDropdown then
        S.StyleDropdownButton(houseInfo.HouseDropdown)
    end

    S.StyleButton(houseInfo.HouseFinderButton)
    S.StyleButton(houseInfo.DashboardNoHousesFrame.NoHouseButton)

    local content = houseInfo.ContentFrame
    hooksecurefunc(content, "Initialize", StyleHouseInfoTabs)
    StyleHouseInfoTabs(content)
    StyleInitiatives(content.InitiativesFrame)

    local upgrade = content.HouseUpgradeFrame
    if upgrade.WatchFavorButton then
        S.StyleCheckButton(upgrade.WatchFavorButton)
    end
end

---------------------------------------------------------------------
-- 12.1 house dropdown and blueprint collection
---------------------------------------------------------------------
local function UpdateBlueprintEntry(frame)
    local selected = frame:IsSelected()
    local hovered = frame:IsHovered()
    local color = selected and "BFI" or (hovered and "widget_highlight" or "widget")
    local alpha = selected and 0.45 or (hovered and 0.8 or 0.55)

    frame.BFIHousingBackground:SetVertexColor(AF.GetColorRGB(color, alpha))
    frame.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB(selected and "BFI" or "border"))
end

local function StyleBlueprintEntry(frame)
    if frame._BFIHousingBlueprintStyled then return end
    frame._BFIHousingBlueprintStyled = true

    CreateSquareElement(frame)
    frame.HighlightBackground:SetAlpha(0)
    hooksecurefunc(frame, "UpdateStateVisuals", UpdateBlueprintEntry)
    UpdateBlueprintEntry(frame)
end

local function StyleBlueprintGroup(frame)
    if frame._BFIHousingBlueprintGroupStyled then return end
    frame._BFIHousingBlueprintGroupStyled = true

    S.RemoveRegions(frame.Header)
    StyleActionButton(frame.Header)
end

local function StyleVisibleBlueprintRows(scrollBox)
    scrollBox:ForEachFrame(function(frame)
        if frame.Header then
            StyleBlueprintGroup(frame)
        elseif frame.HighlightBackground then
            StyleBlueprintEntry(frame)
        end
    end)
end

local function StyleCollection(collection)
    local categories = collection.Categories
    if categories and categories.CategoryPlaceholder then
        StyleCatalogCategory(categories.CategoryPlaceholder)
    end

    local blueprints = collection.BlueprintCollection
    S.StyleScrollBar(blueprints.ScrollBar)
    StyleActionButton(blueprints.ResetButton)
    hooksecurefunc(blueprints.ScrollBox, "Update", StyleVisibleBlueprintRows)
    StyleVisibleBlueprintRows(blueprints.ScrollBox)

    local details = collection.BlueprintDetails
    S.StyleIconButton(details.GearDropdown, AF.GetIcon("Menu3"), 14)
    AF.SetSize(details.GearDropdown, 22, 22)

    local contentSummary = details.ContentSummary
    if contentSummary.ContentsListButton then
        S.StyleButton(contentSummary.ContentsListButton)
    end

    local entryMixin = _G.HousingBlueprintCollectionEntryMixin
    if entryMixin then
        hooksecurefunc(entryMixin, "Init", StyleBlueprintEntry)
    end

    local groupMixin = _G.HousingBlueprintCollectionGroupMixin
    if groupMixin then
        hooksecurefunc(groupMixin, "Init", StyleBlueprintGroup)
    end
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    local frame = _G.HousingDashboardFrame
    S.StyleTitledFrame(frame)
    StyleSideTabs(frame)

    -- Retail 12.0.7.68887 owns HouseDropdown directly under HouseInfoContent.
    -- PTR 12.1.0.68914 moves it to a wrapper on HousingDashboardFrame.
    if frame.HouseDropdown and frame.HouseDropdown.Dropdown then
        S.StyleDropdownButton(frame.HouseDropdown.Dropdown)
    end

    StyleHouseInfo(frame.HouseInfoContent)
    StyleCatalog(frame.CatalogContent)

    if frame.CollectionContent then
        StyleCollection(frame.CollectionContent)
    end
end

-- Frame contracts verified against Gethe wow-ui-source:
-- Retail 12.0.7.68887, commit 4383ced30106d51b27e3e86d1987f1552f0d259d
-- PTR 12.1.0.68914, commit d3915c78aba77a7a9be76acbfa35c674bbb6abe9
-- (Blizzard_HousingDashboard*.xml/.lua and its pinned housing dependencies).
AF.RegisterAddonLoaded("Blizzard_HousingDashboard", StyleBlizzard)
