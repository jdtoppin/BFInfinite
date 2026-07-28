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

local sessionWindowStates = setmetatable({}, {__mode = "k"})
local sourceWindowStates = setmetatable({}, {__mode = "k"})
local controlStates = setmetatable({}, {__mode = "k"})
local resizeButtonStates = setmetatable({}, {__mode = "k"})
local scrollBarStates = setmetatable({}, {__mode = "k"})
local pendingSecondaryPlacements = {}
local placementFrame
local COMPACT_HEADER_HEIGHT = 26

-- FrameXML evidence: Retail PTR 12.1.0.68914, Gethe/wow-ui-source commit
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9. Blizzard_DamageMeter owns all
-- combat data, row order, interaction, layout, and secret-value handling.
-- This file only changes presentation on known native frames and ignores
-- ScrollBox elementData, which can contain secret fields.
--
-- Do not register callbacks on DamageMeterEntry frames or attach AF-owned
-- regions to them. Native entry initialization compares secret names, and any
-- addon execution on those pooled rows can taint Blizzard's comparison.

local function IsActive()
    return type(DM.IsActive) == "function" and DM.IsActive()
end

local function ClearPendingSecondaryPlacements()
    for index in next, pendingSecondaryPlacements do
        pendingSecondaryPlacements[index] = nil
    end
    if placementFrame then
        placementFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function PlacePendingSecondaryWindows()
    if not IsActive() then
        ClearPendingSecondaryPlacements()
        return
    end

    for index = 2, 3 do
        if pendingSecondaryPlacements[index] then
            pendingSecondaryPlacements[index] = nil

            if type(DM.ArrangeSecondaryWindows) == "function" then
                local ok, reason = DM.ArrangeSecondaryWindows({index})
                if not ok and reason == "combat" then
                    -- A closed window returns window_unavailable; continue so
                    -- another queued window can still be placed.
                    -- Combat is the only retryable result.
                    pendingSecondaryPlacements[index] = true
                end
            end
        end
    end

    if placementFrame and next(pendingSecondaryPlacements) then
        placementFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function QueueSecondaryPlacement(index)
    pendingSecondaryPlacements[index] = true

    if not placementFrame then
        placementFrame = _G.CreateFrame("Frame")
        placementFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            PlacePendingSecondaryWindows()
        end)
    end
    placementFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function PlaceSecondaryWindow(index)
    if type(DM.ArrangeSecondaryWindows) ~= "function" then return end

    local ok, reason = DM.ArrangeSecondaryWindows({index})
    if not ok and reason == "combat" then
        QueueSecondaryPlacement(index)
    end
end

local function EnsureBorder(frame)
    S.CreateBackdrop(frame, true, nil, 20)
    AF.SetFrameLevel(frame.BFIBackdrop, 20, frame)
    frame.BFIBackdrop:SetBackdropBorderColor(AF.GetColorRGB("border"))
    frame.BFIBackdrop:Show()
end

local function DisableOwnedMouse(frame)
    frame:EnableMouse(false)
    if frame.EnableMouseMotion then
        frame:EnableMouseMotion(false)
    end
end

local function CaptureNativeRegion(state, region)
    if not region then return end

    state.nativeRegions[#state.nativeRegions + 1] = {
        region = region,
        alpha = region:GetAlpha(),
    }
end

local function SuppressNativeRegions(state)
    for _, regionState in ipairs(state.nativeRegions) do
        regionState.region:SetAlpha(0)
    end
end

local function RestoreNativeRegions(state)
    for _, regionState in ipairs(state.nativeRegions) do
        regionState.region:SetAlpha(regionState.alpha)
    end
end

local function IsControlEmphasized(control)
    if control.IsMenuOpen and control:IsMenuOpen() then
        return true
    end
    if control.IsOver and control:IsOver() then
        return true
    end
    if control.GetButtonState
        and control:GetButtonState() == "PUSHED"
    then
        return true
    end
    return control:IsMouseOver()
end

