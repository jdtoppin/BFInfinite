---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local EncounterJournal

-- Retail 12.0.7.68887, Gethe/wow-ui-source 4383ced30106d51b27e3e86d1987f1552f0d259d
-- and PTR 12.1.0.68914, d3915c78aba77a7a9be76acbfa35c674bbb6abe9.
-- Sources: Blizzard_EncounterJournal/Mainline/{Blizzard_EncounterJournal,
-- Blizzard_MonthlyActivities,Blizzard_LootJournal,Blizzard_LootJournalItems,
-- Blizzard_Journeys}.{lua,xml} and Blizzard_FrameXML/{NavigationBar,
-- RewardTrackTemplates}.*.
-- PTR adds a circle Mask to RenownLevelCardTemplate; it is guarded below.

---------------------------------------------------------------------
-- local styles
---------------------------------------------------------------------
local function StyleArtFrame(frame)
    if not frame or frame._BFIEncounterArtStyled then return end
    frame._BFIEncounterArtStyled = true

    S.CreateBackdrop(frame, true)
    frame.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
end

local function StyleArtButton(button)
    if not button or button._BFIEncounterArtButtonStyled then return end
    button._BFIEncounterArtButtonStyled = true

    StyleArtFrame(button)
    button:HookScript("OnEnter", function(self)
        self.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("white", 0.8))
    end)
    button:HookScript("OnLeave", function(self)
        self.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
    end)
end

local function HideTextureWhenShown(texture, shown)
    if shown then
        AF.TextureHide(texture)
    end
end

local function KeepTextureHidden(texture)
    if not texture or texture._BFIEncounterHidden then return end
    texture._BFIEncounterHidden = true

    texture:Hide()
    hooksecurefunc(texture, "Show", AF.TextureHide)
    hooksecurefunc(texture, "SetShown", HideTextureWhenShown)
end

local function KeepNamedTexturesHidden(owner, names)
    for _, name in ipairs(names) do
        local texture = owner and owner[name]
        if texture then
            KeepTextureHidden(texture)
        end
    end
end

local function SetFlatTexture(texture, color, alpha)
    if not texture then return end

    texture:SetTexture(AF.GetPlainTexture())
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(AF.GetColorRGB(color, alpha))
end

local function SetTextColor(region, color)
    if not region or not region.SetTextColor then return end

    if region.IsObjectType and region:IsObjectType("SimpleHTML") then
        region:SetTextColor("P", AF.GetColorRGB(color))
    else
        region:SetTextColor(AF.GetColorRGB(color))
    end
end

local function StyleEncounterRadio(frame)
    S.StyleMenuSelection(frame, 7)
end

local function StyleEncounterRadioDescriptions(parentDescription)
    for _, description in parentDescription:EnumerateElementDescriptions() do
        if description:IsRadio() then
            description:AddInitializer(StyleEncounterRadio)
        end
        StyleEncounterRadioDescriptions(description)
    end
end

local function StyleEncounterRadioMenu(_, rootDescription)
    StyleEncounterRadioDescriptions(rootDescription)
end

local function CreateHoverOverlay(frame, alpha)
    if frame.BFIEncounterHover then return frame.BFIEncounterHover end

    local overlay = AF.CreateTexture(frame, nil, AF.GetColorTable("white", alpha or 0.08), "OVERLAY", 7)
    frame.BFIEncounterHover = overlay
    overlay:Hide()
    if frame.BFIBackdrop then
        AF.SetOnePixelInside(overlay, frame.BFIBackdrop)
    else
        overlay:SetAllPoints()
    end
    return overlay
end

local function SetFlatCardState(frame)
    if not frame.BFIBackdrop then return end

    local locked = not frame:IsEnabled()
        or (frame.majorFactionData and frame.majorFactionData.isUnlocked == false)
    local color = locked and "widget_dark" or "widget"
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB(color))
    frame.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
end

local function StyleFlatCard(frame)
    if not frame._BFIEncounterFlatCardStyled then
        frame._BFIEncounterFlatCardStyled = true

        local normalTexture = frame:GetNormalTexture()
        local pushedTexture = frame:GetPushedTexture()
        local highlightTexture = frame:GetHighlightTexture()
        local disabledTexture = frame:GetDisabledTexture()
        if normalTexture then
            KeepTextureHidden(normalTexture)
        end
        if pushedTexture then
            KeepTextureHidden(pushedTexture)
        end
        if highlightTexture then
            KeepTextureHidden(highlightTexture)
        end
        if disabledTexture then
            KeepTextureHidden(disabledTexture)
        end

        S.CreateBackdrop(frame)
        local hover = CreateHoverOverlay(frame)
        frame:HookScript("OnEnter", function(self)
            if self:IsEnabled() then
                hover:Show()
            end
        end)
        frame:HookScript("OnLeave", function()
            hover:Hide()
        end)
        frame:HookScript("OnEnable", SetFlatCardState)
        frame:HookScript("OnDisable", function(self)
            hover:Hide()
            SetFlatCardState(self)
        end)
    end

    SetFlatCardState(frame)
end

-- EncounterTabTemplate uses its selected and unselected textures as the
-- semantic icon state. The shared side-tab style intentionally removes every
-- texture, so this local treatment only replaces the outer Blizzard tab shell.
local function SetEncounterTabSelected(tab, selected)
    tab._BFIEncounterSelected = selected
    tab.BFIBackdrop:SetBackdropColor(AF.GetColorRGB(selected and "BFI" or "widget", selected and 0.55 or 1))
end

