---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local communitiesHooksInstalled

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
    SetFlatTexture(button:GetHighlightTexture(), "widget_highlight", 0.75)
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
local function StyleMemberListEntry(button, elementData)
    local normalTexture = button:GetNormalTexture()
    local isHeader = elementData and elementData.invitationHeaderCount

    SetFlatTexture(normalTexture, isHeader and "BFI" or "widget_dark", isHeader and 0.25 or 0.55)
    SetFlatTexture(button:GetHighlightTexture(), "widget_highlight", 0.75)
end

local function StyleMemberList(memberList)
    S.RemoveNineSliceAndBackground(memberList.InsetFrame)
    memberList.WatermarkFrame:SetAlpha(0)
    S.StyleScrollBar(memberList.ScrollBar)
    S.StyleCheckButton(memberList.ShowOfflineButton)

    memberList.ScrollBox:ForEachFrame(StyleMemberListEntry)
end

---------------------------------------------------------------------
-- finder
---------------------------------------------------------------------
local function StyleFinderFrame(finder)
    if not finder then return end

    S.StyleSideTab(finder.ClubFinderSearchTab, 32, 32)
    S.StyleSideTab(finder.ClubFinderPendingTab, 32, 32)
    S.RemoveNineSliceAndBackground(finder.InsetFrame)
    S.RemoveNineSliceAndBackground(finder.DisabledFrame)
    S.RemoveTextures(finder.DisabledFrame)

    local options = finder.OptionsList
    StyleDropdown(options.ClubFilterDropdown)
    StyleDropdown(options.ClubSizeDropdown)
    StyleDropdown(options.SortByDropdown)
    S.StyleCheckButton(options.TankRoleFrame.Checkbox)
    S.StyleCheckButton(options.HealerRoleFrame.Checkbox)
    S.StyleCheckButton(options.DpsRoleFrame.Checkbox)
    S.StyleEditBox(options.SearchBox, -4)
    StyleButton(options.Search)

    for _, cards in next, {
        finder.GuildCards,
        finder.CommunityCards,
        finder.PendingGuildCards,
        finder.PendingCommunityCards,
    } do
        if cards and cards.ScrollBar then
            S.StyleScrollBar(cards.ScrollBar)
        end
    end
end

---------------------------------------------------------------------
-- guild panes
---------------------------------------------------------------------
local function StyleApplicantEntry(button)
    if not button then return end

    SetFlatTexture(button:GetNormalTexture(), "widget_dark", 0.65)
    SetFlatTexture(button:GetHighlightTexture(), "widget_highlight", 0.8)
    StyleButton(button.InviteButton, "BFI")

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
        highlight:SetAllPoints()
        SetFlatTexture(highlight, "widget_highlight", 0.8)
    end

    SetFlatTexture(button.DisabledBG, "disabled", 0.35)
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

    local details = frame.GuildDetailsFrame
    S.RemoveTextures(details)
    S.RemoveTextures(details.Info)
    S.RemoveTextures(details.News)
    S.StyleScrollBar(details.Info.MOTDScrollFrame.ScrollBar)
    S.StyleScrollBar(details.Info.DetailsFrame.ScrollBar)
    S.StyleScrollBar(details.News.ScrollBar)

    local applicants = frame.ApplicantList
    S.RemoveNineSliceAndBackground(applicants.InsetFrame)
    S.StyleScrollBar(applicants.ScrollBar)
    applicants.ScrollBox:ForEachFrame(StyleApplicantEntry)

    if not frame.CommunitiesCalendarButton._BFIStyled then
        S.StyleIconButton(frame.CommunitiesCalendarButton, AF.GetIcon("Calendar"), 16, nil, "widget")
    end
end

---------------------------------------------------------------------
-- main frame
---------------------------------------------------------------------
local function StyleCommunitiesFrame(frame)
    if not frame or frame._BFICommunitiesStyled then return end
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

    for _, tab in next, {
        frame.ChatTab,
        frame.RosterTab,
        frame.GuildBenefitsTab,
        frame.GuildInfoTab,
    } do
        S.StyleSideTab(tab, 32, 32)
    end

    StyleDropdown(frame.StreamDropdown)
    StyleDropdown(frame.GuildMemberListDropdown)
    StyleDropdown(frame.CommunityMemberListDropdown)
    StyleDropdown(frame.CommunitiesListDropdown)
    StyleDropdown(frame.AddToChatButton)

    StyleButton(frame.InviteButton, "BFI")
    StyleButton(frame.GuildLogButton)
    StyleButton(_G.JumpToUnreadButton)

    local controls = frame.CommunitiesControlFrame
    StyleButton(controls.CommunitiesSettingsButton)
    StyleButton(controls.GuildControlButton)
    StyleButton(controls.GuildRecruitmentButton)

    S.RemoveNineSliceAndBackground(frame.Chat.InsetFrame)
    S.StyleScrollBar(frame.Chat.ScrollBar)
    S.StyleEditBox(frame.ChatEditBox)
    frame.Chat.MessageFrame:SetFont(_G.STANDARD_TEXT_FONT, 13 + BFI.vars.blizzardFontSizeDelta, "")

    if not communitiesHooksInstalled then
        communitiesHooksInstalled = true

        hooksecurefunc(_G.CommunitiesListEntryMixin, "Init", StyleCommunitiesListEntry)
        hooksecurefunc(_G.CommunitiesMemberListEntryMixin, "Init", StyleMemberListEntry)
        hooksecurefunc(_G.ClubFinderApplicantEntryMixin, "UpdateMemberInfo", StyleApplicantEntry)
        hooksecurefunc(_G.CommunitiesGuildPerksButtonMixin, "Init", StyleGuildBenefitEntry)
        hooksecurefunc(_G.CommunitiesGuildRewardsButtonMixin, "Init", StyleGuildBenefitEntry)
    end
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    StyleCommunitiesFrame(_G.CommunitiesFrame)
end

AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
AF.RegisterAddonLoaded("Blizzard_Communities", StyleBlizzard)
