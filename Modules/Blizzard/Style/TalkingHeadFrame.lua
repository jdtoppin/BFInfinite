---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local talkingHeadMover

local function GetTalkingHeadEditModeState()
    local frame = _G.TalkingHeadFrame
    local manager = _G.EditModeManagerFrame

    if InCombatLockdown()
        or not frame
        or not manager
        or not manager.IsInitialized
        or not manager:IsInitialized()
        or not manager.GetActiveLayoutInfo
        or not manager.GetActiveLayoutSystemInfo
        or not manager.SaveLayouts
        or not frame.UpdateSystem
        or not frame.IsInitialized
        or not frame:IsInitialized()
        or frame.isInEditMode
        or (manager.IsEditModeActive and manager:IsEditModeActive())
        or (manager.IsShown and manager:IsShown())
    then
        return
    end

    local layoutInfo = manager:GetActiveLayoutInfo()
    local layoutTypes = Enum.EditModeLayoutType
    if not layoutInfo
        or not layoutTypes
        or (layoutInfo.layoutType ~= layoutTypes.Account
            and layoutInfo.layoutType ~= layoutTypes.Character)
    then
        return
    end

    local systemInfo = manager:GetActiveLayoutSystemInfo(frame.system, frame.systemIndex)
    local anchorInfo = systemInfo and systemInfo.anchorInfo
    -- The default Talking Head layout is bottom-managed, so its live geometry
    -- is container-owned rather than represented by anchorInfo.
    if not anchorInfo
        or systemInfo.isInDefaultPosition
        or systemInfo.anchorInfo2
        or anchorInfo.relativeTo ~= "UIParent"
        or anchorInfo.point ~= anchorInfo.relativePoint
    then
        return
    end

    return frame, manager, systemInfo
end

local function GetMoverScale()
    local uiScale = UIParent:GetEffectiveScale()
    local moverScale = AF.UIParent:GetEffectiveScale()
    if uiScale == 0 or moverScale == 0 then return end

    return moverScale / uiScale
end

local function SyncTalkingHeadMover()
    if not talkingHeadMover then return end

    talkingHeadMover.enabled = false

    local frame, _, systemInfo = GetTalkingHeadEditModeState()
    local moverScale = GetMoverScale()
    if not frame or not moverScale or moverScale == 0 then
        if talkingHeadMover.mover then
            talkingHeadMover.mover:Hide()
        end
        return
    end

    local frameScale = frame:GetEffectiveScale() / AF.UIParent:GetEffectiveScale()
    talkingHeadMover:SetSize(frame:GetWidth() * frameScale, frame:GetHeight() * frameScale)
    talkingHeadMover._useOriginalPoints = true
    AF.ClearPoints(talkingHeadMover)
    AF.SetPoint(
        talkingHeadMover,
        systemInfo.anchorInfo.point,
        AF.UIParent,
        systemInfo.anchorInfo.relativePoint,
        systemInfo.anchorInfo.offsetX / moverScale,
        systemInfo.anchorInfo.offsetY / moverScale
    )
    talkingHeadMover.enabled = true
end

local function SaveTalkingHeadPosition(point, x, y)
    local frame, manager, systemInfo = GetTalkingHeadEditModeState()
    local moverScale = GetMoverScale()
    if not frame or not moverScale then
        SyncTalkingHeadMover()
        return
    end

    -- TalkingHeadFrame remains Blizzard-owned. Retail 12.0.7.68887
    -- (Gethe wow-ui-source 4383ced30106d51b27e3e86d1987f1552f0d259d)
    -- and 12.1.0.68914 (jdtoppin wow-ui-source
    -- d3915c78aba77a7a9be76acbfa35c674bbb6abe9) apply this data through
    -- EditModeSystemMixin:UpdateSystem. That path detaches bottom-managed
    -- frames when needed and keeps Blizzard's layout as the saved authority.
    systemInfo.anchorInfo.point = point
    systemInfo.anchorInfo.relativeTo = "UIParent"
    systemInfo.anchorInfo.relativePoint = point
    systemInfo.anchorInfo.offsetX = x * moverScale
    systemInfo.anchorInfo.offsetY = y * moverScale
    systemInfo.anchorInfo2 = nil
    systemInfo.isInDefaultPosition = false

    frame:UpdateSystem(systemInfo)
    manager:SaveLayouts()
    SyncTalkingHeadMover()
end

local function CreateTalkingHeadMover()
    if talkingHeadMover then return end

    talkingHeadMover = CreateFrame("Frame", nil, AF.UIParent)
    talkingHeadMover.enabled = false
    talkingHeadMover:Hide()
    talkingHeadMover:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    talkingHeadMover:SetScript("OnEvent", SyncTalkingHeadMover)

    local manager = _G.EditModeManagerFrame
    if manager and manager.EnterEditMode then
        hooksecurefunc(manager, "EnterEditMode", SyncTalkingHeadMover)
    end
    if manager and manager.ExitEditMode then
        hooksecurefunc(manager, "ExitEditMode", SyncTalkingHeadMover)
    end

    AF.CreateMover(
        talkingHeadMover,
        "BFI: " .. _G.OTHER,
        _G.HUD_EDIT_MODE_TALKING_HEAD_FRAME_LABEL,
        SaveTalkingHeadPosition
    )
end

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

    CreateTalkingHeadMover()

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
AF.RegisterCallback("BFI_PrepareEditModePositions", SyncTalkingHeadMover)
