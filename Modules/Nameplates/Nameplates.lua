---@type BFI
local BFI = select(2, ...)
---@type AbstractFramework
local AF = _G.AbstractFramework
---@class Nameplates
local NP = BFI.modules.Nameplates
local UF = BFI.modules.UnitFrames

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
    and type(AF.CreateSecretCastBar) == "function"
    and type(AF.CreateSecretNamePlateThreatIndicator) == "function"
    and type(UF) == "table"
    and type(UF.HasNativeAuraContainerBackend) == "function"
    and UF.HasNativeAuraContainerBackend() == true
    and type(UF.CreateNativeAuraIndicator) == "function"
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

function NP.GetAppliedHostileNameplateConfig()
    return appliedConfig and appliedConfig.hostile_npc
end

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

    local plateConfig = config.hostile_npc
    local healthBar = plateConfig and plateConfig.healthBar
    local threatGlow = healthBar and healthBar.threatGlow
    if not healthBar
        or not healthBar.enabled
        or not threatGlow
        or not threatGlow.enabled
    then
        return false
    end

    -- New profiles use independent presentation switches. Retain the legacy
    -- style fallback so an older profile still acquires the native carrier
    -- during migration.
    if threatGlow.border ~= nil
        or threatGlow.glow ~= nil
        or threatGlow.bar ~= nil
        or threatGlow.name ~= nil
    then
        return threatGlow.border == true
            or threatGlow.glow == true
            or threatGlow.bar == true
            or (
                threatGlow.name == true
                and plateConfig.nameText
                and plateConfig.nameText.enabled
            )
    end

    return threatGlow.style == "border"
        or threatGlow.style == "glow"
        or threatGlow.style == "both"
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

    -- Keep the protected click carrier independent from every region that
    -- consumes secret unit data. Its geometry is derived from configuration,
    -- so targeting never has to measure a restricted name or status bar.
    np.hitRegion = CreateFrame("Frame", nil, nameplate)
    np.hitRegion:EnableMouse(false)
    np.hitRegion:Hide()

    np.base = nameplate
    np.indicators = {}
    nameplate.bfi = np
    NP.created[nameplate] = np

    local function ReassertCustomHitTest()
        if np.customActive and not np.applyingCustomHitTest then
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

    -- AF's health-bar hover scripts need mouse motion on the custom root, but
    -- Retail 12.0.7 and 12.1 keep visual nameplate frames click-disabled so
    -- the native C++ hit-test carrier remains the sole click owner.
    np:SetMouseClickEnabled(false)
    np:SetMouseMotionEnabled(true)
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

    local nativeHitTestRestored = RestoreNativeHitTest(np)
    -- If the protected setter is temporarily unavailable, keep the
    -- mouse-disabled carrier alive because the native base still references
    -- it. Blizzard will replace those points on its next secure SetUnit.
    if nativeHitTestRestored or not np.customHitTest then
        np.hitRegion:Hide()
        np.hitRegionConfigured = nil
    end
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

local function MakeBounds(width, height, centerX, centerY)
    local halfWidth = width / 2
    local halfHeight = height / 2
    return {
        left = centerX - halfWidth,
        right = centerX + halfWidth,
        bottom = centerY - halfHeight,
        top = centerY + halfHeight,
    }
end

local function GetAnchoredBounds(
    width,
    height,
    position,
    relativeBounds
)
    position = position or {
        "CENTER",
        "CENTER",
        0,
        0,
    }
    local point = position[1] or "CENTER"
    local relativePoint = position[2] or "CENTER"
    local offsetX = position[3] or 0
    local offsetY = position[4] or 0
    local relativeWidth =
        relativeBounds.right - relativeBounds.left
    local relativeHeight =
        relativeBounds.top - relativeBounds.bottom
    local relativeCenterX =
        (relativeBounds.left + relativeBounds.right) / 2
    local relativeCenterY =
        (relativeBounds.bottom + relativeBounds.top) / 2
    local centerX = relativeCenterX
        + GetAnchorFactor(
            relativePoint,
            "LEFT",
            "RIGHT"
        ) * relativeWidth
        - GetAnchorFactor(point, "LEFT", "RIGHT") * width
        + offsetX
    local centerY = relativeCenterY
        + GetAnchorFactor(
            relativePoint,
            "BOTTOM",
            "TOP"
        ) * relativeHeight
        - GetAnchorFactor(point, "BOTTOM", "TOP") * height
        + offsetY

    return MakeBounds(width, height, centerX, centerY)
