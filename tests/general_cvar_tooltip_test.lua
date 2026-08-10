local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
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

local function loadGeneral(getCVar, defaults)
    local callback
    local shownLines
    local AF = {
        HideTooltip = function()
        end,
        RegisterCallback = function(event, registeredCallback)
            assertEqual(event, "BFI_ShowOptionsPanel", "callback event")
            callback = registeredCallback
        end,
        RoundToDecimal = function(value, places)
            local multiplier = 10 ^ places
            return math.floor(value * multiplier + 0.5) / multiplier
        end,
        ShowTooltip = function(_, _, _, _, lines)
            shownLines = lines
        end,
        WrapTextInColor = function(text, color)
            if text == nil then
                error("color text must not be nil", 2)
            end
            return ("[%s]%s"):format(color, tostring(text))
        end,
    }

    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
    local environment = {
        _G = false,
        AbstractFramework = AF,
        GetCVar = getCVar,
        GetCVarBool = function()
            return false
        end,
        GetCVarDefault = function(name)
            return defaults[name]
        end,
        LAG_TOLERANCE = "Lag Tolerance",
        MILLISECONDS_ABBR = "ms",
        SHOW_PLAYER_NAMES = "Show Player Names",
        UNIT_NAME_GUILD = "Guild",
        UNIT_NAME_PLAYER_TITLE = "PvP Title",
        SetCVar = function()
        end,
        debug = debug,
        format = string.format,
        math = math,
        next = next,
        select = select,
        setmetatable = setmetatable,
        string = string,
        table = table,
        tinsert = table.insert,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
    }
    environment._G = environment

    local BFI = {
        L = L,
        funcs = {},
    }

    local chunk, loadError = loadfile("Options/General.lua")
    assertEqual(type(chunk), "function", loadError or "module load")
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    assertEqual(type(callback), "function", "options callback")
    local createCVarPane = findUpvalue(callback, "CreateCVarPane")
    assertEqual(type(createCVarPane), "function", "CVar pane creator upvalue")
    local cvarOptions = findUpvalue(createCVarPane, "cvarOptions")
    assertEqual(type(cvarOptions), "table", "CVar option factories upvalue")
    local cvars = findUpvalue(createCVarPane, "cvars")
    assertEqual(type(cvars), "table", "CVar definitions upvalue")
    local optionOnEnter = findUpvalue(cvarOptions.toggle, "Option_OnEnter")
    assertEqual(type(optionOnEnter), "function", "CVar hover handler upvalue")
    local getCVarTooltipLine = findUpvalue(optionOnEnter, "GetCVarTooltipLine")
    assertEqual(type(getCVarTooltipLine), "function",
        "CVar tooltip builder upvalue")

    return {
        cvars = cvars,
        getCVarTooltipLine = getCVarTooltipLine,
        getShownLines = function()
            return shownLines
        end,
        optionOnEnter = optionOnEnter,
    }
end

local function assertCVarDefinitions(cvars, expected, client)
    for index = 9, 14 do
        local actualName = cvars[index].name
        local expectedName = expected[index]
        if type(expectedName) == "table" then
            assertEqual(type(actualName), "table", client .. " grouped CVar " .. index)
            assertEqual(actualName[1], expectedName[1],
                client .. " first grouped CVar " .. index)
            assertEqual(actualName[2], expectedName[2],
                client .. " second grouped CVar " .. index)
        else
            assertEqual(actualName, expectedName, client .. " CVar " .. index)
        end
    end
    assertEqual(cvars[14].parent, expected[13],
        client .. " directional offset parent CVar")
end

local versionedDefaults = {
    WorldTextScale_v2 = "1",
    floatingCombatTextCombatDamageDirectionalOffset_v2 = "1",
    floatingCombatTextCombatDamageDirectionalScale_v2 = "1",
    floatingCombatTextCombatDamage_v2 = "1",
    floatingCombatTextCombatHealingAbsorbTarget_v2 = "1",
    floatingCombatTextCombatHealing_v2 = "1",
    floatingCombatTextCombatLogPeriodicSpells_v2 = "1",
    floatingCombatTextPetMeleeDamage_v2 = "1",
    floatingCombatTextPetSpellDamage_v2 = "1",
    numericCVar = "1.236",
    stringCVar = "enabled",
}
local versioned = loadGeneral(function()
    return "0"
end, versionedDefaults)
local expectedVersioned = {
    [9] = "WorldTextScale_v2",
    [10] = {
        "floatingCombatTextCombatDamage_v2",
        "floatingCombatTextCombatLogPeriodicSpells_v2",
    },
    [11] = {
        "floatingCombatTextPetMeleeDamage_v2",
        "floatingCombatTextPetSpellDamage_v2",
    },
    [12] = {
        "floatingCombatTextCombatHealing_v2",
        "floatingCombatTextCombatHealingAbsorbTarget_v2",
    },
    [13] = "floatingCombatTextCombatDamageDirectionalScale_v2",
    [14] = "floatingCombatTextCombatDamageDirectionalOffset_v2",
}
assertCVarDefinitions(versioned.cvars, expectedVersioned, "12.0.1+")

for index = 9, 14 do
    local widget = {
        info = {
            label = "Combat text option",
            name = versioned.cvars[index].name,
            tooltip = "Combat text option description.",
        },
    }
    versioned.optionOnEnter(widget)
    assertEqual(type(widget.tooltipLines), "table",
        "versioned combat text hover lines " .. index)
end

local legacy = loadGeneral(function(name)
    if name:sub(-3) == "_v2" then
        return nil
    end
    return "0"
end, {})
local expectedLegacy = {
    [9] = "WorldTextScale",
    [10] = {
        "floatingCombatTextCombatDamage",
        "floatingCombatTextCombatLogPeriodicSpells",
    },
    [11] = {
        "floatingCombatTextPetMeleeDamage",
        "floatingCombatTextPetSpellDamage",
    },
    [12] = {
        "floatingCombatTextCombatHealing",
        "floatingCombatTextCombatHealingAbsorbTarget",
    },
    [13] = "floatingCombatTextCombatDamageDirectionalScale",
    [14] = "floatingCombatTextCombatDamageDirectionalOffset",
}
assertCVarDefinitions(legacy.cvars, expectedLegacy, "12.0.0")

local numericLine = versioned.getCVarTooltipLine("numericCVar")
assertEqual(type(numericLine), "table", "numeric default tooltip type")
assertEqual(numericLine[1], "[yellow_text]\"numericCVar\"", "numeric CVar name")
assertEqual(numericLine[2], "[softlime]Default Value: [white]1.24",
    "rounded numeric default")

local stringLine = versioned.getCVarTooltipLine("stringCVar")
assertEqual(type(stringLine), "table", "string default tooltip type")
assertEqual(stringLine[2], "[softlime]Default Value: [white]enabled",
    "string default")

local widget = {
    info = {
        label = "Missing default",
        name = "missingCVar",
        tooltip = "The client exposes no default for this CVar.",
    },
}
versioned.optionOnEnter(widget)
local shownLines = versioned.getShownLines()
assertEqual(shownLines, widget.tooltipLines, "hover tooltip lines")
assertEqual(shownLines[1], "Missing default", "hover tooltip label")
assertEqual(shownLines[2], "[yellow_text]\"missingCVar\"",
    "missing default falls back to the CVar name")
assertEqual(shownLines[3], "The client exposes no default for this CVar.",
    "hover tooltip description")

print("general_cvar_tooltip_test.lua: ok")
