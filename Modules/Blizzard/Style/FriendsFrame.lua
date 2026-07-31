---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local legacyHooksInstalled
local socialHooksInstalled
local recentAlliesHooksInstalled
local quickJoinHooksInstalled

-- Blizzard exposes the remote project ID, but ships only Retail and
-- Classic-family logo atlases. WOW_PROJECT_MISTS_CLASSIC is 19.
local WOW_PROJECT_ATLAS = {
    [1] = "logo-wow-retail",
    [2] = "logo-wow-classic",
    [5] = "logo-wow-classic",
    [11] = "logo-wow-classic",
    [14] = "logo-wow-classic",
    [19] = "logo-wow-classic",
}

---------------------------------------------------------------------
-- shared
---------------------------------------------------------------------
local function StyleButton(button, color)
    if button then
        S.StyleButton(button, color)
    end
end

local function StyleDropdown(dropdown)
    if dropdown then
        S.StyleDropdownButton(dropdown)
    end
end

local function SetFlatTexture(texture, color, alpha, blendMode)
    if not texture then return end

    texture:SetColorTexture(AF.GetColorRGB(color, alpha))
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetBlendMode(blendMode or "BLEND")
end

local function SetBrightHighlight(texture, alpha)
    SetFlatTexture(texture, "white", alpha or 0.2)
end

local function StyleArtworkButton(button, artwork)
    if not button or button._BFIStyled then return end

    local icon = artwork or button.Icon
    local atlas = icon and icon:GetAtlas()
    local texture = icon and icon:GetTexture()
    local width = icon and icon:GetWidth()
    local height = icon and icon:GetHeight()
    local texCoords = icon and {icon:GetTexCoord()}

    S.StyleButton(button)

    if icon then
        if atlas then
            icon:SetAtlas(atlas, false)
        elseif texture then
            icon:SetTexture(texture)
        end

        if texCoords and #texCoords > 0 then
            icon:SetTexCoord(unpack(texCoords))
        end
        if width and height then
            icon:SetSize(width, height)
        end

        icon:SetAlpha(1)
        icon:Show()
    end
end

local function StyleSocialActionButton(button)
    if not button or button._BFISocialActionStyled then return end
    button._BFISocialActionStyled = true

    -- SocialCardActionButtonMixin moves ActionIcon on mouse down/up. Keep
    -- those scripts and the dynamically selected atlas, replacing only the
    -- Blizzard button chrome.
    button:SetNormalTexture(AF.GetEmptyTexture())
    button:SetPushedTexture(AF.GetEmptyTexture())
    button:SetHighlightTexture(AF.GetEmptyTexture())
    button:SetDisabledTexture(AF.GetEmptyTexture())

    button._BFINormalColor = AF.GetButtonNormalColor("BFI_hover")
    button._BFIHoverColor = AF.GetButtonHoverColor("BFI_hover")

    S.CreateBackdrop(button)
    button.BFIBackdrop:SetBackdropColor(AF.UnpackColor(button._BFINormalColor))
    button.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))

    button:HookScript("OnEnter", function(self)
        if self:IsEnabled() then
            self.BFIBackdrop:SetBackdropColor(AF.UnpackColor(self._BFIHoverColor))
        end
    end)
    button:HookScript("OnLeave", function(self)
        self.BFIBackdrop:SetBackdropColor(AF.UnpackColor(self._BFINormalColor))
    end)
    button:HookScript("OnDisable", function(self)
        self.BFIBackdrop:SetBackdropColor(AF.UnpackColor(self._BFINormalColor))
    end)
end

local function StylePlainDialog(frame)
    if not frame or frame._BFIPlainDialogStyled then return end
    frame._BFIPlainDialogStyled = true

    if frame.Border then
        frame.Border:SetAlpha(0)
    end
    S.RemoveNineSliceAndBackground(frame)
    S.CreateBackdrop(frame)

    frame.BFITopStrip = AF.CreateTexture(frame, nil, "BFI")
    AF.SetPoint(frame.BFITopStrip, "TOPLEFT", frame.BFIBackdrop, 1, -1)
    AF.SetPoint(frame.BFITopStrip, "TOPRIGHT", frame.BFIBackdrop, -1, -1)
    AF.SetHeight(frame.BFITopStrip, 2)

    if frame.CloseButton then
        S.StyleCloseButton(frame.CloseButton)
        AF.ClearPoints(frame.CloseButton)
        AF.SetPoint(frame.CloseButton, "TOPRIGHT")
    end
