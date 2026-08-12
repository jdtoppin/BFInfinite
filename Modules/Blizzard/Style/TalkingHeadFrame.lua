---@type BFI
local BFI = select(2, ...)
local S = BFI.modules.Style
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

local talkingHeadMover

-- Retail 12.1.0.68914 (jdtoppin wow-ui-source d3915c78aba77a7a9be76acbfa35c674bbb6abe9)
-- marks frame scale and anchoring geometry secret-capable. Keep this bridge
-- fail-closed until every native value is ordinary and finite.
local anchorPoints = {
    CENTER = true,
    LEFT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
    RIGHT = true,
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
}

local function IsOrdinaryNumber(value)
    return F.isValueNonSecret(value)
        and type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function IsOrdinaryPositiveNumber(value)
    return IsOrdinaryNumber(value) and value > 0
end

local function IsOrdinaryFramePoint(value)
    return F.isValueNonSecret(value)
        and type(value) == "string"
        and anchorPoints[value] == true
end

local function IsOrdinaryOptionalBoolean(value)
    return F.isValueNonSecret(value)
        and (value == nil or type(value) == "boolean")
end

local function IsOrdinaryTable(value)
    return F.isValueNonSecret(value) and type(value) == "table"
end

local function DisableTalkingHeadMover()
    talkingHeadMover.enabled = false
    if talkingHeadMover.mover then
        talkingHeadMover.mover:Hide()
    end
end

local function SetTalkingHeadMoverFallbackPoint()
    -- AF.CreateMover captures owner:GetPoint() when its overlay is shown, so
    -- this disabled proxy still needs a complete inert anchor before registration.
    talkingHeadMover._useOriginalPoints = true
    AF.ClearPoints(talkingHeadMover)
    AF.SetPoint(talkingHeadMover, "CENTER", AF.UIParent, "CENTER", 0, 0)
end

local function HasOrdinaryTalkingHeadMoverPoint()
    local point, relativeTo, relativePoint, x, y = talkingHeadMover:GetPoint()
    return IsOrdinaryFramePoint(point)
        and F.isValueNonSecret(relativeTo)
        and relativeTo == AF.UIParent
        and IsOrdinaryFramePoint(relativePoint)
        and IsOrdinaryNumber(x)
        and IsOrdinaryNumber(y)
end

local function GetTalkingHeadEditModeState()
    local frame = _G.TalkingHeadFrame
    local manager = _G.EditModeManagerFrame

    if InCombatLockdown()
        or not frame
        or not manager
        or not manager.IsInitialized
        or not manager.GetActiveLayoutInfo
        or not manager.GetActiveLayoutSystemInfo
        or not manager.SaveLayouts
        or not frame.UpdateSystem
        or not frame.IsInitialized
    then
        return
    end

    local isInitialized = manager:IsInitialized()
    local isFrameInitialized = frame:IsInitialized()
    local isInEditMode = frame.isInEditMode
    local isApplyingLayout = manager.layoutApplyInProgress
    if not IsOrdinaryOptionalBoolean(isInitialized)
        or not isInitialized
        or not IsOrdinaryOptionalBoolean(isFrameInitialized)
        or not isFrameInitialized
        or not IsOrdinaryOptionalBoolean(isInEditMode)
        or isInEditMode
        or not IsOrdinaryOptionalBoolean(isApplyingLayout)
        or isApplyingLayout
    then
        return
    end

    if manager.IsEditModeActive then
        local isEditModeActive = manager:IsEditModeActive()
        if not IsOrdinaryOptionalBoolean(isEditModeActive) or isEditModeActive then
            return
        end
    end

    if manager.IsShown then
        local isShown = manager:IsShown()
        if not IsOrdinaryOptionalBoolean(isShown) or isShown then
            return
        end
    end

    local system = frame.system
    local systemIndex = frame.systemIndex
    if not IsOrdinaryNumber(system)
        or not F.isValueNonSecret(systemIndex)
        or (systemIndex ~= nil and not IsOrdinaryNumber(systemIndex))
    then
        return
    end

    local layoutInfo = manager:GetActiveLayoutInfo()
    local layoutTypes = _G.Enum and _G.Enum.EditModeLayoutType
    if not IsOrdinaryTable(layoutInfo)
        or not layoutTypes
    then
        return
    end

    local layoutType = layoutInfo.layoutType
    if not IsOrdinaryNumber(layoutType)
        or (layoutType ~= layoutTypes.Account and layoutType ~= layoutTypes.Character)
    then
        return
    end

    local systemInfo = manager:GetActiveLayoutSystemInfo(system, systemIndex)
    if not IsOrdinaryTable(systemInfo) then return end

    local anchorInfo = systemInfo.anchorInfo
    local isInDefaultPosition = systemInfo.isInDefaultPosition
    local anchorInfo2 = systemInfo.anchorInfo2
    -- The default Talking Head layout is bottom-managed, so its live geometry
    -- is container-owned rather than represented by anchorInfo.
    if not IsOrdinaryTable(anchorInfo)
        or not IsOrdinaryOptionalBoolean(isInDefaultPosition)
        or isInDefaultPosition
        or not F.isValueNonSecret(anchorInfo2)
        or anchorInfo2 ~= nil
        or not IsOrdinaryFramePoint(anchorInfo.point)
        or not F.isValueNonSecret(anchorInfo.relativeTo)
        or anchorInfo.relativeTo ~= "UIParent"
        or not IsOrdinaryFramePoint(anchorInfo.relativePoint)
        or anchorInfo.point ~= anchorInfo.relativePoint
        or not IsOrdinaryNumber(anchorInfo.offsetX)
        or not IsOrdinaryNumber(anchorInfo.offsetY)
    then
        return
    end

    return frame, manager, systemInfo