local function UpdateControlChrome(control)
    local state = controlStates[control]
    if not state then return end

    if state.minimizeOwner then
        local icon = state.minimizeOwner:IsMinimized()
            and "ArrowDown1"
            or "ArrowUp1"
        state.icon:SetTexture(AF.GetIcon(icon))
    end

    local enabled = control:IsEnabled()
    local emphasized = enabled and IsControlEmphasized(control)
    local accent = state.danger and "red" or "BFI"

    if enabled then
        state.chrome:SetBackdropColor(AF.GetColorRGB(
            emphasized and accent or "widget",
            emphasized and 0.25 or 0.65
        ))
        state.chrome:SetBackdropBorderColor(AF.GetColorRGB(
            emphasized and accent or "border"
        ))
        state.icon:SetDesaturated(false)
        if state.danger and not emphasized then
            state.icon:SetVertexColor(AF.GetColorRGB("red", 0.8))
        else
            state.icon:SetVertexColor(AF.GetColorRGB(
                "white",
                emphasized and 0.95 or 0.55
            ))
        end
    else
        state.chrome:SetBackdropColor(AF.GetColorRGB("background", 0.65))
        state.chrome:SetBackdropBorderColor(AF.GetColorRGB("border"))
        state.icon:SetDesaturated(true)
        state.icon:SetVertexColor(AF.GetColorRGB("disabled"))
    end
end

local function RefreshControlChrome(control)
    if not IsActive() then return end

    local state = controlStates[control]
    if not state then return end

    SuppressNativeRegions(state)
    state.chrome:Show()
    UpdateControlChrome(control)
end

local function EnsureControlHooks(control)
    if control._BFIDamageMeterControlHooks then return end
    control._BFIDamageMeterControlHooks = true

    local function Refresh(self)
        RefreshControlChrome(self)
    end

    control:HookScript("OnShow", Refresh)
    control:HookScript("OnEnter", Refresh)
    control:HookScript("OnLeave", Refresh)
    control:HookScript("OnMouseDown", Refresh)
    control:HookScript("OnMouseUp", Refresh)
    control:HookScript("OnEnable", Refresh)
    control:HookScript("OnDisable", Refresh)

    if type(control.OnButtonStateChanged) == "function" then
        hooksecurefunc(control, "OnButtonStateChanged", Refresh)
    end
end

local function ApplyControlChrome(control, options, ...)
    if not control then return end

    local state = controlStates[control]
    if not state then
        state = {
            nativeRegions = {},
            danger = options.danger,
            minimizeOwner = options.minimizeOwner,
        }
        controlStates[control] = state

        for i = 1, select("#", ...) do
            CaptureNativeRegion(state, select(i, ...))
        end

        local chrome = AF.CreateBorderedFrame(control)
        state.chrome = chrome
        DisableOwnedMouse(chrome)
        -- Keep parent-owned labels (notably SessionName) above our backdrop.
        AF.SetFrameLevel(chrome, -1, control)
        if options.fill then
            chrome:SetAllPoints(control)
        else
            AF.SetSize(chrome, options.width or 18, options.height or 18)
            AF.SetPoint(chrome, "CENTER")
        end

        local icon = AF.CreateTexture(
            chrome,
            AF.GetIcon(options.icon),
            "white",
            "ARTWORK"
        )
        state.icon = icon
        AF.SetSize(icon, options.iconSize or 12, options.iconSize or 12)
        AF.SetPoint(
            icon,
            options.iconPoint or "CENTER",
            options.iconX or 0,
            options.iconY or 0
        )
        icon:SetTexCoord(0, 1, 0, 1)

        EnsureControlHooks(control)
    end

    RefreshControlChrome(control)
end

local function RestoreControlChrome(control, state)
    state.chrome:Hide()
    RestoreNativeRegions(state)

    if type(control.OnButtonStateChanged) == "function" then
        control:OnButtonStateChanged()
    end
end

local function IsButtonStateEmphasized(button)
    if button.IsOver and button:IsOver() then
        return true
    end
    if button.IsDown and button:IsDown() then
        return true
    end
    if button.GetButtonState
        and button:GetButtonState() == "PUSHED"
    then
        return true
    end
    return button:IsMouseOver()
end