local function StyleEncounterTab(tab)
    if tab._BFIEncounterTabStyled then return end
    tab._BFIEncounterTabStyled = true

    tab:SetNormalTexture(AF.GetEmptyTexture())
    tab:SetPushedTexture(AF.GetEmptyTexture())
    tab:SetDisabledTexture(AF.GetEmptyTexture())
    tab:SetHighlightTexture(AF.GetEmptyTexture())

    S.CreateBackdrop(tab)
    AF.SetSize(tab, 35, 50)
    tab.unselected:ClearAllPoints()
    tab.unselected:SetPoint("CENTER")
    AF.SetSize(tab.unselected, 24, 22)
    tab.selected:ClearAllPoints()
    tab.selected:SetPoint("CENTER")
    AF.SetSize(tab.selected, 24, 22)
    SetEncounterTabSelected(tab, EncounterJournal.encounter.info.tab == tab:GetID())

    tab:HookScript("OnEnter", function(self)
        self.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("BFI", 0.55))
    end)
    tab:HookScript("OnLeave", function(self)
        SetEncounterTabSelected(self, self._BFIEncounterSelected)
    end)
    hooksecurefunc(tab, "LockHighlight", function(self)
        SetEncounterTabSelected(self, true)
    end)
    hooksecurefunc(tab, "UnlockHighlight", function(self)
        SetEncounterTabSelected(self, false)
    end)
end

---------------------------------------------------------------------
-- shell and static controls
---------------------------------------------------------------------
local function GetBottomTabs()
    return {
        EncounterJournal.JourneysTab,
        EncounterJournal.MonthlyActivitiesTab,
        EncounterJournal.suggestTab,
        EncounterJournal.dungeonsTab,
        EncounterJournal.raidsTab,
        EncounterJournal.LootJournalTab,
        EncounterJournal.TutorialsTab,
    }
end

local function LayoutBottomTabs()
    local previousTab
    for _, tab in ipairs(GetBottomTabs()) do
        if tab:IsShown() then
            AF.ClearPoints(tab)
            if previousTab then
                AF.SetPoint(tab, "TOPLEFT", previousTab, "TOPRIGHT", 1, 0)
            else
                AF.SetPoint(tab, "TOPLEFT", EncounterJournal, "BOTTOMLEFT", 0, -1)
            end
            previousTab = tab
        end
    end
end

local function StyleBottomTabs()
    for _, tab in ipairs(GetBottomTabs()) do
        S.StyleTab(tab)
    end
    LayoutBottomTabs()
    PanelTemplates_UpdateTabs(EncounterJournal)
end

local function StyleSearchPreviewButton(button)
    if button._BFIEncounterPreviewStyled then return end
    button._BFIEncounterPreviewStyled = true

    button:SetNormalTexture(AF.GetEmptyTexture())
    button:SetPushedTexture(AF.GetEmptyTexture())
    button:SetDisabledTexture(AF.GetEmptyTexture())
    button:SetHighlightTexture(AF.GetEmptyTexture())
    S.CreateBackdrop(button)
    button.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))

    if button.iconFrame then
        KeepTextureHidden(button.iconFrame)
    end
    if button.icon then
        S.StyleIcon(button.icon, true)
    end
    if button.selectedTexture then
        button.selectedTexture:SetColorTexture(AF.GetColorRGB("BFI", 0.35))
    end
end

local function StyleSearchPreview()
    local searchBox = EncounterJournal.searchBox
    local preview = searchBox.searchPreviewContainer
    S.RemoveTextures(preview)
    S.CreateBackdrop(preview)

    for _, button in ipairs(searchBox.searchButtons) do
        StyleSearchPreviewButton(button)
    end
    StyleSearchPreviewButton(searchBox.showAllResults)

    S.RemoveTextures(searchBox.searchProgress)
    S.StyleStatusBar(searchBox.searchProgress.bar)
    searchBox.searchProgress.bar:SetStatusBarColor(AF.GetColorRGB("BFI"))
end

local function StyleAdventureGuide()
    local suggestFrame = EncounterJournal.suggestFrame
    local primary = suggestFrame.Suggestion1
    local secondary1 = suggestFrame.Suggestion2
    local secondary2 = suggestFrame.Suggestion3

    S.StyleButton(primary.button, "BFI")
    S.StyleButton(secondary1.centerDisplay.button, "BFI")
    S.StyleButton(secondary2.centerDisplay.button, "BFI")
    S.StyleIconButton(primary.prevButton, AF.GetIcon("ArrowLeft2"), 16)
    S.StyleIconButton(primary.nextButton, AF.GetIcon("ArrowRight2"), 16)

    -- The suggestion panes, portraits, reward rings, and tutorial art carry
    -- Blizzard's content identity and remain intact.
    S.StyleButton(EncounterJournal.TutorialsFrame.Contents.StartButton, "BFI")
end

local function StyleRewardTrackControls(track)
    StyleArtButton(track.LeftButton)
    StyleArtButton(track.JumpLeftButton)
    StyleArtButton(track.RightButton)
    StyleArtButton(track.JumpRightButton)
end

local function StyleFlatStatusBarFill(bar, color)
    if not bar then return end

    if not bar._BFIEncounterFlatFillStyled then
        bar._BFIEncounterFlatFillStyled = true
        S.RemoveTextures(bar)
        bar:SetStatusBarTexture(BFI.media.bar)
        bar:GetStatusBarTexture():SetDrawLayer("BORDER", -1)
    end
    bar:SetStatusBarColor(AF.GetColorRGB(color))
end

