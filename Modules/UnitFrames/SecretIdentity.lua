---@type BFI
local BFI = select(2, ...)
local F = BFI.funcs
local UF = BFI.modules.UnitFrames
---@type AbstractFramework
local AF = _G.AbstractFramework

local IsInRaid = IsInRaid
local UnitClassBase = AF.UnitClassBase
local UnitGUID = UnitGUID
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsPlayer = UnitIsPlayer
local UnitName = UnitName
local UnitPhaseReason = UnitPhaseReason

-- Retail 12.1.0.69273 / wow-ui-source eb941aad makes several identity API
-- results secret when the unit's identity is restricted. Keep this as the
-- single BFI boundary: callers receive either an ordinary value or nil plus
-- a false access flag.
function UF.GetPublicUnitIdentityValue(value)
    if F.isValueNonSecret(value) then
        return value, true
    end
    return nil, false
end

function UF.GetPublicUnitName(unit)
    -- Use C_Unit-derived UnitName directly. FrameXML GetUnitName branches,
    -- compares, and concatenates these results before BFI can reject secrets.
    local name, server = UnitName(unit)
    local publicName, namePublic =
        UF.GetPublicUnitIdentityValue(name)
    local publicServer, serverPublic =
        UF.GetPublicUnitIdentityValue(server)
    if not namePublic or not serverPublic then
        return nil, false
    end
    if publicName == nil then
        return nil, true
    end
    if publicServer and publicServer ~= "" then
        return publicName .. "-" .. publicServer, true
    end
    return publicName, true
end

function UF.GetPublicUnitIdentitySnapshot(unit)
    local name = UF.GetPublicUnitName(unit)
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