local function UpdateResizeButtonChrome(button)
    local state = resizeButtonStates[button]
    if not state then return end

    AF.ClearPoints(state.chrome)
    if state.sourceWindow and not state.sourceWindow:IsRightSide() then
        AF.SetPoint(state.chrome, "BOTTOMLEFT", 8, 8)
        state.icon:SetTexCoord(1, 0, 0, 1)
    else
        AF.SetPoint(state.chrome, "BOTTOMRIGHT", -8, 8)
        state.icon:SetTexCoord(0, 1, 0, 1)
    end

    if button:IsEnabled() then
        local emphasized = IsButtonStateEmphasized(button)
        state.chrome:SetBackdropColor(AF.GetColorRGB(
            emphasized and "BFI" or "widget",
            emphasized and 0.25 or 0.65
        ))
        state.chrome:SetBackdropBorderColor(AF.GetColorRGB(
            emphasized and "BFI" or "border"
        ))
        state.icon:SetDesaturated(false)
        state.icon:SetVertexColor(AF.GetColorRGB(
            "white",
            emphasized and 0.95 or 0.5
        ))
    else
        state.chrome:SetBackdropColor(AF.GetColorRGB("background", 0.65))
        state.chrome:SetBackdropBorderColor(AF.GetColorRGB("border"))
        state.icon:SetDesaturated(true)
        state.icon:SetVertexColor(AF.GetColorRGB("disabled"))
    end
end

local function RefreshResizeButtonChrome(button)
    if not IsActive() then return end

    local state = resizeButtonStates[button]
    if not state then return end

    SuppressNativeRegions(state)
    state.chrome:Show()
    UpdateResizeButtonChrome(button)
end

local function EnsureResizeButtonHooks(button)
    if button._BFIDamageMeterResizeHooks then return end
    button._BFIDamageMeterResizeHooks = true

    local function Refresh(self)
        RefreshResizeButtonChrome(self)
    end

    button:HookScript("OnShow", Refresh)
    button:HookScript("OnEnter", Refresh)
    button:HookScript("OnLeave", Refresh)
    button:HookScript("OnMouseDown", Refresh)
    button:HookScript("OnMouseUp", Refresh)
    button:HookScript("OnEnable", Refresh)
    button:HookScript("OnDisable", Refresh)
end

local function ApplyResizeButtonChrome(button, sourceWindow)
    if not button then return end

    local state = resizeButtonStates[button]
    if not state then
        state = {
            nativeRegions = {},
            sourceWindow = sourceWindow,
        }
        resizeButtonStates[button] = state

        CaptureNativeRegion(state, button:GetNormalTexture())
        CaptureNativeRegion(state, button:GetPushedTexture())
        CaptureNativeRegion(state, button:GetHighlightTexture())

        local chrome = AF.CreateBorderedFrame(button)
        state.chrome = chrome
        DisableOwnedMouse(chrome)
        AF.SetFrameLevel(chrome, 0, button)
        AF.SetSize(chrome, 18, 18)

        local icon = AF.CreateTexture(
            chrome,
            AF.GetIcon("Resize"),
            "white",
            "ARTWORK"
        )
        state.icon = icon
        AF.SetSize(icon, 12, 12)
        AF.SetPoint(icon, "CENTER")

        EnsureResizeButtonHooks(button)
    end

    RefreshResizeButtonChrome(button)
end

local function RestoreResizeButtonChrome(_, state)
    state.chrome:Hide()
    RestoreNativeRegions(state)
end

local function UpdateScrollBarChrome(scrollBar)
    local state = scrollBarStates[scrollBar]
    if not state then return end

    local function UpdateArrow(button, icon)
        if not button:IsEnabled() then
            icon:SetDesaturated(true)
            icon:SetVertexColor(AF.GetColorRGB("disabled"))
        else
            icon:SetDesaturated(false)
            icon:SetVertexColor(AF.GetColorRGB(
                IsButtonStateEmphasized(button) and "white" or "darkgray"
            ))
        end
    end

    UpdateArrow(scrollBar.Back, state.backIcon)
    UpdateArrow(scrollBar.Forward, state.forwardIcon)

    local thumb = scrollBar:GetThumb()
    if thumb:IsEnabled() then
        local emphasized = IsButtonStateEmphasized(thumb)
        state.thumbFill:SetBackdropColor(AF.GetColorRGB(
            "BFI",
            emphasized and 0.9 or 0.65
        ))
        state.thumbFill:SetBackdropBorderColor(AF.GetColorRGB(
            emphasized and "BFI" or "border"
        ))
    else
        state.thumbFill:SetBackdropColor(AF.GetColorRGB("disabled", 0.45))
        state.thumbFill:SetBackdropBorderColor(AF.GetColorRGB("border"))
    end
end

local function RefreshScrollBarChrome(scrollBar)
    if not IsActive() then return end

    local state = scrollBarStates[scrollBar]
    if not state then return end

    SuppressNativeRegions(state)
    state.trackFill:Show()
    state.thumbFill:Show()
    state.backIcon:Show()
    state.forwardIcon:Show()
    UpdateScrollBarChrome(scrollBar)
