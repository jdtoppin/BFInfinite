---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local function FadeInBackdrop(frame)
    local backdrop = frame.BFIBackdrop
    backdrop:ShowNow()
    backdrop:SetAlpha(0)
    backdrop:SetFadeDuration(0.75)
    backdrop:FadeIn()
end

local function FadeOutBackdrop(frame)
    local backdrop = frame.BFIBackdrop
    backdrop:ShowNow()
    backdrop:SetFadeDuration(1)
    backdrop:FadeOut()
end

local function UpdateBackdropShownState(frame)
    if frame.isInEditMode and not frame.isPlaying then
        frame.BFIBackdrop:ShowNow()
    end
end

local function UpdateTextStyle(frame)
    local name = frame.NameFrame.Name
    local text = frame.TextFrame.Text

    name:SetTextColor(AF.GetColorRGB("BFI"))
    text:SetTextColor(AF.GetColorRGB("white"))
    AF.SetFontShadow(name)
    AF.SetFontShadow(text)
end

local function StyleTalkingHeadFrame()
    local frame = _G.TalkingHeadFrame
    if not frame or frame._BFIStyled then return end
    frame._BFIStyled = true

    local mainFrame = frame.MainFrame

    -- Retail 12.0.7.68887 (Gethe wow-ui-source
    -- 4383ced30106d51b27e3e86d1987f1552f0d259d) and 12.1.0.68914
    -- (jdtoppin wow-ui-source d3915c78aba77a7a9be76acbfa35c674bbb6abe9)
    -- share this topology.
    -- Texture-kit updates replace atlases and alpha, but never reshow these
    -- regions, so hiding the native art remains durable between lines.
    S.RemoveTextures(frame.BackgroundFrame, true)
    S.RemoveTextures(frame.PortraitFrame, true)
    S.RemoveTextures(mainFrame, true)
    S.RemoveTextures(mainFrame.Model, true)
    S.RemoveTextures(mainFrame.Overlay, true)

    -- Keep the replacement below Blizzard's parent-level content.
    S.CreateBackdrop(frame, nil, nil, -1)
    S.CreateBackdrop(mainFrame.Model, true, nil, 1)
    S.StyleCloseButton(mainFrame.CloseButton)
    AF.CreateFadeInOutAnimation(frame.BFIBackdrop, 1, true)

    UpdateTextStyle(frame)
    hooksecurefunc(frame, "FadeinFrames", FadeInBackdrop)
    hooksecurefunc(frame, "FadeoutFrames", FadeOutBackdrop)
    hooksecurefunc(frame, "PlayCurrent", UpdateTextStyle)
    hooksecurefunc(frame, "UpdateShownState", UpdateBackdropShownState)
end
AF.RegisterCallback("BFI_StyleBlizzard", StyleTalkingHeadFrame)
