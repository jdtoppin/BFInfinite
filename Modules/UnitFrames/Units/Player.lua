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

-- Preset cards hide aura indicators. Keep them out of the preview descriptor
-- list entirely so opening Unit Frame options never binds a real unit aura
-- list before those hidden widgets can be cleaned up.
UF.previewIndicators = {}
for _, indicator in ipairs(indicators) do
    local isAuraIndicator = type(indicator) == "table"
        and (indicator[2] == "buffs" or indicator[2] == "debuffs")
    if not isAuraIndicator then
        UF.previewIndicators[#UF.previewIndicators + 1] =
            type(indicator) == "table" and AF.Copy(indicator) or indicator
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

local function RestorePlayerConfigModeIndicators()
    for _, indicator in pairs(player.indicators) do
        if indicator.EnableConfigMode then
            indicator:EnableConfigMode()
        end
    end
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

    local wasEnabled = player ~= nil and player.enabled == true
    if not player then
        CreatePlayer()
    end

    -- setup
    UF.SetupUnitFrame(
        player,
        config,
        indicators,
        skipIndicatorUpdates == true and wasEnabled
    )

    if player.inConfigMode then
        if not wasEnabled then
            RestorePlayerConfigModeIndicators()
        end
        player:Show()
    else
        -- visibility NOTE: show must invoke after settings applied
        RegisterUnitWatch(player)
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdatePlayer)
