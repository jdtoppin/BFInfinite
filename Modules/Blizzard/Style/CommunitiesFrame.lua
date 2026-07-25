---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

local communitiesHooksInstalled
local finderGuildCardsStyled = setmetatable({}, {__mode = "k"})
local finderCommunityCardsStyled = setmetatable({}, {__mode = "k"})
local finderCommunityScrollBoxesHooked = setmetatable({}, {__mode = "k"})
local communitiesTabIcons = {
    "Chat",
    "Menu1",
    "Star",
    "Info_Round",
}
local communitiesRadioMenus = {
    "MENU_COMMUNITIES_GUILD_MEMBER_LIST",
    "MENU_COMMUNITIES_MEMBER_LIST",
    "MENU_COMMUNITIES_LIST",
    "MENU_CLUB_FINDER_OPTIONS",
    "MENU_CLUB_SORT_BY",
}

---------------------------------------------------------------------
-- shared
---------------------------------------------------------------------
local function StyleButton(button, color, preservePressScripts)
    if button then
        S.StyleButton(button, color, nil, preservePressScripts)
    end
end

local function StyleDropdown(dropdown, preservePressScripts)
    if dropdown then
        S.StyleDropdownButton(dropdown, preservePressScripts)
    end
end

-- These menu tags and their pooled leftTexture1/leftTexture2 radio contract
-- are unchanged between Retail 12.0.7.68887 (wow-ui-source
-- 4383ced30106d51b27e3e86d1987f1552f0d259d) and PTR 12.1.0.68914
-- (wow-ui-source d3915c78aba77a7a9be76acbfa35c674bbb6abe9).
local function StyleCommunitiesRadio(frame)
    -- Match the full class-color selection used by the Club Finder filter
    -- checkboxes rather than retaining Blizzard's inset radio-dot treatment.
    S.StyleMenuSelection(frame)
end

local function StyleCommunitiesRadioMenu(_, rootDescription)
    for _, description in rootDescription:EnumerateElementDescriptions() do
        if description:IsRadio() then
            description:AddInitializer(StyleCommunitiesRadio)
        end
    end
end

local function StyleCommunitiesStreamButton(frame)
    local fontString = frame.fontString
    if not fontString then return end

    local _, icon = fontString:GetPoint()
    if not icon or not icon.IsObjectType or not icon:IsObjectType("Texture") then return end

    -- Align icon rows such as Create Channel and Notification Settings with
    -- the 13px selection controls above them.
    AF.ClearPoints(icon)
    AF.SetPoint(icon, "LEFT")
    AF.SetSize(icon, 13, 13)

    AF.ClearPoints(fontString)
    AF.SetPoint(fontString, "LEFT", icon, "RIGHT", 7, 1)
end

local function StyleCommunitiesNotificationButton(frame)
    local fontString = frame.fontString
    if not fontString then return end

    local text = fontString:GetText()
    if not F.isValueNonSecret(text) or text ~= _G.COMMUNITIES_NOTIFICATION_SETTINGS then return end

    local _, icon = fontString:GetPoint()
    if not icon or not icon.IsObjectType or not icon:IsObjectType("Texture") then return end

    icon:SetTexture(AF.GetIcon("Settings"))
    icon:SetTexCoord(0, 1, 0, 1)
end

local function StyleCommunitiesStreamMenu(owner, rootDescription)
    StyleCommunitiesRadioMenu(owner, rootDescription)

    for _, description in rootDescription:EnumerateElementDescriptions() do
        if not description:IsRadio() then
            description:AddInitializer(StyleCommunitiesStreamButton)
            description:AddInitializer(StyleCommunitiesNotificationButton)
        end
    end
end

local function SetFlatTexture(texture, color, alpha, blendMode)
    if not texture then return end

    texture:SetColorTexture(AF.GetColorRGB(color, alpha))
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetBlendMode(blendMode or "BLEND")
end

