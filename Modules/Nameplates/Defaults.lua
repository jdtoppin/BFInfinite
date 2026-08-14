---@type BFI
local BFI = select(2, ...)
local F = BFI.funcs
---@class Nameplates
local NP = BFI.modules.Nameplates
---@type AbstractFramework
local AF = _G.AbstractFramework

---------------------------------------------------------------------
-- BFI default cvar values
---------------------------------------------------------------------
-- nameplateShowSelf = 1
-- NameplatePersonalShowAlways = 0
-- NameplatePersonalShowInCombat = 1
-- NameplatePersonalShowWithTarget = 0
local CVAR_DEFAULTS = {
    -- nameOnly
    nameplateShowOnlyNames = 1,
    -- color
    ShowClassColorInNameplate = 1,
    ShowClassColorInFriendlyNameplate = 1,
    nameplateOtherAtBase = 0,
    -- scale
    nameplateGlobalScale = 1.0,
    nameplateLargerScale = 1.0,
    NamePlateHorizontalScale = 1.0,
    NamePlateVerticalScale = 1.0,
    NamePlateClassificationScale = 1.0,
    nameplateMaxScale = 1.0,
    nameplateMinScale = 1.0,
    nameplateSelectedScale = 1.0,
    --! overlap: the smaller the number, the more it overlaps
    nameplateOverlapH = 0.5,
    nameplateOverlapV = 0.5,
    -- motion
    nameplateMotion = F.GetCVarNumber("nameplateMotion"), -- 0:Overlapping 1:Stacking
    nameplateMotionSpeed = 0.025,
    -- distance
    nameplateMaxDistance = 45,
    nameplateTargetBehindMaxDistance = 15, --? what's this cvar for? (broken?)
    -- inset
    nameplateTargetRadialPosition = 1, --? 0:off, 1/2:seems broken, they're the same
    nameplateLargeTopInset = 0.2,
    nameplateLargeBottomInset = 0.2,
    nameplateOtherTopInset = 0.08,
    nameplateOtherBottomInset = -1,
}

function NP.GetCVarDefaults()
    return CVAR_DEFAULTS
end

---------------------------------------------------------------------
-- defaults
---------------------------------------------------------------------
local SCHEMA_VERSION = 7
NP.SCHEMA_VERSION = SCHEMA_VERSION

local defaults = {
    schemaVersion = SCHEMA_VERSION,
    enabled = true,
    cvars = nil,
    alphas = {
        -- base
        occluded = {enabled = true, value = 0.4},
        focus = {enabled = true, value = 1},
        target = {enabled = true, value = 1},
        marked = {enabled = true, value = 1},
        casting = {enabled = true, value = 1},
        mouseover = {enabled = true, value = 1},
        non_target = {enabled = true, value = 0.85},
        no_target = {enabled = false, value = 0.6},
        -- type (multiplier)
        player = 1,
        pet = 1,
        guardian = 1,
        npc = 1, -- classification == normal
        -- classification (multiplier)
        boss = 1,
        rare = 1,
        elite = 1,
        minor = 1,
        totem = 1,
    },
    scales = {
        animatedScaling = true,
        -- base
        -- occluded = {enabled = true, value = 0.4},
        focus = {enabled = false, value = 1},
        target = {enabled = false, value = 1},
        marked = {enabled = false, value = 1},
        casting = {enabled = false, value = 1},
        mouseover = {enabled = false, value = 1},
        non_target = {enabled = false, value = 1},
        no_target = {enabled = false, value = 1},
        -- type (multiplier)
        player = 1,
        pet = 1,
        guardian = 1,
        npc = 1, -- classification == normal
        -- classification (multiplier)
        boss = 1,
        rare = 1,
        elite = 1,
        minor = 1,
        totem = 1,
    },
    -- TODO:
    playersInInstance = {
        -- modify some cvars
    },
}

local nameplateDefaults

