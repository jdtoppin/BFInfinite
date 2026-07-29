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

-- Mirror the Profession Book rows: keep a narrow class-colour accent at the
-- leading edge over a quiet gray surface that fades into the panel. A second
-- class-colour gradient appears only for hover and selected state, without
-- bringing back Blizzard's heavy orange card borders.
local function CreateFadeSurface(frame)
    if frame._BFIHousingFadeSurface then return end
    frame._BFIHousingFadeSurface = true

    S.CreateBackdrop(frame, true)
    if frame.BFIHousingBackground then
        frame.BFIHousingBackground:SetAlpha(0)
    end

    local accent = AF.CreateTexture(frame, nil, nil, "BORDER", -8)
    accent:SetColor("BFI")
    AF.SetPoint(accent, "TOPLEFT", 1, -1)
    AF.SetPoint(accent, "BOTTOMLEFT", 1, 1)
    AF.SetWidth(accent, 2)
    frame.BFIHousingFadeAccent = accent

    local background = AF.CreateGradientTexture(
        frame,
        "HORIZONTAL",
        AF.GetColorTable("background_lighter", 0.5),
        AF.GetColorTable("background_lighter", 0),
        nil,
        "BACKGROUND",
        -8
    )
    AF.SetPoint(background, "TOPLEFT", accent, "TOPRIGHT", 1, 0)
    AF.SetPoint(background, "RIGHT")
    AF.SetPoint(background, "BOTTOM", accent)
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
    state:SetAllPoints(background)
    state:SetBlendMode("ADD")
    state:SetAlpha(0)
    state:Hide()
    frame.BFIHousingFadeState = state
end

local function SetFadeSurfaceState(frame, state)
    local strength = 0
    if state == "pressed" then
        strength = 1
    elseif state == "selected" or state == "hovered" then
        strength = 0.9
    end

    frame.BFIHousingFadeBackground:SetAlpha(state == "disabled" and 0.3 or 1)
    if frame.BFIHousingFadeState then
        frame.BFIHousingFadeState:SetAlpha(strength)
        frame.BFIHousingFadeState:SetShown(strength > 0)
    end
    frame.BFIHousingFadeAccent:SetColor(state == "disabled" and "disabled" or "BFI")
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

-- Category and subcategory IDs are separate DB2 namespaces and overlap.
-- Retail 12.0.7 and PTR 12.1 share the current IDs; PTR adds subcategories
-- 52 (Vines and Hanging Plants) and 53 (Pet Beds). Atlas keys provide a
-- language-neutral secondary lookup, while unknown future entries retain
-- Blizzard's native identity glyph below.
local catalogCategoryIcons = {
    [1] = "Housing_Furnishings",
    [2] = "Housing_Structural",
    [3] = "Housing_Accents",
    [4] = "Housing_Lighting",
    [5] = "Housing_Functional",
    [6] = "Housing_Nature",
    [8] = "Housing_Misc",
    [9] = "Housing_Rooms",
    [17] = "Housing_Featured",
    [18] = "Housing_All",
}

local catalogSubcategoryIcons = {
    [1] = "Housing_Seating",
    [2] = "Housing_Beds",
    [3] = "Housing_Doors",
    [4] = "Housing_Construction",
    [5] = "Housing_Tables",
    [6] = "Housing_Storage",
    [7] = "Housing_Furnishings",
    [8] = "Housing_Windows",
    [9] = "Housing_LargeStructures",
    [10] = "Housing_Structural",
    [11] = "Housing_Ornamental",
    [12] = "Housing_WallHangings",
    [13] = "Housing_FoodDrink",
    [14] = "Housing_Floor",
    [15] = "Housing_Accents",
    [16] = "Housing_LargeLights",
    [17] = "Housing_WallLights",
    [18] = "Housing_CeilingLights",
    [19] = "Housing_SmallLights",
    [21] = "Housing_Lighting",
    [22] = "Housing_Utility",
    [25] = "Housing_LargeFoliage",
    [26] = "Housing_SmallFoliage",
    [27] = "Housing_Bushes",
    [28] = "Housing_GroundCover",
    [29] = "Housing_Nature",
    [34] = "Housing_Misc",
    [35] = "Housing_Rooms",
    [51] = "Housing_Functional",
    [52] = "Housing_Vines",
    [53] = "Housing_PetBeds",
}

