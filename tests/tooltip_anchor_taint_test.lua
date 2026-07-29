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

local callbacks = {}
local moduleEvents = {}
local tooltipCallbacks = {}
local hooks = {
    methods = {},
    named = {},
}
local calls = {
    clearPoints = 0,
    setOwner = {},
    setPoint = 0,
}
local secretValue = {}
local tooltipAnchor

local function resetAnchoring(tooltip, point, owner)
    calls.clearPoints = 0
    calls.setOwner = {}
    calls.setPoint = 0
    tooltip.owner = owner
    tooltip.point = point
end

local function assertNoAnchoring(message)
    assertEqual(calls.clearPoints, 0, message .. " ClearAllPoints calls")
    assertEqual(calls.setPoint, 0, message .. " SetPoint calls")
    assertEqual(#calls.setOwner, 0, message .. " SetOwner calls")
end

local F = {}

function F.LoadPosition()
end

function F.isValueNonSecret(value)
    return value ~= secretValue
end

local uiParent = {
    name = "AF.UIParent",
}

function uiParent:IsForbidden()
    return false
end

local gameTooltip = {
    scripts = {},
}

function gameTooltip:ClearAllPoints()
    calls.clearPoints = calls.clearPoints + 1
    self.point = nil
end

function gameTooltip:GetOwner()
    return self.owner
end

function gameTooltip:Hide()
    self.hidden = true
end

function gameTooltip:HookScript(scriptName, callback)
    self.scripts[scriptName] = callback
end

function gameTooltip:IsForbidden()
    return false
end

function gameTooltip:IsShown()
    return self.shown
end

function gameTooltip:SetOwner(owner, anchorType, x, y)
    if owner.forbidden then
        error("addon attempted to use a forbidden tooltip owner", 2)
    end

    calls.setOwner[#calls.setOwner + 1] = {
        anchorType = anchorType,
        owner = owner,
        x = x,
        y = y,
    }
    self.owner = owner
end

function gameTooltip:SetPoint(...)
    calls.setPoint = calls.setPoint + 1
    self.point = {...}
end

function gameTooltip:SetUnit(unit)
    self.setUnit = unit
end

local statusBar = {}

function statusBar:SetAlpha(alpha)
    self.alpha = alpha
end

function statusBar:SetStatusBarColor()
end

local tooltipModule = {
    config = {
        anchorMode = "fixed",
        anchorPoint = "BOTTOMRIGHT",
        cursorAnchor = {
            x = 12,
            y = 34,
        },
        enabled = true,
        healthBar = {
            colorMode = "class",
            enabled = true,
            height = 8,
        },
        hideUnitTooltipsInCombat = false,
        itemLevel = {
            enabled = false,
        },
        levelDifficultyColor = true,
        mythicPlus = {
            enabled = false,
        },
        position = {},
    },
}

function tooltipModule:RegisterEvent(event, callback)
    moduleEvents[event] = callback
end

local AF = {
    UIParent = uiParent,
}

function AF.CreateMover(frame)
    frame.mover = {
        Hide = function()
        end,
    }
end

function AF.LoadPosition()
end

function AF.RegisterCallback(event, callback)
    callbacks[event] = callbacks[event] or {}
    callbacks[event][#callbacks[event] + 1] = callback
end

function AF.SetHeight(frame, height)
    frame.height = height
end

function AF.SetSize(frame, width, height)
    frame.width = width
    frame.height = height
end

function AF.UpdateMoverSave()
end

local BFI = {
    L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    }),
    funcs = F,
    modules = {
        Tooltip = tooltipModule,
    },
}

