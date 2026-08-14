
---@type BFI
local BFI = select(2, ...)
local DB = BFI.modules.DisableBlizzard
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local init
local function DisableBlizzard()
    --! require ReloadUI to take effect
    if init then return end
    init = true

    local config = DB.config

    -- manager
    if config.manager then
        F.DisableFrame(_G.CompactRaidFrameManager)
        CompactRaidFrameManager_SetSetting("IsShown", "0")
    end

    -- castBar
    if config.castBar then
        F.DisableFrame(_G.PlayerCastingBarFrame)
        F.DisableFrame(_G.PetCastingBarFrame)
    end

    -- BuffsDebuffs keeps these roots active. Its enabled harmful replacement can
    -- temporarily deregister DebuffFrame's exact six private anchors only
    -- after a replacement exists; DeadlyDebuffFrame remains Blizzard-owned.

    F.DisableEditMode(_G.EncounterBar)

    -- exp, rep, pvp
    F.Hide(_G.StatusTrackingBarManager)
end
AF.RegisterCallback("BFI_DisableBlizzard", DisableBlizzard)