end

local function StyleTitledDialog(frame, sourceTitle)
    if not frame or not sourceTitle then return end

    if frame.Border then
        frame.Border:SetAlpha(0)
    end

    -- AddFriendFrame is a ResizeLayoutFrame on PTR 12.1.0.68914. Give the
    -- shared titled-frame skin a root-owned title, while leaving Blizzard's
    -- nested title in the layout so repeated Info/Entry resizing is stable.
    frame.Title = frame:CreateFontString(nil, "OVERLAY")
    local fontObject = sourceTitle:GetFontObject()
    if fontObject then
        frame.Title:SetFontObject(fontObject)
    end
    frame.Title:SetText(sourceTitle:GetText())
    frame.Title.ignoreInLayout = true
    sourceTitle:SetAlpha(0)

    S.StyleTitledFrame(frame, false)
    frame.BFIBg.ignoreInLayout = true
    frame.BFIHeader.ignoreInLayout = true
end

local function StyleRoleIcon(icon, role)
    if not icon or icon._BFIRoleStyled then return end
    icon._BFIRoleStyled = true

    -- AF's second role sheet stays sharp at both the 17px legacy size and the
    -- 24px Social UI size. Retain Blizzard's atlas on older AF versions.
    if AF.SetRoleIcon then
        AF.SetRoleIcon(icon, 2, role)
    end
    S.CreateBackdrop(icon, true, nil, 1)
end

local function StyleCheckButtonWithArtwork(button, size, artwork)
    if not button then return end

    local atlas = artwork and artwork:GetAtlas()
    local texture = artwork and artwork:GetTexture()
    local width = artwork and artwork:GetWidth()
    local height = artwork and artwork:GetHeight()
    local texCoords = artwork and {artwork:GetTexCoord()}

    S.StyleCheckButton(button, size)

    -- StyleCheckButton clears direct texture regions. The modern Raid assist
    -- checkbox also owns a semantic assistant icon, so restore that artwork.
    if artwork then
        if atlas then
            artwork:SetAtlas(atlas, false)
        elseif texture then
            artwork:SetTexture(texture)
        end
        if texCoords and #texCoords > 0 then
            artwork:SetTexCoord(unpack(texCoords))
        end
        if width and height then
            artwork:SetSize(width, height)
        end
        artwork:SetAlpha(1)
        artwork:Show()
    end
end

local function StyleSquarePortrait(icon, owner, mask)
    if not icon or not owner or not owner.BFIHeader then return end

    -- Keep Blizzard's portrait region available to its own update code, but
    -- display the project logo in the 20px BFI header so it cannot overlap
    -- the title or the Raid/Social content below it.
    icon:SetAlpha(0)
    if mask then
        mask:SetAlpha(0)
    end

    local atlas = WOW_PROJECT_ATLAS[_G.WOW_PROJECT_ID]
    if not atlas or not _G.C_Texture.GetAtlasInfo(atlas) then
        return
    end

    if not owner.BFIProjectIcon then
        owner.BFIProjectIcon = owner.BFIHeader:CreateTexture(nil, "ARTWORK")
        S.StyleIcon(owner.BFIProjectIcon, true)
        AF.SetSize(owner.BFIProjectIcon, 16, 16)
        AF.SetPoint(owner.BFIProjectIcon, "LEFT", owner.BFIHeader, 3, 0)
    end

    owner.BFIProjectIcon:SetAtlas(atlas, false)
end

local function SetWoWProjectIcon(icon, gameAccountInfo)
    if not gameAccountInfo or gameAccountInfo.clientProgram ~= _G.BNET_CLIENT_WOW then return end

    local atlas = WOW_PROJECT_ATLAS[gameAccountInfo.wowProjectID]
    if atlas and _G.C_Texture.GetAtlasInfo(atlas) then
        icon:SetAtlas(atlas, false)
    end
end

