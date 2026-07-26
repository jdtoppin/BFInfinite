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

    -- State updates use SetVertexColor, so the source must remain white.
    -- Starting with the dark widget color multiplies every later hover/class
    -- color and makes those states appear almost black.
    local background = AF.CreateTexture(frame, nil, "white", "BACKGROUND", -8)
    frame.BFIHousingBackground = background
    background:SetAllPoints()
end

-- Mirror the Profession Book rows: a narrow class-colour accent at the
-- leading edge, followed by a quiet gray surface that fades into the panel.
-- A second class-colour gradient supplies hover and selected state without
-- bringing back Blizzard's heavy orange card borders.
local function CreateFadeSurface(frame)
    if frame._BFIHousingFadeSurface then return end
    frame._BFIHousingFadeSurface = true

    S.CreateBackdrop(frame, true)
    if frame.BFIHousingBackground then
        frame.BFIHousingBackground:SetAlpha(0)
    end

    local background = AF.CreateGradientTexture(
        frame,
        "HORIZONTAL",
        AF.GetColorTable("background_lighter", 0.5),
        AF.GetColorTable("background_lighter", 0),
        nil,
        "BACKGROUND",
        -8
    )
    background:SetAllPoints()
    frame.BFIHousingFadeBackground = background

    local state = AF.CreateGradientTexture(
        frame,
        "HORIZONTAL",
        AF.GetColorTable("BFI", 0.45),
        AF.GetColorTable("BFI", 0),
        nil,
        "OVERLAY",
        -8
    )
    state:SetAllPoints()
    state:SetBlendMode("ADD")
    frame.BFIHousingFadeState = state

    local accent = AF.CreateTexture(frame, nil, "BFI", "BORDER", -8)
    AF.SetPoint(accent, "TOPLEFT", 1, -1)
    AF.SetPoint(accent, "BOTTOMLEFT", 1, 1)
    AF.SetWidth(accent, 2)
    frame.BFIHousingFadeAccent = accent
end

local function SetFadeSurfaceState(frame, state)
    local strength = 0
    if state == "pressed" then
        strength = 1
    elseif state == "selected" then
        strength = 0.9
    elseif state == "hovered" then
        strength = 0.55
    end

    frame.BFIHousingFadeBackground:SetAlpha(state == "disabled" and 0.3 or 1)
    frame.BFIHousingFadeState:SetAlpha(strength)
    frame.BFIHousingFadeAccent:SetAlpha(strength)
    frame.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB(state == "disabled" and "disabled" or "border"))
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
local function UpdateSideTab(tab, checked)
    tab.Icon:SetTexture(AF.GetIcon(tab._BFIHousingIcon))
    tab.Icon:ResetTexCoord()
    tab.Icon:SetVertexColor(AF.GetColorRGB(checked and "white" or "darkgray"))
    AF.ClearPoints(tab.Icon)
    AF.SetPoint(tab.Icon, "CENTER")
    AF.SetSize(tab.Icon, 24, 24)
end

local function StyleSideTab(tab, icon)
    S.StyleSideTab(tab)

    if not tab._BFIHousingSideTabStyled then
        tab._BFIHousingSideTabStyled = true
        tab._BFIHousingIcon = icon
        hooksecurefunc(tab, "SetChecked", UpdateSideTab)
        tab:HookScript("OnMouseUp", function(self)
            AF.ClearPoints(self.Icon)
            AF.SetPoint(self.Icon, "CENTER")
        end)
    end
end

local function StyleSideTabs(frame)
    for i, tab in ipairs(frame.TabButtons) do
        local icon = "Home"
        if tab == frame.CatalogTabButton then
            icon = "Layout"
        elseif frame.CollectionTabButton and tab == frame.CollectionTabButton then
            icon = "Layers"
        end
        StyleSideTab(tab, icon)

        -- Both 12.0.7's HousingDashboardSideTabTemplate and 12.1's
        -- LargeSideTabButtonTemplate expose Icon and SetChecked. The live
        -- active/inactive atlases contain the entire circular button, so
        -- UpdateSideTab replaces those with icon-only AF glyphs.
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
local function StyleCatalogFilterRadio(frame)
    S.StyleMenuSelection(frame)
end

local function StyleCatalogFilterMenuDescriptions(parentDescription)
    for _, description in parentDescription:EnumerateElementDescriptions() do
        if description:IsRadio() then
            description:AddInitializer(StyleCatalogFilterRadio)
        end
        StyleCatalogFilterMenuDescriptions(description)
    end
end

local function StyleCatalogFilterMenu(dropdown)
    local rootDescription = dropdown:GetMenuDescription()
    if not rootDescription then return end

    StyleCatalogFilterMenuDescriptions(rootDescription)
end

local function IsCatalogEntryPreviewed(frame)
    local catalog = frame._BFIHousingCatalog
    local entryVariantID = frame.entryVariantID
    if not catalog or not entryVariantID then return false end

    return catalog._BFIPreviewedRecordID ~= nil
        and entryVariantID.recordID == catalog._BFIPreviewedRecordID
        and entryVariantID.entryType == catalog._BFIPreviewedEntryType