local function StyleJourneys()
    local frame = EncounterJournal.JourneysFrame
    S.StyleScrollBar(frame.ScrollBar)
    frame.BorderFrame:Hide()

    local progress = frame.JourneyProgress
    S.StyleButton(progress.OverviewBtn, "BFI")
    S.StyleButton(progress.LevelSkipButton, "BFI")
    local companionButton = progress.DelvesCompanionConfigurationFrame.CompanionConfigBtn
    StyleFlatCard(companionButton)
    S.StyleIcon(companionButton.Icon, true)
    KeepTextureHidden(companionButton.IconBorder)
    StyleRewardTrackControls(progress.RenownTrackFrame)
    StyleRewardTrackControls(progress.EncounterRewardProgressFrame)

    SetFlatTexture(progress.DividerTexture, "border")
    progress.DividerTexture:SetHeight(1)
    KeepTextureHidden(progress.DividerGlowTexture)

    local details = progress.ProgressDetailsFrame
    SetFlatTexture(details.JourneyLevelBar, "widget_dark")
    details.JourneyLevelBar:SetHeight(20)
    SetFlatTexture(details.JourneyLevelBg, "BFI", 0.55)
    AF.SetSize(details.JourneyLevelBg, 30, 20)
    S.StyleStatusBar(progress.DelveRewardProgressBar)
    progress.DelveRewardProgressBar:SetStatusBarColor(AF.GetColorRGB("BFI"))

    local overview = frame.JourneyOverview
    KeepTextureHidden(overview.IconBorder)
    KeepTextureHidden(overview.ProgressBorder)
    S.StyleSquareIcon(overview.JourneyIcon, nil, true)
    overview:HookScript("OnShow", function(self)
        S.StyleIcon(self.JourneyIcon)
    end)
    AF.SetSize(overview.OverviewProgressBar, 50, 50)
    overview.OverviewProgressBar:SetDrawEdge(false)
    overview.OverviewProgressBar:SetDrawBling(false)
    SetFlatTexture(overview.LevelFrame, "BFI", 0.55)
    AF.SetSize(overview.LevelFrame, 28, 20)

    SetFlatTexture(overview.DividerTexture, "border")
    overview.DividerTexture:ClearAllPoints()
    overview.DividerTexture:SetPoint("LEFT", overview, 45, 0)
    overview.DividerTexture:SetPoint("RIGHT", overview, -45, 0)
    overview.DividerTexture:SetHeight(1)
    KeepTextureHidden(overview.DividerGlowTexture)
    S.StyleButton(overview.OverviewBtn, "BFI")
end

local function StyleEncounterHelpButton(button)
    if not button or button._BFIEncounterHelpStyled then return end
    button._BFIEncounterHelpStyled = true

    -- Keep Blizzard's contextual HelpPlate click behavior, but use the same
    -- compact AF title-bar launcher and tooltip as the other BFI journals.
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    S.StyleTitleBarInfoButton(EncounterJournal, button)
    AF.SetTooltip(button, "BOTTOMLEFT", 0, -2, _G.MAIN_HELP_BUTTON_TOOLTIP)
    button:HookScript("OnHide", function()
        if AF.Tooltip:GetOwner() == button then
            AF.HideTooltip()
        end
    end)
end

local function StyleMonthlyActivities()
    local frame = EncounterJournal.MonthlyActivitiesFrame
    S.StyleScrollBar(frame.ScrollBar)
    S.StyleScrollBar(frame.FilterList.ScrollBar)
    StyleEncounterHelpButton(frame.HelpButton)

    KeepNamedTexturesHidden(frame, {
        "Bg",
        "DividerVertical",
        "ShadowLeft",
        "ShadowRight",
        "Divider",
    })
    KeepNamedTexturesHidden(frame.ThemeContainer, {
        "Top",
        "Bottom",
        "Left",
        "Right",
        "FilterList",
    })
    KeepTextureHidden(frame.FilterList.Bg)

    S.CreateBackdrop(frame.FilterList)
    frame.FilterList.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_dark"))
    frame.FilterList.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))

    local threshold = frame.ThresholdContainer
    KeepNamedTexturesHidden(threshold, {
        "BarBackgroundGlow",
        "BarBackground",
        "BarBorder",
        "BarBorderGlow",
        "BarFillGlow",
    })
    if threshold.BarEnd and threshold.BarEnd.line then
        KeepTextureHidden(threshold.BarEnd.line)
    end

    S.CreateBackdrop(threshold)
    threshold.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_dark"))
    threshold.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
    StyleFlatStatusBarFill(threshold.ThresholdBar, "BFI")
    StyleFlatStatusBarFill(threshold.BonusThresholdBar, "skyblue")

    frame.ScrollBox:GetView():SetPadding(0, 0, 0, 0, 4)
    frame.FilterList.ScrollBox:GetView():SetPadding(4, 4, 4, 4, 1)
end

local function StyleLootJournals()
    local runeforge = EncounterJournal.LootJournal
    S.StyleDropdownButton(EncounterJournal.LootJournalViewDropdown)
    S.StyleDropdownButton(runeforge.ClassDropdown)
    S.StyleDropdownButton(runeforge.RuneforgePowerDropdown)
    S.StyleScrollBar(runeforge.ScrollBar)

    local itemSets = EncounterJournal.LootJournalItems.ItemSetsFrame
    S.StyleDropdownButton(itemSets.ClassDropdown)
    S.StyleScrollBar(itemSets.ScrollBar)
end

local function GetEncounterTabs()
    local info = EncounterJournal.encounter.info
    return {
        info.overviewTab,
        info.lootTab,
        info.bossTab,
        info.modelTab,
    }
end

local function LayoutEncounterTabs()
    local info = EncounterJournal.encounter.info
    local previousTab
    for _, tab in ipairs(GetEncounterTabs()) do
        if tab:IsShown() then
            AF.ClearPoints(tab)
            if previousTab then
                AF.SetPoint(tab, "TOPLEFT", previousTab, "BOTTOMLEFT", 0, -1)
            else
                AF.SetPoint(tab, "TOPLEFT", info, "TOPRIGHT", 4, -28)
            end
            previousTab = tab
        end
    end
end