-- PTR 12.1.0.68914 FriendsListUtil still colors the character name with
-- NORMAL_FONT_COLOR; only its separate class label receives the class color.
local function GetClassColoredCharacterName(accountInfo, includeBrackets)
    local gameAccountInfo = accountInfo and accountInfo.gameAccountInfo
    local classFilename = gameAccountInfo and gameAccountInfo.classFilename
    -- Live 12.0.7 exposes only classID; 12.1 adds classFilename.
    if not classFilename and gameAccountInfo and gameAccountInfo.classID then
        local classInfo = _G.C_CreatureInfo.GetClassInfo(gameAccountInfo.classID)
        classFilename = classInfo and classInfo.classFile
    end

    if not gameAccountInfo
        or gameAccountInfo.clientProgram ~= _G.BNET_CLIENT_WOW
        or not gameAccountInfo.isOnline
        or not classFilename
        or classFilename == ""
    then
        return
    end

    local characterName = _G.FriendsFrame_GetFormattedCharacterName(
        gameAccountInfo.characterName,
        accountInfo.battleTag,
        gameAccountInfo.clientProgram,
        gameAccountInfo.timerunningSeasonID
    )
    if not characterName or characterName == "" then return end

    if includeBrackets
        and not _G.CanCooperateWithGameAccount(accountInfo)
        and _G.CVarCallbackRegistry:GetCVarValueBool("colorblindMode")
    then
        characterName = gameAccountInfo.characterName .. _G.CANNOT_COOPERATE_LABEL
    end

    if includeBrackets then
        characterName = "(" .. characterName .. ")"
    end

    local classColor = _G.GetClassColorObj(classFilename)
    return classColor and classColor:WrapTextInColorCode(characterName)
end

---------------------------------------------------------------------
-- legacy FriendsFrame (live, and the 12.1 Who fallback)
---------------------------------------------------------------------
local function StyleLegacyPartyButton(button, owner)
    if not button then return end

    if not button._BFIStyled then
        S.StyleIconButton(button, AF.GetIcon("Plus_Small"), 12, nil, "BFI_hover")
        AF.SetSize(button, 24, 24)
        AF.ClearPoints(button)
        AF.SetPoint(button, "RIGHT", owner, -1, 0)
    end

    -- FriendsFrame_UpdateFriendButton reapplies faction-specific Blizzard
    -- state atlases on every refresh. Clear those after the update while
    -- retaining the BFI icon and the native invite click/tooltip scripts.
    button:SetNormalTexture(AF.GetEmptyTexture())
    button:SetPushedTexture(AF.GetEmptyTexture())
    button:SetHighlightTexture(AF.GetEmptyTexture())
    button:SetDisabledTexture(AF.GetEmptyTexture())
end

local function StyleLegacyFriendButton(button)
    if not button or not button.background or not button.gameIcon then return end

    if not button._BFIFriendStyled then
        button._BFIFriendStyled = true
        S.StyleIcon(button.gameIcon, true)
    end

    SetFlatTexture(button.background, "widget_dark", 0.65)
    SetBrightHighlight(button.highlight)
    button:UnlockHighlight()
    StyleLegacyPartyButton(button.travelPassButton, button)

    if button.buttonType == _G.FRIENDS_BUTTON_TYPE_BNET then
        local accountInfo = _G.C_BattleNet.GetFriendAccountInfo(button.id)
        SetWoWProjectIcon(button.gameIcon, accountInfo and accountInfo.gameAccountInfo)

        local characterName = GetClassColoredCharacterName(accountInfo, true)
        if characterName then
            button.name:SetText(_G.BNet_GetBNetAccountName(accountInfo) .. " " .. characterName)
        end
    end

    button.gameIcon.BFIBackdrop:SetShown(button.gameIcon:IsShown())
end

local function StyleLegacyInvite(button)
    if not button or not button.Background then return end

    SetFlatTexture(button.Background, "widget_dark", 0.65)
    StyleButton(button.AcceptButton, "BFI")

    local declineButton = button.DeclineButton
    if declineButton.Icon and not declineButton._BFIStyled then
        S.StyleIconButton(declineButton, AF.GetIcon("Close"), 12, nil, "widget")
    else
        StyleButton(declineButton)
    end
end

local function StyleLegacyInviteHeader(button)
    if not button or not button.BG then return end

    if not button._BFIInviteHeaderStyled then
        button._BFIInviteHeaderStyled = true
        S.RemoveRegions(button)
        S.CreateBackdrop(button)
    end

    SetFlatTexture(button.BG, "widget_dark", 0.75)
    SetBrightHighlight(button:GetHighlightTexture())
end