local function LayoutVerticalTabs(tabs, anchorTo, x, y)
    local previous
    for _, tab in ipairs(tabs) do
        if tab:IsShown() then
            if previous then
                AF.ClearPoints(tab)
                AF.SetPoint(tab, "TOPLEFT", previous, "BOTTOMLEFT")
            elseif anchorTo then
                AF.ClearPoints(tab)
                AF.SetPoint(tab, "TOPLEFT", anchorTo, "TOPRIGHT", x, y)
            end
            previous = tab
        end
    end
end

local function UpdateCommunitiesTabIcon(tab)
    local icon = tab.Icon
    if not icon then return end

    icon:SetVertexColor(AF.GetColorRGB(tab:IsEnabled() and "white" or "disabled"))
end

local function StyleCommunitiesTab(tab, iconName, iconAddon)
    if not tab then return end

    -- Match the World Map rail's padded 35x50 footprint. The layout below
    -- still anchors each visible tab directly to the previous one.
    S.StyleSideTab(tab)

    local icon = tab.Icon
    if icon then
        -- Blizzard supplies opaque inventory-style artwork here. Transparent
        -- AF/BFI glyphs read cleanly inside the padded square rail.
        icon:SetTexture(AF.GetIcon(iconName, iconAddon))
        icon:SetTexCoord(0, 1, 0, 1)
        AF.SetSize(icon, 24, 24)
        AF.ClearPoints(icon)
        AF.SetPoint(icon, "CENTER")
        icon:SetAlpha(1)
        icon:Show()
    end

    if not tab._BFICommunitiesIconStateHooked then
        tab._BFICommunitiesIconStateHooked = true
        tab:HookScript("OnEnable", UpdateCommunitiesTabIcon)
        tab:HookScript("OnDisable", UpdateCommunitiesTabIcon)
    end
    UpdateCommunitiesTabIcon(tab)
end

local function LayoutCommunitiesTabs(frame)
    local tabs = {
        frame.ChatTab,
        frame.RosterTab,
        frame.GuildBenefitsTab,
        frame.GuildInfoTab,
    }

    for i, tab in ipairs(tabs) do
        StyleCommunitiesTab(tab, communitiesTabIcons[i])
    end

    -- World Map offsets its rail from the panel so all four sides of the
    -- shared tab border remain visible.
    LayoutVerticalTabs(tabs, frame, 4, -36)
end

---------------------------------------------------------------------
-- guild / community rail
---------------------------------------------------------------------
local function StyleCommunitiesListEntry(button)
    if not button._BFICommunitiesStyled then
        button._BFICommunitiesStyled = true

        S.CreateBackdrop(button, true)

        button.Background:ClearAllPoints()
        button.Background:SetAllPoints()
        button.Selection:ClearAllPoints()
        button.Selection:SetAllPoints()

        local highlight = button:GetHighlightTexture()
        if highlight then
            highlight:ClearAllPoints()
            highlight:SetAllPoints()
        end
    end

    SetFlatTexture(button.Background, button:IsEnabled() and "widget" or "disabled", 0.75)
    SetFlatTexture(button.Selection, "BFI", 0.45)
    SetFlatTexture(button:GetHighlightTexture(), "white", 0.2)
    SetFlatTexture(button.NewCommunityFlash, "BFI", 0.55, "ADD")

    button.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB(button:IsEnabled() and "border" or "disabled"))
end

local function StyleCommunitiesList(list)
    list.Bg:SetColorTexture(AF.GetColorRGB("background_lighter", 0.35))
    list.TopFiligree:SetAlpha(0)
    list.BottomFiligree:SetAlpha(0)
    list.FilligreeOverlay:SetAlpha(0)
    S.RemoveNineSliceAndBackground(list.InsetFrame)
    S.StyleScrollBar(list.ScrollBar)

    list.ScrollBox:ForEachFrame(StyleCommunitiesListEntry)
end

