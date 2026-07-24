---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
---@class Nameplates
local NP = BFI.modules.Nameplates

local hasNameplateFoundation =
    type(AF.SetNativeNamePlateVisualSuppressed) == "function"
    and type(AF.CreateSecretHealthBar) == "function"
    and type(AF.CreateSecretNameText) == "function"
    and type(AF.CreateSecretAuraList) == "function"
    and type(AF.CreateSecretCastBar) == "function"

NP.created = {}
NP.byUnit = {}
NP.foundationAvailable = hasNameplateFoundation

-- AF.RequireVersion displays the dependency warning but does not stop addon
-- loading. Keep native nameplates untouched when the required foundation is
-- unavailable.
if not hasNameplateFoundation then return end

local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local GetNamePlates = C_NamePlate.GetNamePlates
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack
local UnitIsEnemy = UnitIsEnemy
local UnitIsGameObject = UnitIsGameObject
local UnitIsPlayer = UnitIsPlayer
local UnitIsPVPSanctuary = UnitIsPVPSanctuary
local UnitNameplateShowsWidgetsOnly = UnitNameplateShowsWidgetsOnly

local nextNameplateID = 0
local appliedConfig

local function GetConfigKey(unit)
    local isPlayer = UnitIsPlayer(unit)
    local isHostile = UnitIsEnemy("player", unit)
        or UnitCanAttack("player", unit)

    if isPlayer and UnitIsPVPSanctuary(unit) then
        isHostile = false
    end

    if isPlayer then
        return isHostile and "hostile_player" or "friendly_player"
    end
    return isHostile and "hostile_npc" or "friendly_npc"
end

local function CreateNameplate(nameplate)
    local np = NP.created[nameplate]
    if np then return np end

    nextNameplateID = nextNameplateID + 1
    np = CreateFrame(
        "Frame",
        "BFI_NamePlate" .. nextNameplateID,
        nameplate
    )
    np:Hide()
    np:SetPoint("CENTER")
    np:SetSize(120, 13)
    np:SetFrameLevel(nameplate:GetFrameLevel() + 100)

    np.hitRegion = CreateFrame("Frame", nil, np)
    np.hitRegion:SetPoint("CENTER")
    np.hitRegion:SetSize(120, 40)

    np.base = nameplate
    np.indicators = {}
    nameplate.bfi = np
    NP.created[nameplate] = np

    -- Blizzard can recalculate native click geometry after style/CVar changes.
    -- Treat its anchor table as opaque, retain it for restoration, and redirect
    -- hit testing again on the same permitted update tick.
    hooksecurefunc(nameplate, "SetHitTestPoints", function(_, points)
        if not np.customActive then return end

        np.nativeHitTestPoints = points
        if nameplate:CanChangeHitTestPoints() then
            nameplate:SetAllHitTestPoints(np.hitRegion)
        end
    end)

    NP.CreateIndicators(np)
    return np
end

function NP.GetNameplateForUnit(unit)
    local nameplate = GetNamePlateForUnit(unit)
    if nameplate then
        return NP.created[nameplate], nameplate.UnitFrame
    end
end

function NP.IterateAllVisibleNameplates(func, configKey)
    for _, np in next, NP.created do
        if np.customActive
            and (not configKey or configKey == np.configKey)
        then
            func(np)
        end
    end
end

local function RestoreHitTest(np, discard)
    if np.nativeHitTestPoints
        and np.base:CanChangeHitTestPoints()
    then
        np.base:SetHitTestPoints(np.nativeHitTestPoints)
        np.nativeHitTestPoints = nil
    elseif discard then
        -- Blizzard replaces these points on the next unit-assignment tick.
        np.nativeHitTestPoints = nil
    end
end

local function UpdateHitTest(np)
    if not np.base:CanChangeHitTestPoints() then return end

    if not np.nativeHitTestPoints then
        np.nativeHitTestPoints = np.base:GetHitTestPoints()
    end

    np.base:SetAllHitTestPoints(np.hitRegion)
end

local function DetachNameplate(np, clearUnit)
    if np.customActive then
        NP.OnNameplateHide(np)
    else
        NP.DisableIndicators(np)
    end

    np.customActive = nil
    np:Hide()

    if np.unitFrame then
        AF.SetNativeNamePlateVisualSuppressed(np.unitFrame, false)
    end
    RestoreHitTest(np, clearUnit)

    if clearUnit then
        if np.unit then
            NP.byUnit[np.unit] = nil
        end
        np.unit = nil
        np.unitFrame = nil
        np.configKey = nil
    end
end

local function IsNativeOnlyNameplate(np, unit)
    if np.base:IsForbidden()
        or not np.unitFrame
        or np.unitFrame:IsForbidden()
    then
        return true
    end

    if np.base == GetNamePlateForUnit("player") then
        return true
    end

    return UnitNameplateShowsWidgetsOnly(unit)
        or UnitIsGameObject(unit)
