---@type BFI
local BFI = select(2, ...)
local L = BFI.L
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local pet
local UnitWatchRegistered = UnitWatchRegistered
local indicators = {
    "healthBar",
    "powerBar",
    "nameText",
    "healthText",
    "powerText",
    "portrait",
    "castBar",
    "combatIcon",
    "levelText",
    "targetCounter",
    "raidIcon",
    "targetHighlight",
    "mouseoverHighlight",
    "threatGlow",
    {"nativeAuras", "buffs", "HELPFUL"},
    {"nativeAuras", "debuffs", "HARMFUL"},
}

---------------------------------------------------------------------
-- create
---------------------------------------------------------------------
local function CreatePet()
    local name = "BFI_Pet"
    pet = CreateFrame("Button", name, UF.Parent, "BFIUnitButtonTemplate")
    pet:SetAttribute("unit", "pet")
    pet._updateOnUnitPetChanged = "player"

    -- mover
    AF.CreateMover(pet, "BFI: " .. L["Unit Frames"], _G.PET)

    -- preview rect
    UF.CreatePreviewRect(pet)

    -- config mode
    UF.AddToConfigMode("pet", pet)

    -- indicators
    UF.CreateIndicators(pet, indicators)
end

local function RestorePetConfigModeIndicators()
    for _, indicator in pairs(pet.indicators) do
        if indicator.EnableConfigMode then
            indicator:EnableConfigMode()
        end
    end
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdatePet(_, module, which, skipIndicatorUpdates)
    if module and module ~= "unitFrames" then return end
    if which and which ~= "pet" then return end

    local config = UF.config.pet

    if not (UF.config.general.enabled and config.general.enabled) then
        if pet then
            UF.DisableIndicators(pet)
            if UnitWatchRegistered(pet) then
                UnregisterUnitWatch(pet)
            end
            pet:Hide()
        end
        return
    end

    local wasEnabled = pet ~= nil and pet.enabled == true
    if not pet then
        CreatePet()
    end

    -- setup
    UF.SetupUnitFrame(
        pet,
        config,
        indicators,
        skipIndicatorUpdates == true and wasEnabled
    )

    if pet.inConfigMode then
        if not wasEnabled then
            RestorePetConfigModeIndicators()
        end
        pet:Show()
    elseif not UnitWatchRegistered(pet) then
        -- visibility NOTE: show must invoke after settings applied
        RegisterUnitWatch(pet)
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdatePet)
