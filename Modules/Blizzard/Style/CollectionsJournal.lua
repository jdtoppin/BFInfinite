---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local _G = _G

---------------------------------------------------------------------
-- shared
---------------------------------------------------------------------
local function StyleInset(frame, color)
    if not frame or frame._BFICollectionsInsetStyled then return end
    frame._BFICollectionsInsetStyled = true

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

local function StyleIconButtonStates(button, backdrop)
    if button._BFICollectionsStateStyled then return end
    button._BFICollectionsStateStyled = true

    StyleStateTexture(button.GetHighlightTexture and button:GetHighlightTexture(), backdrop, "white", 0.25)
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
    if not button or button._BFICollectionsRowStyled then return end
    button._BFICollectionsRowStyled = true

    -- These pooled rows carry collected, selected, favorite, and usability
    -- state in Blizzard-owned artwork. Add the BFI framing without replacing
    -- that state-bearing art with the generic button skin.
    S.CreateBackdrop(button, true)
    StyleSquareIcon(button.icon, button.iconBorder)
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
    StyleInset(frame.MountCount, "widget")
    S.StyleEditBox(frame.searchBox, -4)
    S.StyleDropdownButton(frame.FilterDropdown)
    S.StyleScrollBar(frame.ScrollBar)
    S.StyleButton(frame.MountButton, "BFI")

    StylePanelSpellButton(frame.SummonRandomFavoriteSpellFrame.Button)
    StylePanelSpellButton(frame.ToggleDynamicFlightFlyoutButton)

    local popup = frame.DynamicFlightFlyoutPopup
    StyleInset(popup, "widget")
    StylePanelSpellButton(popup.OpenDynamicFlightSkillTreeButton)
    StylePanelSpellButton(popup.DynamicFlightModeButton)
    S.StyleIcon(popup.DynamicFlightModeButton.texture)

    StyleSquareIcon(frame.BottomLeftInset.SlotButton.ItemIcon, frame.BottomLeftInset.SlotButton.ItemBorder)
    StyleSquareIcon(frame.MountDisplay.InfoButton.Icon)
    frame.ScrollBox:ForEachFrame(StyleCollectionListButton)
end

---------------------------------------------------------------------
-- pets
---------------------------------------------------------------------
local function StylePetLoadoutSlot(slot)
    if not slot or slot._BFICollectionsSlotStyled then return end
    slot._BFICollectionsSlotStyled = true

    StyleSquareIcon(slot.icon, slot.iconBorder, slot.qualityBorder)
    StyleProgressBar(slot.healthFrame and slot.healthFrame.healthBar)

    for i = 1, 3 do
        StyleLowercaseIconButton(slot["spell" .. i])
    end
end

local function StylePetCard(card)
    StyleSquareIcon(card.PetInfo.icon, card.PetInfo.qualityBorder)
    StyleProgressBar(card.HealthFrame.healthBar)
    StyleProgressBar(card.xpBar)

    for i = 1, 6 do
        StyleLowercaseIconButton(card["spell" .. i])
    end
end

local function StylePetJournal()
    local frame = _G.PetJournal

    StyleInset(frame.LeftInset, "widget_dark")
    StyleInset(frame.PetCardInset, "widget_dark")
    StyleInset(frame.RightInset, "widget_dark")
    StyleInset(frame.PetCount, "widget")
    S.StyleEditBox(frame.searchBox, -4)
    S.StyleDropdownButton(frame.FilterDropdown)
    S.StyleScrollBar(frame.ScrollBar)
    S.StyleButton(frame.FindBattleButton, "BFI")
    S.StyleButton(frame.SummonButton, "BFI")

    StylePanelSpellButton(frame.HealPetSpellFrame.Button)
    StylePanelSpellButton(frame.SummonRandomPetSpellFrame.Button)

    StylePetLoadoutSlot(frame.Loadout.Pet1)
    StylePetLoadoutSlot(frame.Loadout.Pet2)
    StylePetLoadoutSlot(frame.Loadout.Pet3)
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
    S.StyleDropdownButton(frame.FilterDropdown)
    StyleCollectionBackground(frame.iconsFrame)
    StylePagingFrame(frame.PagingFrame)

    for i = 1, 18 do
        StyleCollectionSpellButton(frame.iconsFrame["spellButton" .. i])
    end
