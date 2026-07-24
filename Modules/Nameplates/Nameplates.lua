---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
---@class Nameplates
local NP = BFI.modules.Nameplates

local hasNameplateGeometryAPI =
    type(C_NamePlate) == "table"
    and type(C_NamePlate.GetNamePlateSize) == "function"
    and type(C_NamePlate.SetNamePlateSize) == "function"
    and type(C_NamePlateManager) == "table"
    and type(C_NamePlateManager.GetNamePlateHitTestInsets) == "function"
    and type(C_NamePlateManager.SetNamePlateHitTestInsets) == "function"
    and type(Enum) == "table"
    and type(Enum.NamePlateType) == "table"

local hasNameplateFoundation =
    type(AF.versionNum) == "number"
    and AF.versionNum >= BFI.requiredAFVersion
    and type(AF.SetNativeNamePlateVisualSuppressed) == "function"
    and type(AF.CreateSecretHealthBar) == "function"
    and type(AF.CreateSecretNameText) == "function"
    and type(AF.CreateSecretAuraList) == "function"
    and type(AF.CreateSecretCastBar) == "function"
    and type(AF.CreateSecretNamePlateThreatIndicator) == "function"
    and hasNameplateGeometryAPI

NP.created = {}
NP.byUnit = {}
NP.foundationAvailable = hasNameplateFoundation

-- AF.RequireVersion displays the dependency warning but does not stop addon
-- loading. Keep native nameplates untouched when the required foundation is
-- unavailable.
if not hasNameplateFoundation then return end

local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local GetNamePlates = C_NamePlate.GetNamePlates
local GetNamePlateSize = C_NamePlate.GetNamePlateSize
local SetNamePlateSize = C_NamePlate.SetNamePlateSize
local GetNamePlateHitTestInsets =
    C_NamePlateManager.GetNamePlateHitTestInsets
local SetNamePlateHitTestInsets =
    C_NamePlateManager.SetNamePlateHitTestInsets
local GetCVarBitfield = C_CVar.GetCVarBitfield
local SetCVarBitfield = C_CVar.SetCVarBitfield
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack
local UnitIsEnemy = UnitIsEnemy
local UnitIsGameObject = UnitIsGameObject
local UnitIsPlayer = UnitIsPlayer
local UnitIsPVPSanctuary = UnitIsPVPSanctuary
local UnitNameplateShowsWidgetsOnly = UnitNameplateShowsWidgetsOnly

local nextNameplateID = 0
local appliedConfig
local previousClickGeometry
local appliedClickGeometry
local progressiveThreatCaptured
local previousProgressiveThreatDisplay
local ownsProgressiveThreatDisplay
local ApplyCustomHitTest
local RestoreNativeHitTest
local ApplyPendingUpdate

local ZERO_HIT_TEST_INSETS = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
}
local FRIENDLY_NAME_PLATE = Enum.NamePlateType.Friendly
local ENEMY_NAME_PLATE = Enum.NamePlateType.Enemy
local PROGRESSIVE_THREAT =
    Enum.NamePlateThreatDisplay.Progressive

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

local function IsThreatWarningConfigured(config)
    if not config then return false end

    for _, configKey in ipairs({
        "hostile_npc",
        "hostile_player",
    }) do
        local plateConfig = config[configKey]
        local healthBar = plateConfig and plateConfig.healthBar
        local threatGlow = healthBar and healthBar.threatGlow
        if healthBar
            and healthBar.enabled
            and threatGlow
            and threatGlow.enabled
        then
            return true
        end
    end
    return false
end

