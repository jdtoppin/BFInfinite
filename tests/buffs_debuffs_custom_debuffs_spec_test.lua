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
    assertEqual(value == true, true, message)
end

local function assertNil(value, message)
    assertEqual(value, nil, message)
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[deepCopy(key)] = deepCopy(child)
    end
    return copy
end

local function countKeys(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function LoadProductionDefaults()
    local productionBD = {}
    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
    environment.AbstractFramework = {
        Copy = deepCopy,
        GetColorTable = function()
            return {1, 1, 1, 1}
        end,
        RegisterCallback = function() end,
    }

    local BFI = {
        modules = {
            BuffsDebuffs = productionBD,
        },
    }
    local chunk = assert(loadfile(
        "Modules/BuffsDebuffs/Defaults.lua"
    ))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
    return productionBD.GetDefaults()
end

local defaults = LoadProductionDefaults()
local PINNED_LEGACY_DEBUFF_CAPACITY = 16 + 6

assertEqual(defaults.debuffs.wrapAfter, 25,
    "production Debuff default icons per row")
assertEqual(defaults.debuffs.maxWraps, 1,
    "production Debuff default line count")
assertTrue(
    defaults.debuffs.wrapAfter * defaults.debuffs.maxWraps
        >= PINNED_LEGACY_DEBUFF_CAPACITY,
    "default combined cap covers pinned 16 ordinary plus 6 private capacity"
)

local function NewHarness(capability)
    local state = {
        registrations = {},
    }
    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
    environment.AnchorUtil = {
        FlowLayoutAxis = {
            Horizontal = "HORIZONTAL",
            Vertical = "VERTICAL",
        },
        FlowDirection = {
            Left = "LEFT",
            Right = "RIGHT",
            Up = "UP",
            Down = "DOWN",
        },
    }
    environment.AuraContainerSortMethod = {
        AuraInstanceIDOnly = "AURA_INSTANCE",
        NameOnly = "NAME",
        ExpirationOnly = "EXPIRATION",
    }
    environment.AuraContainerSortDirection = {
        Normal = "NORMAL",
        Reverse = "REVERSE",
    }
    environment.CustomAuraContainerAuraProcessingPolicy = {
        None = "NONE",
    }

    local BD = {}
    function BD.HasCustomHarmfulAuraContainerCapability()
        return capability == true
    end
    function BD.RegisterCustomAuraContainerPane(which, compiler)
        state.registrations[#state.registrations + 1] = {
            which = which,
            compiler = compiler,
        }
    end
    function BD.GetDefaults()
        assert(capability, "unavailable backend must not inspect defaults")
        return deepCopy(defaults)
    end

    local BFI = {
        modules = {
            BuffsDebuffs = BD,
        },
    }
    local chunk = assert(loadfile(
        "Modules/BuffsDebuffs/CustomDebuffs.lua"
    ))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
    return state
end

do
    local unavailable = NewHarness(false)
    assertEqual(#unavailable.registrations, 0,
        "r38 registers no custom harmful pane")
end

local state = NewHarness(true)
assertEqual(#state.registrations, 1, "one harmful pane registration")
assertEqual(state.registrations[1].which, "debuffs",
    "Debuffs pane registration")
local compile = state.registrations[1].compiler

do
    local config = deepCopy(defaults.debuffs)
    config.enabled = true
    local descriptor = assert(compile(config))

    assertTrue(descriptor.enabled, "enabled projection")
    assertEqual(descriptor.holder.width, 746, "default row width")
    assertEqual(descriptor.holder.height, 26, "default row height")
    assertEqual(descriptor.holderRolesets, "buffs", "holder roleset")
    assertEqual(descriptor.holderAnchor.globalName, "DebuffFrame",
        "DebuffFrame owns the static seam")
    assertEqual(descriptor.holderAnchor.point, "TOPRIGHT",
        "holder anchor point")
    assertEqual(descriptor.holderAnchor.relativePoint, "TOPRIGHT",
        "holder relative point")
    assertEqual(descriptor.holderAnchor.x, 0, "holder X")
    assertEqual(descriptor.holderAnchor.y, 0, "holder Y")
    assertNil(descriptor.position, "Debuffs create no independent mover")
    assertNil(descriptor.positionSave, "Debuffs save no independent position")
    assertNil(descriptor.nativeFollower,
        "Debuffs do not mutate their Blizzard root")

    assertEqual(descriptor.flowLayout.axis, "HORIZONTAL", "flow axis")
    assertEqual(descriptor.flowLayout.anchorPoint, "TOPRIGHT",
        "flow anchor")
    assertEqual(descriptor.flowLayout.horizontalGrowthDirection, "LEFT",
        "right-aligned growth")
    assertEqual(descriptor.flowLayout.verticalGrowthDirection, "DOWN",
        "Debuff rows grow downward")

    assertEqual(#descriptor.groups, 1, "one harmful group")
    local group = descriptor.groups[1]
    assertEqual(group.key, "harmful", "harmful group key")
    assertEqual(group.filterString, "HARMFUL", "native harmful filter")
    assertEqual(group.maxFrameCount, 25, "default aura cap")
    assertEqual(countKeys(group.candidateFilters), 0,
        "no Lua-side candidate classification")
    assertEqual(group.layout.elementSpacing, 4, "default X spacing")
    assertEqual(group.layout.lineSpacing, 6, "default Y spacing")
    assertEqual(group.layout.elementWidth, 26, "default width")
    assertEqual(group.layout.elementHeight, 26, "default height")

    local style = group.buttonStyle
    assertEqual(style.width, 26, "button width")
    assertEqual(style.height, 26, "button height")
    assertEqual(style.iconInset, 1, "icon inset")
    assertEqual(style.nativeDispelColor, true,
        "Blizzard-native square dispel colour")
    assertNil(style.cancelAuraButtons, "harmful auras are not cancellable")
    assertNil(style.dispelColor, "no caller-provided dispel colour")
    assertEqual(style.tooltip.enabled, true, "native tooltip enabled")
    assertEqual(style.tooltip.hideInCombat, false,
        "native combat tooltip remains enabled")
    assertEqual(#descriptor.itemEnchantments, 0,
        "Debuffs have no item enchantments")
    assertEqual(countKeys(descriptor.constructionKey), 2,
        "construction key contains schema and button style")
end

do
    local config = deepCopy(defaults.debuffs)
    config.width = 20
    config.height = 30
    config.spacingX = 2
    config.spacingY = 3
    config.wrapAfter = 4
    config.maxWraps = 2
    config.sortMethod = "INDEX"
    config.sortDirection = "+"
    local descriptor = assert(compile(config))
    local group = descriptor.groups[1]

    assertEqual(descriptor.holder.width, 86, "custom row width")
    assertEqual(descriptor.holder.height, 30, "custom row height")
    assertEqual(group.maxFrameCount, 8, "custom aura cap")
    assertEqual(group.sortMethod, "AURA_INSTANCE", "native sort method")
    assertEqual(group.sortDirection, "NORMAL", "native sort direction")
    assertEqual(group.layout.elementSpacing, 2, "custom X spacing")
    assertEqual(group.layout.lineSpacing, 3, "custom Y spacing")
end

do
    local config = deepCopy(defaults.debuffs)
    config.separateOwn = 1
    local descriptor, diagnostic = compile(config)
    assertNil(descriptor, "Separate Own fails closed")
    assertEqual(diagnostic, "UNSUPPORTED_SEPARATE_OWN",
        "Separate Own diagnostic")
end

do
    local config = deepCopy(defaults.debuffs)
    config.width = {}
    config.height = -100
    config.spacingX = math.huge
    config.spacingY = -50
    config.wrapAfter = 0
    config.maxWraps = 500
    config.sortMethod = "invalid"
    config.sortDirection = "invalid"
    config.stack = {
        font = {false, math.huge, false, "yes"},
        position = {"INVALID", "INVALID", math.huge, {}},
        color = {2, -1, "bad", math.huge},
    }

    local ok, descriptor = pcall(compile, config)
    assertTrue(ok, "malformed config normalizes without assertion")
    local group = descriptor.groups[1]
    assertEqual(group.buttonStyle.width, 26, "invalid width fallback")
    assertEqual(group.buttonStyle.height, 10, "height clamp")
    assertEqual(group.layout.elementSpacing, 4,
        "infinite spacing fallback")
    assertEqual(group.layout.lineSpacing, -1,
        "negative spacing clamp")
    assertEqual(group.maxFrameCount, 50, "normalized aura cap")
    assertEqual(group.sortMethod, "EXPIRATION", "sort fallback")
    assertEqual(group.sortDirection, "REVERSE", "direction fallback")
end

do
    local file = assert(io.open(
        "Modules/BuffsDebuffs/CustomDebuffs.lua",
        "r"
    ))
    local source = file:read("*a")
    file:close()
    for _, pattern in ipairs({
        "C_UnitAuras",
        "C_Secrets",
        "UNIT_AURA",
        ":IsShown",
        ":GetPoint",
        ":GetSize",
        "buttonInfo",
        "auraData",
        "spellId",
        ":SetParent",
        "SecureAuraHeaderTemplate",
    }) do
        assertNil(source:find(pattern, 1, true),
            "forbidden direct dependency: " .. pattern)
    end
end

print("buffs/debuffs custom Debuffs compiler tests passed")
