local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function newFrame(name, parent, template)
    local frame = {
        name = name,
        parent = parent,
        template = template,
        attributes = {},
        registeredClicks = {},
    }
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:RegisterForClicks(...)
        self.registeredClicks = {...}
    end
    function frame:WrapScript(target, script, body)
        target.wrappedScript = {script, body}
    end
    return frame
end

local callbacks = {}
local AF = {}
function AF.RegisterCallback(event, callback, priority)
    callbacks[event] = callbacks[event] or {}
    callbacks[event][#callbacks[event] + 1] = {
        callback = callback,
        priority = priority,
    }
end

local inCombat = false
local created = {}
local overrideClears = 0
local stateDriver
local environment = setmetatable({
    _G = false,
    AbstractFramework = AF,
    InCombatLockdown = function() return inCombat end,
    CreateFrame = function(_, name, parent, template)
        local frame = newFrame(name, parent, template)
        created[#created + 1] = frame
        return frame
    end,
    RegisterStateDriver = function(frame, state, condition)
        stateDriver = {frame, state, condition}
    end,
    ClearOverrideBindings = function(frame)
        overrideClears = overrideClears + 1
        frame.overrideBindingsCleared = true
    end,
    wipe = function(value)
        for key in pairs(value) do value[key] = nil end
    end,
}, {__index = _G})
environment._G = environment

local CC = {}
function CC:RegisterEvent(event, callback)
    self.registeredEvent = {event, callback}
end
function CC:UnregisterEvent(event, callback)
    if self.registeredEvent
        and self.registeredEvent[1] == event
        and self.registeredEvent[2] == callback
    then
        self.registeredEvent = nil
    end
end

local unit = newFrame("BFITestUnit")
unit:SetAttribute("type1", "target")
unit:SetAttribute("type2", "togglemenu")
local BFI = {
    modules = {ClickCastings = CC},
    vars = {unitButtons = {BFITestUnit = unit}},
}

local codec = assert(loadfile("Modules/ClickCastings/BindingCodec.lua"))
setfenv(codec, environment)
codec("BFInfinite", BFI)

CC.activeConfig = {
    enabled = true,
    bindings = {
        {"type1", "target"},
        {"alt-type1", "spell", 2061},
        {"type-shiftR", "target"},
    },
}

local runtime = assert(loadfile("Modules/ClickCastings/Runtime.lua"))
setfenv(runtime, environment)
runtime("BFInfinite", BFI)

assertEqual(stateDriver[2], "mouseoverstate", "mouseover cleanup driver")
assertEqual(CC.Refresh(), true, "initial refresh completes")
assertEqual(unit.attributes.type1, "click",
    "enabled target bypasses an unbound native interaction")
assertEqual(unit._bfiClickCastingProxy.attributes.type1, "target",
    "enabled target action lives on the secure proxy")
assertEqual(unit.attributes["alt-type1"], "spell", "spell type applied")
assertEqual(unit.attributes["alt-spell1"], 2061, "spell payload applied")
assertEqual(unit.attributes["*type-BFI_CC_3"], "click",
    "keyboard target routed through outer click")
assert(unit.attributes["*clickbutton-BFI_CC_3"],
    "keyboard target has proxy delegate")
local proxy = unit._bfiClickCastingProxy
assertEqual(proxy.attributes["*type-BFI_CC_3"], "target",
    "proxy carries real keyboard target action")
assertEqual(proxy.attributes["useparent-toggleForVehicle"], true,
    "proxy inherits protected vehicle routing")
assertEqual(proxy.attributes.useOnKeyDown, false,
    "proxy accepts programmatic up click")
assert(unit.attributes._onmousedown:find("self:Run", 1, true),
    "secure mouse-down refresh is installed")
assertEqual(overrideClears, 1, "refresh clears old hover overrides")

CC.activeConfig.bindings = {{"type2", "focus"}}
CC.Refresh()
assertEqual(unit.attributes["alt-type1"], nil,
    "old type attribute cleared from ledger")
assertEqual(unit.attributes["alt-spell1"], nil,
    "old payload attribute cleared from ledger")
assertEqual(proxy.attributes["*type-BFI_CC_3"], nil,
    "old proxy action cleared from ledger")
assertEqual(unit.attributes.type2, "focus", "replacement action applied")

inCombat = true
CC.activeConfig.bindings = {{"type3", "assist"}}
assertEqual(CC.Refresh(), false, "combat refresh defers")
assertEqual(unit.attributes.type2, "focus", "combat keeps active config")
assertEqual(CC.registeredEvent[1], "PLAYER_REGEN_ENABLED",
    "combat refresh registers flush")

inCombat = false
CC.FlushPending()
assertEqual(unit.attributes.type2, nil, "deferred refresh clears old action")
assertEqual(unit.attributes.type3, "assist", "deferred refresh applies once safe")

CC.activeConfig.enabled = false
CC.Refresh()
assertEqual(unit.attributes.type1, "target", "disable restores left target")
assertEqual(unit.attributes.type2, "togglemenu", "disable restores right menu")

environment.Enum = {
    ClickBindingType = {None = 0, Spell = 1, Macro = 2, Interaction = 3},
    ClickBindingInteraction = {Target = 1, OpenContextMenu = 2},
}
environment.GetStringFromModifiers = function(modifiers)
    return modifiers == 1 and "SHIFT" or ""
end
environment.C_ClickBindings = {
    GetEffectiveInteractionButton = function(button)
        return button == "Button4" and "LeftButton" or button
    end,
}

CC.activeConfig.enabled = true
CC.activeConfig.bindings = {
    {"type1", "target"},
    {"type2", "togglemenu"},
    {"shift-type1", "spell", 2061},
    {"shift-type4", "focus"},
    {"type3", "assist"},
}
environment.C_ClickBindings.GetProfileInfo = function()
    return {
        {
            type = environment.Enum.ClickBindingType.Interaction,
            actionID = environment.Enum.ClickBindingInteraction.Target,
            button = "LeftButton",
            modifiers = 0,
        },
        {
            type = environment.Enum.ClickBindingType.Interaction,
            actionID = environment.Enum.ClickBindingInteraction.OpenContextMenu,
            button = "RightButton",
            modifiers = 0,
        },
        {
            type = environment.Enum.ClickBindingType.Interaction,
            actionID = environment.Enum.ClickBindingInteraction.Target,
            button = "Button4",
            modifiers = 1,
        },
        {
            type = environment.Enum.ClickBindingType.Spell,
            actionID = 17,
            button = "MiddleButton",
            modifiers = 0,
        },
    }
end
local conflicts = CC.GetNativeConflicts()
assertEqual(#conflicts, 2,
    "canonical target/menu cooperate while remapped and spell chords warn")
assertEqual(conflicts[1].localBinding[2], "spell",
    "interaction remapping checks the effective BFI chord")
assertEqual(conflicts[1].physicalBinding[2], "focus",
    "interaction remapping also reports the ignored physical BFI chord")
assertEqual(conflicts[2].localBinding[2], "assist",
    "native spell binding reports its preempted physical BFI action")

print("click_casting_runtime_test: ok")
