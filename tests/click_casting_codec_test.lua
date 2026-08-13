local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local CC = {}
local BFI = {modules = {ClickCastings = CC}}
assert(loadfile("Modules/ClickCastings/BindingCodec.lua"))(
    "BFInfinite",
    BFI
)

assertEqual(CC.NormalizeModifiers("shift-alt-ctrl-"), "alt-ctrl-shift-",
    "modifier order follows SecureButton_GetModifierPrefix")
assertEqual(CC.EncodeBinding({key = "BUTTON5", alt = true, shift = true}),
    "alt-shift-type5", "modified mouse encoding")
assertEqual(CC.EncodeBinding({key = "MOUSEWHEELUP", ctrl = true}),
    "type-ctrlMOUSEWHEELUP", "wheel encoding")
assertEqual(CC.EncodeBinding({key = "R", alt = true}), "type-altR",
    "keyboard encoding")

local binding = CC.DecodeBinding("alt-ctrl-type4")
assertEqual(binding.key, "BUTTON4", "mouse decoding")
assertEqual(binding.alt, true, "alt decoding")
assertEqual(binding.ctrl, true, "ctrl decoding")
assertEqual(binding.shift, false, "shift decoding")

binding = CC.DecodeBinding("type-shiftMOUSEWHEELDOWN")
assertEqual(binding.key, "MOUSEWHEELDOWN", "wheel decoding")
assertEqual(binding.shift, true, "wheel modifier decoding")

assertEqual(CC.IsProxyAction("type1", "target"), true,
    "enabled plain target survives an unbound native interaction")
assertEqual(CC.IsProxyAction("type2", "togglemenu"), true,
    "enabled plain menu survives an unbound native interaction")
assertEqual(CC.IsProxyAction("shift-type1", "target"), true,
    "modified target uses proxy")
assertEqual(CC.IsProxyAction("type-shiftT", "target"), true,
    "keyboard target uses proxy")

local compiled = CC.Compile({
    enabled = true,
    bindings = {
        {"type1", "target"},
        {"type-shiftR", "spell", 2006},
        {"type-ctrlMOUSEWHEELUP", "target"},
        {"type-shiftR", "macro", "duplicate"},
    },
})
assertEqual(#compiled.actions, 3, "duplicate chord keeps first action")
assertEqual(compiled.actions[2].sourceAttribute, "type-shiftR",
    "compiler retains saved attribute")
assertEqual(compiled.actions[2].typeAttribute, "*type-BFI_CC_2",
    "hover action uses wildcard virtual button")
assertEqual(compiled.actions[3].useProxy, true,
    "hover target routes through proxy")
assert(compiled.snippet:find("SHIFT%-R", 1, false),
    "keyboard override appears in secure snippet")
assert(compiled.snippet:find("CTRL%-MOUSEWHEELUP", 1, false),
    "wheel override appears in secure snippet")

compiled = CC.Compile({enabled = false, bindings = {}})
assertEqual(#compiled.actions, 2, "disabled module restores baseline actions")
assertEqual(compiled.actions[1].actionType, "target",
    "disabled baseline target")
assertEqual(compiled.actions[2].actionType, "togglemenu",
    "disabled baseline menu")
assertEqual(compiled.actions[1].useProxy, false,
    "disabled baseline retains BFI's legacy direct interaction")

compiled = CC.Compile({
    enabled = true,
    bindings = {
        {"type3", "spell", ""},
        {"type4", "custom", ""},
        {"type5", "focus"},
    },
})
assertEqual(#compiled.actions, 1,
    "incomplete payload actions stay visible in settings but do not execute")
assertEqual(compiled.actions[1].typeAttribute, "type5",
    "payload-free action still compiles")

print("click_casting_codec_test: ok")
