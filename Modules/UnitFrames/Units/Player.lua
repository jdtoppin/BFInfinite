---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local player
local indicators = {
    "healthBar",
    "powerBar",
    "extraManaBar",
    "classPowerBar",
    "nameText",
    "healthText",
    "powerText",
    "portrait",
    "castBar",
    "staggerBar",
    "combatIcon",
    "leaderIcon",
    "leaderText",
    "levelText",
    "targetCounter",
    "statusTimer",
    "statusIcon",
    "raidIcon",
    "readyCheckIcon",
    "roleIcon",
    "factionIcon",
    "restingIndicator",
    "targetHighlight",
    "mouseoverHighlight",
    "threatGlow",
    "incDmgHealText",
    {"nativeAuras", "buffs", "HELPFUL"},
    {"nativeAuras", "debuffs", "HARMFUL"},
}

-- Preset cards are ordinary, non-unit preview frames. Keep their aura
-- widgets on the legacy preview path so opening options cannot allocate
-- restricted native containers for every preset.
UF.previewIndicators = AF.Copy(indicators)
for _, indicator in ipairs(UF.previewIndicators) do
    if type(indicator) == "table" and indicator[1] == "nativeAuras" then
        indicator[1] = "auras"
    end
end

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function CreatePlayer()
    local name = "BFI_Player"
    player = CreateFrame("Button", name, UF.Parent, "BFIUnitButtonTemplate")
    player:SetAttribute("unit", "player")

    -- mover
    AF.CreateMover(player, "BFI: " .. L["Unit Frames"], _G.PLAYER)

    -- preview rect
    UF.CreatePreviewRect(player)

    -- config mode
    UF.AddToConfigMode("player", player)

    -- indicators
    player.hasCastBarTicks = true
    player.hasLatency = true
    UF.CreateIndicators(player, indicators)
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdatePlayer(_, module, which, skipIndicatorUpdates)
    if module and module ~= "unitFrames" then return end
    if which and which ~= "player" then return end

    local config = UF.config.player

    if not (UF.config.general.enabled and config.general.enabled) then
        if player then
            UF.DisableIndicators(player)
            UnregisterUnitWatch(player)
            player:Hide()
        end
        return
    end

    if not player then
        CreatePlayer()
    end

    -- setup
    UF.SetupUnitFrame(player, config, indicators, skipIndicatorUpdates)

    -- visibility NOTE: show must invoke after settings applied
    RegisterUnitWatch(player)
end
AF.RegisterCallback("BFI_UpdateModule", UpdatePlayer)