end

local function EnsureScrollBarPartHooks(scrollBar, part)
    if part._BFIDamageMeterScrollHooks then return end
    part._BFIDamageMeterScrollHooks = true

    local function Refresh()
        RefreshScrollBarChrome(scrollBar)
    end

    part:HookScript("OnShow", Refresh)
    if type(part.OnButtonStateChanged) == "function" then
        hooksecurefunc(part, "OnButtonStateChanged", Refresh)
    end
end

local function ApplyScrollBarChrome(scrollBar)
    if not scrollBar
        or not scrollBar.Track
        or not scrollBar.Back
        or not scrollBar.Forward
        or not scrollBar.GetThumb
    then
        return
    end

    local thumb = scrollBar:GetThumb()
    if not thumb then return end

    local state = scrollBarStates[scrollBar]
    if not state then
        state = {nativeRegions = {}}
        scrollBarStates[scrollBar] = state

        local track = scrollBar.Track
        CaptureNativeRegion(state, track.Begin)
        CaptureNativeRegion(state, track.Middle)
        CaptureNativeRegion(state, track.End)
        CaptureNativeRegion(state, thumb.Begin)
        CaptureNativeRegion(state, thumb.Middle)
        CaptureNativeRegion(state, thumb.End)
        CaptureNativeRegion(state, scrollBar.Back.Texture)
        CaptureNativeRegion(state, scrollBar.Forward.Texture)

        local trackFill = AF.CreateTexture(
            track,
            nil,
            "widget_dark",
            "BACKGROUND",
            -8
        )
        state.trackFill = trackFill
        AF.SetPoint(trackFill, "TOP", track, "TOP")
        AF.SetPoint(trackFill, "BOTTOM", track, "BOTTOM")
        AF.SetWidth(trackFill, 2)

        local thumbFill = AF.CreateBorderedFrame(thumb)
        state.thumbFill = thumbFill
        DisableOwnedMouse(thumbFill)
        AF.SetFrameLevel(thumbFill, 0, thumb)
        AF.SetPoint(thumbFill, "TOPLEFT", thumb, "TOPLEFT", 1, 0)
        AF.SetPoint(
            thumbFill,
            "BOTTOMRIGHT",
            thumb,
            "BOTTOMRIGHT",
            -1,
            0
        )

        local backIcon = AF.CreateTexture(
            scrollBar.Back,
            AF.GetIcon("ArrowUp_Small"),
            "darkgray",
            "ARTWORK"
        )
        state.backIcon = backIcon
        AF.SetSize(backIcon, 10, 10)
        AF.SetPoint(backIcon, "CENTER")

        local forwardIcon = AF.CreateTexture(
            scrollBar.Forward,
            AF.GetIcon("ArrowDown_Small"),
            "darkgray",
            "ARTWORK"
        )
        state.forwardIcon = forwardIcon
        AF.SetSize(forwardIcon, 10, 10)
        AF.SetPoint(forwardIcon, "CENTER")

        EnsureScrollBarPartHooks(scrollBar, scrollBar.Back)
        EnsureScrollBarPartHooks(scrollBar, scrollBar.Forward)
        EnsureScrollBarPartHooks(scrollBar, thumb)
        if type(thumb.OnSizeChanged) == "function" then
            hooksecurefunc(thumb, "OnSizeChanged", function()
                RefreshScrollBarChrome(scrollBar)
            end)
        end
    end

    RefreshScrollBarChrome(scrollBar)
end

local function RestoreScrollBarChrome(scrollBar, state)
    state.trackFill:Hide()
    state.thumbFill:Hide()
    state.backIcon:Hide()
    state.forwardIcon:Hide()
    RestoreNativeRegions(state)

    if type(scrollBar.Back.OnButtonStateChanged) == "function" then
        scrollBar.Back:OnButtonStateChanged()
    end
    if type(scrollBar.Forward.OnButtonStateChanged) == "function" then
        scrollBar.Forward:OnButtonStateChanged()
    end

    local thumb = scrollBar:GetThumb()
    if thumb and type(thumb.OnButtonStateChanged) == "function" then
        thumb:OnButtonStateChanged()
    end
end

