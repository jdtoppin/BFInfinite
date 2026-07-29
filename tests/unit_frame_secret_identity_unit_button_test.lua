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
    guidCalls = 0,
    identityChecks = 0,
    indicatorUpdates = 0,
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
    return {
        name = unit,
        class = "MAGE",
        guid = nil,
        isPlayer = false,
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
        return secret
    end,
    UnitHasVehicleUI = function()
        return false
    end,
    UnitIsPlayer = function()
        state.unitIsPlayerCalls =
            state.unitIsPlayerCalls + 1
        return true
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
assertEqual(state.unitIsPlayerCalls, 0,
    "secret GUID short-circuits UnitIsPlayer")
assertEqual(frame.__effectiveGuid, nil,
    "secret effective GUID is cleared")
assertEqual(frame.__unitGuid, nil,
    "secret unit GUID is not cached")

print("unit_frame_secret_identity_unit_button_test.lua: ok")
