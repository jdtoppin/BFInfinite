---@type BFI
local BFI = select(2, ...)
local F = BFI.funcs
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local GetUnitName = GetUnitName
local IsInRaid = IsInRaid
local UnitClassBase = AF.UnitClassBase
local UnitGUID = UnitGUID
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsPlayer = UnitIsPlayer
local UnitPhaseReason = UnitPhaseReason

-- Retail 12.1 PTR 7 makes several identity APIs secret when the unit's
-- identity is secret. Keep this as the single BFI boundary: callers receive
-- either an ordinary value or nil plus a false access flag.
function UF.GetPublicUnitIdentityValue(value)
    if F.isValueNonSecret(value) then
        return value, true
    end
    return nil, false
end

function UF.GetPublicUnitIdentitySnapshot(unit)
    local name = UF.GetPublicUnitIdentityValue(GetUnitName(unit, true))
    local class = UF.GetPublicUnitIdentityValue(UnitClassBase(unit))
    local guid = UF.GetPublicUnitIdentityValue(UnitGUID(unit))
    local isPlayer = UF.GetPublicUnitIdentityValue(UnitIsPlayer(unit))
    local inVehicle =
        UF.GetPublicUnitIdentityValue(UnitHasVehicleUI(unit))

    return {
        name = name,
        class = class,
        guid = guid,
        isPlayer = isPlayer,
        inVehicle = inVehicle,
    }
end

function UF.GetPublicUnitGroupRole(unit)
    return UF.GetPublicUnitIdentityValue(
        UnitGroupRolesAssigned(unit)
    )
end

function UF.GetPublicUnitLeadership(unit)
    local isLeader, leaderPublic =
        UF.GetPublicUnitIdentityValue(UnitIsGroupLeader(unit))
    if not leaderPublic then
        return false, false, false
    end

    local isAssistant = false
    if IsInRaid() then
        local assistantPublic
        isAssistant, assistantPublic =
            UF.GetPublicUnitIdentityValue(
                UnitIsGroupAssistant(unit)
            )
        if not assistantPublic then
            return false, false, false
        end
    end

    return isLeader == true, isAssistant == true, true
end

function UF.GetPublicUnitPhaseReason(unit)
    return UF.GetPublicUnitIdentityValue(UnitPhaseReason(unit))
end
