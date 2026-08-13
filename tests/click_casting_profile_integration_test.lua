local function assertContains(source, text, message)
    if not source:find(text, 1, true) then
        error(message or ("missing source text: " .. text), 2)
    end
end

local function assertBefore(source, first, second, message)
    local firstAt = assert(source:find(first, 1, true), "missing " .. first)
    local secondAt = assert(source:find(second, 1, true), "missing " .. second)
    if firstAt >= secondAt then error(message, 2) end
end

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local init = readFile("Init.lua")
assertContains(init, "BFI.modules.ClickCastings = {}",
    "ClickCastings module registered")

local utils = readFile("Utils.lua")
assertContains(utils,
    'clickCastings = {localized = L["Click Casting"], class = "ClickCastings"}',
    "module registry entry")
assertContains(utils, "if M.NormalizeConfig then",
    "atomic module normalizer hook")

local modules = readFile("Modules/LoadModules.xml")
assertBefore(modules, 'ClickCastings\\Load.xml', 'UnitFrames\\Load.xml',
    "secure runtime must load before unit frame construction")

local unitTemplate = readFile("Modules/UnitFrames/UnitButton.xml")
assertContains(unitTemplate, "SecureHandlerEnterLeaveTemplate",
    "unit buttons support secure hover binding cleanup")
assertContains(unitTemplate, "SecureHandlerMouseUpDownTemplate",
    "unit buttons actively dispatch the secure mouse-down refresh")

local unitButton = readFile("Modules/UnitFrames/UnitButton.lua")
assertContains(unitButton, 'self:HookScript("OnEnter", UnitButton_OnEnter)',
    "unit-frame hover behavior preserves the secure template handler")
assertBefore(unitButton, 'self:HookScript("OnEnter", UnitButton_OnEnter)',
    "BFI.modules.ClickCastings.RegisterFrame(self)",
    "secure wrapping happens after the unit frame installs its hover hook")

local options = readFile("Options/OptionsFrame.lua")
assertContains(options,
    'auraColorsAvailable and "auras" or "-auras",\n'
        .. '    "clickCastings",\n'
        .. '    -- "social",\n'
        .. '    "SEPARATOR",',
    "Click Casting appears beneath Auras in the shared settings group")
assertContains(options,
    'button:SetTextColor(isEnabled() and "white" or "disabled")',
    "disabled Click Casting dims its navigation text without disabling it")
assertContains(options,
    'AF.RegisterCallback("BFI_UpdateModule", function(_, module)',
    "Click Casting navigation state refreshes with module changes")

local profiles = readFile("Options/Profiles.lua")
assertContains(profiles,
    '{text = L["Click Casting"], id = "clickCastings"}',
    "module-copy UI includes Click Casting")
assertContains(profiles, 'if module == "clickCastings" then',
    "ordered bindings use replacement copy semantics")
assertContains(profiles, "wipe(BFIProfile[to][module])",
    "Click Casting module copy clears the destination class map")
assertContains(profiles, "AF.Copy(BFIProfile[from][module])",
    "Click Casting module copy clones the full schema-v2 class map")
assertContains(profiles, "F.ReviseProfile(data.profile, true)",
    "imported profile normalizes immediately")

local clickOptions = readFile("Options/ClickCastings.lua")
assertContains(clickOptions, 'payload:SetScript("OnReceiveDrag"',
    "the value editor accepts spell, macro, and item cursor drops")
assertContains(clickOptions,
    'binding[3] = payloadActions[value] and "" or nil',
    "changing action types clears incompatible payloads")

print("click_casting_profile_integration_test: ok")