local function StyleLegacyListElement(button)
    if button and button.gameIcon then
        StyleLegacyFriendButton(button)
    elseif button and button.AcceptButton then
        StyleLegacyInvite(button)
    elseif button and button.BG then
        StyleLegacyInviteHeader(button)
    end
end

local function StyleRecentAllyButton(button)
    if not button or not button.GetNormalTexture then return end

    SetFlatTexture(button.NormalTexture or button:GetNormalTexture(), "widget_dark", 0.65)
    SetBrightHighlight(button.HighlightTexture or button:GetHighlightTexture())
end

local function StyleLegacyTabs(frame)
    local tabSystem = frame.FriendsTabHeader and frame.FriendsTabHeader.TabSystem
    if tabSystem then
        S.StyleTabSystem(tabSystem, true)
    end

    local previous
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            S.StyleTab(tab)
            AF.ClearPoints(tab)
            if previous then
                AF.SetPoint(tab, "TOPLEFT", previous, "TOPRIGHT", 1, 0)
            else
                AF.SetPoint(tab, "TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
            end
            previous = tab
        end
    end
end

local function StyleWhoFrame(whoFrame)
    if not whoFrame then return end

    local editBox = whoFrame.EditBox or _G.WhoFrameEditBox
    if editBox then
        -- SearchBoxTemplate's extra glue-style Backdrop is not one of the
        -- generic Left/Middle/Right regions removed by StyleEditBox.
        if editBox.Backdrop then
            editBox.Backdrop:SetAlpha(0)
        end
        S.StyleEditBox(editBox, -4)
    end
    S.RemoveNineSliceAndBackground(whoFrame.WhoFrameListInset)
    StyleDropdown(_G.WhoFrameDropdown)
    StyleButton(_G.WhoFrameGroupInviteButton)
    StyleButton(_G.WhoFrameAddFriendButton)
    StyleButton(_G.WhoFrameWhoButton)
    S.StyleScrollBar(whoFrame.ScrollBar)

    for i = 1, 4 do
        StyleButton(_G["WhoFrameColumnHeader" .. i], "widget")
    end
end

local function StyleWhoListButton(button)
    if button and button.GetHighlightTexture then
        SetBrightHighlight(button:GetHighlightTexture())
    end
end

local function StyleAddFriendFrame()
    local frame = _G.AddFriendFrame
    if frame and not frame._BFIAddFriendStyled then
        frame._BFIAddFriendStyled = true

        local entryFrame = frame.EntryFrame
        local titleContainer = entryFrame and entryFrame.TitleContainer
        if titleContainer and titleContainer.Title then
            StyleTitledDialog(frame, titleContainer.Title)
        else
            StylePlainDialog(frame)
        end

        local infoFrame = frame.InfoFrame
        if infoFrame then
            StyleButton(infoFrame.OkayButton or infoFrame.ContinueButton)
        end

        local editBoxContainer = entryFrame and entryFrame.EditBoxContainer
        local nameEditBox = (editBoxContainer and editBoxContainer.NameEditBox)
            or (entryFrame and entryFrame.NameEditBox)
            or _G.AddFriendNameEditBox
        if nameEditBox then
            S.StyleEditBox(nameEditBox, -4)
        end

        StyleButton((editBoxContainer and editBoxContainer.AcceptButton)
            or (entryFrame and entryFrame.AcceptButton)
            or _G.AddFriendEntryFrameAcceptButton)
        StyleButton((editBoxContainer and editBoxContainer.CancelButton)
            or (entryFrame and entryFrame.CancelButton)
            or _G.AddFriendEntryFrameCancelButton)
    end

    local inviteFrame = _G.BattleNetInviteFrame
    if inviteFrame and not inviteFrame._BFIBattleNetInviteStyled then
        inviteFrame._BFIBattleNetInviteStyled = true
        StylePlainDialog(inviteFrame)
        StyleButton(inviteFrame.SendButton)
        StyleButton(inviteFrame.CancelButton)
    end
end

local function StyleLegacyRaidFrame()
    local raidFrame = _G.RaidFrame
    if not raidFrame or raidFrame._BFILegacyRaidStyled then return end
    raidFrame._BFILegacyRaidStyled = true

    StyleButton(_G.RaidFrameRaidInfoButton)
    StyleButton(_G.RaidFrameConvertToRaidButton)

    if _G.RaidFrameAllAssistCheckButton then
        S.StyleCheckButton(_G.RaidFrameAllAssistCheckButton, 14)
    end

    local roleCount = raidFrame.RoleCount
    if roleCount then
        StyleRoleIcon(roleCount.TankIcon, "TANK")
        StyleRoleIcon(roleCount.HealerIcon, "HEALER")
        StyleRoleIcon(roleCount.DamagerIcon, "DAMAGER")
    end

    local notInRaid = raidFrame.RaidFrameNotInRaid
    if notInRaid and notInRaid.ScrollingDescriptionScrollBar then
        S.StyleScrollBar(notInRaid.ScrollingDescriptionScrollBar)
    end
end

local function StyleLegacyIgnoreList(ignoreList)
    if not ignoreList then return end

    S.StyleTitledFrame(ignoreList)
    StyleButton(ignoreList.UnignorePlayerButton)
    S.StyleScrollBar(ignoreList.ScrollBar)
end

local function StyleLegacyBroadcast(broadcast)
    if not broadcast then return end

    if broadcast.Border then
        broadcast.Border:SetAlpha(0)
    end
    S.CreateBackdrop(broadcast)
    S.StyleEditBox(broadcast.EditBox)
    StyleButton(broadcast.UpdateButton)
    StyleButton(broadcast.CancelButton)
end

local function InstallLegacyHooks()
    if legacyHooksInstalled then return end
    legacyHooksInstalled = true

    if _G.FriendsFrame_Update then
        hooksecurefunc("FriendsFrame_Update", function()
            StyleSquarePortrait(_G.FriendsFrameIcon, _G.FriendsFrame)
        end)
    end
    if _G.FriendsFrame_UpdateFriendButton then
        hooksecurefunc("FriendsFrame_UpdateFriendButton", StyleLegacyFriendButton)
    end
    if _G.FriendsFrame_FriendButtonSetSelection then
        hooksecurefunc("FriendsFrame_FriendButtonSetSelection", function(button)
            -- Selection remains available to Send Message and context actions,
            -- but the Contacts list has no persistent active-row state.
            button:UnlockHighlight()
        end)
    end
    if _G.FriendsFrame_UpdateFriendInviteButton then
        hooksecurefunc("FriendsFrame_UpdateFriendInviteButton", StyleLegacyInvite)
    end
    if _G.FriendsFrame_UpdatePartyInviteButton then
        hooksecurefunc("FriendsFrame_UpdatePartyInviteButton", StyleLegacyInvite)
    end
    if _G.FriendsFrame_UpdateFriendInviteHeaderButton then
        hooksecurefunc("FriendsFrame_UpdateFriendInviteHeaderButton", StyleLegacyInviteHeader)
    end
    if _G.FriendsFrame_UpdatePartyInviteHeaderButton then
        hooksecurefunc("FriendsFrame_UpdatePartyInviteHeaderButton", StyleLegacyInviteHeader)
    end
    if _G.WhoList_InitButton then
        hooksecurefunc("WhoList_InitButton", StyleWhoListButton)
    end
end

local function StyleLegacyFriendsFrame()
    local frame = _G.FriendsFrame
    if not frame or frame._BFIFriendsStyled then return end
    frame._BFIFriendsStyled = true

    S.StyleTitledFrame(frame)
    S.RemoveNineSliceAndBackground(frame.Inset)
    StyleSquarePortrait(_G.FriendsFrameIcon, frame)
    StyleLegacyTabs(frame)

    local header = frame.FriendsTabHeader
    StyleDropdown(header.StatusDropdown)
    StyleArtworkButton(header.BattlenetFrame.ContactsMenuButton)

    S.RemoveTextures(header.BattlenetFrame)
    S.CreateBackdrop(header.BattlenetFrame)
    header.BattlenetFrame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_dark"))

    StyleButton(_G.FriendsFrameAddFriendButton, "BFI")
    StyleButton(_G.FriendsFrameSendMessageButton)
    S.StyleScrollBar(_G.FriendsListFrame.ScrollBar)
    _G.FriendsListFrame.ScrollBox:ForEachFrame(StyleLegacyListElement)

    StyleWhoFrame(_G.WhoFrame)
    if _G.WhoFrame and _G.WhoFrame.ScrollBox then
        _G.WhoFrame.ScrollBox:ForEachFrame(StyleWhoListButton)
    end
    StyleLegacyIgnoreList(frame.IgnoreListWindow)
    StyleLegacyBroadcast(header.BattlenetFrame.BroadcastFrame)
    StyleAddFriendFrame()
    StyleLegacyRaidFrame()

    InstallLegacyHooks()
end

---------------------------------------------------------------------
-- 12.1 SocialUI
---------------------------------------------------------------------
local function LayoutSocialTabIcon(tab, yOffset)
    local icon = tab and tab.Icon
    if not icon then return end

    AF.SetSize(icon, 24, 24)
    AF.ClearPoints(icon)
    AF.SetPoint(icon, "CENTER", 0, (tab.iconBaseYOffset or 0) + (yOffset or 0))
end

local function StyleSocialTab(tab)
    S.StyleSideTab(tab)

    if not tab._BFISocialIconLayoutHooked then
        tab._BFISocialIconLayoutHooked = true
        hooksecurefunc(tab, "SetChecked", function(self)
            LayoutSocialTabIcon(self)
        end)
        hooksecurefunc(tab, "RefreshIconAnchoring", function(self)
            LayoutSocialTabIcon(self)
        end)
        tab:HookScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and self:IsEnabled() then
                LayoutSocialTabIcon(self, -1)
            end
        end)
        tab:HookScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                LayoutSocialTabIcon(self)
            end
        end)
    end

    LayoutSocialTabIcon(tab)
