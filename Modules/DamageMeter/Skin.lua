---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type Style
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

DM.Skin = DM.Skin or {}
local Skin = DM.Skin

local entryStates = setmetatable({}, {__mode = "k"})
local fontStates = setmetatable({}, {__mode = "k"})
local sessionWindowStates = setmetatable({}, {__mode = "k"})
local sourceWindowStates = setmetatable({}, {__mode = "k"})

-- FrameXML evidence: Retail PTR 12.1.0.68914, Gethe/wow-ui-source commit
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9. Blizzard_DamageMeter owns all
-- combat data, row order, interaction, layout, and secret-value handling.
-- This file only changes presentation on known native frames and ignores
-- ScrollBox elementData, which can contain secret fields.

local function IsActive()
    return type(DM.IsActive) == "function" and DM.IsActive()
end

local function CaptureFont(fontString)
    if not fontString or fontStates[fontString] then return end

    local font, size, flags = fontString:GetFont()
    fontStates[fontString] = {
        fontObject = fontString.GetFontObject and fontString:GetFontObject(),
        font = font,
        size = size,
        flags = flags,
    }
end

local function ApplyFont(fontString)
    if not fontString then return end

    CaptureFont(fontString)
    local _, size, flags = fontString:GetFont()
    fontString:SetFont(AF.LSM_GetFont("BFI"), size or 12, flags or "")
end

local function RestoreFont(fontString)
    local state = fontStates[fontString]
    if not state then return end

    if state.fontObject and fontString.SetFontObject then
        fontString:SetFontObject(state.fontObject)
    elseif state.font then
        fontString:SetFont(state.font, state.size or 12, state.flags or "")
    end
end

local function EnsureBorder(frame)
    S.CreateBackdrop(frame, true, nil, 20)
    AF.SetFrameLevel(frame.BFIBackdrop, 20, frame)
    frame.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
    frame.BFIBackdrop:Show()
end

local function EnsureEntryHooks(entry)
    if entry._BFIDamageMeterHooks then return end
    entry._BFIDamageMeterHooks = true

    hooksecurefunc(entry, "UpdateStyle", function(self)
        if IsActive() then
            Skin.ApplyEntry(self)
        end
    end)
    hooksecurefunc(entry, "UpdateBackground", function(self)
        if IsActive() then
            Skin.ApplyEntry(self)
        end
    end)
end

function Skin.ApplyEntry(entry)
    if not IsActive() or not entry or not DM.config then return end

    EnsureEntryHooks(entry)

    local statusBar = entry:GetStatusBar()
    local state = entryStates[entry]
    if not state then
        local statusTexture = statusBar:GetStatusBarTexture()
        state = {
            statusTexture = statusTexture:GetTexture(),
            statusAtlas = statusTexture:GetAtlas(),
        }
        entryStates[entry] = state
    end

    local backing = entry._BFIDamageMeterBacking
    if not backing then
        backing = AF.CreateTexture(statusBar, nil, nil, "BACKGROUND", -8)
        entry._BFIDamageMeterBacking = backing
        backing:SetAllPoints(statusBar)
    end

    backing:SetColorTexture(AF.UnpackColor(
        AF.GetColorTable("background", DM.config.barBackgroundAlpha)
    ))
    backing:Show()

    statusBar:SetStatusBarTexture(AF.LSM_GetBarTexture(DM.config.barTexture))
    entry:GetBackground():SetAlpha(0)
    entry:GetBackgroundEdge():SetAlpha(0)

    ApplyFont(entry:GetName())
    ApplyFont(entry:GetValue())
end

local function OnEntryInitialized(_, entry)
    if IsActive() then
        Skin.ApplyEntry(entry)
    end
end

local function RegisterScrollBox(scrollBox)
    if not scrollBox or scrollBox._BFIDamageMeterCallback then return end
    scrollBox._BFIDamageMeterCallback = true

    _G.ScrollUtil.AddInitializedFrameCallback(
        scrollBox,
        OnEntryInitialized,
        Skin,
        false
    )

    scrollBox:ForEachFrame(function(entry)
        Skin.ApplyEntry(entry)
    end)
end

local function ApplySourceWindow(sourceWindow)
    if not sourceWindow or not IsActive() then return end

    local state = sourceWindowStates[sourceWindow]
    if not state then
        local background = sourceWindow:GetBackground()
        state = {
            backgroundAlpha = background:GetAlpha(),
        }
        sourceWindowStates[sourceWindow] = state

        local fill = AF.CreateTexture(
            sourceWindow,
            nil,
            "background",
            "BACKGROUND",
            1
        )
        sourceWindow._BFIDamageMeterFill = fill
        fill:SetAllPoints(background)
    end

    EnsureBorder(sourceWindow)
    sourceWindow:GetBackground():SetAlpha(0)
    sourceWindow._BFIDamageMeterFill:SetColor("background")
    sourceWindow._BFIDamageMeterFill:Show()
    RegisterScrollBox(sourceWindow:GetScrollBox())
end

local function ApplySessionBackground(sessionWindow)
    if not IsActive() then return end

    sessionWindow:GetBackground():SetAlpha(0)
    sessionWindow._BFIDamageMeterBodyFill:SetColor("background")
    sessionWindow._BFIDamageMeterBodyFill:SetAlpha(
        sessionWindow:GetBackgroundAlpha()
    )
    sessionWindow._BFIDamageMeterBodyFill:Show()
end