local catalogAtlasIcons = {
    ["category-icons_accents"] = "Housing_Accents",
    ["category-icons_all"] = "Housing_All",
    ["category-icons_beds"] = "Housing_Beds",
    ["category-icons_bushes"] = "Housing_Bushes",
    ["category-icons_doors"] = "Housing_Doors",
    ["category-icons_featured"] = "Housing_Featured",
    ["category-icons_floor"] = "Housing_Floor",
    ["category-icons_food-and-drink"] = "Housing_FoodDrink",
    ["category-icons_furnishings"] = "Housing_Furnishings",
    ["category-icons_ground-cover"] = "Housing_GroundCover",
    ["category-icons_hanging-lights"] = "Housing_CeilingLights",
    ["category-icons_interactive"] = "Housing_Functional",
    ["category-icons_large-foliage"] = "Housing_LargeFoliage",
    ["category-icons_large-lights"] = "Housing_LargeLights",
    ["category-icons_large-structures"] = "Housing_LargeStructures",
    ["category-icons_lighting"] = "Housing_Lighting",
    ["category-icons_misc"] = "Housing_Misc",
    ["category-icons_ornamental"] = "Housing_Ornamental",
    ["category-icons_pets"] = "Housing_PetBeds",
    ["category-icons_plants"] = "Housing_Nature",
    ["category-icons_rooms"] = "Housing_Rooms",
    ["category-icons_seating"] = "Housing_Seating",
    ["category-icons_small-foliage"] = "Housing_SmallFoliage",
    ["category-icons_small-lights"] = "Housing_SmallLights",
    ["category-icons_storage"] = "Housing_Storage",
    ["category-icons_structural"] = "Housing_Structural",
    ["category-icons_tables-and-desks"] = "Housing_Tables",
    ["category-icons_utility"] = "Housing_Utility",
    ["category-icons_vines"] = "Housing_Vines",
    ["category-icons_wall-hangings"] = "Housing_WallHangings",
    ["category-icons_wall-lights"] = "Housing_WallLights",
    ["category-icons_walls-and-columns"] = "Housing_Construction",
    ["category-icons_windows"] = "Housing_Windows",
}

local function GetCatalogCategoryIcon(frame)
    if not AF.hasHousingIcons then
        return
    end

    local iconName
    if frame.atlasKey == "category-icons_all" then
        iconName = "Housing_All"
    elseif frame.isSubcategory then
        iconName = catalogSubcategoryIcons[frame.ID]
    else
        iconName = catalogCategoryIcons[frame.ID]
    end

    return iconName or catalogAtlasIcons[frame.atlasKey]
end

local function IsCatalogEntryPreviewed(frame)
    local catalog = frame._BFIHousingCatalog
    local entryVariantID = frame.entryVariantID
    if not catalog or not entryVariantID then return false end

    return catalog._BFIPreviewedRecordID ~= nil
        and entryVariantID.recordID == catalog._BFIPreviewedRecordID
        and entryVariantID.entryType == catalog._BFIPreviewedEntryType
end

local function HideCatalogEntryChrome(frame)
    frame.Background:SetAlpha(0)
    frame.Background:Hide()
    frame.HoverBackground:SetAlpha(0)
    frame.HoverBackground:Hide()
    if frame.SpecialRoomFrame then
        frame.SpecialRoomFrame:SetAlpha(0)
        frame.SpecialRoomFrame:Hide()
    end
    if frame.SpecialRoomIcon then
        frame.SpecialRoomIcon:SetAlpha(0)
        frame.SpecialRoomIcon:Hide()
    end
end