local function StyleEncounterBackgrounds()
    local instanceSelect = EncounterJournal.instanceSelect
    KeepNamedTexturesHidden(instanceSelect, {
        "bg",
        "evergreenBg",
    })

    local encounter = EncounterJournal.encounter
    local instance = encounter.instance
    KeepNamedTexturesHidden(instance, {
        "loreBG",
        "titleBG",
    })
    SetTextColor(instance.title, "white")
    local loreFont = instance.LoreScrollingFont
    if loreFont and loreFont.ScrollBox and loreFont.ScrollBox.FontStringContainer then
        SetTextColor(loreFont.ScrollBox.FontStringContainer.FontString, "gray")
    end

    local info = encounter.info
    KeepTextureHidden(_G.EncounterJournalEncounterFrameInfoBG)
    KeepNamedTexturesHidden(info, {
        "leftShadow",
        "rightShadow",
    })
    KeepNamedTexturesHidden(info.model, {
        "dungeonBG",
    })
    KeepTextureHidden(_G.EncounterJournalEncounterFrameInfoModelFrameShadow)
    KeepTextureHidden(_G.EncounterJournalEncounterFrameInfoModelFrameTitleBG)
    SetTextColor(info.model.imageTitle, "white")

    local details = info.detailsScroll.child
    SetTextColor(details.description, "gray")

    local overview = info.overviewScroll.child
    KeepTextureHidden(overview.header)
    SetTextColor(overview.loreDescription, "gray")
    SetTextColor(overview.Title or overview.title or _G[overview:GetName() .. "Title"], "white")
    if overview.overviewDescription then
        SetTextColor(overview.overviewDescription.Text, "gray")
    end
end

local function StyleInstanceHeaderIcon()
    local info = EncounterJournal.encounter.info
    local button = info.instanceButton
    local icon = button.icon

    button:SetNormalTexture(AF.GetEmptyTexture())
    button:SetHighlightTexture(AF.GetEmptyTexture())
    AF.ClearPoints(button)
    AF.SetPoint(button, "TOPLEFT", info, "TOPLEFT", 8, -8)
    AF.SetSize(button, 40, 40)

    icon:SetMask("")
    AF.ClearPoints(icon)
    AF.SetPoint(icon, "CENTER", button)
    AF.SetSize(icon, 32, 32)
    S.StyleIcon(icon, true)
end

local function UpdateGreatVaultButton(button)
    if not button.BFIIcon then return end

    local active = button.hasActiveSeason
    button.BFIIcon:SetDesaturated(not active)
    button.BFIIcon:SetVertexColor(AF.GetColorRGB(active and "yellow_text" or "disabled"))
end

local function StyleGreatVaultButton(button)
    S.StyleIconButton(button, AF.GetIcon("Calendar"), 18, "yellow_text", "widget")
    button:HookScript("OnShow", UpdateGreatVaultButton)
    UpdateGreatVaultButton(button)
end

local function StyleEncounterControls()
    local instanceSelect = EncounterJournal.instanceSelect
    S.StyleDropdownButton(instanceSelect.ExpansionDropdown)
    S.StyleScrollBar(instanceSelect.ScrollBar)
    StyleGreatVaultButton(instanceSelect.GreatVaultButton)

    local info = EncounterJournal.encounter.info
    S.StyleScrollBar(info.BossesScrollBar)
    S.StyleScrollBar(info.detailsScroll.ScrollBar)
    S.StyleScrollBar(info.overviewScroll.ScrollBar)
    S.StyleScrollBar(info.LootContainer.ScrollBar)
    S.StyleScrollBar(EncounterJournal.encounter.instance.LoreScrollBar)
    S.StyleDropdownButton(info.difficulty)
    S.StyleDropdownButton(info.LootContainer.filter)
    S.StyleDropdownButton(info.LootContainer.slotFilter)
    if _G.Menu then
        _G.Menu.ModifyMenu("MENU_EJ_DIFFICULTY", StyleEncounterRadioMenu)
    end
    local clearFilter = info.LootContainer.classClearFilter
    local clearFilterButton = _G[clearFilter:GetName() .. "ExitButton"]
    S.StyleIconButton(clearFilterButton, AF.GetIcon("Close"), 12, nil, "red")
    S.StyleIconButton(EncounterJournal.encounter.instance.mapButton, AF.GetIcon("World"), 18)

    StyleEncounterBackgrounds()
    StyleInstanceHeaderIcon()

    for _, tab in ipairs(GetEncounterTabs()) do
        StyleEncounterTab(tab)
    end
    LayoutEncounterTabs()
end

local function StyleShell()
    S.StyleTitledFrame(EncounterJournal)
    S.RemoveNineSliceAndBackground(EncounterJournal.inset)
    S.StyleNavBar(EncounterJournal.navBar)
    AF.ClearPoints(EncounterJournal.navBar)
    AF.SetPoint(EncounterJournal.navBar, "TOPLEFT", EncounterJournal, "TOPLEFT", 10, -25)

    S.StyleEditBox(EncounterJournal.searchBox, -4)
    StyleSearchPreview()
    S.StyleTitledFrame(EncounterJournal.searchResults, false)
    S.StyleScrollBar(EncounterJournal.searchResults.ScrollBar)

    StyleBottomTabs()
    StyleEncounterControls()
    StyleAdventureGuide()
    StyleMonthlyActivities()
    StyleLootJournals()
    StyleJourneys()
end

---------------------------------------------------------------------
-- instance, encounter, search, and loot pools
---------------------------------------------------------------------
local function StyleInstanceButton(button)
    if button._BFIEncounterInstanceStyled then return end
    button._BFIEncounterInstanceStyled = true

    button:SetNormalTexture(AF.GetEmptyTexture())
    button:SetPushedTexture(AF.GetEmptyTexture())
    button:SetDisabledTexture(AF.GetEmptyTexture())

    local highlight = button:GetHighlightTexture()
    highlight:SetColorTexture(AF.GetColorRGB("white", 0.12))
    highlight:SetAllPoints()
    StyleArtFrame(button)