end

local function LayoutSocialTabs(frame)
    local previous
    for _, tabData in ipairs(frame.availableTabData or {}) do
        local tab = frame:GetTabByType(tabData.tabType)
        if tab then
            StyleSocialTab(tab)
            AF.ClearPoints(tab)
            if previous then
                AF.SetPoint(tab, "TOPLEFT", previous, "BOTTOMLEFT", 0, -1)
            else
                AF.SetPoint(tab, "TOPLEFT", frame, "TOPRIGHT", 4, -122)
            end
            previous = tab
        end
    end
end

local function StyleSocialCard(card)
    if not card or not card.Background then return end

    if not card._BFISocialCardStyled then
        card._BFISocialCardStyled = true

        local gameIcon = card.GameIconHolder and card.GameIconHolder.Icon
        if gameIcon then
            S.StyleIcon(gameIcon, true)
        end
    end

    SetFlatTexture(card.Background, "widget_dark", 0.7)
    SetBrightHighlight(card:GetHighlightTexture())
    card:SetHighlightLocked(false)

    StyleSocialActionButton(card.PartyButton)
    StyleSocialActionButton(card.RAFSummonButton)

    local gameIconHolder = card.GameIconHolder
    if gameIconHolder and gameIconHolder.Icon and gameIconHolder.Icon.BFIBackdrop then
        local accountInfo = card.elementData and card.elementData.accountInfo
        SetWoWProjectIcon(gameIconHolder.Icon, accountInfo and accountInfo.gameAccountInfo)
        gameIconHolder.Icon.BFIBackdrop:SetShown(gameIconHolder:IsShown())

        local characterName = GetClassColoredCharacterName(accountInfo)
        if characterName and card.Name then
            card.Name:SetText(characterName)
        end
    end