do
    defaults.cvars = AF.Copy(NP.GetCVarDefaults())

    nameplateDefaults = {
        healthBar = {
            enabled = true,
            position = {"CENTER", "CENTER", 0, 0},
            anchorTo = "root",
            frameLevel = 1,
            width = 120,
            height = 13,
            colorAlpha = 1,
            lossColor = {
                useDarkerForground = false,
                alpha = 0.6,
                rgb = AF.GetColorTable("black")
            },
            bgColor = AF.GetColorTable("background", 0),
            borderColor = AF.GetColorTable("border"),
            texture = "AF",
            mouseoverHighlight = {
                enabled = true,
                color = AF.GetColorTable("white", 0.1)
            },
            shield = {
                enabled = true,
                color = AF.GetColorTable("damage_absorb", 0.6),
                reverseFill = true,
            },
            overshieldGlow = {
                enabled = true,
                color = AF.GetColorTable("damage_absorb"),
            },
            thresholds = {
                enabled = false,
                width = 7,
                height = 25,
                values = { --! must be descending sorted
                    {value = 0.3, color = AF.GetColorTable("gold")},
                },
            },
            threatGlow = {
                enabled = false,
                border = true,
                glow = true,
                bar = false,
                name = false,
                borderSize = 2,
                size = 4,
                outset = 3,
                borderAlpha = 0.8,
                glowAlpha = 0.8,
                barAlpha = 0.65,
                nameAlpha = 1,
                useCustomColor = false,
                color = AF.GetColorTable("orange"),
                stateColors = {
                    enabled = true,
                    warning = {
                        enabled = true,
                        rgb = {
                            AF.ConvertHEXToRGB("#CC0000"),
                        },
                    },
                    transition = {
                        enabled = true,
                        rgb = {
                            AF.ConvertHEXToRGB("#FFA000"),
                        },
                    },
                    safe = {
                        -- Safe is continuous while a unit is securely held.
                        -- Keep it opt-in so enabling threat colors does not
                        -- tint every engaged nameplate by default.
                        enabled = false,
                        rgb = {
                            AF.ConvertHEXToRGB("#0F96E6"),
                        },
                    },
                    offTank = {
                        enabled = true,
                        rgb = {
                            AF.ConvertHEXToRGB("#0FAAC8"),
                        },
                    },
                },
                combatOnly = false,
                instancesOnly = false,
                tankOnly = false,
            },
        },
        nameText = {
            enabled = true,
            placement = "outside",
            position = {"BOTTOM", "TOP", 0, 1},
            anchorTo = "healthBar",
            parent = "healthBar",
            length = 1,
            font = {"BFI", 12, "none", true},
            color = {type = "custom_color", rgb = AF.GetColorTable("white")}, -- class/custom
            showOtherServerSign = false,
        },
        healthText = {
            enabled = true,
            position = {"CENTER", "CENTER", -5, 0},
            anchorTo = "healthBar",
            parent = "healthBar",
            font = {"BFI", 11, "none", true},
            color = {type = "custom_color", rgb = AF.GetColorTable("white")}, -- class/custom
            format = {
                numeric = "current_short",
                percent = "current",
                delimiter = " - ",
                showPercentSign = true,
                useAsianUnits = false,
            },
            hideIfFull = true,
        },
        levelText = {
            enabled = true,
            position = {"RIGHT", "RIGHT", -5, 0},
            anchorTo = "healthBar",
            parent = "healthBar",
            font = {"BFI", 11, "none", true},
            color = {type = "level_color", rgb = AF.GetColorTable("white")}, -- level/class/custom
            highLevelTexture = {
                enabled = true,
                size = 16,
            },
        },
        castBar = {
            enabled = true,
            position = {"TOP", "BOTTOM", 0, -2},
            anchorTo = "healthBar",
            frameLevel = 3,
            width = 120,
            height = 13,
            color = {AF.ConvertHEXToRGB("#FF7E23")},
            interruptibleColor = {AF.ConvertHEXToRGB("#FFFF00")},
            uninterruptibleColor = {AF.ConvertHEXToRGB("#CC4D4D")},
            bgColor = AF.GetColorTable("background", 0.75),
            borderColor = AF.GetColorTable("border"),
            texture = "AF",
            fadeDuration = 1,
            interruptibleCheck = {
                enabled = true,
                requireUsable = true,
            },
            interruptReadyTick = {
                enabled = true,
                color = {0, 1, 0, 1},
            },
            uninterruptibleIcon = {
                enabled = true,
                size = 16,
                position = {"LEFT", "RIGHT", 2, 0},
            },
            importantGlow = {
                enabled = true,
                color = {AF.ConvertHEXToRGB("#FFE157")},
            },
            importantIcon = {
                enabled = true,
                size = 16,
                position = {"LEFT", "RIGHT", 2, 0},
            },
            playerTargetHighlight = {
                enabled = true,
                color = {1, 0.15, 0.15, 0.22},
            },
            icon = {
                enabled = true,
                position = {"BOTTOMRIGHT", "BOTTOMLEFT", -2, 0},
                width = 18,
                height = 18
            },
            nameText = {
                enabled = true,
                font = {"BFI", 11, "none", true},
                position = {"LEFT", "LEFT", 3, 0},
                color = AF.GetColorTable("white"),
                length = 0.75,
                showInterruptSource = true,
            },
            durationText = {
                enabled = true,
                font = {"BFI", 11 , "none", true},
                position = {"RIGHT", "RIGHT", -3, 0},
                format = "%.1f",
                color = AF.GetColorTable("white"),
            },
            spellTargetText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"TOP", "BOTTOM", 0, -1},
                color = AF.GetColorTable("white"),
            },
            spark = {
                enabled = true,
                texture = "plain",
                width = 1,
                height = 0,
            },
        },
        raidIcon = {
            enabled = true,
            position = {"RIGHT", "LEFT", -2, 0},
            anchorTo = "healthBar",
            frameLevel = 2,
            size = 13,
            style = "af",
        },
        classIcon = {
            enabled = false,
            position = {"RIGHT", "TOPRIGHT", 0, 0},
            anchorTo = "healthBar",
            frameLevel = 2,
            size = 16,
        },
    }

    local hostile = {
        targetIndicator = {
            enabled = true,
            position = {"BOTTOM", "TOP", 0, 30},
            anchorTo = "healthBar",
            frameLevel = 1,
            -- Kept for profiles created before target/focus presentation
            -- settings became independent.
            size = 40,
            target = {
                texture = "Arrow1_Red",
                color = AF.GetColorTable("white"),
                layout = "top",
                size = 40,
                topSpacing = 30,
                sideSize = 22,
                sideSpacing = 2,
                healthBarHighlight = {
                    enabled = false,
                    color = AF.GetColorTable("white", 0.25),
                },
                nameTextEmphasis = {
                    enabled = false,
                    sizeDelta = 2,
                    outline = "thickoutline",
                    shadow = true,
                },
            },
            focus = {
                texture = "Arrow1_Blue",
                color = AF.GetColorTable("white"),
                layout = "top",
                size = 40,
                topSpacing = 30,
                sideSize = 22,
                sideSpacing = 2,
                healthBarHighlight = {
                    enabled = false,
                    color = AF.GetColorTable("white", 0.25),
                },
                nameTextEmphasis = {
                    enabled = false,
                    sizeDelta = 2,
                    outline = "thickoutline",
                    shadow = true,
                },
            },
        },
        buffs = {
            enabled = true,
            position = {"BOTTOM", "TOP", 0, 10},
            anchorTo = "debuffs",
            orientation = "left_to_right",
            cooldownStyle = "none",
            width = 23,
            height = 23,
            spacingX = 3,
            spacingY = 6,
            numPerLine = 3,
            numTotal = 3,
            frameLevel = 2,
            durationText = {
                enabled = true,
                font = {"BFI", 12, "outline", false},
                position = {"RIGHT", "TOPRIGHT", 0, -2},
                color = {
                    normal = AF.GetColorTable("white"), -- normal
                    percent = {enabled = false, value = 0.5, rgb = AF.GetColorTable("aura_percent")}, -- less than 50%
                    seconds = {enabled = true, value = 5, rgb = AF.GetColorTable("aura_seconds")}, -- less than 5sec
                },
            },
            stackText = {
                enabled = true,
                font = {"BFI", 12, "outline", false},
                position = {"RIGHT", "BOTTOMRIGHT", 0, 2},
                color = AF.GetColorTable("white"),
            },
            filters = {
                castByMe = false,
                castByOthers = false,
                castByUnit = false,
                castByNPC = false,
                isBossAura = false,
                dispellable = true,
                canBeDispelled = true,
            },
            blockers = {},
            blacklist = {},
            auraTypeColor = {
                castByMe = false,
                dispellable = true,
                debuffType = false,
            },
            glowDispellableByMe = true,
        },
        debuffs = {
            enabled = true,
            position = {"BOTTOM", "TOP", 0, 18},
            anchorTo = "healthBar",
            orientation = "left_to_right",
            cooldownStyle = "none",
            width = 25,
            height = 15,
            spacingX = 3,
            spacingY = 6,
            numPerLine = 4,
            numTotal = 8,
            frameLevel = 2,
            durationText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"RIGHT", "TOPRIGHT", 0, -2},
                color = {
                    normal = AF.GetColorTable("white"), -- normal
                    percent = {enabled = false, value = 0.5, rgb = AF.GetColorTable("aura_percent")}, -- less than 50%
                    seconds = {enabled = true, value = 5, rgb = AF.GetColorTable("aura_seconds")}, -- less than 5sec
                },
            },
            stackText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"RIGHT", "BOTTOMRIGHT", 0, 2},
                color = AF.GetColorTable("white"),
            },
            filters = {
                castByMe = true,
                castByOthers = false,
                castByUnit = false,
                castByNPC = false,
                isBossAura = false,
                dispellable = false,
            },
            blockers = {
                crowdControlType = true,
            },
            blacklist = {},
            auraTypeColor = {
                castByMe = false,
                dispellable = false,
                debuffType = false,
            },
        },
        crowdControls = {
            enabled = true,
            position = {"BOTTOM", "TOP", 0, 15},
            anchorTo = "buffs",
            orientation = "left_to_right",
            cooldownStyle = "none",
            width = 40,
            height = 24,
            spacingX = 5,
            spacingY = 10,
            numPerLine = 3,
            numTotal = 3,
            frameLevel = 2,
            durationText = {
                enabled = true,
                font = {"BFI", 13, "outline", false},
                position = {"RIGHT", "TOPRIGHT", 0, -2},
                color = {
                    normal = AF.GetColorTable("white"), -- normal
                    percent = {enabled = false, value = 0.5, rgb = AF.GetColorTable("aura_percent")}, -- less than 50%
                    seconds = {enabled = true, value = 5, rgb = AF.GetColorTable("aura_seconds")}, -- less than 5sec
                },
            },
            stackText = {
                enabled = true,
                font = {"BFI", 13, "outline", false},
                position = {"RIGHT", "BOTTOMRIGHT", 0, 2},
                color = AF.GetColorTable("white"),
            },
            crowdControlTypes = {
                [1] = true,
                [2] = true,
                [3] = true,
                [4] = true,
                [5] = true,
                [6] = true,
                [7] = true,
                [8] = true,
                [9] = true,
                [10] = true,
                [11] = true,
                [12] = true,
                [13] = true,
                [14] = false,
                [15] = false,
                [99] = true,
            },
            -- filters = {},
            -- blockers = {},
            -- blacklist = {},
            auraTypeColor = {
                castByMe = false,
                dispellable = false,
                debuffType = false,
            },
        },
    }

    local hostile_npc = {
        rareIndicator = {
            enabled = true,
            position = {"RIGHT", "TOPRIGHT", 0, 0},
            anchorTo = "healthBar",
            frameLevel = 2,
            color = AF.GetColorTable("white"),
            size = 16,
        },
        questIndicator = {
            enabled = true,
            position = {"LEFT", "RIGHT", 0, 0},
            anchorTo = "healthBar",
            frameLevel = 2,
            size = 18,
            hideInInstance = true,
        }
    }

    local friendly = {
        nameText = {
            enabled = true,
            placement = "outside",
            position = {"CENTER", "CENTER", 0, -10},
            anchorTo = "root",
            parent = "root",
            length = 0,
            font = {"BFI", 13, "outline", false},
            color = {type = "class_color", rgb = AF.GetColorTable("white")}, -- class/custom
            showOtherServerSign = true,
        },
        raidIcon = {
            enabled = true,
            position = {"RIGHT", "LEFT", -2, 2},
            anchorTo = "nameText",
            frameLevel = 2,
            size = 13,
            style = "af",
        },
        targetIndicator = {
            enabled = true,
            position = {"BOTTOM", "TOP", 0, 15},
            anchorTo = "nameText",
            frameLevel = 1,
            -- Kept for profiles created before target/focus presentation
            -- settings became independent.
            size = 40,
            target = {
                texture = "Arrow1_Green",
                color = AF.GetColorTable("white"),
                layout = "top",
                size = 40,
                topSpacing = 15,
                sideSize = 22,
                sideSpacing = 2,
                healthBarHighlight = {
                    enabled = false,
                    color = AF.GetColorTable("white", 0.25),
                },
                nameTextEmphasis = {
                    enabled = false,
                    sizeDelta = 2,
                    outline = "thickoutline",
                    shadow = true,
                },
            },
            focus = {
                texture = "Arrow1_Blue",
                color = AF.GetColorTable("white"),
                -- Friendly focus markers were historically hidden by using
                -- an empty texture. Keep them hidden by presentation instead
                -- so choosing a layout in options can show a real marker.
                layout = "none",
                size = 40,
                topSpacing = 15,
                sideSize = 22,
                sideSpacing = 2,
                healthBarHighlight = {
                    enabled = false,
                    color = AF.GetColorTable("white", 0.25),
                },
                nameTextEmphasis = {
                    enabled = false,
                    sizeDelta = 2,
                    outline = "thickoutline",
                    shadow = true,
                },
            },
        },
        buffs = {
            enabled = false,
            position = {"BOTTOM", "TOP", 0, 10},
            anchorTo = "debuffs",
            orientation = "left_to_right",
            cooldownStyle = "none",
            width = 23,
            height = 23,
            spacingX = 3,
            spacingY = 6,
            numPerLine = 5,
            numTotal = 5,
            frameLevel = 2,
            durationText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"RIGHT", "TOPRIGHT", 0, -2},
                color = {
                    normal = AF.GetColorTable("white"), -- normal
                    percent = {enabled = false, value = 0.5, rgb = AF.GetColorTable("aura_percent")}, -- less than 50%
                    seconds = {enabled = true, value = 5, rgb = AF.GetColorTable("aura_seconds")}, -- less than 5sec
                },
            },
            stackText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"RIGHT", "BOTTOMRIGHT", 0, 2},
                color = AF.GetColorTable("white"),
            },
            filters = {
                castByMe = true,
                castByOthers = false,
                castByUnit = false,
                castByNPC = false,
                isBossAura = false,
                dispellable = false,
            },
            blockers = {},
            blacklist = {},
            auraTypeColor = {
                castByMe = false,
                dispellable = false,
                debuffType = false,
            },
        },
        debuffs = {
            enabled = false,
            position = {"BOTTOM", "TOP", 0, 18},
            anchorTo = "healthBar",
            orientation = "left_to_right",
            cooldownStyle = "none",
            width = 25,
            height = 15,
            spacingX = 3,
            spacingY = 6,
            numPerLine = 4,
            numTotal = 8,
            frameLevel = 2,
            durationText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"RIGHT", "TOPRIGHT", 0, -2},
                color = {
                    normal = AF.GetColorTable("white"), -- normal
                    percent = {enabled = false, value = 0.5, rgb = AF.GetColorTable("aura_percent")}, -- less than 50%
                    seconds = {enabled = true, value = 5, rgb = AF.GetColorTable("aura_seconds")}, -- less than 5sec
                },
            },
            stackText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"RIGHT", "BOTTOMRIGHT", 0, 2},
                color = AF.GetColorTable("white"),
            },
            filters = {
                castByMe = false,
                castByOthers = false,
                castByUnit = false,
                castByNPC = false,
                isBossAura = false,
                dispellable = true,
            },
            blockers = {
                crowdControlType = true,
            },
            blacklist = {},
            auraTypeColor = {
                castByMe = false,
                dispellable = true,
                debuffType = false,
            },
        },
        crowdControls = {
            enabled = false,
            position = {"BOTTOM", "TOP", 0, 15},
            anchorTo = "buffs",
            orientation = "left_to_right",
            cooldownStyle = "none",
            width = 45,
            height = 25,
            spacingX = 3,
            spacingY = 6,
            numPerLine = 3,
            numTotal = 3,
            frameLevel = 2,
            durationText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"RIGHT", "TOPRIGHT", 0, -2},
                color = {
                    normal = AF.GetColorTable("white"), -- normal
                    percent = {enabled = false, value = 0.5, rgb = AF.GetColorTable("aura_percent")}, -- less than 50%
                    seconds = {enabled = true, value = 5, rgb = AF.GetColorTable("aura_seconds")}, -- less than 5sec
                },
            },
            stackText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"RIGHT", "BOTTOMRIGHT", 0, 2},
                color = AF.GetColorTable("white"),
            },
            crowdControlTypes = {
                [1] = true,
                [2] = true,
                [3] = true,
                [4] = true,
                [5] = true,
                [6] = true,
                [7] = true,
                [8] = true,
                [9] = true,
                [10] = true,
                [11] = true,
                [12] = true,
                [13] = true,
                [14] = false,
                [15] = false,
                [99] = true,
            },
            -- filters = {},
            -- blockers = {},
            -- blacklist = {},
            auraTypeColor = {
                castByMe = false,
                dispellable = false,
                debuffType = false,
            },
        },
    }

    -- hostile
    defaults.hostile_npc = AF.Copy(nameplateDefaults, hostile, hostile_npc)
    defaults.hostile_npc.healthBar.threatGlow.enabled = true
    -- Semantic classification is evaluated entirely by AF's secret-safe
    -- health-color pipeline. Do not add NPC identities or Lua-side unit
    -- classification here.
    defaults.hostile_npc.healthBar.semanticColor = {
        boss = {
            enabled = true,
            rgb = {AF.ConvertHEXToRGB("#FF00FF")},
        },
        lieutenant = {
            enabled = true,
            rgb = {AF.ConvertHEXToRGB("#9370DB")},
        },
        caster = {
            enabled = true,
            rgb = {AF.ConvertHEXToRGB("#00BFFF")},
        },
        default = {
            enabled = true,
            rgb = {AF.ConvertHEXToRGB("#BE301D")},
        },
    }
    defaults.hostile_player = AF.Copy(nameplateDefaults, hostile)

    -- update hostile_player
    defaults.hostile_player.buffs.enabled = false
    defaults.hostile_player.buffs.glowDispellableByMe = false

    -- friendly
    defaults.friendly_npc = AF.Copy(nameplateDefaults, friendly)
    defaults.friendly_player = AF.Copy(nameplateDefaults, friendly)

    local friendly_enabled = {
        nameText = true,
        raidIcon = true,
        targetIndicator = true,
    }

    -- update friendly_npc
    for n, t in pairs(defaults.friendly_npc) do
        t.enabled = friendly_enabled[n]
    end

    -- update friendly_player
    for n, t in pairs(defaults.friendly_player) do
        t.enabled = friendly_enabled[n]
    end
