---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

local PVEFrame = _G.PVEFrame
local ChallengesFrame

---------------------------------------------------------------------
--    ___ _         _ _                      ___
--   / __| |_  __ _| | |___ _ _  __ _ ___ __| __| _ __ _ _ __  ___
--  | (__| ' \/ _` | | / -_) ' \/ _` / -_|_-< _| '_/ _` | '  \/ -_)
--   \___|_||_\__,_|_|_\___|_||_\__, \___/__/_||_| \__,_|_|_|_\___|
--                              |___/
---------------------------------------------------------------------
local function StyleChallengesFrame()
    ChallengesFrame = _G.ChallengesFrame
    _G.ChallengesFrameInset:Hide()
    ChallengesFrame:DisableDrawLayer("BACKGROUND")

    --------------------------------------------------
    -- WeeklyInfo
    --------------------------------------------------
    local WeeklyInfo = ChallengesFrame.WeeklyInfo
    WeeklyInfo:SetAllPoints(ChallengesFrame)

    local Child = WeeklyInfo.Child
    Child:SetPoint("TOPLEFT", 6, -12)
    -- Child:SetPoint("TOPRIGHT", -6, -12)

    --------------------------------------------------
    -- AffixesContainer
    --------------------------------------------------
    local AffixesContainer = Child.AffixesContainer
    hooksecurefunc(AffixesContainer, "Layout", function(self)
        local children = self:GetLayoutChildren()
        for i, child in ipairs(children) do
            -- ChallengesKeystoneFrameAffixTemplate
            child.Border:Hide()
            S.StyleIcon(child.Portrait, true)
        end
    end)

    --------------------------------------------------
    -- ChallengesDungeonIconFrameTemplate
    --------------------------------------------------
    local function UpdateDungeon(frame)
        if frame._BFIStyled then return end
        frame._BFIStyled = true
        -- print(frame.mapID, C_ChallengeMode.GetMapUIInfo(frame.mapID))

        frame:DisableDrawLayer("BORDER")

        -- Icon
        S.StyleIcon(frame.Icon, true)
        frame.Icon:SetAllPoints()

        -- HighestLevel
        frame.HighestLevel:SetDrawLayer("OVERLAY")
        AF.RemoveFontShadow(frame.HighestLevel)
    end

    local function LineUpFrames(frames)
        local num = #frames
        local width = WeeklyInfo:GetWidth()
        local spacing = 2
        local padding = 3
        local frameWidth = (width - (num - 1) * spacing - padding * 2) / num

        for i, f in ipairs(frames) do
            f:ClearAllPoints()
            f:SetSize(frameWidth, frameWidth)
            if i == 1 then
                f:SetPoint("BOTTOMLEFT", WeeklyInfo, padding, padding)
                Child.SeasonBest:ClearAllPoints()
                Child.SeasonBest:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 2)
            else
                f:SetPoint("BOTTOMLEFT", frames[i - 1], "BOTTOMRIGHT", spacing, 0)
            end
        end
    end

    hooksecurefunc(ChallengesFrame, "Update", function()
        for _, f in next, ChallengesFrame.DungeonIcons do
            UpdateDungeon(f)
        end
        LineUpFrames(ChallengesFrame.DungeonIcons)
    end)
end

---------------------------------------------------------------------
-- SeasonChangeNoticeFrame
---------------------------------------------------------------------
local function StyleSeasonChangeNoticeFrame()
    local SeasonChangeNoticeFrame = ChallengesFrame.SeasonChangeNoticeFrame

    SeasonChangeNoticeFrame:ClearAllPoints()
    SeasonChangeNoticeFrame:SetPoint("TOPLEFT", PVEFrame.BFIHeader, "BOTTOMLEFT", 2, -1)
    SeasonChangeNoticeFrame:SetPoint("BOTTOMRIGHT", PVEFrame.BFIBg, -2, 2)

    S.RemoveTextures(SeasonChangeNoticeFrame)
    S.StyleButton(SeasonChangeNoticeFrame.Leave, "BFI")
    S.CreateBackdrop(SeasonChangeNoticeFrame)
    SeasonChangeNoticeFrame.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget", 0.95))

    --------------------------------------------------
    -- Affix
    --------------------------------------------------
    local Affix = SeasonChangeNoticeFrame.Affix
    Affix.AffixBorder:Hide()
    S.StyleIcon(Affix.Portrait, true)

    --------------------------------------------------
    -- texts
    --------------------------------------------------
    local function UpdateText(text, color)
        text:SetTextColor(AF.GetColorRGB(color))
        AF.SetFontShadow(text)
    end

    UpdateText(SeasonChangeNoticeFrame.NewSeason, "yellow_text")
    UpdateText(SeasonChangeNoticeFrame.SeasonDescription, "white")
    UpdateText(SeasonChangeNoticeFrame.SeasonDescription2, "white")
    UpdateText(SeasonChangeNoticeFrame.SeasonDescription3, "white")