end

local function StyleFriendRequestCard(card)
    if not card or not card.Background then return end

    SetFlatTexture(card.Background, "widget_dark", 0.7)
    SetBrightHighlight(card:GetHighlightTexture())
    card:SetHighlightLocked(false)
    StyleButton(card.AcceptButton, "BFI")
    if not card.DeclineButton._BFIStyled then
        S.StyleIconButton(card.DeclineButton, AF.GetIcon("Close"), 12, nil, "widget")
    end
end

local function MatchSocialFilterHeight(filterBar)
    local dropdown = filterBar and filterBar.SearchFilterDropdown
    local searchBar = filterBar and filterBar.SearchBar
    if dropdown and searchBar then
        dropdown:SetHeight(searchBar:GetHeight())
    end
end

local function StyleSocialContent(content)
    if not content or content._BFISocialContentStyled then return end
    content._BFISocialContentStyled = true

    if content.TopDivider then
        SetFlatTexture(content.TopDivider, "border", 0.8)
    end
    if content.BottomDivider then
        SetFlatTexture(content.BottomDivider, "border", 0.8)
    end

    local filterBar = content.FilterBar
    if filterBar then
        StyleDropdown(filterBar.SearchFilterDropdown)
        S.StyleEditBox(filterBar.SearchBar)

        -- SocialUIShared uses different base heights and text-scale weights
        -- for these controls. Reconcile after TextSizeManager updates all of
        -- its registered objects so callback iteration order cannot undo it.
        if not filterBar._BFIFilterHeightHooked then
            filterBar._BFIFilterHeightHooked = true
            _G.EventRegistry:RegisterCallback(
                "TextSizeManager.OnTextScaleUpdated",
                MatchSocialFilterHeight,
                filterBar
            )
        end
        MatchSocialFilterHeight(filterBar)
    end

    StyleButton(content.ActionButton, "BFI")
    if content.ScrollBar then
        S.StyleScrollBar(content.ScrollBar)
    end
