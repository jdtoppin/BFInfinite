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
-- Blizzard_Journeys}.{lua,xml} and Blizzard_FrameXML/RewardTrackTemplates.*.
-- PTR adds a circle Mask to RenownLevelCardTemplate; it is guarded below.

---------------------------------------------------------------------
-- local styles
---------------------------------------------------------------------
local function StyleArtFrame(frame)
    if not frame or frame._BFIEncounterArtStyled then return end
    frame._BFIEncounterArtStyled = true

    S.CreateBackdrop(frame, true)
    frame.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("BFI", 0.7))
end

local function StyleArtButton(button)
    if not button or button._BFIEncounterArtButtonStyled then return end
    button._BFIEncounterArtButtonStyled = true

    StyleArtFrame(button)
    button:HookScript("OnEnter", function(self)
        self.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("white", 0.8))
    end)
    button:HookScript("OnLeave", function(self)
        self.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("BFI", 0.7))
    end)
end

local function HideTextureWhenShown(texture, shown)
    if shown then
        AF.TextureHide(texture)
    end
end

local function KeepTextureHidden(texture)
    if texture._BFIEncounterHidden then return end
    texture._BFIEncounterHidden = true

    texture:Hide()
    hooksecurefunc(texture, "Show", AF.TextureHide)
    hooksecurefunc(texture, "SetShown", HideTextureWhenShown)
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
    AF.SetSize(tab, 50, 50)
    tab.unselected:ClearAllPoints()
    tab.unselected:SetPoint("CENTER")
    tab.selected:ClearAllPoints()
    tab.selected:SetPoint("CENTER")
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

local function StyleJourneys()
    local frame = EncounterJournal.JourneysFrame
    S.StyleScrollBar(frame.ScrollBar)
    S.RemoveTextures(frame.BorderFrame)
    StyleArtFrame(frame)

    local progress = frame.JourneyProgress
    S.StyleButton(progress.OverviewBtn, "BFI")
    S.StyleButton(progress.LevelSkipButton, "BFI")
    StyleArtButton(progress.DelvesCompanionConfigurationFrame.CompanionConfigBtn)
    StyleRewardTrackControls(progress.RenownTrackFrame)
    StyleRewardTrackControls(progress.EncounterRewardProgressFrame)

    S.StyleButton(frame.JourneyOverview.OverviewBtn, "BFI")
end

local function StyleMonthlyActivities()
    local frame = EncounterJournal.MonthlyActivitiesFrame
    S.StyleScrollBar(frame.ScrollBar)
    S.StyleScrollBar(frame.FilterList.ScrollBar)
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
                AF.SetPoint(tab, "TOPLEFT", info, "TOPRIGHT", 4, -35)
            end
            previousTab = tab
        end
    end
end

local function StyleEncounterControls()
    local instanceSelect = EncounterJournal.instanceSelect
    S.StyleDropdownButton(instanceSelect.ExpansionDropdown)
    S.StyleScrollBar(instanceSelect.ScrollBar)
    StyleArtButton(instanceSelect.GreatVaultButton)

    local info = EncounterJournal.encounter.info
    S.StyleScrollBar(info.BossesScrollBar)
    S.StyleScrollBar(info.detailsScroll.ScrollBar)
    S.StyleScrollBar(info.overviewScroll.ScrollBar)
    S.StyleScrollBar(info.LootContainer.ScrollBar)
    S.StyleScrollBar(EncounterJournal.encounter.instance.LoreScrollBar)
    S.StyleDropdownButton(info.difficulty)
    S.StyleDropdownButton(info.LootContainer.filter)
    S.StyleDropdownButton(info.LootContainer.slotFilter)
    local clearFilter = info.LootContainer.classClearFilter
    local clearFilterButton = _G[clearFilter:GetName() .. "ExitButton"]
    S.StyleIconButton(clearFilterButton, AF.GetIcon("Close"), 12, nil, "red")
    S.StyleIconButton(EncounterJournal.encounter.instance.mapButton, AF.GetIcon("World"), 18)

    local instanceButton = info.instanceButton
    instanceButton:SetNormalTexture(AF.GetEmptyTexture())
    instanceButton:SetHighlightTexture(AF.GetEmptyTexture())
    S.StyleIcon(instanceButton.icon, true)

    for _, tab in ipairs(GetEncounterTabs()) do
        StyleEncounterTab(tab)
    end
    LayoutEncounterTabs()
end

local function StyleShell()
    S.StyleTitledFrame(EncounterJournal)
    S.RemoveNineSliceAndBackground(EncounterJournal.inset)
    StyleArtFrame(EncounterJournal.inset)

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
    highlight:SetColorTexture(AF.GetColorRGB("BFI", 0.25))
    highlight:SetAllPoints()
    StyleArtButton(button)
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

---------------------------------------------------------------------
-- Monthly Activities pools
---------------------------------------------------------------------
local function StyleMonthlyActivityButton(button)
    StyleArtFrame(button)
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
        button:HookScript("OnEnter", function(self)
            self.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("BFI", 0.35))
        end)
        button:HookScript("OnLeave", function(self)
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
    if not frame.LockFrame then return end

    StyleArtFrame(frame)
    if frame.WatchedFactionToggleFrame then
        S.StyleCheckButton(frame.WatchedFactionToggleFrame.WatchFactionCheckbox)
    end
end

local function StyleJourneyList(frame)
    frame.JourneysList:ForEachFrame(StyleJourneyListFrame)
end

local function StyleJourneyReward(reward)
    if reward._BFIJourneyRewardStyled then return end
    reward._BFIJourneyRewardStyled = true

    S.StyleSquareIcon(reward.RewardCardIcon, reward.TextureMask, true)
    S.StyleIconBorder(reward.RewardCardIconBorderDefault, reward.RewardCardIcon.BFIBackdrop)
end

local function StyleJourneyRewards(frame)
    for reward in frame.rewardPool:EnumerateActive() do
        StyleJourneyReward(reward)
    end
end

local function StyleJourneyHighlight(highlight)
    StyleArtFrame(highlight)
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

local function UpdateRenownBorderState(border, atlas)
    local color = "border"
    if atlas and atlas:find("-yellow", 1, true) then
        color = "yellow"
    elseif atlas and atlas:find("-grey", 1, true) then
        color = "disabled"
    end
    border.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB(color))
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
        hooksecurefunc(level.IconBorder, "SetAtlas", UpdateRenownBorderState)
    end
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
    hooksecurefunc("EncounterJournal_DisplayInstance", LayoutEncounterTabs)
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