end

local function GetNameTextHeight(config)
    local nameText = config.nameText or {}
    local font = nameText.font or {}
    local height = font[2] or 12
    local targetIndicator = config.targetIndicator

    if targetIndicator and targetIndicator.enabled then
        for _, stateKey in ipairs({"target", "focus"}) do
            local state = targetIndicator[stateKey]
            local emphasis = state and state.nameTextEmphasis
            if emphasis and emphasis.enabled then
                height = math.max(
                    height,
                    math.max(
                        1,
                        (font[2] or 12)
                            + (emphasis.sizeDelta or 0)
                    )
                )
            end
        end
    end

    -- Include a narrow allowance for outlines and shadows without measuring
    -- the secret FontString.
    return height + 2
end

local function GetCustomHitBounds(config)
    local healthBar = config.healthBar or {}
    local rootWidth = healthBar.width or 120
    local rootHeight = healthBar.height or 13
    local rootBounds = MakeBounds(
        rootWidth,
        rootHeight,
        0,
        0
    )
    local healthBounds = GetAnchoredBounds(
        healthBar.width or rootWidth,
        healthBar.height or rootHeight,
        healthBar.position,
        rootBounds
    )

    -- Match the visible health bar exactly. Text inside the bar naturally
    -- shares this target; text outside it and the intervening gap do not.
    if healthBar.enabled then
        return healthBounds
    end

    local nameText = config.nameText or {}
    local placement = nameText.placement or "outside"
    local nameVisible = nameText.enabled
        and (
            placement == "inside"
            or nameText.parent ~= "healthBar"
        )
    if not nameVisible then
        return
    end

    local position = nameText.position
    local anchorBounds = rootBounds
    local parentWidth = rootWidth
    local length = nameText.length

    if placement == "inside" then
        position = {"CENTER", "CENTER", 0, 0}
        anchorBounds = healthBounds
        length = 0.9
    elseif nameText.anchorTo == "healthBar" then
        anchorBounds = healthBounds
    end

    -- Auto-width name-only plates can contain secret identity text, so their
    -- glyph width cannot be inspected. A root-width carrier is deterministic
    -- and bounded; fixed-length names retain their configured precision.
    local nameWidth = rootWidth
    if length and length > 0 then
        nameWidth = parentWidth * length
    end

    return GetAnchoredBounds(
        nameWidth,
        GetNameTextHeight(config),
        position,
        anchorBounds
    )
end