---------------------------------------------------------------------
-- member list
---------------------------------------------------------------------
local function StyleProfessionHeader(entry)
    local header = entry and entry.ProfessionHeader
    if not header then return end

    if not header._BFICommunitiesProfessionStyled then
        header._BFICommunitiesProfessionStyled = true

        -- CommunitiesMemberListEntryTemplate uses three pieces of the
        -- CollapsibleHeader texture for profession categories. Replace only
        -- that shell so the native profession identity and collapse state
        -- remain intact.
        S.RemoveTextures(header.Left, true)
        S.RemoveTextures(header.Middle, true)
        S.RemoveTextures(header.Right, true)
        S.CreateBackdrop(header)
        header.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
        header.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))

        local highlight = header:CreateTexture(nil, "HIGHLIGHT")
        AF.SetOnePixelInside(highlight, header.BFIBackdrop)
        SetFlatTexture(highlight, "white", 0.2)
        header:SetHighlightTexture(highlight)

        header.CollapsedIcon:SetTexture(AF.GetIcon("Plus_Small"))
        header.CollapsedIcon:SetTexCoord(0, 1, 0, 1)
        AF.ClearPoints(header.CollapsedIcon)
        AF.SetPoint(header.CollapsedIcon, "LEFT", header, "LEFT", 7, 0)
        AF.SetSize(header.CollapsedIcon, 12, 12)

        header.ExpandedIcon:SetTexture(AF.GetIcon("Minus_Small"))
        header.ExpandedIcon:SetTexCoord(0, 1, 0, 1)
        AF.ClearPoints(header.ExpandedIcon)
        AF.SetPoint(header.ExpandedIcon, "LEFT", header, "LEFT", 7, 0)
        AF.SetSize(header.ExpandedIcon, 12, 12)

        S.StyleIcon(header.Icon, true)
        AF.ClearPoints(header.Icon)
        AF.SetPoint(header.Icon, "LEFT", header, "LEFT", 24, 0)
        AF.SetSize(header.Icon, 16, 16)

        AF.ClearPoints(header.Name)
        AF.SetPoint(header.Name, "LEFT", header.Icon, "RIGHT", 6, 1)
        header.Name:SetTextColor(AF.GetColorRGB("white"))

        local allRecipes = header.AllRecipes
        StyleButton(allRecipes, nil, true)
        AF.ClearPoints(allRecipes)
        AF.SetPoint(allRecipes, "RIGHT", header, "RIGHT", -4, 0)
        local fontString = allRecipes:GetFontString()
        AF.SetSize(allRecipes, fontString:GetStringWidth() + 10, 18)
    end

    -- Blizzard updates the profession texture each time a pooled row is
    -- initialized. Reapply the square crop without replacing that identity.
    S.StyleIcon(header.Icon, true)
end

local function StyleMemberListEntry(button, elementData)
    local normalTexture = button:GetNormalTexture()
    local isHeader = elementData and elementData.invitationHeaderCount

    SetFlatTexture(normalTexture, isHeader and "BFI" or "widget_dark", isHeader and 0.25 or 0.55)
    SetFlatTexture(button:GetHighlightTexture(), "widget_highlight", 0.75)

    local memberInfo = elementData and elementData.memberInfo
    local professionHeader = button.ProfessionHeader
    if professionHeader and (professionHeader:IsShown() or (memberInfo and memberInfo.professionHeaderId)) then
        StyleProfessionHeader(button)
    end
end

local function StyleMemberList(memberList)
    S.RemoveNineSliceAndBackground(memberList.InsetFrame)
    memberList.WatermarkFrame:SetAlpha(0)
    S.StyleScrollBar(memberList.ScrollBar)
    S.StyleCheckButton(memberList.ShowOfflineButton)

    memberList.ScrollBox:ForEachFrame(StyleMemberListEntry)
end

local function StyleColumnHeader(header)
    if not header._BFIStyled then
        S.StyleButton(header, "widget")
    end
end