local function ApplyProgressiveThreatDisplay(config)
    local requested = IsThreatWarningConfigured(config)
    local current = GetCVarBitfield(
        "nameplateThreatDisplay",
        PROGRESSIVE_THREAT
    ) == true

    if requested then
        if not progressiveThreatCaptured then
            progressiveThreatCaptured = true
            previousProgressiveThreatDisplay = current
            ownsProgressiveThreatDisplay = not current
        end

        if not current then
            -- If the user or another addon turns the bit off while BFI's
            -- option remains enabled, treat that newer false value as the
            -- state to restore after BFI releases the carrier.
            if not ownsProgressiveThreatDisplay then
                previousProgressiveThreatDisplay = false
                ownsProgressiveThreatDisplay = true
            end

            -- Retail 12.0.7.68887 (4383ced) and 12.1.0.68824
            -- (fa38386) drive the native aggro carrier from this public CVar
            -- bit. Maintain it only while BFI's threat option consumes it.
            SetCVarBitfield(
                "nameplateThreatDisplay",
                PROGRESSIVE_THREAT,
                true
            )
        end
        return
    end

    -- Compare-and-swap restoration: release only the bit BFI enabled, and
    -- only while it still has BFI's applied value. Other threat-display bits
    -- remain untouched.
    if progressiveThreatCaptured
        and ownsProgressiveThreatDisplay
        and current
    then
        SetCVarBitfield(
            "nameplateThreatDisplay",
            PROGRESSIVE_THREAT,
            previousProgressiveThreatDisplay
        )
    end

    progressiveThreatCaptured = nil
    previousProgressiveThreatDisplay = nil
    ownsProgressiveThreatDisplay = nil
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

    np.base = nameplate
    np.indicators = {}
    nameplate.bfi = np
    NP.created[nameplate] = np

    local function ReassertCustomHitTest()
        if np.customActive then
            ApplyCustomHitTest(np)
        end
    end
    if type(nameplate.SetHitTestPoints) == "function" then
        hooksecurefunc(
            nameplate,
            "SetHitTestPoints",
            ReassertCustomHitTest
        )
    end
    if type(nameplate.ClearAllHitTestPoints) == "function" then
        hooksecurefunc(
            nameplate,
            "ClearAllHitTestPoints",
            ReassertCustomHitTest
        )
    end

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

local function DetachNameplate(np, clearUnit)
    local wasCustomActive = np.customActive
    np.customActive = nil

    if wasCustomActive then
        NP.OnNameplateHide(np)
    else
        NP.DisableIndicators(np)
    end

    RestoreNativeHitTest(np)
    np:Hide()

    if np.unitFrame then
        AF.SetNativeNamePlateVisualSuppressed(np.unitFrame, false)
    end

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

local function ApplyRootGeometry(np, config)
    local healthBar = config.healthBar or {}
    AF.SetSize(
        np,
        healthBar.width or 120,
        healthBar.height or 13
    )
end

local function GetAnchorFactor(point, negative, positive)
    if type(point) ~= "string" then return 0 end
    if point:find(negative, 1, true) then return -0.5 end
    if point:find(positive, 1, true) then return 0.5 end
    return 0
end

local function GetHealthBarBounds(healthBar)
    local width = healthBar.width or 120
    local height = healthBar.height or 13
    local position = healthBar.position or {
        "CENTER",
        "CENTER",
        0,
        0,
    }
    local point = position[1] or "CENTER"
    local relativePoint = position[2] or "CENTER"
    local offsetX = position[3] or 0
    local offsetY = position[4] or 0
    local centerX = (
        GetAnchorFactor(relativePoint, "LEFT", "RIGHT")
        - GetAnchorFactor(point, "LEFT", "RIGHT")
    ) * width + offsetX
    local centerY = (
        GetAnchorFactor(relativePoint, "BOTTOM", "TOP")
        - GetAnchorFactor(point, "BOTTOM", "TOP")
    ) * height + offsetY

    return width + 2 * math.abs(centerX),
        height + 2 * math.abs(centerY)
end

local function GetRequiredNamePlateSize(config)
    local width, height = 120, 13
    for _, configKey in ipairs({
        "friendly_npc",
        "friendly_player",
        "hostile_npc",
        "hostile_player",
    }) do
        local plateConfig = config[configKey]
        if plateConfig and plateConfig.healthBar then
            local healthWidth, healthHeight =
                GetHealthBarBounds(plateConfig.healthBar)
            width = math.max(width, healthWidth)
            height = math.max(height, healthHeight)
        end
    end
    return width, height
end

local function GetInsets(plateType)
    local left, right, top, bottom =
        GetNamePlateHitTestInsets(plateType)
    return {
        left = left,
        right = right,
        top = top,
        bottom = bottom,
    }
end

local function SetInsets(plateType, insets)
    SetNamePlateHitTestInsets(
        plateType,
        insets.left,
        insets.right,
        insets.top,
        insets.bottom
    )
end

local function InsetsEqual(first, second)
    return first
        and second
        and first.left == second.left
        and first.right == second.right
        and first.top == second.top
        and first.bottom == second.bottom
