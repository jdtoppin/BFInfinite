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
    type(AF.SetNativeNamePlateVisualSuppressed) == "function"
    and type(AF.CreateSecretHealthBar) == "function"
    and type(AF.CreateSecretNameText) == "function"
    and type(AF.CreateSecretAuraList) == "function"
    and type(AF.CreateSecretCastBar) == "function"
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

local FULL_HIT_TEST_INSET = -10000
local FULL_HIT_TEST_INSETS = {
    left = FULL_HIT_TEST_INSET,
    right = FULL_HIT_TEST_INSET,
    top = FULL_HIT_TEST_INSET,
    bottom = FULL_HIT_TEST_INSET,
}
local FRIENDLY_NAME_PLATE = Enum.NamePlateType.Friendly
local ENEMY_NAME_PLATE = Enum.NamePlateType.Enemy

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

    np.base = nameplate
    np.indicators = {}
    nameplate.bfi = np
    NP.created[nameplate] = np

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
    local width = healthBar.width or 0
    local height = healthBar.height or 0
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

local function GetClickSize(config, faction)
    local width = config[faction .. "ClickableAreaWidth"] or 120
    local height = config[faction .. "ClickableAreaHeight"] or 40
    local npcConfig = config[faction .. "_npc"]
    local playerConfig = config[faction .. "_player"]

    if npcConfig and npcConfig.healthBar then
        local healthWidth, healthHeight =
            GetHealthBarBounds(npcConfig.healthBar)
        width = math.max(width, healthWidth)
        height = math.max(height, healthHeight)
    end
    if playerConfig and playerConfig.healthBar then
        local healthWidth, healthHeight =
            GetHealthBarBounds(playerConfig.healthBar)
        width = math.max(width, healthWidth)
        height = math.max(height, healthHeight)
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

    local friendlyWidth, friendlyHeight =
        GetClickSize(config, "friendly")
    local enemyWidth, enemyHeight =
        GetClickSize(config, "hostile")

    -- Retail 12.0.7.68887 and 12.1.0.68824 provide one shared C++
    -- nameplate size plus per-faction numeric hit-test insets. Expanding the
    -- native region to those bounds avoids measuring restricted frame regions.
    local width = math.max(
        previousClickGeometry.width,
        friendlyWidth,
        enemyWidth
    )
    local height = math.max(
        previousClickGeometry.height,
        friendlyHeight,
        enemyHeight
    )
    SetNamePlateSize(width, height)
    SetNamePlateHitTestInsets(
        FRIENDLY_NAME_PLATE,
        FULL_HIT_TEST_INSET,
        FULL_HIT_TEST_INSET,
        FULL_HIT_TEST_INSET,
        FULL_HIT_TEST_INSET
    )
    SetNamePlateHitTestInsets(
        ENEMY_NAME_PLATE,
        FULL_HIT_TEST_INSET,
        FULL_HIT_TEST_INSET,
        FULL_HIT_TEST_INSET,
        FULL_HIT_TEST_INSET
    )

    local appliedWidth, appliedHeight = GetNamePlateSize()
    local friendlyInsets = GetInsets(FRIENDLY_NAME_PLATE)
    local enemyInsets = GetInsets(ENEMY_NAME_PLATE)

    -- Another nameplate addon may synchronously reassert these globals from a
    -- secure post-hook. Only claim ownership when our entire bundle stuck.
    if appliedWidth == width
        and appliedHeight == height
        and InsetsEqual(friendlyInsets, FULL_HIT_TEST_INSETS)
        and InsetsEqual(enemyInsets, FULL_HIT_TEST_INSETS)
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

local function InsetsMatch(plateType, expectedInsets)
    return InsetsEqual(GetInsets(plateType), expectedInsets)
end

local function ClickGeometryIsApplied()
    if not appliedClickGeometry then return false end

    local width, height = GetNamePlateSize()
    return width == appliedClickGeometry.width
        and height == appliedClickGeometry.height
        and InsetsMatch(
            FRIENDLY_NAME_PLATE,
            appliedClickGeometry.friendlyInsets
        )
        and InsetsMatch(
            ENEMY_NAME_PLATE,
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

    -- Keep Blizzard's unit-frame controller alive. AF only suppresses its
    -- visual presentation; Blizzard retains click ownership while the global
    -- native hit region above covers BFI's health bar.
    AF.SetNativeNamePlateVisualSuppressed(np.unitFrame, true)
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
        ApplyClickGeometry(appliedConfig)
        SyncVisibleNameplates()
    else
        appliedConfig = nil
        for _, np in next, NP.created do
            DetachNameplate(np, false)
        end
        RestoreClickGeometry()
    end
end

local function ApplyPendingUpdate()
    ApplyModuleState()
end

local function NativeNamePlateSizeUpdated()
    if not appliedConfig
        or not previousClickGeometry
        or not appliedClickGeometry
    then
        return
    end

    -- Preserve Blizzard's newest requested size for disable/restore before BFI
    -- resumes ownership. Do not call restricted setters from combat.
    local width, height = GetNamePlateSize()
    previousClickGeometry.width = width
    previousClickGeometry.height = height
    appliedClickGeometry.width = width
    appliedClickGeometry.height = height

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
