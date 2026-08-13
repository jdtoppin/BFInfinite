local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local secret = {}
local state = {
    guid = "Player-1",
    guidCalls = 0,
    identityChecks = 0,
    indicatorUpdates = 0,
    isPlayer = true,
    snapshotPublic = true,
    unitIsPlayerCalls = 0,
}
local UF = {}
local AF = {}
local BFI = {
    funcs = {},
    modules = {
        UnitFrames = UF,
    },
    vars = {},
}

function UF.GetPublicUnitIdentityValue(value)
    state.identityChecks = state.identityChecks + 1
    if value == secret then
        return nil, false
    end
    return value, true
end

function UF.GetPublicUnitIdentitySnapshot(unit)
    if not state.snapshotPublic then
        return {
            name = nil,
            class = nil,
            guid = nil,
            isPlayer = nil,
            inVehicle = nil,
        }
    end
    return {
        name = "Public-Realm",
        class = "MAGE",
        guid = state.guid,
        isPlayer = state.isPlayer,
        inVehicle = false,
    }
end

function UF.OnButtonHide()
end

function UF.OnButtonShow()
end

function UF.UpdateIndicators(_, force)
    state.indicatorUpdates = state.indicatorUpdates + 1
    state.lastForce = force
end

function AF.AddToPixelUpdater_Auto()
end

function AF.RegisterCallback()
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    Mixin = function(target, mixin)
        for key, value in pairs(mixin) do
            target[key] = value
        end
        return target
    end,
    PingableType_UnitFrameMixin = {},
    UnitExists = function()
        return true
    end,
    UnitGUID = function()
        state.guidCalls = state.guidCalls + 1
        return state.guid
    end,
    UnitHasVehicleUI = function()
        return false
    end,
    UnitIsPlayer = function()
        state.unitIsPlayerCalls =
            state.unitIsPlayerCalls + 1
        return state.isPlayer
    end,
    error = error,
    next = next,
    pairs = pairs,
    select = select,
    strfind = string.find,
    strmatch = string.match,
    tostring = tostring,
    wipe = function(target)
        for key in pairs(target) do
            target[key] = nil
        end
    end,
}
environment._G = environment
setmetatable(environment, {
    __index = function(_, key)
        if key == "UnitIsUnit" then
            error(
                "UnitButton must not access identity-sensitive UnitIsUnit",
                2
            )
        end
        error("unexpected UnitButton global: " .. tostring(key), 2)
    end,
})

local chunk, loadError =
    loadfile("Modules/UnitFrames/UnitButton.lua")
assertTrue(chunk, loadError)
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local frame = {
    attributes = {},
    effectiveUnit = "targettarget",
    hooks = {},
    indicators = {},
    scripts = {},
    shown = true,
    states = {},
    tooltip = {
        enabled = false,
    },
    unit = "targettarget",
    _updateOnUnitTargetChanged = "target",
}

function frame:GetName()
    return "BFI_TargetTarget"
end

function frame:HookScript(name, callback)
    self.hooks[name] = callback
end

function frame:IsVisible()
    return self.shown
end

function frame:RegisterEvent()
end

function frame:RegisterForClicks()
end

function frame:RegisterUnitEvent()
end

function frame:SetAttribute(key, value)
    self.attributes[key] = value
end

function frame:SetScript(name, callback)
    self.scripts[name] = callback
end

function frame:UnregisterAllEvents()
end

environment.BFIUnitButton_OnLoad(frame)
frame.unit = "targettarget"
frame.effectiveUnit = "targettarget"
frame._updateOnUnitTargetChanged = "target"
frame.hooks.OnShow(frame)

frame.scripts.OnEvent(frame, "UNIT_TARGET", "target")
assertEqual(state.indicatorUpdates, 1,
    "UNIT_TARGET routed update count")
assertEqual(state.lastForce, true,
    "UNIT_TARGET routed force flag")

frame.scripts.OnUpdate(frame, 0.25)
frame.scripts.OnUpdate(frame, 0.25)
assertEqual(state.guidCalls, 1,
    "identical unit tokens reuse the effective GUID query")
assertEqual(state.unitIsPlayerCalls, 1,
    "public GUID checks UnitIsPlayer")
assertEqual(frame.__effectiveGuid, "Player-1",
    "public effective GUID is cached")
assertEqual(frame.__unitGuid, "Player-1",
    "public player GUID is cached")

state.guid = secret
state.snapshotPublic = false
frame.scripts.OnEvent(frame, "UNIT_NAME_UPDATE", "targettarget")
frame.scripts.OnUpdate(frame, 0.25)
frame.scripts.OnUpdate(frame, 0.25)
assertEqual(state.guidCalls, 2,
    "secret transition still queries one effective GUID")
assertEqual(state.unitIsPlayerCalls, 1,
    "secret GUID short-circuits UnitIsPlayer")
assertEqual(frame.__effectiveGuid, nil,
    "secret transition clears effective GUID")
assertEqual(frame.__unitGuid, nil,
    "secret transition clears prior public unit GUID")
assertEqual(frame.states.name, nil,
    "secret transition clears cached name")
assertEqual(frame.states.class, nil,
    "secret transition clears cached class")
assertEqual(frame.states.guid, nil,
    "secret transition clears cached state GUID")
assertEqual(frame.states.isPlayer, nil,
    "secret transition clears cached player state")
assertEqual(frame.states.inVehicle, nil,
    "secret transition clears cached vehicle state")

state.guid = "Player-2"
state.isPlayer = true
frame.scripts.OnUpdate(frame, 0.25)
frame.scripts.OnUpdate(frame, 0.25)
assertEqual(frame.__unitGuid, "Player-2",
    "later public player GUID can be cached")

state.guid = "Creature-1"
state.isPlayer = false
frame.scripts.OnUpdate(frame, 0.25)
frame.scripts.OnUpdate(frame, 0.25)
assertEqual(frame.__effectiveGuid, "Creature-1",
    "ordinary nonplayer effective GUID remains public")
assertEqual(frame.__unitGuid, nil,
    "ordinary nonplayer clears prior player GUID")

print("unit_frame_secret_identity_unit_button_test.lua: ok")