end

local function StyleInstanceList()
    EncounterJournal.instanceSelect.ScrollBox:ForEachFrame(StyleInstanceButton)
end

local function StyleBossButton(button)
    if not button._BFIStyled then
        S.StyleButton(button, "widget")
        button:BFI_HookHighlight()
    end

    if EncounterJournal.encounterID == button.encounterID then
        button:LockHighlight()
    else
        button:UnlockHighlight()
    end
end

local function StyleEncounterItem(button)
    if not button._BFIEncounterItemStyled then
        button._BFIEncounterItemStyled = true
        KeepTextureHidden(button.bossTexture)
        KeepTextureHidden(button.bosslessTexture)
        S.CreateBackdrop(button)
        button.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
        button:HookScript("OnEnter", function(self)
            self.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("BFI", 0.35))
        end)
        button:HookScript("OnLeave", function(self)
            self.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
        end)
    end

    S.StyleIcon(button.icon, true)
    S.StyleIconBorder(button.IconBorder, button.icon.BFIBackdrop)

    button.slot:SetTextColor(AF.GetColorRGB("darkgray"))
    button.armorType:SetTextColor(AF.GetColorRGB("darkgray"))
    button.boss:SetTextColor(AF.GetColorRGB("darkgray"))
end

local function StyleEncounterItemHeader(header)
    if header.TipButton._BFIStyled then return end
    S.StyleIconButton(header.TipButton, AF.GetIcon("Question"), 14)
end

local function StyleSearchResult(button)
    if not button._BFIEncounterSearchStyled then
        button._BFIEncounterSearchStyled = true
        button:SetNormalTexture(AF.GetEmptyTexture())
        button:SetPushedTexture(AF.GetEmptyTexture())
        button:SetDisabledTexture(AF.GetEmptyTexture())
        button:SetHighlightTexture(AF.GetEmptyTexture())
        KeepTextureHidden(button.iconFrame)
        S.CreateBackdrop(button)
        button.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
        S.StyleIcon(button.icon, true)
        button:HookScript("OnEnter", function(self)
            self.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("BFI", 0.35))
        end)
        button:HookScript("OnLeave", function(self)
            self.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
        end)
    end

    button.path:SetTextColor(AF.GetColorRGB("darkgray"))
    button.resultType:SetTextColor(AF.GetColorRGB("darkgray"))
end

local function StyleCreatureButton(button)
    if button._BFIEncounterCreatureStyled then return end
    button._BFIEncounterCreatureStyled = true

    button:SetNormalTexture(AF.GetEmptyTexture())
    button:SetHighlightTexture(AF.GetEmptyTexture())
    S.StyleSquareIcon(button.creature, button.CircleMask, true)
end

local function StyleCreatureButtons()
    for _, button in ipairs(EncounterJournal.encounter.info.creatureButtons) do
        StyleCreatureButton(button)
    end
end

local function StyleEncounterBullet(bullet)
    if bullet.Bullet then
        SetFlatTexture(bullet.Bullet, "gray")
        AF.SetSize(bullet.Bullet, 3, 3)
    end
    SetTextColor(bullet.Text, "gray")
end

local function UpdateEncounterInfoHeaderState(button)
    if not button or not button.BFIBackdrop then return end

    local header = button:GetParent()
    local expanded = header.expanded
    button.BFIBackdrop:SetBackdropColor(AF.GetColorRGB(expanded and "BFI" or "widget", expanded and 0.35 or 1))
    button.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
    SetTextColor(button.title, "white")
    SetTextColor(button.expandedIcon, "white")

    if button.abilityIcon and button.abilityIcon.BFIBackdrop then
        button.abilityIcon.BFIBackdrop:SetShown(button.abilityIcon:IsShown())
    end
    if button.portrait and button.portrait.icon and button.portrait.icon.BFIBackdrop then
        button.portrait.icon.BFIBackdrop:SetShown(button.portrait:IsShown())
    end
end

local function StyleEncounterInfoHeader(header)
    if not header or not header.button then return end

    local button = header.button
    if not button._BFIEncounterInfoHeaderStyled then
        button._BFIEncounterInfoHeaderStyled = true

        -- The native expanded/collapsed shell is twelve parchment slices.
        -- Suppress those layers while preserving the semantic ability,
        -- creature, role, title, and +/- overlay regions.
        button:DisableDrawLayer("BACKGROUND")
        button:DisableDrawLayer("HIGHLIGHT")

        local glow = button:GetName() and _G[button:GetName() .. "Glow"]
        if glow then
            glow:Hide()
            hooksecurefunc(glow, "Show", function(self)
                self:Hide()
            end)
        end

        S.CreateBackdrop(button)
        local hover = CreateHoverOverlay(button)
        button:HookScript("OnEnter", function()
            hover:Show()
        end)
        button:HookScript("OnLeave", function(self)
            hover:Hide()
            UpdateEncounterInfoHeaderState(self)
        end)

        if button.abilityIcon then
            S.StyleIcon(button.abilityIcon, true)
        end
        if button.portrait then
            KeepNamedTexturesHidden(button.portrait, {
                "frame",
                "frameHighlight",
            })
            S.StyleIcon(button.portrait.icon, true)
        end

        SetFlatTexture(header.descriptionBG, "widget_dark")
        KeepTextureHidden(header.descriptionBGBottom)
    end

    SetTextColor(header.description, "gray")
    if header.overviewDescription then
        SetTextColor(header.overviewDescription.Text, "gray")
    end
    for _, bullet in ipairs(header.Bullets or {}) do
        StyleEncounterBullet(bullet)
    end
    UpdateEncounterInfoHeaderState(button)