local function StyleColumnDisplay(display)
    if not display then return end

    if not display._BFICommunitiesStyled then
        display._BFICommunitiesStyled = true
        S.RemoveTextures(display, true)

        hooksecurefunc(display, "LayoutColumns", function(self)
            for header in self.columnHeaders:EnumerateActive() do
                StyleColumnHeader(header)
            end
        end)
    end

    for header in display.columnHeaders:EnumerateActive() do
        StyleColumnHeader(header)
    end
end

---------------------------------------------------------------------
-- finder
---------------------------------------------------------------------
local function StyleFinderGuildCard(card)
    if not card or finderGuildCardsStyled[card] then return end
    finderGuildCardsStyled[card] = true

    AF.ClearPoints(card.CardBackground)
    card.CardBackground:SetAllPoints()
    SetFlatTexture(card.CardBackground, "widget_dark", 0.85)

    S.CreateBackdrop(card, true)
    StyleButton(card.RequestJoin, nil, true)

    local highlight = card:CreateTexture(nil, "HIGHLIGHT")
    AF.SetOnePixelInside(highlight, card.BFIBackdrop)
    SetFlatTexture(highlight, "white", 0.2)
    card:SetHighlightTexture(highlight)
end

local function StyleFinderGuildCards(cards)
    if not cards or not cards.Cards then return end

    for _, card in next, cards.Cards do
        StyleFinderGuildCard(card)
    end

    if cards.PreviousPage and not cards.PreviousPage._BFIStyled then
        S.StyleIconButton(cards.PreviousPage, AF.GetIcon("ArrowLeft2"), 16)
    end
    if cards.NextPage and not cards.NextPage._BFIStyled then
        S.StyleIconButton(cards.NextPage, AF.GetIcon("ArrowRight2"), 16)
    end
end

local function StyleFinderCommunityCard(card)
    if not card or finderCommunityCardsStyled[card] then return end
    finderCommunityCardsStyled[card] = true

    -- CommunityLogo is the target of restricted C_Club.SetAvatarTexture.
    -- Keep the logo, mask, and card initializer untouched; only flatten the
    -- existing row surfaces after Blizzard has completed UpdateCard. Do not
    -- add a child backdrop: these pooled buttons are reused by later calls.
    AF.ClearPoints(card.Background)
    card.Background:SetAllPoints()
    SetFlatTexture(card.Background, "widget_dark", 0.85)

    AF.ClearPoints(card.HighlightBackground)
    AF.SetPoint(card.HighlightBackground, "TOPLEFT", 1, -1)
    AF.SetPoint(card.HighlightBackground, "BOTTOMRIGHT", -1, 1)
    SetFlatTexture(card.HighlightBackground, "white", 0.2)
end

local function StyleFinderCommunityCards(scrollBox)
    scrollBox:ForEachFrame(StyleFinderCommunityCard)
end

local function HookFinderCommunityCards(cards)
    local scrollBox = cards and cards.ScrollBox
    if not scrollBox then return end

    if not finderCommunityScrollBoxesHooked[scrollBox] then
        finderCommunityScrollBoxesHooked[scrollBox] = true

        -- Retail 12.0.7.68887 (Gethe 4383ced) and PTR 12.1.0.68914
        -- (Gethe d3915c7) initialize pooled cards inside ScrollBox:Update.
        -- ClubFinder.lua:1324-1420 calls the restricted avatar API before
        -- the initializer finishes, so this post-hook keeps BFI outside it.
        -- Keep the paired ScrollBar native too: S.StyleScrollBar installs
        -- addon state/scripts on this Update path before initialization.
        hooksecurefunc(scrollBox, "Update", StyleFinderCommunityCards)
    end

    StyleFinderCommunityCards(scrollBox)
end