local function EnsureSessionWindowHooks(sessionWindow)
    if sessionWindow._BFIDamageMeterHooks then return end
    sessionWindow._BFIDamageMeterHooks = true

    hooksecurefunc(sessionWindow, "UpdateBackground", function(self)
        if IsActive() then
            ApplySessionBackground(self)
        end
    end)
end

function Skin.ApplySessionWindow(sessionWindow)
    if not IsActive() or not sessionWindow or not DM.config then return end

    local state = sessionWindowStates[sessionWindow]
    if not state then
        local header = sessionWindow:GetHeader()
        state = {
            headerAlpha = header:GetAlpha(),
        }
        sessionWindowStates[sessionWindow] = state

        local headerFill = AF.CreateGradientTexture(
            sessionWindow,
            "HORIZONTAL",
            "header",
            "header",
            nil,
            "BACKGROUND",
            2
        )
        sessionWindow._BFIDamageMeterHeaderFill = headerFill
        headerFill:SetAllPoints(header)

        local bodyFill = AF.CreateTexture(
            sessionWindow:GetMinimizeContainer(),
            nil,
            "background",
            "BACKGROUND",
            -8
        )
        sessionWindow._BFIDamageMeterBodyFill = bodyFill
        bodyFill:SetAllPoints(sessionWindow:GetBackground())
    end

    EnsureSessionWindowHooks(sessionWindow)
    EnsureBorder(sessionWindow)

    sessionWindow:GetHeader():SetAlpha(0)
    if DM.config.accentHeader then
        sessionWindow._BFIDamageMeterHeaderFill:SetColor(
            "HORIZONTAL",
            AF.GetColorTable("BFI", 0.8),
            AF.GetColorTable("header", 0.95)
        )
    else
        sessionWindow._BFIDamageMeterHeaderFill:SetColor(
            "HORIZONTAL",
            "header",
            "header"
        )
    end
    sessionWindow._BFIDamageMeterHeaderFill:Show()

    ApplySessionBackground(sessionWindow)
    ApplyFont(sessionWindow:GetDamageMeterTypeName())
    ApplyFont(sessionWindow:GetSessionName())
    ApplyFont(sessionWindow:GetSessionTimerFontString())
    ApplyFont(sessionWindow:GetNotActiveFontString())

    RegisterScrollBox(sessionWindow:GetScrollBox())
    Skin.ApplyEntry(sessionWindow:GetLocalPlayerEntry())
    ApplySourceWindow(sessionWindow:GetSourceWindow())
end

local function RestoreEntry(entry, state)
    if entry._BFIDamageMeterBacking then
        entry._BFIDamageMeterBacking:Hide()
    end

    local statusTexture = entry:GetStatusBar():GetStatusBarTexture()
    if state.statusAtlas then
        statusTexture:SetAtlas(state.statusAtlas)
    else
        statusTexture:SetTexture(state.statusTexture)
    end

    RestoreFont(entry:GetName())
    RestoreFont(entry:GetValue())
    entry:UpdateStyle()
    entry:UpdateBackground()
end

local function RestoreSourceWindow(sourceWindow, state)
    if sourceWindow._BFIDamageMeterFill then
        sourceWindow._BFIDamageMeterFill:Hide()
    end
    if sourceWindow.BFIBackdrop then
        sourceWindow.BFIBackdrop:Hide()
    end

    sourceWindow:GetBackground():SetAlpha(state.backgroundAlpha)
end

local function RestoreSessionWindow(sessionWindow, state)
    if sessionWindow._BFIDamageMeterHeaderFill then
        sessionWindow._BFIDamageMeterHeaderFill:Hide()
    end
    if sessionWindow._BFIDamageMeterBodyFill then
        sessionWindow._BFIDamageMeterBodyFill:Hide()
    end
    if sessionWindow.BFIBackdrop then
        sessionWindow.BFIBackdrop:Hide()
    end

    sessionWindow:GetHeader():SetAlpha(state.headerAlpha)
    RestoreFont(sessionWindow:GetDamageMeterTypeName())
    RestoreFont(sessionWindow:GetSessionName())
    RestoreFont(sessionWindow:GetSessionTimerFontString())
    RestoreFont(sessionWindow:GetNotActiveFontString())
    sessionWindow:UpdateBackground()
end

function Skin.Install()
    local damageMeter = _G.DamageMeter
    if not damageMeter
        or type(damageMeter.SetupSessionWindow) ~= "function"
        or type(damageMeter.ForEachSessionWindow) ~= "function" then
        return false
    end

    if not damageMeter._BFIDamageMeterSetupHook then
        damageMeter._BFIDamageMeterSetupHook = true
        hooksecurefunc(damageMeter, "SetupSessionWindow", function(self, index)
            if not IsActive() then return end

            local sessionWindow = self:GetSessionWindow(index)
            if sessionWindow then
                Skin.ApplySessionWindow(sessionWindow)
            end
        end)
    end

    return true
end

function Skin.ApplyAll()
    if not IsActive() or not Skin.Install() then return end

    _G.DamageMeter:ForEachSessionWindow(function(sessionWindow)
        Skin.ApplySessionWindow(sessionWindow)
    end)
end

function Skin.Disable()
    for entry, state in next, entryStates do
        RestoreEntry(entry, state)
    end
    for sourceWindow, state in next, sourceWindowStates do
        RestoreSourceWindow(sourceWindow, state)
    end
    for sessionWindow, state in next, sessionWindowStates do
        RestoreSessionWindow(sessionWindow, state)
    end
end