end

local function StyleEncounterInfoHeaders()
    local encounter = EncounterJournal.encounter
    for _, header in ipairs(encounter.usedHeaders or {}) do
        StyleEncounterInfoHeader(header)
    end
    for _, header in ipairs(encounter.overviewFrame.overviews or {}) do
        StyleEncounterInfoHeader(header)
    end
    for _, bullet in ipairs(encounter.overviewFrame.Bullets or {}) do
        StyleEncounterBullet(bullet)
    end
end

---------------------------------------------------------------------
-- Monthly Activities pools
---------------------------------------------------------------------
local function UpdateMonthlyActivityState(button)
    if not button.BFIBackdrop then return end

    local data = button:GetData()
    if not data then return end

    local normalTexture = button:GetNormalTexture()
    local atlas = normalTexture and normalTexture:GetAtlas()
    local selected = atlas == "activities-incomplete-active"
    local color = "widget_dark"
    local alpha = 1

    if selected then
        color = "BFI"
        alpha = 0.35
    elseif data.completed then
        color = "widget"
    end

    button.BFIBackdrop:SetBackdropColor(AF.GetColorRGB(color, alpha))
    button.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))

    -- Blizzard's completed atlas uses black text. The Achievement-style dark
    -- card needs the standard light type treatment instead.
    if data.completed then
        button.TextContainer.NameText:SetFontObject("GameFontHighlightMedium")
        button.TextContainer.NameText:SetTextColor(AF.GetColorRGB("white"))
        button.TextContainer.ConditionsText:SetFontObject("GameFontNormal")
        button.TextContainer.ConditionsText:SetTextColor(AF.GetColorRGB("gray"))
    end
end

local function UpdateMonthlyCollapseIndicator(button)
    local indicator = button.HeaderCollapseIndicator
    if not indicator then return end

    local data = button:GetData()
    local node = button:GetElementData()
    if not data or not data.hasChild or not node then
        indicator:Hide()
        return
    end

    indicator:SetTexture(AF.GetIcon(node:IsCollapsed() and "Plus_Small" or "Minus_Small"))
    indicator:SetTexCoord(0, 1, 0, 1)
    AF.ClearPoints(indicator)
    AF.SetPoint(indicator, "RIGHT", button, "RIGHT", -12, 0)
    AF.SetSize(indicator, 16, 16)
    indicator:Show()
end

local function StyleMonthlyActivityButton(button)
    if not button._BFIMonthlyActivityStyled then
        button._BFIMonthlyActivityStyled = true

        local normalTexture = button:GetNormalTexture()
        local highlightTexture = button:GetHighlightTexture()
        if normalTexture then
            KeepTextureHidden(normalTexture)
        end
        if highlightTexture then
            KeepTextureHidden(highlightTexture)
        end
        KeepNamedTexturesHidden(button, {
            "Coin",
            "Mask",
            "Ribbon",
            "RibbonStacked",
        })

        S.CreateBackdrop(button)
        local hover = CreateHoverOverlay(button)
        button:HookScript("OnEnter", function(self)
            if self:IsEnabled() then
                hover:Show()
            end
        end)
        button:HookScript("OnLeave", function()
            hover:Hide()
        end)
        button:HookScript("OnDisable", function()
            hover:Hide()
        end)
    end

    UpdateMonthlyActivityState(button)
    UpdateMonthlyCollapseIndicator(button)
end

local function SetMonthlyFilterState(button, selected)
    if not button.BFIBackdrop then return end
    button._BFIMonthlyFilterSelected = selected
    KeepTextureHidden(button.Texture)
    button.BFIBackdrop:SetBackdropColor(AF.GetColorRGB(selected and "BFI" or "widget", selected and 0.55 or 1))
end

local function StyleMonthlyFilterButton(button)
    if not button._BFIMonthlyFilterStyled then
        button._BFIMonthlyFilterStyled = true
        local selected = button.Texture:IsShown()
        S.CreateBackdrop(button)
        local hover = CreateHoverOverlay(button)
        button:HookScript("OnEnter", function()
            hover:Show()
        end)
        button:HookScript("OnLeave", function(self)
            hover:Hide()
            SetMonthlyFilterState(self, self._BFIMonthlyFilterSelected)
        end)
        hooksecurefunc(button, "UpdateStateInternal", SetMonthlyFilterState)
        SetMonthlyFilterState(button, selected)
        return
    end

    SetMonthlyFilterState(button, button._BFIMonthlyFilterSelected)
end

local function StyleMonthlyRewardButton(button)
    if button._BFIMonthlyRewardStyled then return end
    button._BFIMonthlyRewardStyled = true

    button.NormalTexture:SetAlpha(0)
    S.StyleSquareIcon(button.Icon, button.CircleMask, true)

    button.HighlightTexture:SetAlpha(1)
    button.HighlightTexture:SetColorTexture(AF.GetColorRGB("white", 0.2))
    AF.SetOnePixelInside(button.HighlightTexture, button.Icon.BFIBackdrop)

    button.PushedTexture:SetAlpha(1)
    button.PushedTexture:SetColorTexture(AF.GetColorRGB("yellow", 0.2))
    AF.SetOnePixelInside(button.PushedTexture, button.Icon.BFIBackdrop)

    if button.IconBorder then
        S.StyleIconBorder(button.IconBorder, button.Icon.BFIBackdrop)
    end
end