end

---------------------------------------------------------------------
-- heirlooms
---------------------------------------------------------------------
local function StyleHeirloomButton(_, button)
    StyleCollectionSpellButton(button)
end

local function StyleHeirlooms()
    local frame = _G.HeirloomsJournal

    StyleProgressBar(frame.progressBar, "lime")
    S.StyleEditBox(frame.SearchBox, -4)
    S.StyleDropdownButton(frame.FilterDropdown)
    S.StyleDropdownButton(frame.ClassDropdown)
    StyleCollectionBackground(frame.iconsFrame)
    StylePagingFrame(frame.PagingFrame)

    for _, button in next, frame.heirloomEntryFrames do
        StyleCollectionSpellButton(button)
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

local function StyleWardrobeSetButton(button)
    if button._BFICollectionsRowStyled then return end
    button._BFICollectionsRowStyled = true

    -- Preserve the set progress, selected, favorite, and unavailable visuals.
    S.CreateBackdrop(button, true)
    StyleSquareIcon(button.IconFrame.Icon)
end

local function StyleWardrobeSetItem(item)
    if item._BFICollectionsIconStyled then return end
    item._BFICollectionsIconStyled = true

    StyleSquareIcon(item.Icon, item.IconBorder)
end

local function StyleWardrobeSetButtons(scrollBox)
    scrollBox:ForEachFrame(StyleWardrobeSetButton)
end

local function StyleWardrobeSetItems(frame)
    for item in frame.DetailsFrame.itemFramesPool:EnumerateActive() do
        StyleWardrobeSetItem(item)
    end
end

local function StyleWardrobe()
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
    S.StyleDropdownButton(frame.FilterButton)
    S.StyleDropdownButton(frame.ClassDropdown)

    StyleCollectionBackground(itemsFrame)
    StylePagingFrame(itemsFrame.PagingFrame)
    S.StyleDropdownButton(itemsFrame.WeaponDropdown)
    StyleWardrobeSlotButtons(itemsFrame)

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
    if entry._BFICollectionsCardStyled then return end
    entry._BFICollectionsCardStyled = true

    -- The scene thumbnail, favorite marker, name plate, and hover frame are
    -- semantic card state, so retain them and add only the shared BFI edge.
    S.CreateBackdrop(entry, true)
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
    -- (Gethe wow-ui-source 4383ced) and PTR 12.1.0.68914
    -- (Gethe wow-ui-source d3915c7). The Collections XML surface is stable
    -- between those pinned artifacts.
    hooksecurefunc("MountJournal_InitMountButton", StyleCollectionListButton)
    hooksecurefunc("PetJournal_InitPetButton", StyleCollectionListButton)
    hooksecurefunc("ToySpellButton_UpdateButton", StyleCollectionSpellButton)
    hooksecurefunc(_G.HeirloomsJournal, "UpdateButton", StyleHeirloomButton)
    hooksecurefunc(_G.WardrobeCollectionFrame.ItemsCollectionFrame, "CreateSlotButtons", StyleWardrobeSlotButtons)
    hooksecurefunc(_G.WardrobeSetsScrollFrameButtonMixin, "Init", StyleWardrobeSetButton)
    hooksecurefunc(_G.WardrobeSetsDetailsItemMixin, "OnShow", StyleWardrobeSetItem)
    hooksecurefunc(_G.WarbandSceneEntryMixin, "Init", StyleWarbandSceneEntry)

    S.StyleTitledFrame(collectionsJournal)
    StyleTabs(collectionsJournal)
    StyleMountJournal()
    StylePetJournal()
    StyleToyBox()
    StyleHeirlooms()
    StyleWardrobe()
    StyleWarbandScenes()
end

AF.RegisterAddonLoaded("Blizzard_Collections", StyleBlizzard)