local environment = {
    AbstractFramework = AF,
    BFI = BFI,
    C_ClassColor = {
        GetClassColor = function()
            return {r = 1, g = 1, b = 1}
        end,
    },
    C_MythicPlus = {
        RequestMapInfo = function()
        end,
    },
    C_PlayerInfo = {
        GetContentDifficultyCreatureForPlayer = function()
            return 0
        end,
        GetPlayerMythicPlusRatingSummary = function()
        end,
    },
    CreateFrame = function()
        tooltipAnchor = {}
        return tooltipAnchor
    end,
    DISABLED_FONT_COLOR = {r = 0.5, g = 0.5, b = 0.5},
    DUNGEON_SCORE = "Dungeon Score",
    Enum = {
        TooltipDataLineType = {
            None = 0,
            UnitLevel = 1,
            UnitType = 2,
        },
        TooltipDataType = {
            Unit = 1,
        },
        WorldCursorAnchorType = {
            Cursor = 2,
            Nameplate = 3,
        },
    },
    GREEN_FONT_COLOR = {
        GetRGB = function()
            return 0, 1, 0
        end,
    },
    GameTooltip = gameTooltip,
    GameTooltipStatusBar = statusBar,
    GetDifficultyColor = function()
        return {r = 1, g = 1, b = 1}
    end,
    GetFactionColor = function()
        return {r = 1, g = 1, b = 1}
    end,
    GetGuildInfo = function()
    end,
    HIGHLIGHT_FONT_COLOR = {r = 1, g = 1, b = 1},
    InCombatLockdown = function()
        return false
    end,
    IsAltKeyDown = function()
        return false
    end,
    IsShiftKeyDown = function()
        return false
    end,
    NORMAL_FONT_COLOR = {r = 1, g = 1, b = 1},
    OTHER = "Other",
    STAT_AVERAGE_ITEM_LEVEL = "Item Level",
    TooltipDataProcessor = {
        AddLinePostCall = function(_, callback)
            tooltipCallbacks.line = callback
        end,
        AddTooltipPostCall = function(_, callback)
            tooltipCallbacks.post = callback
        end,
        AddTooltipPreCall = function(_, callback)
            tooltipCallbacks.pre = callback
        end,
    },
    UNKNOWN = "Unknown",
    UnitClassBase = function()
        return "MAGE"
    end,
    UnitExists = function()
        return true
    end,
    UnitFactionGroup = function()
        return "Alliance"
    end,
    UnitIsPlayer = function()
        return true
    end,
    format = string.format,
    hooksecurefunc = function(target, method, callback)
        if type(target) == "string" then
            hooks.named[target] = method
        else
            hooks.methods[method] = callback
        end
    end,
}
environment._G = environment
setmetatable(environment, {
    __index = _G,
})

local chunk, loadError = loadfile("Modules/Tooltip/Tooltip.lua")
assertTrue(chunk, loadError)
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertTrue(callbacks.BFI_UpdateModule, "missing tooltip update callback")
callbacks.BFI_UpdateModule[1]()

local defaultAnchorHook = hooks.named.GameTooltip_SetDefaultAnchor
local worldCursorHook = hooks.methods.SetWorldCursor
assertTrue(defaultAnchorHook, "missing GameTooltip_SetDefaultAnchor hook")
assertTrue(worldCursorHook, "missing GameTooltip:SetWorldCursor hook")
assertTrue(tooltipCallbacks.line, "missing unit-level color callback")
assertTrue(tooltipCallbacks.post, "missing unit tooltip post-call")

local function newForbiddenOwner(forbiddenResult)
    local owner = {
        forbidden = true,
    }

    function owner:IsForbidden()
        return forbiddenResult
    end

    return setmetatable(owner, {
        __index = function(_, key)
            error("addon accessed forbidden owner field " .. tostring(key), 2)
        end,
    })
end

local forbiddenOwner = newForbiddenOwner(secretValue)
local accessibleOwner = {}

function accessibleOwner:IsForbidden()
    return false
end

-- Secret object references are rejected before nil comparison or methods.
local nativePoint = {"NATIVE_SECRET_OBJECT", secretValue}
resetAnchoring(gameTooltip, nativePoint, secretValue)
defaultAnchorHook(gameTooltip, secretValue)

assertNoAnchoring("secret object")
assertEqual(gameTooltip.point, nativePoint, "secret object native point")

-- Protected nameplate aura ownership and placement remain entirely native.
nativePoint = {"NATIVE_FORBIDDEN", forbiddenOwner}
resetAnchoring(gameTooltip, nativePoint, forbiddenOwner)
defaultAnchorHook(gameTooltip, forbiddenOwner)

assertNoAnchoring("protected default anchor")
assertEqual(gameTooltip.owner, forbiddenOwner, "protected native owner")
assertEqual(gameTooltip.point, nativePoint, "protected native point")

local explicitlyForbiddenOwner = newForbiddenOwner(true)
nativePoint = {"NATIVE_TRUE_FORBIDDEN", explicitlyForbiddenOwner}
resetAnchoring(gameTooltip, nativePoint, explicitlyForbiddenOwner)
defaultAnchorHook(gameTooltip, explicitlyForbiddenOwner)

assertNoAnchoring("true forbidden owner")
assertEqual(gameTooltip.point, nativePoint, "true forbidden native point")

-- Accessible owners retain the configured fixed-anchor behavior.
resetAnchoring(gameTooltip, {"NATIVE_ACCESSIBLE"}, accessibleOwner)
defaultAnchorHook(gameTooltip, accessibleOwner)