end

local function ApplyRootGeometry(np, config, configKey)
    local healthBar = config.healthBar or {}
    AF.SetSize(
        np,
        healthBar.width or 120,
        healthBar.height or 13
    )

    local faction = configKey:match("^hostile")
        and "hostile"
        or "friendly"
    AF.SetSize(
        np.hitRegion,
        appliedConfig[faction .. "ClickableAreaWidth"] or 120,
        appliedConfig[faction .. "ClickableAreaHeight"] or 40
    )
end

local function AttachNameplate(np, unit)
    if np.unit and np.unit ~= unit then
        NP.byUnit[np.unit] = nil
    end
    np.unit = unit
    np.unitFrame = np.base.UnitFrame
    NP.byUnit[unit] = np

    if not appliedConfig
        or IsNativeOnlyNameplate(np, unit)
    then
        DetachNameplate(np, false)
        return
    end

    if np.customActive then
        NP.OnNameplateHide(np)
    end
    np.customActive = nil
    np:Hide()

    local configKey = GetConfigKey(unit)
    local config = appliedConfig[configKey]
    if not config then
        DetachNameplate(np, false)
        return
    end

    np.configKey = configKey
    np:SetFrameLevel(np.base:GetFrameLevel() + 100)
    ApplyRootGeometry(np, config, configKey)
    NP.SetupIndicators(np, config)

    np:Show()
    NP.OnNameplateShow(np)
    np.customActive = true

    -- Keep Blizzard's unit-frame controller alive. AF only suppresses its
    -- visual presentation and preserves WidgetContainer.
    AF.SetNativeNamePlateVisualSuppressed(np.unitFrame, true)
    UpdateHitTest(np)
end

local function UpdateTargetIndicators()
    local targetNameplate = GetNamePlateForUnit("target")
    local focusNameplate = GetNamePlateForUnit("focus")

    for nameplate, np in next, NP.created do
        if np.customActive then
            np:SetFrameLevel(nameplate:GetFrameLevel() + 100)
            local indicator = NP.GetIndicator(
                np,
                "targetIndicator",
                true
            )
            if indicator then
                indicator:SetTargetState(
                    nameplate == targetNameplate,
                    nameplate == focusNameplate
                )
            end
        end
    end
end
NP.UpdateTargetIndicators = UpdateTargetIndicators

local function NamePlateCreated(_, _, nameplate)
    if appliedConfig and not nameplate:IsForbidden() then
        CreateNameplate(nameplate)
    end
end

local function NamePlateUnitAdded(_, _, unit)
    if not appliedConfig then return end

    local nameplate = GetNamePlateForUnit(unit)
    if not nameplate or nameplate:IsForbidden() then return end

    local np = CreateNameplate(nameplate)
    AttachNameplate(np, unit)
    UpdateTargetIndicators()
end

local function NamePlateUnitRemoved(_, _, unit)
    local np = NP.byUnit[unit]
    if not np then
        local nameplate = GetNamePlateForUnit(unit)
        np = nameplate and NP.created[nameplate]
    end
    if np then
        DetachNameplate(np, true)
    end
end

local function NamePlateFactionChanged(_, _, unit)
    local np = NP.byUnit[unit]
    if np then
        AttachNameplate(np, unit)
        UpdateTargetIndicators()
    end
end

local function SyncVisibleNameplates()
    for _, nameplate in next, GetNamePlates() do
        if not nameplate:IsForbidden() then
            local unit = nameplate:GetUnit()
            if unit then
                AttachNameplate(CreateNameplate(nameplate), unit)
            end
        end
    end

    UpdateTargetIndicators()
end

local function ApplyModuleState()
    NP:UnregisterEvent("PLAYER_REGEN_ENABLED")

    if NP.config and NP.config.enabled then
        appliedConfig = AF.Copy(NP.config)
        SyncVisibleNameplates()
    else
        appliedConfig = nil
        for _, np in next, NP.created do
            DetachNameplate(np, false)
        end
    end
end

local function ApplyPendingUpdate()
    ApplyModuleState()
end

local function UpdateNameplates(_, module)
    if module and module ~= "nameplates" then return end

    if InCombatLockdown() then
        NP:RegisterEvent(
            "PLAYER_REGEN_ENABLED",
            ApplyPendingUpdate
        )
        return
    end

    ApplyModuleState()
end

NP:RegisterEvent("NAME_PLATE_CREATED", NamePlateCreated)
NP:RegisterEvent("NAME_PLATE_UNIT_ADDED", NamePlateUnitAdded)
NP:RegisterEvent("NAME_PLATE_UNIT_REMOVED", NamePlateUnitRemoved)
NP:RegisterEvent("UNIT_FACTION", NamePlateFactionChanged)
NP:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateTargetIndicators)
NP:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateTargetIndicators)
AF.RegisterCallback("BFI_UpdateModule", UpdateNameplates)