local function StyleFinderFrame(finder)
    if not finder then return end

    local tabs = {
        finder.ClubFinderSearchTab,
        finder.ClubFinderPendingTab,
    }
    StyleCommunitiesTab(tabs[1], "World")
    StyleCommunitiesTab(tabs[2], "History", BFI.name)
    LayoutVerticalTabs(tabs, finder:GetParent(), 4, -36)

    S.RemoveNineSliceAndBackground(finder.InsetFrame)
    S.RemoveNineSliceAndBackground(finder.DisabledFrame)
    S.RemoveTextures(finder.DisabledFrame)

    local options = finder.OptionsList
    -- RequestClubsList and the returned avatar update both accept secret
    -- arguments only while untainted. Preserve Blizzard's press scripts and
    -- displaced-region state on every request input.
    StyleDropdown(options.ClubFilterDropdown, true)
    StyleDropdown(options.ClubSizeDropdown, true)
    StyleDropdown(options.SortByDropdown, true)
    S.StyleCheckButton(options.TankRoleFrame.Checkbox)
    S.StyleCheckButton(options.HealerRoleFrame.Checkbox)
    S.StyleCheckButton(options.DpsRoleFrame.Checkbox)
    S.StyleEditBox(options.SearchBox, -4, -7, nil, 7)
    StyleButton(options.Search, nil, true)

    StyleFinderGuildCards(finder.GuildCards)
    StyleFinderGuildCards(finder.PendingGuildCards)
    HookFinderCommunityCards(finder.CommunityCards)
    HookFinderCommunityCards(finder.PendingCommunityCards)
end

---------------------------------------------------------------------
-- guild panes
---------------------------------------------------------------------
local function StyleApplicantEntry(button)
    if not button then return end

    SetFlatTexture(button:GetNormalTexture(), "widget_dark", 0.65)
    SetFlatTexture(button:GetHighlightTexture(), "widget_highlight", 0.8)
    StyleButton(button.InviteButton)

    local cancelButton = button.CancelInvitationButton
    if cancelButton and not cancelButton._BFIStyled then
        S.StyleIconButton(cancelButton, AF.GetIcon("Close"), 12, nil, "widget")
    end
end

local function StyleGuildBenefitEntry(button)
    if not button or not button.Icon then return end

    if not button._BFIGuildBenefitStyled then
        button._BFIGuildBenefitStyled = true

        for _, region in next, {button:GetRegions()} do
            if region:IsObjectType("Texture")
                and region ~= button.Icon
                and region ~= button.Lock
                and region ~= button.DisabledBG
            then
                S.RemoveTextures(region, true)
            end
        end

        S.RemoveTextures(button.NormalBorder, true)
        S.RemoveTextures(button.DisabledBorder, true)
        S.StyleIcon(button.Icon, true)
        S.CreateBackdrop(button)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        AF.SetOnePixelInside(highlight, button.Icon.BFIBackdrop)
        SetFlatTexture(highlight, "white", 0.2)
        button:SetHighlightTexture(highlight)
    end

    SetFlatTexture(button.DisabledBG, "disabled", 0.35)
end

local function StyleGuildFactionBar(bar)
    if not bar or bar._BFICommunitiesStyled then return end
    bar._BFICommunitiesStyled = true

    for _, texture in next, {
        bar.Left,
        bar.Right,
        bar.Middle,
        bar.BG,
        bar.Shadow,
    } do
        S.RemoveTextures(texture, true)
    end

    S.CreateBackdrop(bar)
    bar.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_dark"))

    bar.Progress:SetTexture(BFI.media.bar)
    bar.Progress:SetTexCoord(0, 1, 0, 1)
    bar.Progress:SetVertexColor(AF.GetColorRGB("BFI"))
    AF.ClearPoints(bar.Progress)
    AF.SetPoint(bar.Progress, "TOPLEFT", 1, -1)
    AF.SetPoint(bar.Progress, "BOTTOMLEFT", 1, 1)
end

local function StyleGuildNewsEntry(button)
    if not button then return end

    SetFlatTexture(button.header, "widget", 0.75)
    SetFlatTexture(button:GetHighlightTexture(), "white", 0.2)