end

local function UpdateCatalogEntry(frame, isPressed)
    local state = "normal"
    if not frame:IsEnabled() then
        state = "disabled"
    elseif isPressed then
        state = "pressed"
    elseif frame.isSelected or IsCatalogEntryPreviewed(frame) then
        state = "selected"
    elseif frame._BFIHousingHovered or frame:IsMouseMotionFocus() then
        state = "hovered"
    end

    SetFadeSurfaceState(frame, state)
end

local function StyleCatalogEntry(frame)
    if not frame.Background
        or not frame.HoverBackground
        or not frame.UpdateVisuals
        or not frame.UpdateBackground
    then
        return
    end

    if not frame._BFIHousingCatalogStyled then
        frame._BFIHousingCatalogStyled = true

        CreateFadeSurface(frame)

        -- Keep the decor icon/model, quantities, and dye state. Only the
        -- ornamental card chrome is replaced.
        frame.Background:SetAlpha(0)
        frame.HoverBackground:SetAlpha(0)
        if frame.SpecialRoomFrame then
            frame.SpecialRoomFrame:SetAlpha(0)
        end

        hooksecurefunc(frame, "UpdateVisuals", UpdateCatalogEntry)
        hooksecurefunc(frame, "UpdateBackground", UpdateCatalogEntry)
        frame:HookScript("OnEnter", function(self)
            self._BFIHousingHovered = true
            UpdateCatalogEntry(self)
        end)
        frame:HookScript("OnLeave", function(self)
            self._BFIHousingHovered = nil
            UpdateCatalogEntry(self)
        end)
        frame:HookScript("OnHide", function(self)
            self._BFIHousingHovered = nil
        end)
        frame:HookScript("OnEnable", UpdateCatalogEntry)
        frame:HookScript("OnDisable", UpdateCatalogEntry)
    end

    UpdateCatalogEntry(frame)
end

local function StyleVisibleCatalogEntries(scrollBox)
    scrollBox:ForEachFrame(function(frame)
        frame._BFIHousingCatalog = scrollBox._BFIHousingCatalog
        StyleCatalogEntry(frame)
    end)
end

local function UpdateCatalogCategory(frame, isPressed)
    local isActive = frame.IsActive and frame:IsActive() or frame.isActive
    local state = "normal"
    if not frame:IsEnabled() then
        state = "disabled"
    elseif isPressed then
        state = "pressed"
    elseif isActive then
        state = "selected"
    elseif frame._BFIHousingHovered or frame:IsMouseMotionFocus() then
        state = "hovered"
    end

    SetFadeSurfaceState(frame, state)

    -- Blizzard category atlases include their circular chrome. Keep their
    -- category identity, but show only the centered glyph through a clipped
    -- square viewport; the BFI surface owns hover and selection state.
    local inactiveAtlas = frame.atlasNames and frame.atlasNames["_inactive"]
    if inactiveAtlas then
        frame.BFIHousingGlyph:SetAtlas(inactiveAtlas)
    else
        frame.BFIHousingGlyph:SetTexture(frame.Icon:GetTexture())
        frame.BFIHousingGlyph:SetTexCoord(frame.Icon:GetTexCoord())
    end
    frame.Icon:SetAlpha(0)
    frame.HoverIcon:SetAlpha(0)
    frame.BFIHousingGlyph:SetVertexColor(AF.GetColorRGB(frame:IsEnabled() and "white" or "disabled"))

    if frame.SelectedBackground then
        frame.SelectedBackground:SetAlpha(0)
        frame.SelectedBackground.FlipbookSparkleAnim:Stop()
    end
end

local function StyleCatalogCategory(frame)
    -- Let VerticalLayoutFrame expand every category surface across the full
    -- rail while the clipped identity glyph remains centered within it.
    frame.expand = true
    frame.align = nil

    if not frame._BFIHousingCategoryStyled then
        frame._BFIHousingCategoryStyled = true

        CreateFadeSurface(frame)
        frame.Icon:SetAlpha(0)
        frame.HoverIcon:SetAlpha(0)

        local glyphClip = CreateFrame("Frame", nil, frame)
        glyphClip:SetClipsChildren(true)
        AF.SetFrameLevel(glyphClip, 1)
        AF.SetSize(glyphClip, 30, 30)
        AF.SetPoint(glyphClip, "CENTER")
        frame.BFIHousingGlyphClip = glyphClip

        local glyph = glyphClip:CreateTexture(nil, "ARTWORK")
        AF.SetSize(glyph, 48, 48)
        AF.SetPoint(glyph, "CENTER")
        frame.BFIHousingGlyph = glyph

        frame:HookScript("OnEnter", function(self)
            self._BFIHousingHovered = true
            UpdateCatalogCategory(self)
        end)
        frame:HookScript("OnLeave", function(self)
            self._BFIHousingHovered = nil
            UpdateCatalogCategory(self)
        end)
        frame:HookScript("OnHide", function(self)
            self._BFIHousingHovered = nil
        end)
        frame:HookScript("OnEnable", UpdateCatalogCategory)
        frame:HookScript("OnDisable", UpdateCatalogCategory)
        hooksecurefunc(frame, "UpdateVisuals", UpdateCatalogCategory)
    end

    UpdateCatalogCategory(frame)