local function UpdateCatalogEntry(frame, isPressed)
    -- Blizzard refreshes the orange default/active/pressed atlases throughout
    -- the pooled entry lifecycle. Re-suppress them before applying BFI state.
    HideCatalogEntryChrome(frame)

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
        HideCatalogEntryChrome(frame)

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
            HideCatalogEntryChrome(self)
            SetFadeSurfaceState(self, "normal")
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

    -- Prefer BFI's flat semantic category family. Unknown future categories
    -- retain Blizzard's identity glyph, clipped to remove its circular chrome.
    local customIcon = GetCatalogCategoryIcon(frame)
    local inactiveAtlas = frame.atlasNames and frame.atlasNames["_inactive"]
    if customIcon then
        local success = AF.SetHousingIcon
            and AF.SetHousingIcon(frame.BFIHousingGlyph, customIcon)
        if not success then
            frame.BFIHousingGlyph:SetTexture(AF.GetIcon(customIcon))
        end
        frame.BFIHousingGlyph:SetTexCoord(0, 1, 0, 1)
        -- AF's source artwork uses one normalized internal safe area. Filling
        -- the viewport keeps the visible mark legible without touching chrome.
        AF.SetSize(frame.BFIHousingGlyph, 30, 30)
    elseif inactiveAtlas then
        frame.BFIHousingGlyph:SetAtlas(inactiveAtlas)
        AF.SetSize(frame.BFIHousingGlyph, 48, 48)
    else
        frame.BFIHousingGlyph:SetTexture(frame.Icon:GetTexture())
        frame.BFIHousingGlyph:SetTexCoord(frame.Icon:GetTexCoord())
        AF.SetSize(frame.BFIHousingGlyph, 48, 48)
    end
    frame.Icon:SetAlpha(0)
    frame.Icon:Hide()
    frame.HoverIcon:SetAlpha(0)
    frame.HoverIcon:Hide()
    frame.BFIHousingGlyph:SetVertexColor(AF.GetColorRGB(frame:IsEnabled() and "white" or "disabled"))

    if frame.SelectedBackground then
        frame.SelectedBackground:SetAlpha(0)
        frame.SelectedBackground:Hide()
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
            SetFadeSurfaceState(self, "normal")
        end)
        frame:HookScript("OnEnable", UpdateCatalogCategory)
        frame:HookScript("OnDisable", UpdateCatalogCategory)
        hooksecurefunc(frame, "UpdateVisuals", UpdateCatalogCategory)
    end

    UpdateCatalogCategory(frame)
end

local function HideCatalogBackButtonChrome(button)
    button.Icon:SetAlpha(0)
    button.Icon:Hide()
    button.HoverIcon:SetAlpha(0)
    button.HoverIcon:Hide()
    button.Text:SetAlpha(0)
    button.Text:Hide()
end

local function UpdateCatalogBackButton(button)
    HideCatalogBackButtonChrome(button)

    local color = "darkgray"
    if not button:IsEnabled() then
        color = "disabled"
    elseif button._BFIHousingHovered or button:IsMouseMotionFocus() then
        color = "BFI"
    end
    button.BFIHousingBackIcon:SetVertexColor(AF.GetColorRGB(color))
end

local function StyleCatalogBackButton(button)
    button.expand = nil
    button.align = "center"
    button.fixedWidth = 35
    button.fixedHeight = 35
    AF.SetSize(button, 35, 35)

    if not button._BFIHousingBackStyled then
        button._BFIHousingBackStyled = true

        button.enabledTooltip = button.enabledTooltip or button.Text:GetText()
        button.Icon.ignoreInLayout = true
        button.HoverIcon.ignoreInLayout = true
        button.Text.ignoreInLayout = true
        HideCatalogBackButtonChrome(button)

        local icon = AF.CreateTexture(button, AF.GetIcon("ArrowLeft1"), "darkgray", "ARTWORK", 1)
        AF.SetSize(icon, 20, 20)
        AF.SetPoint(icon, "CENTER")
        button.BFIHousingBackIcon = icon

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
            UpdateCatalogBackButton(self)
        end)
        button:HookScript("OnShow", UpdateCatalogBackButton)
        button:HookScript("OnEnable", UpdateCatalogBackButton)
        button:HookScript("OnDisable", UpdateCatalogBackButton)
        hooksecurefunc(button, "UpdateVisuals", UpdateCatalogBackButton)
    end

    UpdateCatalogBackButton(button)
end

local function HideCatalogCategoriesChrome(categories)
    categories.Background:SetAlpha(0)
    categories.Background:Hide()
    categories.TopBorder:SetAlpha(0)
    categories.TopBorder:Hide()
    categories.SubcategoriesDivider:SetAlpha(0)
    categories.SubcategoriesDivider:Hide()
end

local function StyleCatalogCategories(categories)
    categories.topPadding = 0
    categories.spacing = 0
    HideCatalogCategoriesChrome(categories)

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

