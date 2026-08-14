---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- native aura button tooltip
---------------------------------------------------------------------
local auraButtonTooltipStyled

local function StyleAuraButtonTooltip()
    if auraButtonTooltipStyled then return end

    local inbound = _G.AuraContainerInbound
    if type(inbound) ~= "table" or type(inbound.SetTooltipBackdrop) ~= "function" then return end

    -- Retail 12.1.0.69273 / wow-ui-source eb941aad028d73dd:
    -- AuraButtonTooltip is hidden and forbidden. Use Blizzard's global inbound
    -- styling surface instead of reading or mutating the object.
    local pixel = AF.GetOnePixelForRegion(_G.UIParent)
    local backgroundR, backgroundG, backgroundB, backgroundA = AF.GetColorRGB("background")
    local borderR, borderG, borderB, borderA = AF.GetColorRGB("border")
    local texture = AF.GetPlainTexture()

    inbound.SetTooltipBackdrop({
        backdropInfo = {
            bgFile = texture,
            edgeFile = texture,
            edgeSize = pixel,
            insets = {
                left = pixel,
                right = pixel,
                top = pixel,
                bottom = pixel,
            },
        },
        borderColor = CreateColor(borderR, borderG, borderB, borderA),
        centerColor = CreateColor(backgroundR, backgroundG, backgroundB, backgroundA),
        anchorOffsets = {
            left = pixel,
            right = -pixel,
            top = -pixel,
            bottom = pixel,
        },
    })

    auraButtonTooltipStyled = true
end

---------------------------------------------------------------------
-- style
---------------------------------------------------------------------
-- Retail 12.1.0.68914 (wow-ui-source d3915c78aba7) defines CompareHeader's
-- rounded background in GameTooltip.xml. TooltipComparisonManager.lua owns
-- its label, dynamic width, and visibility, so only replace the artwork.
local function StyleCompareHeader(header)
    if not header or header._BFIStyled then return end
    header._BFIStyled = true

    S.RemoveTextures(header, true)
    AF.ApplyDefaultBackdropWithColors(header, "widget")
    AF.AddToPixelUpdater_CustomGroup("BFIStyled", header)
end

local function Style(tooltip, _, embedded)
    if not tooltip or tooltip:IsForbidden() or not tooltip.NineSlice then return end
    if embedded or tooltip.IsEmbedded then return end -- Interface/AddOns/Blizzard_SharedXML/SharedTooltipTemplates.lua#L44

    if tooltip.Delimiter1 then tooltip.Delimiter1:SetTexture() end
    if tooltip.Delimiter2 then tooltip.Delimiter2:SetTexture() end

    AF.ApplyDefaultBackdropWithColors(tooltip.NineSlice)
    AF.SetOnePixelInside(tooltip.NineSlice, tooltip)

    StyleCompareHeader(tooltip.CompareHeader)
end

---------------------------------------------------------------------
-- GameTooltip_ShowStatusBar
---------------------------------------------------------------------
-- Interface/AddOns/Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua
local function GameTooltip_ShowStatusBar(tooltip)
    if not tooltip or not tooltip.statusBarPool or tooltip:IsForbidden() then return end

    local bar = tooltip.statusBarPool:GetNextActive()
    if not bar or bar.BFIBackdrop then return end

    S.RemoveTextures(bar)
    S.CreateBackdrop(bar, nil, 1)
    bar:SetStatusBarTexture(BFI.media.bar)
end

---------------------------------------------------------------------
-- GameTooltip_ShowProgressBar
---------------------------------------------------------------------
-- Interface\AddOns\Blizzard_CovenantCallings\CovenantCallings.lua
-- Interface\AddOns\Blizzard_FrameXMLUtil\Mainline\ReputationUtil.lua
-- Interface\AddOns\Blizzard_PVPUI\Blizzard_PVPUI.lua
local function GameTooltip_ShowProgressBar(tooltip)
    if not tooltip or not tooltip.progressBarPool or tooltip:IsForbidden() then return end

    local bar = tooltip.progressBarPool:GetNextActive()
    if not (bar and bar.Bar) then return end

    bar = bar.Bar
    if bar.BFIBackdrop then return end

    S.StyleStatusBar(bar, 1)
end

---------------------------------------------------------------------
-- init
---------------------------------------------------------------------
local function StyleBlizzard()
    StyleAuraButtonTooltip()

    -- init
    for _, tooltip in next, {
        _G.EmbeddedItemTooltip,
        _G.FriendsTooltip,
        _G.GameTooltip,
        _G.ItemRefShoppingTooltip1,
        _G.ItemRefShoppingTooltip2,
        _G.ItemRefTooltip,
        _G.QuickKeybindTooltip,
        _G.ReputationParagonTooltip,
        _G.ShoppingTooltip1,
        _G.ShoppingTooltip2,
        _G.WorldMapTooltip,
        _G.LibDBIconTooltip,
        _G.SettingsTooltip,
        QuestMapLog_GetCampaignTooltip(), -- Interface\AddOns\Blizzard_UIPanels_Game\Mainline\WarCampaignTemplates.lua
    } do
        Style(tooltip)
    end

    -- EmbeddedItemTooltip.ItemTooltip
    local embeddedTooltip = _G.EmbeddedItemTooltip.ItemTooltip
    S.StyleIcon(embeddedTooltip.Icon, true) -- create backdrop
    S.StyleIconBorder(embeddedTooltip.IconBorder, embeddedTooltip.Icon.BFIBackdrop)

    -- GameTooltipStatusBar
    local bar = _G.GameTooltipStatusBar
    bar:SetStatusBarTexture(BFI.media.bar)
    bar:ClearAllPoints()
    AF.SetPoint(bar, "TOPLEFT", _G.GameTooltip, "BOTTOMLEFT", 1, 0)
    AF.SetPoint(bar, "TOPRIGHT", _G.GameTooltip, "BOTTOMRIGHT", -1, 0)
    S.CreateBackdrop(bar, nil, 1)
    AF.AddToPixelUpdater_Auto(bar)

    -- hook
    hooksecurefunc("SharedTooltip_SetBackdropStyle", Style)
    hooksecurefunc("GameTooltip_ShowStatusBar", GameTooltip_ShowStatusBar)
    hooksecurefunc("GameTooltip_ShowProgressBar", GameTooltip_ShowProgressBar)
end
AF.RegisterCallback("BFI_StyleBlizzard", StyleBlizzard)
if type(AF.RegisterAddonLoaded) == "function" then
    AF.RegisterAddonLoaded(
        "Blizzard_AuraContainer",
        StyleAuraButtonTooltip
    )
end