end

local function CaptureClickGeometry()
    if previousClickGeometry then return end

    local width, height = GetNamePlateSize()
    previousClickGeometry = {
        width = width,
        height = height,
        friendlyInsets = GetInsets(FRIENDLY_NAME_PLATE),
        enemyInsets = GetInsets(ENEMY_NAME_PLATE),
    }
end

local function ApplyClickGeometry(config)
    CaptureClickGeometry()

    local requiredWidth, requiredHeight =
        GetRequiredNamePlateSize(config)
    local width = math.max(
        previousClickGeometry.width,
        requiredWidth
    )
    local height = math.max(
        previousClickGeometry.height,
        requiredHeight
    )

    -- The per-frame hit-test anchors below provide the exact shape. Neutral
    -- manager insets keep that shape precise, while the shared native bounds
    -- remain large enough for configured custom bars.
    SetNamePlateSize(width, height)
    SetInsets(FRIENDLY_NAME_PLATE, ZERO_HIT_TEST_INSETS)
    SetInsets(ENEMY_NAME_PLATE, ZERO_HIT_TEST_INSETS)

    local appliedWidth, appliedHeight = GetNamePlateSize()
    local friendlyInsets = GetInsets(FRIENDLY_NAME_PLATE)
    local enemyInsets = GetInsets(ENEMY_NAME_PLATE)
    if appliedWidth == width
        and appliedHeight == height
        and InsetsEqual(friendlyInsets, ZERO_HIT_TEST_INSETS)
        and InsetsEqual(enemyInsets, ZERO_HIT_TEST_INSETS)
    then
        appliedClickGeometry = {
            width = appliedWidth,
            height = appliedHeight,
            friendlyInsets = friendlyInsets,
            enemyInsets = enemyInsets,
        }
    else
        appliedClickGeometry = nil
    end
end

local function ClickGeometryIsApplied()
    if not appliedClickGeometry then return false end

    local width, height = GetNamePlateSize()
    return width == appliedClickGeometry.width
        and height == appliedClickGeometry.height
        and InsetsEqual(
            GetInsets(FRIENDLY_NAME_PLATE),
            appliedClickGeometry.friendlyInsets
        )
        and InsetsEqual(
            GetInsets(ENEMY_NAME_PLATE),
            appliedClickGeometry.enemyInsets
        )
end

local function RestoreClickGeometry()
    if not previousClickGeometry then return end

    if ClickGeometryIsApplied() then
        SetNamePlateSize(
            previousClickGeometry.width,
            previousClickGeometry.height
        )
        SetInsets(
            FRIENDLY_NAME_PLATE,
            previousClickGeometry.friendlyInsets
        )
        SetInsets(
            ENEMY_NAME_PLATE,
            previousClickGeometry.enemyInsets
        )
    end

    previousClickGeometry = nil
    appliedClickGeometry = nil
end

local function CanChangeHitTestPoints(nameplate)
    return nameplate
        and type(nameplate.CanChangeHitTestPoints) == "function"
        and nameplate:CanChangeHitTestPoints()
end

ApplyCustomHitTest = function(np)
    local healthBar = NP.GetIndicator(np, "healthBar", true)
    local clickRegion = healthBar
        or NP.GetIndicator(np, "nameText", true)
    if not clickRegion
        or not CanChangeHitTestPoints(np.base)
        or type(np.base.SetAllHitTestPoints) ~= "function"
    then
        return false
    end

    -- Retail 12.0.7 and 12.1 let a nameplate bind its protected click target
    -- directly to an untainted region on the tick a unit is assigned. Using
    -- the custom bar itself gives exact targeting without reading or measuring
    -- a restricted nameplate region.
    np.base:SetAllHitTestPoints(clickRegion)
    np.customHitTest = true
    return true
end