end

local function StyleRecentAllies()
    local recentAlliesFrame = _G.RecentAlliesFrame
    local list = recentAlliesFrame and recentAlliesFrame.List
    if list then
        S.StyleScrollBar(list.ScrollBar)
        list.ScrollBox:ForEachFrame(StyleRecentAllyButton)
    end

    local socialFrame = _G.SocialUIFrame
    if socialFrame then
        StyleSocialContent(socialFrame.RecentAlliesList)
    end

    if recentAlliesHooksInstalled then return end

    local hooked
    if _G.RecentAlliesEntryMixin then
        hooksecurefunc(_G.RecentAlliesEntryMixin, "Initialize", StyleRecentAllyButton)
        hooked = true
    end
    if _G.RecentAlliesSocialCardMixin then
        hooksecurefunc(_G.RecentAlliesSocialCardMixin, "Initialize", StyleSocialCard)
        hooked = true
    end
    recentAlliesHooksInstalled = hooked
end

local function StyleSocialIgnoreList(ignoreList)
    if not ignoreList then return end

    S.StyleTitledFrame(ignoreList)
    StyleButton(ignoreList.BlockButton)
    StyleButton(ignoreList.UnblockButton)
    S.StyleScrollBar(ignoreList.ScrollBar)
end

local function StyleSocialBroadcast(broadcast)
    if not broadcast then return end

    if broadcast.Border then
        broadcast.Border:SetAlpha(0)
    end
    S.CreateBackdrop(broadcast)
    S.StyleEditBox(broadcast.EditBox)
    StyleButton(broadcast.UpdateButton)
    StyleButton(broadcast.CancelButton)
end

local function StyleQuickJoinButton(button)
    if not button or not button.Background then return end

    SetFlatTexture(button.Background, "widget_dark", 0.65)
    SetBrightHighlight(button.Highlight)
    SetFlatTexture(button.Selected, "BFI", 0.45)
end

local function StyleQuickJoin()
    local legacyFrame = _G.QuickJoinFrame
    if legacyFrame then
        S.StyleScrollBar(legacyFrame.ScrollBar)
        StyleButton(legacyFrame.JoinQueueButton, "BFI")
        legacyFrame.ScrollBox:ForEachFrame(StyleQuickJoinButton)
    end

    local socialFrame = _G.SocialUIFrame
    local socialQuickJoin = socialFrame and socialFrame.QuickJoinFrame
    if socialQuickJoin then
        StyleSocialContent(socialQuickJoin)
        socialQuickJoin.ScrollBox:ForEachFrame(StyleQuickJoinButton)
    end

    if not quickJoinHooksInstalled and _G.QuickJoinButtonMixin then
        quickJoinHooksInstalled = true
        hooksecurefunc(_G.QuickJoinButtonMixin, "Init", StyleQuickJoinButton)
    end
end

local function InstallSocialHooks()
    if socialHooksInstalled then return end
    socialHooksInstalled = true

    if _G.SocialUITabMixin then
        hooksecurefunc(_G.SocialUITabMixin, "Initialize", StyleSocialTab)
    end
    if _G.FriendsListSocialCardMixin then
        hooksecurefunc(_G.FriendsListSocialCardMixin, "Initialize", StyleSocialCard)
        hooksecurefunc(_G.FriendsListSocialCardMixin, "SetSelected", function(card)
            card:SetHighlightLocked(false)
        end)
    end
    if _G.FriendRequestsListSocialCardMixin then
        hooksecurefunc(_G.FriendRequestsListSocialCardMixin, "Initialize", StyleFriendRequestCard)
        hooksecurefunc(_G.FriendRequestsListSocialCardMixin, "SetSelected", function(card)
            card:SetHighlightLocked(false)
        end)
    end