assertEqual(#calls.setOwner, 0, "accessible fixed SetOwner calls")
assertEqual(calls.clearPoints, 1, "accessible fixed ClearAllPoints calls")
assertEqual(calls.setPoint, 1, "accessible fixed SetPoint calls")
assertEqual(gameTooltip.owner, accessibleOwner, "accessible fixed owner")
assertEqual(gameTooltip.point[1], "BOTTOMRIGHT", "accessible fixed point")
assertEqual(gameTooltip.point[2], tooltipAnchor, "accessible fixed relative frame")
assertEqual(gameTooltip.point[3], "TOPRIGHT", "accessible fixed relative point")

-- Secret frames derived from accessible owner config also fail closed.
local parentResultOwner = {
    tooltip = {
        anchorTo = "parent",
        enabled = true,
        position = {"TOPLEFT", "BOTTOMLEFT", 1, 2},
    },
}

function parentResultOwner:GetParent()
    return secretValue
end

function parentResultOwner:IsForbidden()
    return false
end

nativePoint = {"NATIVE_PARENT_RESULT", parentResultOwner}
resetAnchoring(gameTooltip, nativePoint, parentResultOwner)
defaultAnchorHook(gameTooltip, parentResultOwner)

assertNoAnchoring("secret GetParent result")
assertEqual(gameTooltip.point, nativePoint, "secret GetParent native point")

local rootResultOwner = {
    root = secretValue,
    tooltip = {
        anchorTo = "root",
        enabled = true,
        position = {"TOPLEFT", "BOTTOMLEFT", 1, 2},
    },
}

function rootResultOwner:IsForbidden()
    return false
end

nativePoint = {"NATIVE_ROOT_RESULT", rootResultOwner}
resetAnchoring(gameTooltip, nativePoint, rootResultOwner)
defaultAnchorHook(gameTooltip, rootResultOwner)

assertNoAnchoring("secret root result")
assertEqual(gameTooltip.point, nativePoint, "secret root native point")

nativePoint = {"NATIVE_NAMEPLATE", forbiddenOwner}
resetAnchoring(gameTooltip, nativePoint, forbiddenOwner)
worldCursorHook(gameTooltip, 3, forbiddenOwner)

assertNoAnchoring("protected nameplate world cursor")
assertEqual(gameTooltip.point, nativePoint, "protected nameplate native point")

-- The known native Cursor branch safely resets its UIParent owner mode.
tooltipModule.config.anchorMode = "fixed"
resetAnchoring(gameTooltip, {"NATIVE_CURSOR"}, uiParent)
worldCursorHook(gameTooltip, 2)

assertEqual(#calls.setOwner, 1, "world cursor fixed SetOwner calls")
assertEqual(calls.setOwner[1].owner, uiParent, "world cursor fixed owner")
assertEqual(calls.setOwner[1].anchorType, "ANCHOR_NONE",
    "world cursor fixed anchor type")

-- Accessible cursor policies preserve their historical owner.
tooltipModule.config.anchorMode = "cursor_right"
resetAnchoring(gameTooltip, {"NATIVE_CURSOR_POLICY"}, accessibleOwner)
defaultAnchorHook(gameTooltip, accessibleOwner)

assertEqual(#calls.setOwner, 1, "cursor policy SetOwner calls")
assertEqual(calls.setOwner[1].owner, accessibleOwner, "cursor policy owner")
assertEqual(calls.setOwner[1].anchorType, "ANCHOR_CURSOR_RIGHT",
    "cursor policy anchor type")
assertEqual(calls.setOwner[1].x, 12, "cursor policy x offset")
assertEqual(calls.setOwner[1].y, 34, "cursor policy y offset")

nativePoint = {"NATIVE_PROTECTED_CURSOR_POLICY", forbiddenOwner}
resetAnchoring(gameTooltip, nativePoint, forbiddenOwner)
defaultAnchorHook(gameTooltip, forbiddenOwner)

assertNoAnchoring("protected cursor policy")
assertEqual(gameTooltip.point, nativePoint, "protected cursor policy native point")

-- Later GetOwner consumers use the same gate.
gameTooltip.owner = forbiddenOwner
gameTooltip.hidden = false
gameTooltip.scripts.OnShow(gameTooltip)
moduleEvents.PLAYER_REGEN_DISABLED()

assertEqual(gameTooltip.hidden, false, "protected owner visibility")

-- An inaccessible owner must not suppress the independent unit-tooltip policy.
tooltipCallbacks.pre(gameTooltip)
tooltipModule.config.hideUnitTooltipsInCombat = true
gameTooltip.hidden = false
moduleEvents.PLAYER_REGEN_DISABLED()

assertEqual(gameTooltip.hidden, true, "protected owner unit-tooltip visibility")
tooltipModule.config.hideUnitTooltipsInCombat = false

-- IsShown can be Shown-secret; refreshing stops before SetUnit.
tooltipModule.config.itemLevel.enabled = true
tooltipModule.config.itemLevel.showOnAlt = true
tooltipCallbacks.pre(gameTooltip)
gameTooltip.shown = secretValue
gameTooltip.setUnit = nil
moduleEvents.MODIFIER_STATE_CHANGED(nil, nil, "LALT")

assertEqual(gameTooltip.setUnit, nil, "secret shown refresh")

gameTooltip.shown = true
moduleEvents.MODIFIER_STATE_CHANGED(nil, nil, "LALT")

assertEqual(gameTooltip.setUnit, "mouseover", "visible tooltip refresh")

print("tooltip anchor taint tests passed")
