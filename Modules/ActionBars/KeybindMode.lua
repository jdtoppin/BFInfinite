---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class ActionBars
local AB = BFI.modules.ActionBars
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local QUICK_KEYBIND_ADDON = "Blizzard_QuickKeybind"

local registeredButtons = {}
local overlays = {}
local quickKeybindHooked = false
local keybindModeActive = false

local keybindOverlayParent = CreateFrame("Frame", "BFIKeybindOverlayParent", AF.UIParent)
keybindOverlayParent:SetAllPoints(AF.UIParent)
keybindOverlayParent:SetFrameStrata("HIGH")
keybindOverlayParent:Hide()

---------------------------------------------------------------------
-- overlays
---------------------------------------------------------------------
local function UpdateOverlay(overlay)
    local button = overlay.button
    local shown = keybindModeActive and button:IsShown() and not button:GetAttribute("statehidden")

    overlay:SetShown(shown)
end

local function CreateOverlay(button, commandName)
    local overlay = CreateFrame("Button", nil, keybindOverlayParent, "QuickKeybindButtonTemplate")
    overlay.button = button
    overlay.commandName = commandName
    overlay:SetAllPoints(button)
    overlay:RegisterForClicks("AnyUp")
    overlay:EnableMouse(true)

    -- Keep the click-blocking native overlay without Blizzard's rounded action-button art.
    overlay.QuickKeybindHighlightTexture:Hide()

    button:HookScript("OnShow", function()
        UpdateOverlay(overlay)
    end)
    button:HookScript("OnHide", function()
        overlay:Hide()
    end)

    overlays[button] = overlay
    UpdateOverlay(overlay)
end

local function CreateOverlays()
    for button, commandName in pairs(registeredButtons) do
        local overlay = overlays[button]
        if overlay then
            overlay.commandName = commandName
        else
            CreateOverlay(button, commandName)
        end
    end
end

function AB.CreateKeybindOverlay(button, commandName)
    registeredButtons[button] = commandName

    local overlay = overlays[button]
    if overlay then
        overlay.commandName = commandName
    end
end

---------------------------------------------------------------------
-- Blizzard Quick Keybind integration
---------------------------------------------------------------------
local function OnQuickKeybindShow()
    keybindModeActive = true
    CreateOverlays()
    keybindOverlayParent:Show()

    for _, overlay in pairs(overlays) do
        UpdateOverlay(overlay)
    end
end

local function OnQuickKeybindHide()
    keybindModeActive = false
    keybindOverlayParent:Hide()
end

local function SkinQuickKeybind(frame)
    if frame._BFIKeybindStyled then return end
    frame._BFIKeybindStyled = true

    S.RemoveTextures(frame.BG, true)
    S.RemoveTextures(frame.Header, true)

    S.CreateBackdrop(frame)
    AF.ShowNormalGlow(frame, "shadow", 2)

    S.CreateBackdrop(frame.Header)
    AF.ClearPoints(frame.Header.BFIBackdrop)
    AF.SetPoint(frame.Header.BFIBackdrop, "BOTTOMLEFT", frame, "TOPLEFT", 0, -1)
    AF.SetPoint(frame.Header.BFIBackdrop, "BOTTOMRIGHT", frame, "TOPRIGHT", 0, -1)
    AF.SetHeight(frame.Header.BFIBackdrop, 20)
    frame.Header.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("header"))

    frame.Header.Text:SetText("BFI " .. L["Keybind Mode"])
    frame.Header.Text:SetTextColor(AF.GetColorRGB("BFI"))

    S.StyleButton(frame.OkayButton, "BFI")
    S.StyleButton(frame.CancelButton)
    S.StyleButton(frame.DefaultsButton)
    S.StyleCheckButton(frame.UseCharacterBindingsButton, 15)
end

local function EnsureQuickKeybind()
    if not _G.QuickKeybindFrame then
        C_AddOns.LoadAddOn(QUICK_KEYBIND_ADDON)
    end

    local frame = _G.QuickKeybindFrame
    if not frame then
        return
    end

    if not quickKeybindHooked then
        quickKeybindHooked = true
        SkinQuickKeybind(frame)
        frame:HookScript("OnShow", OnQuickKeybindShow)
        frame:HookScript("OnHide", OnQuickKeybindHide)
    end

    return frame
end

function AB.ActivateKeybindMode()
    if InCombatLockdown() then return end

    local frame = EnsureQuickKeybind()
    if frame then
        ShowUIPanel(frame)
    end
end

function AB.DeactivateKeybindMode()
    if InCombatLockdown() then return end

    local frame = _G.QuickKeybindFrame
    if frame and frame:IsShown() then
        frame:CancelBinding()
    end
end

function AB.IsKeybindModeActive()
    return keybindModeActive
end

AF.RegisterCallback("AF_PLAYER_LOGIN_DELAYED", EnsureQuickKeybind)

---------------------------------------------------------------------
-- deactivate keybind mode on module update
---------------------------------------------------------------------
AF.RegisterCallback("BFI_UpdateModule", function(_, module)
    if module ~= "actionBars" then return end
    if not keybindModeActive then return end
    AB.DeactivateKeybindMode()
end)