end

local function StyleSocialRaidFrame(raidFrame)
    if not raidFrame or raidFrame._BFISocialRaidStyled then return end
    raidFrame._BFISocialRaidStyled = true

    StyleButton(raidFrame.RaidInfoButton)
    StyleButton(raidFrame.ConvertToRaidButton)
    StyleCheckButtonWithArtwork(
        raidFrame.AllAssistCheckButton,
        14,
        raidFrame.AllAssistCheckButton and raidFrame.AllAssistCheckButton.Icon
    )

    StyleRoleIcon(raidFrame.TankFrame and raidFrame.TankFrame.Icon, "TANK")
    StyleRoleIcon(raidFrame.HealerFrame and raidFrame.HealerFrame.Icon, "HEALER")
    StyleRoleIcon(raidFrame.DamagerFrame and raidFrame.DamagerFrame.Icon, "DAMAGER")
end

local function StyleSocialUI()
    local frame = _G.SocialUIFrame
    if not frame or frame._BFISocialStyled then return end
    frame._BFISocialStyled = true

    -- PTR 12.1.0.68914 (Gethe wow-ui-source d3915c7) routes Contacts,
    -- Quick Join, and Raid through SocialUIFrame, but keeps FriendsFrame
    -- as the Who view and fallback. Both shells therefore remain styled.
    S.StyleTitledFrame(frame)
    frame.TopFade:SetAlpha(0)
    frame.BottomFade:SetAlpha(0)

    local portraitContainer = frame.PortraitContainer
    StyleSquarePortrait(portraitContainer.portrait, frame, portraitContainer.CircleMask)

    local battleNetBar = frame.BattleNetBar
    battleNetBar.Background:SetAlpha(0)
    local controls = battleNetBar.ControlsContainer
    SetFlatTexture(controls.BattleNetBackground, "widget_dark", 0.8)
    StyleDropdown(controls.OnlineStatusDropdown)
    StyleArtworkButton(controls.BattleNetMenuButton)

    if not frame._BFISocialTabLayoutHooked then
        frame._BFISocialTabLayoutHooked = true
        hooksecurefunc(frame, "RefreshTabs", LayoutSocialTabs)
    end
    LayoutSocialTabs(frame)
    frame:RefreshTabStates()

    for _, tabData in next, frame.tabDefinitions do
        StyleSocialContent(tabData.contentFrame)
    end

    local friendsList = frame.FriendsList
    if friendsList and friendsList.ScrollBox then
        friendsList.ScrollBox:ForEachFrame(StyleSocialCard)
    end

    local friendRequestsList = frame.FriendRequestsList
    if friendRequestsList and friendRequestsList.ScrollBox then
        friendRequestsList.ScrollBox:ForEachFrame(StyleFriendRequestCard)
    end

    StyleSocialRaidFrame(frame.RaidFrame)
    StyleSocialIgnoreList(frame.IgnoreListFrame)
    StyleSocialBroadcast(frame.BattleNetBroadcastFrame)
    InstallSocialHooks()
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleRaidFrames()
    StyleLegacyRaidFrame()

    local socialFrame = _G.SocialUIFrame
    if socialFrame then
        StyleSocialRaidFrame(socialFrame.RaidFrame)
    end
end

local function StyleBlizzard()
    StyleLegacyFriendsFrame()
    StyleSocialUI()
    StyleRecentAllies()
    StyleQuickJoin()
    StyleAddFriendFrame()
    StyleRaidFrames()
end

AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
AF.RegisterAddonLoaded("Blizzard_FriendsFrame", StyleLegacyFriendsFrame)
AF.RegisterAddonLoaded("Blizzard_AddFriend", StyleAddFriendFrame)
AF.RegisterAddonLoaded("Blizzard_RecentAllies", StyleRecentAllies)
AF.RegisterAddonLoaded("Blizzard_QuickJoin", StyleQuickJoin)
AF.RegisterAddonLoaded("Blizzard_RaidFrame", StyleRaidFrames)
AF.RegisterAddonLoaded("Blizzard_SocialUI", StyleBlizzard)
