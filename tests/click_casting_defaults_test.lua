local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local callbacks = {}
local AF = {
    player = {class = "PRIEST"},
    Copy = copy,
}
function AF.NormalizeBinding(binding)
    if type(binding) ~= "table"
        or type(binding.key) ~= "string"
        or binding.key == "META"
    then
        return
    end
    return copy(binding)
end
function AF.RegisterCallback(event, callback)
    callbacks[event] = callback
end
function AF.Merge(target, source)
    for key, value in pairs(source) do target[key] = copy(value) end
end

local environment = setmetatable({
    _G = false,
    AbstractFramework = AF,
    wipe = function(value)
        for key in pairs(value) do value[key] = nil end
    end,
}, {__index = _G})
environment._G = environment

local CC = {}
local BFI = {modules = {ClickCastings = CC}}
local codec = assert(loadfile("Modules/ClickCastings/BindingCodec.lua"))
setfenv(codec, environment)
codec("BFInfinite", BFI)
local chunk = assert(loadfile("Modules/ClickCastings/Defaults.lua"))
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local normalized = CC.NormalizeConfig(nil)
assertEqual(normalized.schemaVersion, 2, "schema version")
assertEqual(#normalized.classes.PRIEST.bindings, 2,
    "current class receives baseline bindings")
assertEqual(normalized.classes.PRIEST.smartResurrection, "disabled",
    "smart resurrection defaults disabled")
assertEqual(normalized.classes.PRIEST.preferMassResurrection, true,
    "mass resurrection preference defaults on for Cell parity")

normalized = CC.NormalizeConfig({
    schemaVersion = 1,
    classes = {
        PRIEST = {enabled = true, bindings = {}},
        DRUID = {
            enabled = true,
            smartResurrection = "invalid",
            preferMassResurrection = "yes",
            bindings = {
                {"garbage-type1", "spell", 8936},
                {"type-META", "spell", 8936},
                {"type1", "spell", 774},
                {"type1", "spell", 8936},
                {"bad"},
            },
        },
    },
})
assertEqual(normalized.schemaVersion, 2,
    "schema-v1 profile migrates to schema v2")
assertEqual(#normalized.classes.PRIEST.bindings, 0,
    "intentional empty binding list is atomic")
assertEqual(normalized.classes.PRIEST.smartResurrection, "disabled",
    "schema-v1 class gains the Smart Resurrection default")
assertEqual(normalized.classes.PRIEST.preferMassResurrection, true,
    "schema-v1 class gains the mass resurrection preference")
assertEqual(#normalized.classes.DRUID.bindings, 1,
    "other class bindings reject malformed and duplicate chords")
assertEqual(normalized.classes.DRUID.smartResurrection, "disabled",
    "invalid smart resurrection mode is normalized")
assertEqual(normalized.classes.DRUID.preferMassResurrection, true,
    "invalid mass preference is normalized")

local profile = {clickCastings = normalized}
callbacks.BFI_UpdateProfile(nil, profile)
assertEqual(CC.config, normalized, "profile module config assigned")
assertEqual(CC.activeConfig, normalized.classes.PRIEST,
    "current class config selected inside BFI profile")

local druid = normalized.classes.DRUID
CC.activeConfig.smartResurrection = "normal+combat"
CC.activeConfig.preferMassResurrection = false
CC.ResetToDefaults()
assertEqual(#CC.activeConfig.bindings, 2,
    "reset restores current class baseline")
assertEqual(CC.activeConfig.smartResurrection, "disabled",
    "reset restores current class smart resurrection mode")
assertEqual(CC.activeConfig.preferMassResurrection, true,
    "reset restores current class mass resurrection preference")
assertEqual(normalized.classes.DRUID, druid,
    "reset leaves other class data intact")

local oldActive = CC.activeConfig
normalized.classes = {}
callbacks.BFI_UpdateModule(nil, "clickCastings")
assert(CC.activeConfig ~= oldActive,
    "module replacement refreshes the nested active class pointer")
assertEqual(#CC.activeConfig.bindings, 2,
    "module replacement normalizes the current class defaults")

print("click_casting_defaults_test: ok")