RestoreNativeHitTest = function(np)
    if not np.customHitTest then return false end

    -- Blizzard clears NamePlateBaseMixin.unitToken before addon
    -- NAME_PLATE_UNIT_REMOVED callbacks run, then releases UnitFrame. There is
    -- no live click target to restore at that point, and both 12.0.7 and 12.1
    -- reapply native frame options before the next unit's OnUnitSet callback.
    -- Avoid asking GetFrameOptions to classify a nil unit token or touching a
    -- stale pooled frame.
    local base = np.base
    if not base
        or not np.unitFrame
        or base.UnitFrame ~= np.unitFrame
        or type(base.GetUnit) ~= "function"
        or not base:GetUnit()
    then
        np.customHitTest = nil
        return true
    end

    if not CanChangeHitTestPoints(base) then
        return false
    end

    if type(np.unitFrame.UpdateHitTestArea) == "function" then
        np.unitFrame:UpdateHitTestArea(NamePlateSetupOptions)
    elseif type(np.unitFrame.ApplyFrameOptions) == "function"
        and type(base.GetFrameOptions) == "function"
    then
        -- 12.0.7 sets the native hit-test points as part of this method;
        -- 12.1 exposes the narrower UpdateHitTestArea helper above.
        np.unitFrame:ApplyFrameOptions(
            NamePlateSetupOptions,
            base:GetFrameOptions()
        )
    else
        return false
    end

    np.customHitTest = nil
    return true
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
    ApplyRootGeometry(np, config)
    NP.SetupIndicators(np, config)

    np:Show()
    NP.OnNameplateShow(np)
    np.customActive = true
    ApplyCustomHitTest(np)

    -- Keep Blizzard's unit-frame controller alive. AF only suppresses its
    -- visual presentation; Blizzard retains protected click ownership while
    -- its hit-test points follow BFI's visible health bar.
    AF.SetNativeNamePlateVisualSuppressed(np.unitFrame, true)
end

local function UpdateTargetIndicators()
    local targetNameplate = GetNamePlateForUnit("target")
    local focusNameplate = GetNamePlateForUnit("focus")

    for nameplate, np in next, NP.created do
        if np.customActive then
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
        -- A faction change can switch the visible click carrier between the
        -- health bar and name text. Outside the protected same-tick update
        -- window, keep the current visual and hit target paired until combat
        -- ends instead of leaving a stale invisible click region.
        if InCombatLockdown() then
            NP:RegisterEvent(
                "PLAYER_REGEN_ENABLED",
                ApplyPendingUpdate
            )
            return
        end

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
        ApplyProgressiveThreatDisplay(appliedConfig)
        ApplyClickGeometry(appliedConfig)
        SyncVisibleNameplates()
    else
        appliedConfig = nil
        ApplyProgressiveThreatDisplay(nil)
        for _, np in next, NP.created do
            DetachNameplate(np, false)
        end
        RestoreClickGeometry()
    end
end

local function NamePlateCVarUpdated(_, _, cvar)
    if cvar == "nameplateThreatDisplay"
        and appliedConfig
    then
        ApplyProgressiveThreatDisplay(appliedConfig)
    end
end

local function PlayerLogout()
    -- Keep the temporary Progressive bit from persisting across a logout or
    -- reload. An enabled BFI profile will acquire it again on the next load.
    appliedConfig = nil
    ApplyProgressiveThreatDisplay(nil)
end

ApplyPendingUpdate = function()
    ApplyModuleState()
end

local function NativeNamePlateSizeUpdated()
    if not appliedConfig or not previousClickGeometry then
        return
    end

    -- Preserve Blizzard's newest requested native bounds for disable/restore,
    -- then reapply BFI's required bounds when restricted setters are legal.
    local width, height = GetNamePlateSize()
    previousClickGeometry.width = width
    previousClickGeometry.height = height
    if appliedClickGeometry then
        appliedClickGeometry.width = width
        appliedClickGeometry.height = height
    end

    if InCombatLockdown() then
        NP:RegisterEvent(
            "PLAYER_REGEN_ENABLED",
            ApplyPendingUpdate
        )
    else
        ApplyClickGeometry(appliedConfig)
    end
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
NP:RegisterEvent("CVAR_UPDATE", NamePlateCVarUpdated)
NP:RegisterEvent("PLAYER_LOGOUT", PlayerLogout)
NP:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateTargetIndicators)
NP:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateTargetIndicators)
if NamePlateDriverFrame
    and type(NamePlateDriverFrame.UpdateNamePlateSize) == "function"
then
    hooksecurefunc(
        NamePlateDriverFrame,
        "UpdateNamePlateSize",
        NativeNamePlateSizeUpdated
    )
end
AF.RegisterCallback("BFI_UpdateModule", UpdateNameplates)