end

local function GetMoverScale()
    local uiScale = UIParent:GetEffectiveScale()
    local moverScale = AF.UIParent:GetEffectiveScale()
    if not IsOrdinaryPositiveNumber(uiScale) or not IsOrdinaryPositiveNumber(moverScale) then return end

    local scale = moverScale / uiScale
    if not IsOrdinaryPositiveNumber(scale) then return end

    return scale, moverScale
end

local function SyncTalkingHeadMover()
    if not talkingHeadMover then return end

    local frame, _, systemInfo = GetTalkingHeadEditModeState()
    local moverScale, moverEffectiveScale = GetMoverScale()
    if not frame or not moverScale then
        DisableTalkingHeadMover()
        return
    end

    local frameEffectiveScale = frame:GetEffectiveScale()
    local frameWidth = frame:GetWidth()
    local frameHeight = frame:GetHeight()
    local anchorInfo = systemInfo.anchorInfo
    if not IsOrdinaryPositiveNumber(frameEffectiveScale)
        or not IsOrdinaryPositiveNumber(frameWidth)
        or not IsOrdinaryPositiveNumber(frameHeight)
    then
        DisableTalkingHeadMover()
        return
    end

    local frameScale = frameEffectiveScale / moverEffectiveScale
    if not IsOrdinaryPositiveNumber(frameScale) then
        DisableTalkingHeadMover()
        return
    end

    local moverWidth = frameWidth * frameScale
    local moverHeight = frameHeight * frameScale
    local offsetX = anchorInfo.offsetX / moverScale
    local offsetY = anchorInfo.offsetY / moverScale
    if not IsOrdinaryPositiveNumber(moverWidth)
        or not IsOrdinaryPositiveNumber(moverHeight)
        or not IsOrdinaryNumber(offsetX)
        or not IsOrdinaryNumber(offsetY)
    then
        DisableTalkingHeadMover()
        return
    end

    talkingHeadMover.enabled = false
    talkingHeadMover:SetSize(moverWidth, moverHeight)
    talkingHeadMover._useOriginalPoints = true
    AF.ClearPoints(talkingHeadMover)
    AF.SetPoint(
        talkingHeadMover,
        systemInfo.anchorInfo.point,
        AF.UIParent,
        systemInfo.anchorInfo.relativePoint,
        offsetX,
        offsetY
    )
    if not HasOrdinaryTalkingHeadMoverPoint() then
        SetTalkingHeadMoverFallbackPoint()
        DisableTalkingHeadMover()
        return
    end
    talkingHeadMover.enabled = true
end

local function SaveTalkingHeadPosition(point, x, y)
    local frame, manager, systemInfo = GetTalkingHeadEditModeState()
    local moverScale = GetMoverScale()
    if not frame
        or not moverScale
        or not IsOrdinaryFramePoint(point)
        or not IsOrdinaryNumber(x)
        or not IsOrdinaryNumber(y)
    then
        SyncTalkingHeadMover()
        return
    end

    local offsetX = x * moverScale
    local offsetY = y * moverScale
    if not IsOrdinaryNumber(offsetX) or not IsOrdinaryNumber(offsetY) then
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
    systemInfo.anchorInfo.offsetX = offsetX
    systemInfo.anchorInfo.offsetY = offsetY
    systemInfo.anchorInfo2 = nil
    systemInfo.isInDefaultPosition = false

    frame:UpdateSystem(systemInfo)
    manager:SaveLayouts()
    SyncTalkingHeadMover()
end

local function CreateTalkingHeadMover()
    if talkingHeadMover then return end

    talkingHeadMover = CreateFrame("Frame", nil, AF.UIParent)
    talkingHeadMover:SetSize(1, 1)
    SetTalkingHeadMoverFallbackPoint()
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