end

local function StyleNoteBackground(frame)
    S.RemoveNineSliceAndBackground(frame)
    S.CreateBackdrop(frame)
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget"))
end

local function StyleGuildMemberDetail(frame)
    if not frame or frame._BFIGuildMemberDetailStyled then return end

    frame.Border:SetAlpha(0)
    -- This popup's text is drawn directly on a level-1000 frame. Put the
    -- child backdrop one level behind it so it cannot cover the member data.
    S.CreateBackdrop(frame, nil, nil, -1)
    frame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("background"))

    S.StyleCloseButton(frame.CloseButton)
    AF.ClearPoints(frame.CloseButton)
    AF.SetPoint(frame.CloseButton, "TOPRIGHT")

    StyleButton(frame.RemoveButton)
    StyleButton(frame.GroupInviteButton)
    StyleDropdown(frame.RankDropdown)
    StyleNoteBackground(frame.NoteBackground)
    StyleNoteBackground(frame.OfficerNoteBackground)

    frame._BFIGuildMemberDetailStyled = true
end

local function StyleGuildNewsFiltersFrame(frame)
    if not frame or frame._BFICommunitiesNewsFiltersStyled then return end
    frame._BFICommunitiesNewsFiltersStyled = true

    S.StyleTitledFrame(frame)
    for _, checkButton in next, frame.GuildNewsFilterButtons do
        S.StyleCheckButton(checkButton)
    end
end

local function StyleGuildPanes(frame)
    local benefits = frame.GuildBenefitsFrame
    S.RemoveTextures(benefits)
    S.RemoveTextures(benefits.Perks)
    S.RemoveTextures(benefits.Rewards)
    S.StyleScrollBar(benefits.Perks.ScrollBar)
    S.StyleScrollBar(benefits.Rewards.ScrollBar)
    benefits.Perks.ScrollBox:ForEachFrame(StyleGuildBenefitEntry)
    benefits.Rewards.ScrollBox:ForEachFrame(StyleGuildBenefitEntry)
    StyleGuildFactionBar(benefits.FactionFrame.Bar)

    local details = frame.GuildDetailsFrame
    S.RemoveTextures(details)
    S.RemoveTextures(details.Info)
    S.RemoveTextures(details.News)
    S.StyleScrollBar(details.Info.MOTDScrollFrame.ScrollBar)
    S.StyleScrollBar(details.Info.DetailsFrame.ScrollBar)
    S.StyleScrollBar(details.News.ScrollBar)
    details.News.ScrollBox:ForEachFrame(StyleGuildNewsEntry)

    local applicants = frame.ApplicantList
    S.RemoveNineSliceAndBackground(applicants.InsetFrame)
    S.StyleScrollBar(applicants.ScrollBar)
    applicants.ScrollBox:ForEachFrame(StyleApplicantEntry)
    StyleColumnDisplay(applicants.ColumnDisplay)

    if not frame.CommunitiesCalendarButton._BFIStyled then
        S.StyleIconButton(frame.CommunitiesCalendarButton, AF.GetIcon("Calendar"), 16, nil, "widget")
    end

    StyleGuildNewsFiltersFrame(_G.CommunitiesGuildNewsFiltersFrame)
end

---------------------------------------------------------------------
-- main frame
---------------------------------------------------------------------
local function RefreshCommunitiesFrame(frame)
    if not frame then return end

    LayoutCommunitiesTabs(frame)

    local communitiesList = frame.CommunitiesList
    if communitiesList and communitiesList.ScrollBox then
        communitiesList.ScrollBox:ForEachFrame(StyleCommunitiesListEntry)
    end

    local memberDetail = frame.GuildMemberDetailFrame
    if memberDetail and memberDetail:IsShown() then
        StyleGuildMemberDetail(memberDetail)
    end
end

