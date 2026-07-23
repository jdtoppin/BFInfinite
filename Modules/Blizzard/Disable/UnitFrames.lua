---@type BFI
local BFI = select(2, ...)
---@class DisableBlizzard
local DB = BFI.modules.DisableBlizzard
---@type AbstractFramework
local AF = _G.AbstractFramework

-- Keep Blizzard's unit-frame controllers and event handlers active. Retail
-- nameplates share CompactUnitFrame_SetUpFrame and CompactUnitFrame_SetUnit
-- with party and raid frames, so hooking or unregistering those paths taints
-- Blizzard's subsequent secret-value updates.
local function HideVisualRoot(frame)
    if frame then
        frame:SetParent(AF.hiddenParent)
    end
end

local init
local function DisableBlizzardUnitFrames()
    -- Requires ReloadUI to restore Blizzard's visual unit frames.
    if init then return end
    init = true

    local config = DB.config

    if config.player then
        HideVisualRoot(_G.PlayerFrame)
        HideVisualRoot(_G.PetFrame)
    end

    if config.target then
        HideVisualRoot(_G.TargetFrame)
    end

    if config.focus then
        HideVisualRoot(_G.FocusFrame)
    end

    if config.party then
        HideVisualRoot(_G.PartyFrame)
        HideVisualRoot(_G.CompactPartyFrame)
    end

    if config.raid then
        HideVisualRoot(_G.CompactRaidFrameContainer)
    end

    if config.boss then
        HideVisualRoot(_G.BossTargetFrameContainer)
    end
end
AF.RegisterCallback("BFI_DisableBlizzard", DisableBlizzardUnitFrames)