local function HideCatalogPreviewChrome(preview)
    preview.PreviewBackground:SetAlpha(0)
    preview.PreviewBackground:Hide()
    preview.PreviewCornerLeft:SetAlpha(0)
    preview.PreviewCornerLeft:Hide()
    preview.PreviewCornerRight:SetAlpha(0)
    preview.PreviewCornerRight:Hide()
end

local function HideCatalogDivider(frame)
    if not frame.Divider then return end
    frame.Divider:SetAlpha(0)
    frame.Divider:Hide()
end

local function UpdatePreviewedCatalogEntry(preview, entryInfo)
    local catalog = preview._BFIHousingCatalog
    if not catalog then return end

    HideCatalogPreviewChrome(preview)
    catalog._BFIPreviewedRecordID = entryInfo and entryInfo.recordID or nil
    catalog._BFIPreviewedEntryType = entryInfo and entryInfo.entryType or nil
    StyleVisibleCatalogEntries(catalog.OptionsContainer.ScrollBox)
end

local function StyleModelSceneControlButton(button, icon, fallbackIcon, flipFallback)
    -- ModelScene rotation starts on mouse-down and stops on mouse-up. Preserve
    -- those native scripts while replacing only Blizzard's button chrome.
    S.StyleButton(button, nil, nil, true)

    if AF.hasViewIcons and AF.SetAdaptiveIcon then
        AF.SetAdaptiveIcon(button.Icon, icon)
        button.Icon:SetTexCoord(0, 1, 0, 1)
    else
        button.Icon:SetTexture(AF.GetIcon(fallbackIcon))
        button.Icon:SetTexCoord(flipFallback and 1 or 0, flipFallback and 0 or 1, 0, 1)
    end

    button.Icon:SetAlpha(1)
    button.Icon:Show()
    button.Icon:SetVertexColor(AF.GetColorRGB("white"))
    AF.ClearPoints(button.Icon)
    AF.SetPoint(button.Icon, "CENTER")
    AF.SetSize(button.Icon, 18, 18)
end

local function StyleModelSceneControls(controls)
    if not controls or controls._BFIHousingStyled then return end
    controls._BFIHousingStyled = true

    StyleModelSceneControlButton(controls.zoomInButton, "View_ZoomIn", "Plus")
    StyleModelSceneControlButton(controls.zoomOutButton, "View_ZoomOut", "Minus")
    StyleModelSceneControlButton(controls.rotateLeftButton, "View_RotateLeft", "Refresh_Round")
    StyleModelSceneControlButton(controls.rotateRightButton, "View_RotateRight", "Refresh_Round", true)
    StyleModelSceneControlButton(controls.resetButton, "View_Reset", "Reset_Small")

    -- Blizzard's atlases include broad transparent gutters and overlap by six
    -- pixels. AF backdrops fill the controls, so leave a clean one-pixel gap.
    controls.buttonHorizontalPadding = 1
    controls:UpdateLayout()
end

local function StyleCatalog(catalog)
    catalog.Background:SetAlpha(0)
    catalog.Background:Hide()
    HideCatalogDivider(catalog)
    catalog:HookScript("OnShow", HideCatalogDivider)

    S.StyleDropdownButton(catalog.Filters.FilterDropdown)
    catalog.Filters.FilterDropdown.displacedRegions = nil
    S.StyleEditBox(catalog.SearchBox, -4)
    AF.SetHeight(catalog.SearchBox, 20)

    hooksecurefunc(catalog.Filters.FilterDropdown, "GenerateMenu", StyleCatalogFilterMenu)
    StyleCatalogFilterMenu(catalog.Filters.FilterDropdown)

    local categories = catalog.Categories
    HideCatalogCategoriesChrome(categories)
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
    HideCatalogPreviewChrome(preview)

    preview._BFIHousingCatalog = catalog
    hooksecurefunc(preview, "ClearPreviewData", UpdatePreviewedCatalogEntry)
    hooksecurefunc(preview, "PreviewCatalogEntryInfo", UpdatePreviewedCatalogEntry)
    preview:HookScript("OnShow", HideCatalogPreviewChrome)
    UpdatePreviewedCatalogEntry(preview, preview.catalogEntryInfo)

    StyleModelSceneControls(preview.ModelSceneControls)
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
    HideCatalogDivider(collection)
    collection:HookScript("OnShow", HideCatalogDivider)

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