local function ConfigureHitRegion(np, config)
    local bounds = GetCustomHitBounds(config)
    if not bounds then
        np.hitRegion:Hide()
        np.hitRegionConfigured = nil
        return false
    end

    local healthBar = config.healthBar or {}
    if healthBar.enabled then
        local position = healthBar.position or {
            "CENTER",
            "CENTER",
            0,
            0,
        }

        -- Mirror the visible bar's AF pixel rounding and anchor tuple exactly.
        -- The carrier remains a plain frame with config-only geometry.
        AF.ClearPoints(np.hitRegion)
        AF.SetSize(
            np.hitRegion,
            healthBar.width or 120,
            healthBar.height or 13
        )
        AF.SetPoint(
            np.hitRegion,
            position[1],
            np,
            position[2],
            position[3],
            position[4]
        )
        np.hitRegion:Show()
        np.hitRegionConfigured = true
        return true
    end

    AF.ClearPoints(np.hitRegion)
    np.hitRegion:SetSize(
        math.max(1, bounds.right - bounds.left),
        math.max(1, bounds.top - bounds.bottom)
    )
    np.hitRegion:SetPoint(
        "BOTTOMLEFT",
        np.base,
        "CENTER",
        bounds.left,
        bounds.bottom
    )
    np.hitRegion:Show()
    np.hitRegionConfigured = true
    return true
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
        local bounds = plateConfig
            and GetCustomHitBounds(plateConfig)
        if bounds then
            width = math.max(
                width,
                2 * math.max(
                    math.abs(bounds.left),
                    math.abs(bounds.right)
                )
            )
            height = math.max(
                height,
                2 * math.max(
                    math.abs(bounds.bottom),
                    math.abs(bounds.top)
                )
            )
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
    if not np.hitRegion
        or not np.hitRegionConfigured
        or np.applyingCustomHitTest
        or not CanChangeHitTestPoints(np.base)
        or type(np.base.ClearAllHitTestPoints) ~= "function"
        or type(np.base.SetAllHitTestPoints) ~= "function"
    then
        return false
    end

    -- Retail 12.0.7.68887 (4383ced) and 12.1.0.68824 (fa38386) allow this
    -- protected update on the unit-assignment tick. Clear Blizzard's existing
    -- name/health anchors first, then bind the click target to a plain,
    -- numerically configured carrier. The guard keeps our secure post-hooks
    -- from recursively re-entering this sequence.
    np.applyingCustomHitTest = true
    np.base:ClearAllHitTestPoints()
    np.base:SetAllHitTestPoints(np.hitRegion)
    np.applyingCustomHitTest = nil
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

    local unitFrame = np.unitFrame
    local healthBars = unitFrame.HealthBarsContainer
    local healthBar = healthBars and healthBars.healthBar
    local setupOptions = NamePlateSetupOptions
    local healthBarHeight =
        setupOptions and setupOptions.healthBarHeight
    if not healthBar
        or type(healthBarHeight) ~= "number"
        or type(base.SetHitTestPoints) ~= "function"
    then
        return false
    end

    -- Do not call Blizzard's broad ApplyFrameOptions method here. On Retail
    -- 12.0.7 it also rewrites CompactUnitFrame state from addon execution;
    -- a reused native plate can then reach secret health comparisons under
    -- BFI taint. Restore only the documented C++ hit-test anchors copied from
    -- Blizzard_NamePlateUnitFrame.lua in 12.0.7.68887 (4383ced) and
    -- 12.1.0.68824 (fa38386). In 12.1, show-only-name plates intentionally
    -- have no hit-test anchors.
    if type(unitFrame.UpdateHitTestArea) == "function"
        and unitFrame.showOnlyName == true
    then
        if type(base.ClearAllHitTestPoints) ~= "function" then
            return false
        end
        base:ClearAllHitTestPoints()
    elseif setupOptions.unitNameInsideHealthBar then
        base:SetHitTestPoints({
            {
                point = "TOPLEFT",
                relativeTo = healthBar,
                relativePoint = "TOPLEFT",
                offsetX = -10,
                offsetY = healthBarHeight / 2,
            },
            {
                point = "BOTTOMRIGHT",
                relativeTo = healthBar,
                relativePoint = "BOTTOMRIGHT",
                offsetX = 10,
                offsetY = -healthBarHeight / 2,
            },
        })
    elseif unitFrame.name then
        base:SetHitTestPoints({
            {
                point = "TOPLEFT",
                relativeTo = unitFrame.name,
                relativePoint = "TOPLEFT",
                offsetX = -14,
                offsetY = 0,
            },
            {
                point = "BOTTOMRIGHT",
                relativeTo = healthBar,
                relativePoint = "BOTTOMRIGHT",
                offsetX = 10,
                offsetY = -healthBarHeight / 2,
            },
        })
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
    ConfigureHitRegion(np, config)

    -- Preserve the protected unit-assignment window: bind the native carrier
    -- before secret-backed visual widgets receive their unit.
    np.customActive = true
    ApplyCustomHitTest(np)

    NP.SetupIndicators(np, config)
    np:Show()
    NP.OnNameplateShow(np)

    -- Keep Blizzard's unit-frame controller alive. AF only suppresses its
    -- visual presentation; Blizzard retains protected click ownership while
    -- its hit-test points follow BFI's bar or name-only carrier.
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
            local debuffs = NP.GetIndicator(np, "debuffs")
            if debuffs then
                -- Reaction changes can invalidate the enemy-only native
                -- policy before the protected nameplate rebuild is legal.
                -- Curtain this row immediately and keep its native container
                -- opaque until the complete plate is reattached after combat.
                debuffs:Disable()
            end
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
