---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local targettarget
local UnitWatchRegistered = UnitWatchRegistered
local indicators = {
    "healthBar",
    "powerBar",
    "nameText",
    "healthText",
    "powerText",
    "levelText",
    "targetCounter",
    "portrait",
    "castBar",
    "raidIcon",
    "roleIcon",
    "targetHighlight",
    "mouseoverHighlight",
    "threatGlow",
    {"nativeAuras", "buffs", "HELPFUL"},
    {"nativeAuras", "debuffs", "HARMFUL"},
}

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function CreateTargetTarget()
    local name = "BFI_TargetTarget"
    targettarget = CreateFrame("Button", name, UF.Parent, "BFIUnitButtonTemplate")
    targettarget:SetAttribute("unit", "targettarget")
    -- targettarget._refreshOnUpdate = true
    targettarget._updateOnPlayerTargetChanged = true
    targettarget._updateOnUnitTargetChanged = "target"
    targettarget._skipDataCache = true -- BFI.vars.guids/names

    -- mover
    AF.CreateMover(targettarget, "BFI: " .. L["Unit Frames"], L["Target Target"])

    -- preview rect
    UF.CreatePreviewRect(targettarget)

    -- config mode
    UF.AddToConfigMode("targettarget", targettarget)

    -- indicators
    UF.CreateIndicators(targettarget, indicators)
end

local function RestoreTargetTargetConfigModeIndicators()
    for _, indicator in pairs(targettarget.indicators) do
        if indicator.EnableConfigMode then
            indicator:EnableConfigMode()
        end
    end
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateTargetTarget(_, module, which, skipIndicatorUpdates)
    if module and module ~= "unitFrames" then return end
    if which and which ~= "targettarget" then return end

    local config = UF.config.targettarget

    if not (UF.config.general.enabled and config.general.enabled) then
        if targettarget then
            UF.DisableIndicators(targettarget)
            if UnitWatchRegistered(targettarget) then
                UnregisterUnitWatch(targettarget)
            end
            targettarget:Hide()
        end
        return
    end

    local wasEnabled =
        targettarget ~= nil and targettarget.enabled == true
    if not targettarget then
        CreateTargetTarget()
    end

    -- setup
    UF.SetupUnitFrame(
        targettarget,
        config,
        indicators,
        skipIndicatorUpdates == true and wasEnabled
    )

    if targettarget.inConfigMode then
        if not wasEnabled then
            RestoreTargetTargetConfigModeIndicators()
        end
        targettarget:Show()
    elseif not UnitWatchRegistered(targettarget) then
        -- visibility NOTE: show must invoke after settings applied
        RegisterUnitWatch(targettarget)
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateTargetTarget)
