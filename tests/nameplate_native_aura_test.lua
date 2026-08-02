local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
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

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local sourceFile = assert(io.open(
    "Modules/Nameplates/Indicators/Auras.lua",
    "r"
))
local source = sourceFile:read("*a")
sourceFile:close()
for _, forbidden in ipairs({
    "CreateSecretAuraList",
    "GetUnitAuraInstanceIDs",
    "C_UnitAuras",
}) do
    assertEqual(source:find(forbidden, 1, true), nil,
        "legacy nameplate aura dependency " .. forbidden)
end

local createdOptions
local nativeConfigs = {}
local comparisonConfigs = {}
local placements = {}
local frameLevels = {}

local NP = {
    created = {},
    config = {},
}
local UF = {}
local AF = {}

function AF.Copy(value)
    return copy(value)
end

function AF.SetFrameLevel(frame, level, relativeTo)
    frameLevels[#frameLevels + 1] = {
        frame = frame,
        level = level,
        relativeTo = relativeTo,
    }
end

function NP.LoadIndicatorPosition(frame, position, anchorTo)
    placements[#placements + 1] = {
        frame = frame,
        position = copy(position),
        anchorTo = anchorTo,
    }
end

function UF.CreateNativeAuraIndicator(
    parent,
    name,
    auraFilter,
    hasSubFrame,
    options
)
    createdOptions = copy(options)
    local frame = {
        root = parent,
        name = name,
        auraFilter = auraFilter,
        hasSubFrame = hasSubFrame,
    }
    function frame:LoadConfig(config)
        self.nativeConfigLoads = (self.nativeConfigLoads or 0) + 1
        nativeConfigs[#nativeConfigs + 1] = copy(config)
        self.nativeConstructionStyle = config.cooldownStyle
    end
    function frame:RequiresReloadForConfig(config)
        comparisonConfigs[#comparisonConfigs + 1] = copy(config)
        return self.nativeConstructionStyle ~= nil
            and config.cooldownStyle ~= self.nativeConstructionStyle
    end
    function frame:GetNativeAuraState()
        return {built = self.nativeBuilt ~= false}
    end
    return frame
end

local BFI = {
    modules = {
        Nameplates = NP,
        UnitFrames = UF,
    },
}
local environment = {
    _G = false,
    AbstractFramework = AF,
    assert = assert,
    ipairs = ipairs,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
}
environment._G = environment
setmetatable(environment, {
    __index = function(_, key)
        error("unexpected nameplate-aura global: " .. tostring(key), 2)
    end,
})

local chunk, loadError = loadfile(
    "Modules/Nameplates/Indicators/Auras.lua"
)
assertTrue(chunk, loadError)
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local root = {
    configKey = "hostile_npc",
    indicators = {},
}
local debuffs = NP.CreateDebuffs(root, "BFI_NamePlate7Debuffs")
root.indicators.debuffs = debuffs

assertEqual(debuffs.auraFilter, "HARMFUL", "native base filter")
assertEqual(debuffs.hasSubFrame, false, "native subframe")
assertEqual(debuffs._nameplateAuraType, "enemyDebuffs",
    "nameplate aura type")
assertEqual(createdOptions.includeSpellColors, false,
    "Global Colors opt-out")
assertEqual(createdOptions.allowCombatInitialBuild, true,
    "combat initial-build runtime option")
assertEqual(createdOptions.keepNativeEnabledWhenHidden, true,
    "hidden nameplate native enabled state")
assertEqual(createdOptions.immediateConfigCommit, true,
    "immediate nameplate config commit")
assertEqual(createdOptions.controller.liveUnitChanges, true,
    "live unit-token option")
assertEqual(createdOptions.controller.allowCombatInitialBuild, true,
    "combat initial-build controller option")
assertEqual(createdOptions.controller.alphaOnlyVisibility, true,
    "alpha-only visibility option")

local plateConfig = {
    nameText = {
        placement = "inside",
        anchorTo = "healthBar",
        position = {"BOTTOM", "TOP", 0, 2},
        font = {"BFI", 10, "outline", false},
    },
}
local hostileConfig = {
    enabled = true,
    position = {"BOTTOM", "TOP", 0, 18},
    anchorTo = "healthBar",
    cooldownStyle = "block_clock",
    spellColors = {
        [774] = {0.2, 0.8, 0.3, 1},
    },
    filters = {
        all = true,
    },
}
plateConfig.debuffs = hostileConfig
NP.config.hostile_npc = plateConfig

debuffs:LoadConfig(hostileConfig, plateConfig)
local normalized = nativeConfigs[1]
assertEqual(normalized.enabled, true, "hostile debuffs enabled")
assertEqual(normalized.mode, "blacklist", "native spell-list mode")
assertEqual(#normalized.blacklist, 0, "native empty spell blacklist")
assertEqual(normalized.whitelist, nil, "native whitelist omission")
assertEqual(normalized.filters.player, true, "enemy player-cast filter")
assertEqual(normalized.filters.all, false, "enemy all-aura filter")
assertEqual(normalized.tooltip.enabled, false, "nameplate aura tooltip")
assertEqual(normalized.subFrame, nil, "nameplate aura subframe")
assertEqual(normalized.spellColors, nil, "nameplate spell colors")
assertEqual(normalized.position[4], 6, "inside-name reserved offset")

debuffs:LoadConfig(copy(hostileConfig), copy(plateConfig))
assertEqual(#nativeConfigs, 1,
    "identical hostile pool-reuse config")

root.configKey = "friendly_npc"
debuffs.enabled = true
debuffs:LoadConfig(hostileConfig, plateConfig)
assertEqual(debuffs.enabled, false, "friendly debuffs fail closed")
assertEqual(#nativeConfigs, 1,
    "friendly pool assignment preserves enemy snapshot")
assertEqual(
    debuffs:RequiresReloadForConfig(hostileConfig, plateConfig),
    false,
    "friendly pool assignment reload preflight"
)

root.configKey = "hostile_npc"
debuffs.enabled = true
debuffs:LoadConfig(copy(hostileConfig), copy(plateConfig))
assertEqual(#nativeConfigs, 1,
    "friendly-to-hostile pool reuse config")
assertEqual(
    debuffs:RequiresReloadForConfig(hostileConfig, plateConfig),
    false,
    "unchanged nameplate construction reload"
)
assertEqual(comparisonConfigs[1].spellColors, nil,
    "reload comparison Global Colors opt-out")
assertEqual(comparisonConfigs[1].position[4], 6,
    "reload comparison effective position")

NP.created[root] = root
root.configKey = "friendly_npc"
local unbuiltRoot = {
    configKey = "hostile_npc",
    indicators = {},
}
local unbuiltDebuffs = NP.CreateDebuffs(
    unbuiltRoot,
    "BFI_NamePlate8Debuffs"
)
unbuiltRoot.indicators.debuffs = unbuiltDebuffs
unbuiltDebuffs.nativeBuilt = false
unbuiltDebuffs:LoadConfig(hostileConfig, plateConfig)
local unbuiltConfigLoads = unbuiltDebuffs.nativeConfigLoads
NP.created[unbuiltRoot] = unbuiltRoot

local constructionConfig = copy(hostileConfig)
constructionConfig.cooldownStyle = "block_vertical"
local constructionPlateConfig = copy(plateConfig)
constructionPlateConfig.debuffs = constructionConfig
NP.config.hostile_npc = constructionPlateConfig
local beforeConstructionPreparation = #nativeConfigs
assertEqual(NP.PrepareNameplateAuraConfigUpdate(), true,
    "hidden pool construction reload preflight")
assertEqual(#nativeConfigs, beforeConstructionPreparation + 1,
    "hidden pool construction config preparation")
assertEqual(unbuiltDebuffs.nativeConfigLoads, unbuiltConfigLoads,
    "untouched pool row remains unbuilt")

local tuningConfig = copy(constructionConfig)
tuningConfig.position[4] = 20
local tuningPlateConfig = copy(constructionPlateConfig)
tuningPlateConfig.debuffs = tuningConfig
NP.config.hostile_npc = tuningPlateConfig
local beforeTuningPreparation = #nativeConfigs
assertEqual(NP.PrepareNameplateAuraConfigUpdate(), false,
    "hidden pool tuning reload preflight")
assertEqual(#nativeConfigs, beforeTuningPreparation + 1,
    "hidden pool tuning config preparation")
assertEqual(nativeConfigs[#nativeConfigs].position[4], 8,
    "hidden pool tuning effective position")

root.configKey = "hostile_npc"
debuffs.enabled = true
local beforePreparedHostileReturn = #nativeConfigs
debuffs:LoadConfig(copy(tuningConfig), copy(tuningPlateConfig))
assertEqual(#nativeConfigs, beforePreparedHostileReturn,
    "prepared hidden pool hostile return")

local holder = {}
createdOptions.applyPlacement(holder, {
    frameLevel = 5,
    position = {"TOPLEFT", "TOPLEFT", 3, -4},
    anchorTo = "healthBar",
}, root)
assertEqual(frameLevels[1].frame, holder, "placement holder")
assertEqual(frameLevels[1].level, 5, "placement frame level")
assertEqual(frameLevels[1].relativeTo, root, "placement root")
assertEqual(placements[1].position[3], 3, "placement x offset")
assertEqual(placements[1].position[4], -4, "placement y offset")
assertEqual(placements[1].anchorTo, "healthBar", "placement anchor")

assertEqual(NP.CreateBuffs, nil, "unsupported nameplate Buffs constructor")
assertEqual(NP.CreateCrowdControls, nil,
    "unsupported nameplate Crowd Controls constructor")

print("nameplate_native_aura_test.lua: ok")