end

-- local customDefaults = {
--     trigger = "npcName",
--     hide = false,
--     scale = {
--         enabled = false,
--         value = 1,
--     },
--     color = {
--         enabled = false,
--         value = AF.GetColorTable("white"),
--     },
--     glow = {
--         enabled = false,
--         color = AF.GetColorTable("yellow"),
--     },
--     texture = {
--         enabled = false,
--         width = 32,
--         height = 32,
--         useCustom = false,
--         path = "star",
--     },
-- }

function NP.GetDefaults()
    return AF.Copy(defaults)
end

function NP.MigrateConfig(config)
    local existingConfig = type(config) == "table"
    if not existingConfig then
        config = {}
    end

    local schemaVersion = tonumber(config.schemaVersion) or 0
    if existingConfig and schemaVersion < 1 then
        -- Preserve the former opt-in behavior for existing legacy profiles.
        -- An absent config belongs to a fresh profile and receives the
        -- shipped enabled default when the missing values merge below.
        config.enabled = false
    end

    if schemaVersion < 2 then
        local hostileNPC = config.hostile_npc
        local healthBar = type(hostileNPC) == "table"
            and hostileNPC.healthBar
        local threatGlow = type(healthBar) == "table"
            and healthBar.threatGlow
        if type(threatGlow) == "table" then
            local style = threatGlow.style
            if threatGlow.border == nil then
                threatGlow.border = style ~= "glow"
            end
            if threatGlow.glow == nil then
                threatGlow.glow = style ~= "border"
            end
            if threatGlow.bar == nil then
                threatGlow.bar = false
            end
            if threatGlow.name == nil then
                threatGlow.name = false
            end

            local alpha = tonumber(threatGlow.alpha)
            if threatGlow.borderAlpha == nil then
                threatGlow.borderAlpha = alpha or 0.8
            end
            if threatGlow.glowAlpha == nil then
                threatGlow.glowAlpha = alpha or 0.8
            end
            if threatGlow.barAlpha == nil then
                threatGlow.barAlpha = 0.65
            end
            if threatGlow.nameAlpha == nil then
                threatGlow.nameAlpha = 1
            end

            threatGlow.style = nil
            threatGlow.alpha = nil
        end
    end

    if schemaVersion < 3 then
        local hostileNPC = config.hostile_npc
        local healthBar = type(hostileNPC) == "table"
            and hostileNPC.healthBar
        local threatGlow = type(healthBar) == "table"
            and healthBar.threatGlow
        if type(threatGlow) == "table"
            and threatGlow.stateColors == nil
        then
            -- Existing default/native-color profiles gain the qualitative
            -- palette. Preserve an explicitly selected legacy single color
            -- by leaving that profile on the native fallback until the user
            -- opts into separate state colors.
            threatGlow.stateColors = AF.Copy(
                defaults.hostile_npc.healthBar.threatGlow.stateColors
            )
            if threatGlow.useCustomColor == true then
                threatGlow.stateColors.enabled = false
            end
        end
    end

    if schemaVersion < 4 then
        local hostileNPC = config.hostile_npc
        local healthBar = type(hostileNPC) == "table"
            and hostileNPC.healthBar
        local threatGlow = type(healthBar) == "table"
            and healthBar.threatGlow
        local stateColors = type(threatGlow) == "table"
            and threatGlow.stateColors
        local safe = type(stateColors) == "table"
            and stateColors.safe
        if type(safe) == "table" then
            -- Schema 3 enabled Safe automatically. Unlike warning states,
            -- Safe is present on every securely held/inactive-threat plate,
            -- so a persisted full-bar carrier could cover all health fills.
            -- Preserve the color and presentation settings, but require the
            -- user to opt back into the continuous Safe state.
            safe.enabled = false
        end
    end

    if schemaVersion < 5 then
        for _, plateType in ipairs({
            "hostile_npc",
            "hostile_player",
            "friendly_npc",
            "friendly_player",
        }) do
            local plateConfig = config[plateType]
            local castBar = type(plateConfig) == "table"
                and plateConfig.castBar
            local interruptibleCheck = type(castBar) == "table"
                and castBar.interruptibleCheck
            if type(interruptibleCheck) == "table" then
                if type(castBar.uninterruptibleIcon) ~= "table" then
                    local defaultCastBar =
                        defaults[plateType].castBar
                    castBar.uninterruptibleIcon = AF.Copy(
                        defaultCastBar.uninterruptibleIcon
                    )
                    if interruptibleCheck.showTexture ~= nil then
                        castBar.uninterruptibleIcon.enabled =
                            interruptibleCheck.enabled ~= false
                            and interruptibleCheck.showTexture == true
                    end
                end
                interruptibleCheck.showTexture = nil
            end
        end
    end

    if schemaVersion < 6 then
        for _, plateType in ipairs({
            "hostile_npc",
            "hostile_player",
            "friendly_npc",
            "friendly_player",
        }) do
            local plateConfig = config[plateType]
            local castBar = type(plateConfig) == "table"
                and plateConfig.castBar
            local icon = type(castBar) == "table"
                and castBar.uninterruptibleIcon
            local position = type(icon) == "table"
                and icon.position
            if type(position) == "table"
                and position[1] == "CENTER"
                and position[2] == "CENTER"
                and position[3] == 0
                and position[4] == 0
            then
                icon.position = {"LEFT", "RIGHT", 2, 0}
                if icon.size == 14 then
                    icon.size = 16
                end
            end
        end
    end

    -- Threat presentation is owned exclusively by hostile NPC plates. Older
    -- profiles shared these settings with hostile players; keep those
    -- dormant rather than allowing their legacy value to drive the feature.
    for _, plateType in ipairs({
        "hostile_player",
        "friendly_npc",
        "friendly_player",
    }) do
        local plateConfig = config[plateType]
        local healthBar = type(plateConfig) == "table"
            and plateConfig.healthBar
        local threatGlow = type(healthBar) == "table"
            and healthBar.threatGlow
        if type(threatGlow) == "table" then
            threatGlow.enabled = false
        end
    end

    -- Preserve a legacy custom marker size when hydrating the new
    -- target/focus-specific presentation tables.
    for _, plateType in ipairs({
        "hostile_npc",
        "hostile_player",
        "friendly_npc",
        "friendly_player",
    }) do
        local plateConfig = config[plateType]
        local indicator = type(plateConfig) == "table"
            and plateConfig.targetIndicator
        if type(indicator) == "table" then
            for _, stateKey in ipairs({"target", "focus"}) do
                local state = indicator[stateKey]
                if state == nil then
                    state = {}
                    indicator[stateKey] = state
                end
                if type(state) == "table" then
                    if state.layout == nil
                        and state.texture ~= nil
                    then
                        if plateType:find("^friendly_")
                            and stateKey == "focus"
                            and state.texture == "none"
                        then
                            state.layout = "none"
                            state.texture = "Arrow1_Blue"
                        else
                            state.layout = "top"
                        end
                    end

                    if state.size == nil
                        and indicator.size ~= nil
                    then
                        state.size = indicator.size
                    end

                    if state.topSpacing == nil
                        and type(indicator.position) == "table"
                        and indicator.position[1] == "BOTTOM"
                        and indicator.position[2] == "TOP"
                        and type(indicator.position[4]) == "number"
                    then
                        state.topSpacing = indicator.position[4]
                    end
                end
            end
        end
    end

    config.schemaVersion = SCHEMA_VERSION
    return F.MergeMissingDefaults(config, defaults)
end

function NP.GetNameplateDefaults()
    return AF.Copy(nameplateDefaults)
end

function NP.ResetToDefaults()
    wipe(NP.config)
    AF.Merge(NP.config, defaults)
end

AF.RegisterCallback("BFI_UpdateProfile", function(_, t)
    t.nameplates = NP.MigrateConfig(t.nameplates)
    NP.config = t.nameplates
end)