local function EnsureSourceWindowHooks(sourceWindow)
    if sourceWindow._BFIDamageMeterHooks then return end
    sourceWindow._BFIDamageMeterHooks = true

    hooksecurefunc(sourceWindow, "AnchorToSessionWindow", function(self)
        if IsActive() then
            RefreshResizeButtonChrome(self:GetResizeButton())
        end
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

    EnsureSourceWindowHooks(sourceWindow)
    ApplyScrollBarChrome(sourceWindow:GetScrollBar())
    ApplyResizeButtonChrome(sourceWindow:GetResizeButton(), sourceWindow)

    local closeButton = sourceWindow:GetCloseButton()
    ApplyControlChrome(
        closeButton,
        {
            icon = "Close",
            iconSize = 12,
            width = 18,
            height = 18,
            danger = true,
        },
        closeButton:GetNormalTexture(),
        closeButton:GetPushedTexture(),
        closeButton:GetHighlightTexture(),
        closeButton:GetDisabledTexture()
    )
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

local function ApplySessionControlChrome(sessionWindow)
    local typeDropdown = sessionWindow:GetDamageMeterTypeDropdown()
    ApplyControlChrome(
        typeDropdown,
        {
            icon = "ArrowDown_Small",
            iconSize = 11,
            width = 18,
            height = 18,
        },
        typeDropdown.Arrow
    )

    local sessionDropdown = sessionWindow:GetSessionDropdown()
    ApplyControlChrome(
        sessionDropdown,
        {
            icon = "ArrowDown_Small",
            iconSize = 7,
            iconPoint = "BOTTOM",
            iconY = -1,
            fill = true,
        },
        sessionDropdown.Background,
        sessionDropdown.Arrow,
        sessionDropdown.Text
    )

    local settingsDropdown = sessionWindow:GetSettingsDropdown()
    ApplyControlChrome(
        settingsDropdown,
        {
            icon = "Settings",
            iconSize = 13,
            width = 18,
            height = 18,
        },
        settingsDropdown.Icon
    )

    local minimizeButton = sessionWindow:GetMinimizeButton()
    ApplyControlChrome(
        minimizeButton,
        {
            icon = "ArrowUp1",
            iconSize = 14,
            width = 18,
            height = 18,
            minimizeOwner = sessionWindow,
        },
        minimizeButton:GetNormalTexture(),
        minimizeButton:GetPushedTexture(),
        minimizeButton:GetHighlightTexture(),
        minimizeButton:GetDisabledTexture()
    )

    ApplyScrollBarChrome(sessionWindow:GetScrollBar())
    ApplyResizeButtonChrome(sessionWindow:GetResizeButton())
end

local function EnsureSessionWindowHooks(sessionWindow)
    if sessionWindow._BFIDamageMeterHooks then return end
    sessionWindow._BFIDamageMeterHooks = true

    hooksecurefunc(sessionWindow, "UpdateBackground", function(self)
        if IsActive() then
            ApplySessionBackground(self)
        end
    end)
    hooksecurefunc(sessionWindow, "SetMinimized", function(self)
        if IsActive() then
            RefreshControlChrome(self:GetMinimizeButton())
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
            headerHeight = header:GetHeight(),
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

    sessionWindow:GetHeader():SetHeight(COMPACT_HEADER_HEIGHT)
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

    ApplySessionControlChrome(sessionWindow)
    ApplySourceWindow(sessionWindow:GetSourceWindow())
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
    sessionWindow:GetHeader():SetHeight(state.headerHeight)
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
                -- Window creation and category selection stay in Blizzard's
                -- native menu. Once setup is complete, positioning the new
                -- frame does not refresh or inspect its combat rows.
                if index > 1
                    and type(DM.ArrangeSecondaryWindows) == "function"
                then
                    PlaceSecondaryWindow(index)
                end
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
    ClearPendingSecondaryPlacements()

    for control, state in next, controlStates do
        RestoreControlChrome(control, state)
    end
    for resizeButton, state in next, resizeButtonStates do
        RestoreResizeButtonChrome(resizeButton, state)
    end
    for scrollBar, state in next, scrollBarStates do
        RestoreScrollBarChrome(scrollBar, state)
    end
    for sourceWindow, state in next, sourceWindowStates do
        RestoreSourceWindow(sourceWindow, state)
    end
    for sessionWindow, state in next, sessionWindowStates do
        RestoreSessionWindow(sessionWindow, state)
    end
end
