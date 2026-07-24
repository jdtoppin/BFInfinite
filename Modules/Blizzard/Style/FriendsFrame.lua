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

local function StyleArtworkButton(button)
    if not button or button._BFIStyled then return end

    local icon = button.Icon
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

local function StyleSquarePortrait(icon, owner, mask)
    if not icon then return end

    local atlas = WOW_PROJECT_ATLAS[_G.WOW_PROJECT_ID]
    if atlas and _G.C_Texture.GetAtlasInfo(atlas) then
        icon:SetAtlas(atlas, false)
    end

    if mask then
        S.StyleSquareIcon(icon, mask, true)
    else
        S.StyleIcon(icon, true)
    end

    AF.SetSize(icon, 40, 40)
    AF.ClearPoints(icon)
    AF.SetPoint(icon, "TOPLEFT", owner, "TOPLEFT", 5, -5)
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
local function StyleLegacyFriendButton(button)
    if not button or not button.background or not button.gameIcon then return end

    if not button._BFIFriendStyled then
        button._BFIFriendStyled = true
        S.StyleIcon(button.gameIcon, true)
    end

    SetFlatTexture(button.background, "widget_dark", 0.65)
    SetFlatTexture(button.highlight, "widget_highlight", 0.8)

    if button.buttonType == _G.FRIENDS_BUTTON_TYPE_BNET then
        local accountInfo = _G.C_BattleNet.GetFriendAccountInfo(button.id)
        SetWoWProjectIcon(button.gameIcon, accountInfo and accountInfo.gameAccountInfo)

        local characterName = GetClassColoredCharacterName(accountInfo, true)
        if characterName then
            button.name:SetText(_G.BNet_GetBNetAccountName(accountInfo) .. " " .. characterName)
        end
    end

    button.gameIcon:SetTexCoord(AF.GetDefaultTexCoord())
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
    SetFlatTexture(button:GetHighlightTexture(), "widget_highlight", 0.8)
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
    SetFlatTexture(button.HighlightTexture or button:GetHighlightTexture(), "widget_highlight", 0.8)
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

    S.StyleEditBox(whoFrame.EditBox, -4)
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

    if _G.FriendsFrame_UpdateFriendButton then
        hooksecurefunc("FriendsFrame_UpdateFriendButton", StyleLegacyFriendButton)
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
    StyleLegacyIgnoreList(frame.IgnoreListWindow)
    StyleLegacyBroadcast(header.BattlenetFrame.BroadcastFrame)

    InstallLegacyHooks()
end

---------------------------------------------------------------------
-- 12.1 SocialUI
---------------------------------------------------------------------
local function StyleSocialTab(tab)
    S.StyleSideTab(tab)
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
    SetFlatTexture(card:GetHighlightTexture(), "widget_highlight", 0.8)

    local gameIconHolder = card.GameIconHolder
    if gameIconHolder and gameIconHolder.Icon and gameIconHolder.Icon.BFIBackdrop then
        local accountInfo = card.elementData and card.elementData.accountInfo
        SetWoWProjectIcon(gameIconHolder.Icon, accountInfo and accountInfo.gameAccountInfo)
        gameIconHolder.Icon:SetTexCoord(AF.GetDefaultTexCoord())
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
    SetFlatTexture(card:GetHighlightTexture(), "widget_highlight", 0.8)
    StyleButton(card.AcceptButton, "BFI")
    if not card.DeclineButton._BFIStyled then
        S.StyleIconButton(card.DeclineButton, AF.GetIcon("Close"), 12, nil, "widget")
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

    if content.FilterBar then
        StyleDropdown(content.FilterBar.SearchFilterDropdown)
        S.StyleEditBox(content.FilterBar.SearchBar)
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
    SetFlatTexture(button.Highlight, "widget_highlight", 0.8)
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
    end
    if _G.FriendRequestsListSocialCardMixin then
        hooksecurefunc(_G.FriendRequestsListSocialCardMixin, "Initialize", StyleFriendRequestCard)
    end
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
    portraitContainer:SetAlpha(1)
    StyleSquarePortrait(portraitContainer.portrait, frame, portraitContainer.CircleMask)

    local battleNetBar = frame.BattleNetBar
    battleNetBar.Background:SetAlpha(0)
    local controls = battleNetBar.ControlsContainer
    SetFlatTexture(controls.BattleNetBackground, "widget_dark", 0.8)
    StyleDropdown(controls.OnlineStatusDropdown)
    StyleArtworkButton(controls.BattleNetMenuButton)

    for tab in frame:EnumerateTabs() do
        StyleSocialTab(tab)
    end
    frame:RefreshTabStates()

    for _, tabData in next, frame.tabDefinitions do
        StyleSocialContent(tabData.contentFrame)
    end

    StyleSocialIgnoreList(frame.IgnoreListFrame)
    StyleSocialBroadcast(frame.BattleNetBroadcastFrame)
    InstallSocialHooks()
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    StyleLegacyFriendsFrame()
    StyleSocialUI()
    StyleRecentAllies()
    StyleQuickJoin()
end

AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
AF.RegisterAddonLoaded("Blizzard_FriendsFrame", StyleLegacyFriendsFrame)
AF.RegisterAddonLoaded("Blizzard_RecentAllies", StyleRecentAllies)
AF.RegisterAddonLoaded("Blizzard_QuickJoin", StyleQuickJoin)
AF.RegisterAddonLoaded("Blizzard_SocialUI", StyleBlizzard)
