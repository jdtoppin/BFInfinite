local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertSame(actual, expected, message)
    if actual ~= expected then
        error(message or "expected identical values", 2)
    end
end

local function findUpvalue(func, targetName)
    local index = 1
    while true do
        local name, value = debug.getupvalue(func, index)
        if not name then
            return nil
        elseif name == targetName then
            return value
        end
        index = index + 1
    end
end

local inCombat = true
local addonLoadedCallback
local registeredEvent
local regenCallback
local registrationCount = 0

local AF = {}
local S = {}

function AF.RegisterAddonLoaded(addon, callback)
    assertEqual(addon, "Blizzard_PlayerSpells", "registered addon")
    addonLoadedCallback = callback
end

function S:RegisterEventOnce(event, callback)
    assertSame(self, S, "event owner")
    registrationCount = registrationCount + 1
    registeredEvent = event
    regenCallback = callback
end

local function makeSpellBookFrame(label)
    local state = {
        borderCalls = 0,
        clearCalls = 0,
        label = label,
        pointCalls = 0,
        removeCalls = 0,
        styleCalls = 0,
    }
    local button = {_testState = state}
    local assistedFrame = {
        Button = button,
        _testState = state,
    }
    local pagedSpellsFrame = {label = label .. " paged spells"}
    local spellBookFrame = {
        AssistedCombatRotationSpellFrame = assistedFrame,
        PagedSpellsFrame = pagedSpellsFrame,
    }

    state.assistedFrame = assistedFrame
    state.button = button
    state.pagedSpellsFrame = pagedSpellsFrame
    state.spellBookFrame = spellBookFrame
    return state
end

function S.RemoveTextures(frame)
    local state = frame._testState
    state.removeCalls = state.removeCalls + 1
    assertSame(frame, state.assistedFrame, state.label .. " texture target")
end

function AF.ClearPoints(frame)
    local state = frame._testState
    state.clearCalls = state.clearCalls + 1
    assertSame(frame, state.assistedFrame, state.label .. " clear target")
end

function AF.SetPoint(frame, point, relativeTo, relativePoint, x, y)
    local state = frame._testState
    state.pointCalls = state.pointCalls + 1
    assertSame(frame, state.assistedFrame, state.label .. " point target")
    assertEqual(point, "BOTTOMRIGHT", state.label .. " point")
    assertSame(relativeTo, state.pagedSpellsFrame, state.label .. " relative frame")
    assertEqual(relativePoint, "TOPRIGHT", state.label .. " relative point")
    assertEqual(x, -10, state.label .. " x offset")
    assertEqual(y, 10, state.label .. " y offset")
end

function S.StyleSpellItemButton(button)
    local state = button._testState
    state.styleCalls = state.styleCalls + 1
    assertSame(button, state.button, state.label .. " button target")

    button.BFIBackdrop = {}
    function button.BFIBackdrop:SetBackdropBorderColor(r, g, b)
        state.borderCalls = state.borderCalls + 1
        state.borderColor = {r, g, b}
    end
end

function AF.GetColorRGB(color)
    assertEqual(color, "border", "requested color")
    return 0.125, 0.25, 0.5
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    InCombatLockdown = function()
        return inCombat
    end,
    TalentButtonUtil = {
        BaseVisualState = {
            RefundInvalid = 1,
            DisplayError = 2,
            Gated = 3,
            Selectable = 4,
            Maxed = 5,
            Locked = 6,
            Disabled = 7,
        },
    },
    select = select,
}
environment._G = environment

local BFI = {
    modules = {
        Style = S,
    },
}

local chunk, loadError = loadfile("Modules/Blizzard/Style/PlayerSpellsFrame.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(addonLoadedCallback), "function", "addon-loaded callback")
local styleSpellBookFrame = findUpvalue(
    addonLoadedCallback,
    "StyleSpellBookFrame"
)
assertEqual(type(styleSpellBookFrame), "function", "Spellbook style upvalue")
local styleAssistedCombatFrame = findUpvalue(
    styleSpellBookFrame,
    "StyleAssistedCombatFrame"
)
assertEqual(
    type(styleAssistedCombatFrame),
    "function",
    "assisted-combat style upvalue"
)

local deferred = makeSpellBookFrame("deferred")
styleAssistedCombatFrame(deferred.spellBookFrame)
styleAssistedCombatFrame(deferred.spellBookFrame)

assertEqual(registrationCount, 1, "lockdown registration count")
assertEqual(registeredEvent, "PLAYER_REGEN_ENABLED", "lockdown event")
assertEqual(type(regenCallback), "function", "lockdown callback")
assertEqual(deferred.removeCalls, 0, "lockdown texture mutations")
assertEqual(deferred.clearCalls, 0, "lockdown clear mutations")
assertEqual(deferred.pointCalls, 0, "lockdown point mutations")
assertEqual(deferred.styleCalls, 0, "lockdown button styling")
assertEqual(deferred.borderCalls, 0, "lockdown border mutations")

inCombat = false
regenCallback()

assertEqual(registrationCount, 1, "post-combat registration count")
assertEqual(deferred.removeCalls, 1, "post-combat texture mutations")
assertEqual(deferred.clearCalls, 1, "post-combat clear mutations")
assertEqual(deferred.pointCalls, 1, "post-combat point mutations")
assertEqual(deferred.styleCalls, 1, "post-combat button styling")
assertEqual(deferred.borderCalls, 1, "post-combat border mutations")
assertEqual(deferred.borderColor[1], 0.125, "post-combat border red")
assertEqual(deferred.borderColor[2], 0.25, "post-combat border green")
assertEqual(deferred.borderColor[3], 0.5, "post-combat border blue")

local immediate = makeSpellBookFrame("immediate")
styleAssistedCombatFrame(immediate.spellBookFrame)

assertEqual(registrationCount, 1, "immediate registration count")
assertEqual(immediate.removeCalls, 1, "immediate texture mutations")
assertEqual(immediate.clearCalls, 1, "immediate clear mutations")
assertEqual(immediate.pointCalls, 1, "immediate point mutations")
assertEqual(immediate.styleCalls, 1, "immediate button styling")
assertEqual(immediate.borderCalls, 1, "immediate border mutations")

print("player_spells_combat_style_test.lua: ok")