local function StyleMonthlyThresholds(frame)
    if not frame.thresholdFrames then return end
    for _, threshold in ipairs(frame.thresholdFrames) do
        SetFlatTexture(threshold.LineComplete, "BFI")
        AF.SetSize(threshold.LineComplete, 1, 33)
        if threshold.LineIncomplete and threshold.LineIncomplete.LineIncompleteTexture then
            SetFlatTexture(threshold.LineIncomplete.LineIncompleteTexture, "border")
            AF.SetSize(threshold.LineIncomplete.LineIncompleteTexture, 1, 33)
        end
        StyleMonthlyRewardButton(threshold.RewardItem)
    end
end

local function StyleExistingMonthlyFrames()
    local frame = EncounterJournal.MonthlyActivitiesFrame
    frame.FilterList.ScrollBox:ForEachFrame(StyleMonthlyFilterButton)
    frame.ScrollBox:ForEachFrame(StyleMonthlyActivityButton)
    StyleMonthlyThresholds(frame)
end

---------------------------------------------------------------------
-- Loot Journal pools
---------------------------------------------------------------------
local function StyleRuneforgePower(button)
    if button._BFIRuneforgeStyled then return end
    button._BFIRuneforgeStyled = true

    StyleArtButton(button)
    S.StyleSquareIcon(button.Icon, button.CircleMask, true)
    button.Background:Hide()
    S.StyleIconBorder(button.BackgroundOverlay, button.Icon.BFIBackdrop)
end

local function StyleLootJournalSetItem(button)
    S.StyleIcon(button.Icon, true)
    S.StyleIconBorder(button.Border, button.Icon.BFIBackdrop)
    if not button.itemID then return end

    -- LootJournalItemSetsMixin:ConfigureItemButton uses the same public set
    -- item ID and Epic fallback before applying Blizzard's atlas border.
    local _, _, itemQuality = C_Item.GetItemInfo(button.itemID)
    itemQuality = itemQuality or Enum.ItemQuality.Epic
    local r, g, b = C_Item.GetItemQualityColor(itemQuality)
    button.Icon.BFIBackdrop:SetBackdropBorderColor(r, g, b)
end

local function StyleLootJournalSet(setButton)
    StyleArtFrame(setButton)
    for _, itemButton in ipairs(setButton.ItemButtons) do
        StyleLootJournalSetItem(itemButton)
    end
end

---------------------------------------------------------------------
-- Journeys pools
---------------------------------------------------------------------
local function StyleJourneyListFrame(frame)
    if frame.CategoryDivider then
        SetFlatTexture(frame.CategoryDivider, "border")
        frame.CategoryDivider:SetHeight(1)
        return
    end
    if not frame.LockFrame then return end

    StyleFlatCard(frame)
    if frame.IconFrame then
        KeepTextureHidden(frame.IconFrame.Border)
        S.StyleIcon(frame.IconFrame.Icon, true)
        AF.SetSize(frame.RenownCardProgressBar, 40, 40)
        frame.RenownCardProgressBar:SetDrawEdge(false)
        frame.RenownCardProgressBar:SetDrawBling(false)
    end
    if frame.JourneyCardProgressBar then
        S.StyleStatusBar(frame.JourneyCardProgressBar)
        frame.JourneyCardProgressBar:SetStatusBarColor(AF.GetColorRGB("BFI"))
    end
    if frame.WatchedFactionToggleFrame then
        S.StyleCheckButton(frame.WatchedFactionToggleFrame.WatchFactionCheckbox)
    end
end

local function StyleJourneyList(frame)
    if frame.JourneysList.ClearEdgeFade then
        frame.JourneysList:ClearEdgeFade()
    end
    frame.JourneysList:ForEachFrame(StyleJourneyListFrame)
end

local function StyleJourneyReward(reward)
    if reward._BFIJourneyRewardStyled then return end
    reward._BFIJourneyRewardStyled = true

    SetFlatTexture(reward.RewardCardBG, "widget")
    SetFlatTexture(reward.RewardCardBGGlow, "BFI", 0.35)
    S.StyleSquareIcon(reward.RewardCardIcon, reward.TextureMask, true)
    S.StyleIconBorder(reward.RewardCardIconBorderDefault, reward.RewardCardIcon.BFIBackdrop)
    reward.RewardCardIcon.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
end

local function StyleJourneyRewards(frame)
    for reward in frame.rewardPool:EnumerateActive() do
        StyleJourneyReward(reward)
    end
end

local function StyleJourneyHighlight(highlight)
    if highlight._BFIJourneyHighlightStyled then return end
    highlight._BFIJourneyHighlightStyled = true

    KeepTextureHidden(highlight.Background)
    S.CreateBackdrop(highlight)
    highlight.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
    highlight.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
end

local function StyleJourneyHighlights(frame)
    for highlight in frame.highlightPool:EnumerateActive() do
        StyleJourneyHighlight(highlight)
    end
end

local function IsEncounterJournalDescendant(frame)
    local parent = frame
    while parent do
        if parent == EncounterJournal then return true end
        parent = parent:GetParent()
    end
    return false
end

local function StyleRenownLevel(level)
    if level._BFIRenownLevelStyled or not IsEncounterJournalDescendant(level) then return end
    level._BFIRenownLevelStyled = true

    local iconMask = level.IconMask or level.Mask
    S.StyleSquareIcon(level.Icon, iconMask, true)
    if level.HighlightTexture then
        S.StyleSquareIcon(level.HighlightTexture, iconMask)
    end
    if level.IconBorder then
        S.StyleIconBorder(level.IconBorder, level.Icon.BFIBackdrop)
    end
    if level.RewardCardBG then
        KeepTextureHidden(level.RewardCardBG)
        level.BFIRenownBackground = AF.CreateTexture(level, nil, "widget_dark", "BACKGROUND", -8)
        level.BFIRenownBackground:SetPoint("TOPLEFT", 3, -3)
        level.BFIRenownBackground:SetPoint("BOTTOMRIGHT", -3, 3)
        local trackMask = level:GetParent().Mask
        if trackMask then
            level.BFIRenownBackground:AddMaskTexture(trackMask)
        end
    end