local function StyleCommunitiesFrame(frame)
    if not frame then return end
    if frame._BFICommunitiesStyled then
        RefreshCommunitiesFrame(frame)
        return
    end
    frame._BFICommunitiesStyled = true

    S.StyleTitledFrame(frame)
    S.RemoveNineSliceAndBackground(frame.Inset)

    -- Communities supplies a second portrait layer outside the inherited
    -- portrait container. Keep the BFI title treatment consistent.
    frame.PortraitOverlay:SetAlpha(0)

    StyleCommunitiesList(frame.CommunitiesList)
    StyleMemberList(frame.MemberList)
    StyleFinderFrame(frame.GuildFinderFrame)
    StyleFinderFrame(frame.CommunityFinderFrame)
    StyleGuildPanes(frame)
    StyleColumnDisplay(frame.MemberList.ColumnDisplay)

    LayoutCommunitiesTabs(frame)

    StyleDropdown(frame.StreamDropdown)
    StyleDropdown(frame.GuildMemberListDropdown)
    StyleDropdown(frame.CommunityMemberListDropdown)
    StyleDropdown(frame.CommunitiesListDropdown)
    StyleDropdown(frame.AddToChatButton)

    StyleButton(frame.InviteButton)
    StyleButton(frame.GuildLogButton)
    StyleButton(_G.JumpToUnreadButton)

    local controls = frame.CommunitiesControlFrame
    StyleButton(controls.CommunitiesSettingsButton)
    StyleButton(controls.GuildControlButton)
    StyleButton(controls.GuildRecruitmentButton)

    S.RemoveNineSliceAndBackground(frame.Chat.InsetFrame)
    S.StyleScrollBar(frame.Chat.ScrollBar)
    -- Blizzard's 32px hitbox reaches into the 20px bottom-button row.
    -- A 20px edit box clears that row under both maximize/minimize layouts.
    AF.SetHeight(frame.ChatEditBox, 20)
    S.StyleEditBox(frame.ChatEditBox)
    frame.Chat.MessageFrame:SetFont(_G.STANDARD_TEXT_FONT, 13 + BFI.vars.blizzardFontSizeDelta, "")
    frame:HookScript("OnShow", RefreshCommunitiesFrame)

    if not communitiesHooksInstalled then
        communitiesHooksInstalled = true

        hooksecurefunc(_G.CommunitiesListEntryMixin, "Init", StyleCommunitiesListEntry)
        hooksecurefunc(_G.CommunitiesMemberListEntryMixin, "Init", StyleMemberListEntry)
        hooksecurefunc(_G.ClubFinderApplicantEntryMixin, "UpdateMemberInfo", StyleApplicantEntry)
        hooksecurefunc(_G.CommunitiesGuildPerksButtonMixin, "Init", StyleGuildBenefitEntry)
        hooksecurefunc(_G.CommunitiesGuildRewardsButtonMixin, "Init", StyleGuildBenefitEntry)
        hooksecurefunc(_G.CommunitiesGuildNewsButtonMixin, "Init", StyleGuildNewsEntry)
        -- The XML frame already copied its mixin methods by ADDON_LOADED, so
        -- hook the live instance rather than the source mixin table.
        hooksecurefunc(frame, "UpdateCommunitiesTabs", RefreshCommunitiesFrame)
        hooksecurefunc(frame, "OpenGuildMemberDetailFrame", function(self)
            StyleGuildMemberDetail(self.GuildMemberDetailFrame)
        end)

        for _, menuTag in ipairs(communitiesRadioMenus) do
            _G.Menu.ModifyMenu(menuTag, StyleCommunitiesRadioMenu)
        end
        _G.Menu.ModifyMenu("MENU_COMMUNITIES_STREAM", StyleCommunitiesStreamMenu)
    end

    RefreshCommunitiesFrame(frame)
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    StyleCommunitiesFrame(_G.CommunitiesFrame)
end

AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
AF.RegisterAddonLoaded("Blizzard_Communities", StyleBlizzard)
