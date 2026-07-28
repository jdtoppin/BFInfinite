---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

local ADDON_NAME = "Blizzard_DamageMeter"
local active
local addonCallbackRegistered
local deferredLoadFrame
local pendingLoadCallbacks = {}

local function IsNativeAddonLoaded()
    return _G.C_AddOns.IsAddOnLoaded(ADDON_NAME)
end

function DM.IsActive()
    return active == true and DM.config and DM.config.enabled == true
end

local function UnregisterAddonCallback()
    if not addonCallbackRegistered then return end

    AF.UnregisterAddonLoaded(ADDON_NAME, DM.OnNativeAddonLoaded)
    addonCallbackRegistered = nil
end

local function CancelDeferredLoad()
    if deferredLoadFrame then
        deferredLoadFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function HasPendingLoadCallbacks()
    return #pendingLoadCallbacks > 0
end

local function AddPendingLoadCallback(callback)
    if type(callback) ~= "function" then return end

    for _, pendingCallback in ipairs(pendingLoadCallbacks) do
        if pendingCallback == callback then
            return
        end
    end

    pendingLoadCallbacks[#pendingLoadCallbacks + 1] = callback
end

local function RunPendingLoadCallbacks()
    local callbacks = pendingLoadCallbacks
    pendingLoadCallbacks = {}

    for _, callback in ipairs(callbacks) do
        callback(_G.DamageMeter)
    end
end

function DM.OnNativeAddonLoaded()
    UnregisterAddonCallback()
    CancelDeferredLoad()

    if DM.IsActive() and DM.Skin.Install() then
        DM.Skin.ApplyAll()
        if type(DM.ApplyDefaultPositionIfNeeded) == "function" then
            DM.ApplyDefaultPositionIfNeeded()
        end
    end

    RunPendingLoadCallbacks()
end

function DM.EnsureNativeLoaded(callback)
    AddPendingLoadCallback(callback)

    if IsNativeAddonLoaded() then
        DM.OnNativeAddonLoaded()
        return true
    end

    if not addonCallbackRegistered then
        addonCallbackRegistered = true
        AF.RegisterAddonLoaded(ADDON_NAME, DM.OnNativeAddonLoaded)
    end

    if _G.InCombatLockdown() then
        if not deferredLoadFrame then
            deferredLoadFrame = _G.CreateFrame("Frame")
            deferredLoadFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if DM.IsActive() or HasPendingLoadCallbacks() then
                    DM.EnsureNativeLoaded()
                end
            end)
        end
        deferredLoadFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end

    _G.C_AddOns.LoadAddOn(ADDON_NAME)
    if IsNativeAddonLoaded() then
        DM.OnNativeAddonLoaded()
        return true
    end

    return false
end

function DM.Enable()
    if active then
        if IsNativeAddonLoaded() then
            DM.Skin.ApplyAll()
            if type(DM.ApplyDefaultPositionIfNeeded) == "function" then
                DM.ApplyDefaultPositionIfNeeded()
            end
        else
            DM.EnsureNativeLoaded()
        end
        return
    end

    active = true
    DM.EnsureNativeLoaded()
end

function DM.Disable()
    if not active then
        if not HasPendingLoadCallbacks() then
            UnregisterAddonCallback()
            CancelDeferredLoad()
        end
        return
    end

    active = nil
    if not HasPendingLoadCallbacks() then
        UnregisterAddonCallback()
        CancelDeferredLoad()
    end
    DM.Skin.Disable()
end

function DM.Refresh()
    if DM.IsActive() then
        DM.EnsureNativeLoaded()
    end
end

local function UpdateDamageMeter(_, module)
    if module and module ~= "damageMeter" then return end
    if not DM.config then return end

    if DM.config.enabled then
        DM.Enable()
    else
        DM.Disable()
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateDamageMeter)

AF.RegisterCallback("BFI_UpdateFont", function()
    if DM.IsActive() then
        DM.Skin.ApplyAll()
    end
end)
