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

function DM.OnNativeAddonLoaded()
    UnregisterAddonCallback()
    if not DM.IsActive() then return end

    if DM.Skin.Install() then
        DM.Skin.ApplyAll()
    end
end

local function LoadNativeAddon()
    if not DM.IsActive() then return end

    if IsNativeAddonLoaded() then
        DM.OnNativeAddonLoaded()
        return
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
                if DM.IsActive() then
                    LoadNativeAddon()
                end
            end)
        end
        deferredLoadFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    _G.C_AddOns.LoadAddOn(ADDON_NAME)
    if IsNativeAddonLoaded() then
        DM.OnNativeAddonLoaded()
    end
end

function DM.Enable()
    if active then
        if IsNativeAddonLoaded() then
            DM.Skin.ApplyAll()
        else
            LoadNativeAddon()
        end
        return
    end

    active = true
    LoadNativeAddon()
end

function DM.Disable()
    if not active then
        UnregisterAddonCallback()
        CancelDeferredLoad()
        return
    end

    active = nil
    UnregisterAddonCallback()
    CancelDeferredLoad()
    DM.Skin.Disable()
end

function DM.Refresh()
    if DM.IsActive() then
        LoadNativeAddon()
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
