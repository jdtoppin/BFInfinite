---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local boss
local UnitWatchRegistered = UnitWatchRegistered
local indicators = {
    "healthBar",
    "powerBar",
    "nameText",
    "healthText",
    "powerText",
    "portrait",
    "castBar",
    "levelText",
    -- "targetCounter", -- not possible with secrets
    "raidIcon",
    "targetHighlight",
    "mouseoverHighlight",
    {"auras", "buffs", "HELPFUL"},
    {"nativeAuras", "debuffs", "HARMFUL"},
}

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function CreateBoss()
    local name = "BFI_Boss"
    boss = CreateFrame("Frame", name, AF.UIParent, "SecureFrameTemplate")
    UF.AddToConfigMode("boss.container", boss)

    for i = 1, 8 do
        boss[i] = CreateFrame("Button", name .. i, boss, "BFIUnitButtonTemplate")
        boss[i]:SetAttribute("unit", "boss" .. i)
        UF.AddToConfigMode("boss", boss[i])
        UF.CreateIndicators(boss[i], indicators)
        UF.CreatePreviewRect(boss[i])
    end

    boss.driverKey = "state-visibility"
    boss.driverValue = "[@boss1,exists] show;hide"

    -- mover
    AF.CreateMover(boss, "BFI: " .. L["Unit Frames"], _G.BOSS)

    -- pixel perfect
    AF.AddToPixelUpdater_Auto(boss, nil, true)
end

local function RestoreBossConfigModeIndicators()
    for i = 1, 8 do
        for _, indicator in pairs(boss[i].indicators) do
            if indicator.EnableConfigMode then
                indicator:EnableConfigMode()
            end
        end
    end
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateBoss(_, module, which, skipIndicatorUpdates)
    if module and module ~= "unitFrames" then return end
    if which and which ~= "boss" then return end

    local config = UF.config.boss

    if not (UF.config.general.enabled and config.general.enabled) then
        if boss then
            UnregisterAttributeDriver(boss)
            for i = 1, 8 do
                if UnitWatchRegistered(boss[i]) then
                    UnregisterUnitWatch(boss[i])
                end
                UF.DisableIndicators(boss[i])
            end
            boss.enabled = false -- for mover
            boss:Hide()
        end
        return
    end

    local wasEnabled = boss ~= nil and boss.enabled == true
    if not boss then
        CreateBoss()
    end

    boss.enabled = true -- for mover

    -- setup
    UF.SetupUnitGroup(
        boss,
        config,
        indicators,
        skipIndicatorUpdates == true and wasEnabled
    )

    for i = 1, 8 do
        if not boss[i].inConfigMode
            and not UnitWatchRegistered(boss[i])
        then
            -- Register only after every indicator is configured. This also
            -- restores watches removed by the disabled-module path.
            RegisterUnitWatch(boss[i])
        end
    end

    if boss.inConfigMode then
        -- The disabled path hides the container. Re-enabling while Boss
        -- config mode owns visibility must restore both the indicator
        -- preview methods and the container directly.
        if not wasEnabled then
            RestoreBossConfigModeIndicators()
        end
        boss:Show()
    else
        -- visibility NOTE: show must invoke after settings applied
        RegisterAttributeDriver(boss, boss.driverKey, boss.driverValue)
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateBoss)