end

---------------------------------------------------------------------
-- ChallengesKeystoneFrame
---------------------------------------------------------------------
local function StyleKeystoneText(text, color)
    text:SetTextColor(AF.GetColorRGB(color))
    AF.SetFontShadow(text)
end

local function StyleKeystoneAffix(affix)
    if affix._BFIKeystoneStyled then return end
    affix._BFIKeystoneStyled = true

    affix.Border:Hide()
    S.StyleSquareIcon(affix.Portrait, affix.CircleMask, true)

    -- Blizzard's circular artwork deliberately overlays this label on the
    -- icon's lower edge. Inset it above BFI's square outline so the border
    -- cannot cover the glyphs; native SetUp still owns text and font size.
    affix.Percent:ClearAllPoints()
    affix.Percent:SetPoint("BOTTOM", affix.Portrait, "BOTTOM", 0, 3)
end

local function StyleKeystoneAffixes(frame)
    for _, affix in ipairs(frame.Affixes) do
        StyleKeystoneAffix(affix)
    end
end

local function StyleKeystoneOuterBackground(frame)
    for _, region in next, {frame:GetRegions()} do
        if region:IsObjectType("Texture") then
            local atlas = region:GetAtlas()
            if F.isValueNonSecret(atlas)
                and atlas == "ChallengeMode-KeystoneFrame"
            then
                region:SetColorTexture(AF.GetColorRGB("background", 0.95))
                return
            end
        end
    end
end

local function StyleChallengesKeystoneFrame()
    local frame = _G.ChallengesKeystoneFrame
    if not frame or frame._BFIKeystoneStyled then return end
    frame._BFIKeystoneStyled = true

    -- Retail 12.1.0.68914, jdtoppin/wow-ui-source
    -- d3915c78aba77a7a9be76acbfa35c674bbb6abe9. Reset restores the
    -- shown/alpha state of every direct region. Replace only the anonymous
    -- outer atlas so Blizzard's named rune, glow, and insertion animations
    -- remain fully owned and functional.
    StyleKeystoneOuterBackground(frame)
    S.CreateBackdrop(frame, true, nil, 1)

    frame.InstructionBackground:SetColorTexture(
        AF.GetColorRGB("widget", 0.95)
    )
    frame.Divider:SetVertexColor(AF.GetColorRGB("BFI"))

    S.StyleCloseButton(frame.CloseButton)
    S.StyleButton(frame.StartButton, "BFI", nil, true)
    S.StyleSquareIcon(
        frame.KeystoneSlot.Texture,
        frame.KeystoneSlot.CircleMask,
        true
    )

    StyleKeystoneText(frame.DungeonName, "BFI")
    StyleKeystoneText(frame.PowerLevel, "yellow_text")
    StyleKeystoneText(frame.TimeLimit, "white")
    StyleKeystoneText(frame.Instructions, "white")

    StyleKeystoneAffixes(frame)
    hooksecurefunc(frame, "CreateAndPositionAffixes", StyleKeystoneAffixes)
end

local function InitializeChallengesUI()
    StyleChallengesFrame()
    StyleSeasonChangeNoticeFrame()
    StyleChallengesKeystoneFrame()
end

local challengesUILoaded = _G.C_AddOns.IsAddOnLoaded(
    "Blizzard_ChallengesUI"
)
local blizzardStyleReady
local challengesUIInitialized

local function TryInitializeChallengesUI()
    if challengesUIInitialized
        or not challengesUILoaded
        or not blizzardStyleReady
    then
        return
    end

    challengesUIInitialized = true
    InitializeChallengesUI()
end

AF.RegisterCallback("BFI_StyleBlizzard", function()
    blizzardStyleReady = true
    TryInitializeChallengesUI()
end)

if not challengesUILoaded then
    AF.RegisterAddonLoaded("Blizzard_ChallengesUI", function()
        challengesUILoaded = true
        StyleChallengesKeystoneFrame()
        TryInitializeChallengesUI()
    end)
else
    -- This popup has no dependency on the PVE shell and can be styled as
    -- soon as its load-on-demand addon is available. The main panels still
    -- wait for BFI_StyleBlizzard so their BFI header anchors already exist.
    StyleChallengesKeystoneFrame()
end