end

local function UpdateCatalogBackButton(button, isPressed)
    local state = "normal"
    if not button:IsEnabled() then
        state = "disabled"
    elseif isPressed then
        state = "pressed"
    elseif button._BFIHousingHovered or button:IsMouseMotionFocus() then
        state = "hovered"
    end
    SetFadeSurfaceState(button, state)
end

local function StyleCatalogBackButton(button)
    button.expand = true
    button.align = nil

    if not button._BFIHousingBackStyled then
        button._BFIHousingBackStyled = true
        StyleActionButton(button)
        CreateFadeSurface(button)
        button:HookScript("OnEnter", function(self)
            self._BFIHousingHovered = true
            UpdateCatalogBackButton(self)
        end)
        button:HookScript("OnLeave", function(self)
            self._BFIHousingHovered = nil
            UpdateCatalogBackButton(self)
        end)
        button:HookScript("OnHide", function(self)
            self._BFIHousingHovered = nil
        end)
        button:HookScript("OnEnable", UpdateCatalogBackButton)
        button:HookScript("OnDisable", UpdateCatalogBackButton)
        hooksecurefunc(button, "UpdateVisuals", UpdateCatalogBackButton)
    end

    UpdateCatalogBackButton(button)
end

local function StyleCatalogCategories(categories)
    categories.topPadding = 0
    categories.spacing = 0

    StyleCatalogBackButton(categories.BackButton)
    StyleCatalogCategory(categories.AllSubcategoriesStandIn)

    for frame in categories.categoryPool:EnumerateActive() do
        StyleCatalogCategory(frame)
    end
    for frame in categories.subcategoryPool:EnumerateActive() do
        StyleCatalogCategory(frame)
    end

    categories:Layout()
end

local function UpdatePreviewedCatalogEntry(preview, entryInfo)
    local catalog = preview._BFIHousingCatalog
    if not catalog then return end

    catalog._BFIPreviewedRecordID = entryInfo and entryInfo.recordID or nil
    catalog._BFIPreviewedEntryType = entryInfo and entryInfo.entryType or nil
    StyleVisibleCatalogEntries(catalog.OptionsContainer.ScrollBox)
end

local function StyleCatalog(catalog)
    catalog.Background:SetAlpha(0)
    catalog.Divider:SetColorTexture(AF.GetColorRGB("border", 0.65))
    AF.SetWidth(catalog.Divider, 1)

    S.StyleDropdownButton(catalog.Filters.FilterDropdown)
    catalog.Filters.FilterDropdown.displacedRegions = nil
    S.StyleEditBox(catalog.SearchBox, -4)
    AF.SetHeight(catalog.SearchBox, 20)

    hooksecurefunc(catalog.Filters.FilterDropdown, "GenerateMenu", StyleCatalogFilterMenu)
    StyleCatalogFilterMenu(catalog.Filters.FilterDropdown)

    local categories = catalog.Categories
    categories.Background:SetAlpha(0)
    categories.TopBorder:SetAlpha(0)
    categories.SubcategoriesDivider:SetAlpha(0)
    categories.SubcategoriesDivider.ignoreInLayout = true

    StyleCatalogCategories(categories)
    hooksecurefunc(categories, "DisplayTopLevelCategories", StyleCatalogCategories)
    hooksecurefunc(categories, "DisplaySubcategoriesUnderCategory", StyleCatalogCategories)

    local options = catalog.OptionsContainer
    S.StyleScrollBar(options.ScrollBar)
    options.ScrollBox:ClearEdgeFade()
    options.ScrollBox._BFIHousingCatalog = catalog
    hooksecurefunc(options.ScrollBox, "Update", StyleVisibleCatalogEntries)
    StyleVisibleCatalogEntries(options.ScrollBox)

    local preview = catalog.PreviewFrame
    preview.PreviewBackground:SetAlpha(0)
    preview.PreviewCornerLeft:SetAlpha(0)
    preview.PreviewCornerRight:SetAlpha(0)
    CreateFadeSurface(preview)
    SetFadeSurfaceState(preview, "selected")

    preview._BFIHousingCatalog = catalog
    hooksecurefunc(preview, "ClearPreviewData", UpdatePreviewedCatalogEntry)
    hooksecurefunc(preview, "PreviewCatalogEntryInfo", UpdatePreviewedCatalogEntry)
    UpdatePreviewedCatalogEntry(preview, preview.catalogEntryInfo)

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