end

local function UpdateRenownLevel(level, _, displayLevel, selected)
    if not IsEncounterJournalDescendant(level) then return end
    StyleRenownLevel(level)

    displayLevel = displayLevel or 0
    local levelNumber = level:GetLevel()
    local earned = levelNumber <= displayLevel
    local lastEarned = levelNumber == displayLevel
    local color = "widget_dark"
    local alpha = 1

    if selected then
        color = "BFI"
        alpha = 0.3
    elseif lastEarned then
        color = "widget_highlight"
    elseif earned then
        color = "widget"
    end

    if level.BFIRenownBackground then
        level.BFIRenownBackground:SetColorTexture(AF.GetColorRGB(color, alpha))
    end

    local levelTexture = level.LevelSquare or level.LevelRectangle
    if levelTexture then
        SetFlatTexture(levelTexture, selected and "BFI" or color, selected and 0.65 or alpha)
        AF.SetSize(levelTexture, level.LevelSquare and 30 or 28, level.LevelSquare and 22 or 18)
    end

    level.Level:SetTextColor(AF.GetColorRGB(earned and "white" or "disabled"))
    level.Icon.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
end

---------------------------------------------------------------------
-- hooks
---------------------------------------------------------------------
local function HookMixin(mixin, method, callback)
    if mixin and mixin[method] then
        hooksecurefunc(mixin, method, callback)
    end
end

local function RegisterHooks()
    hooksecurefunc("EncounterJournal_ListInstances", StyleInstanceList)
    hooksecurefunc("EncounterJournal_DisplayInstance", function()
        StyleEncounterBackgrounds()
        StyleInstanceHeaderIcon()
        LayoutEncounterTabs()
    end)
    hooksecurefunc("EncounterJournal_DisplayEncounter", function()
        StyleEncounterInfoHeaders()
        LayoutEncounterTabs()
    end)
    hooksecurefunc("EncounterJournal_UpdateButtonState", function(button)
        StyleEncounterInfoHeader(button:GetParent())
    end)
    hooksecurefunc("EncounterJournal_ToggleHeaders", StyleEncounterInfoHeaders)
    hooksecurefunc("EncounterJournal_SetUpOverview", StyleEncounterInfoHeaders)
    hooksecurefunc("EncounterJournal_SetBullets", function(object)
        local owner = object and object:GetParent()
        for _, bullet in ipairs(owner and owner.Bullets or {}) do
            StyleEncounterBullet(bullet)
        end
    end)
    hooksecurefunc("EncounterJournal_ShowCreatures", StyleCreatureButtons)
    hooksecurefunc("EncounterJournal_CheckAndDisplaySuggestedContentTab", LayoutBottomTabs)
    hooksecurefunc("EncounterJournal_CheckAndDisplayTradingPostTab", LayoutBottomTabs)
    EncounterJournal:HookScript("OnShow", LayoutBottomTabs)
    hooksecurefunc(EncounterJournal.instanceSelect.ScrollBox, "Update", function(scrollBox)
        scrollBox:ForEachFrame(StyleInstanceButton)
    end)

    HookMixin(_G.EncounterBossButtonMixin, "Init", StyleBossButton)
    HookMixin(_G.EncounterJournalItemMixin, "Init", StyleEncounterItem)
    HookMixin(_G.EncounterJournalItemHeaderMixin, "Init", StyleEncounterItemHeader)
    HookMixin(_G.EncounterSearchResultLGMixin, "Init", StyleSearchResult)

    HookMixin(_G.MonthlyActivitiesButtonMixin, "Init", StyleMonthlyActivityButton)
    HookMixin(_G.MonthlySupersedeActivitiesButtonMixin, "Init", StyleMonthlyActivityButton)
    HookMixin(_G.MonthlyActivitiesButtonMixin, "UpdateButtonStateShared", StyleMonthlyActivityButton)
    HookMixin(_G.MonthlyActivitiesFilterListButtonMixin, "Init", StyleMonthlyFilterButton)
    HookMixin(_G.MonthlyActivitiesRewardButtonMixin, "OnLoad", StyleMonthlyRewardButton)
    hooksecurefunc(EncounterJournal.MonthlyActivitiesFrame, "SetThresholds", StyleMonthlyThresholds)

    HookMixin(_G.RuneforgeLegendaryPowerLootJournalMixin, "Init", StyleRuneforgePower)
    hooksecurefunc(EncounterJournal.LootJournalItems.ItemSetsFrame, "ConfigureItemButton", function(_, button)
        StyleLootJournalSetItem(button)
    end)
    HookMixin(_G.LootJournalItemSetButtonMixin, "Init", StyleLootJournalSet)

    local journeys = EncounterJournal.JourneysFrame
    hooksecurefunc(journeys, "Refresh", StyleJourneyList)
    hooksecurefunc(journeys.JourneysList, "Update", function(scrollBox)
        scrollBox:ForEachFrame(StyleJourneyListFrame)
    end)
    hooksecurefunc(journeys.JourneyProgress, "SetRewards", StyleJourneyRewards)
    hooksecurefunc(journeys.JourneyOverview.Highlights, "DisplayHighlights", StyleJourneyHighlights)
    HookMixin(_G.RenownLevelMixin, "TryInit", StyleRenownLevel)
    HookMixin(_G.RenownLevelMixin, "Refresh", UpdateRenownLevel)
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    EncounterJournal = _G.EncounterJournal
    if not EncounterJournal then return end

    StyleShell()
    RegisterHooks()

    StyleInstanceList()
    StyleCreatureButtons()
    StyleExistingMonthlyFrames()
end

AF.RegisterAddonLoaded("Blizzard_EncounterJournal", StyleBlizzard)
