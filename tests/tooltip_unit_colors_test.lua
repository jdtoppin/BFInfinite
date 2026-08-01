local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertColor(region, red, green, blue, message)
    local color = region.color
    if not color then
        error((message or "region color") .. ": no color was applied", 2)
    end
    assertEqual(color[1], red, (message or "region color") .. " red")
    assertEqual(color[2], green, (message or "region color") .. " green")
    assertEqual(color[3], blue, (message or "region color") .. " blue")
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

local function setUpvalue(func, targetName, targetValue)
    local index = 1
    while true do
        local name = debug.getupvalue(func, index)
        if not name then
            return false
        elseif name == targetName then
            debug.setupvalue(func, index, targetValue)
            return true
        end
        index = index + 1
    end
end

local function makeColor(red, green, blue)
    return {
        b = blue,
        g = green,
        r = red,
        GetRGB = function()
            return red, green, blue
        end,
    }
end

local function makeFontString()
    local fontString = {}
    function fontString:SetTextColor(...)
        self.color = {...}
    end
    return fontString
end

local secretValue = {}
local renderedUnit = "nameplate7"
local renderedUnitGUID = "Player-1-00000001"
local playerResult = true
local playerInGuildResult = true
local unitPVPResult = false
local classFilename = "MAGE"
local accessibleResult = true
local forbiddenResult = false
local classColorCalls = 0
local guildLookupCalls = 0
local mythicPlusUnit
local itemLevelUnit
local fontStrings = {}
for index = 1, 8 do
    fontStrings[index] = makeFontString()
end

local setUnitCalls = 0
local tooltipScripts = {}
local gameTooltip = {}
function gameTooltip:GetLeftLine(index)
    return fontStrings[index]
end
function gameTooltip:HookScript(script, callback)
    tooltipScripts[script] = callback
end
function gameTooltip:CanBeAccessedInContext()
    return accessibleResult
end
function gameTooltip:IsForbidden()
    return forbiddenResult
end
function gameTooltip:IsShown()
    error("the initial native tooltip pass must not inspect IsShown", 2)
end
function gameTooltip:SetUnit()
    setUnitCalls = setUnitCalls + 1
end
function gameTooltip:SetWorldCursor()
end
function gameTooltip:Hide()
end

local statusBar = {}
function statusBar:SetAlpha(alpha)
    self.alpha = alpha
end
function statusBar:SetStatusBarColor(...)
    self.color = {...}
end

local tooltipPreCalls = {}
local tooltipPostCalls = {}
local linePostCallCount = 0
local TooltipDataProcessor = {}
function TooltipDataProcessor.AddTooltipPreCall(dataType, callback)
    tooltipPreCalls[dataType] = callback
end
function TooltipDataProcessor.AddTooltipPostCall(dataType, callback)
    tooltipPostCalls[dataType] = callback
end
function TooltipDataProcessor.AddLinePostCall()
    linePostCallCount = linePostCallCount + 1
end

local callbacks = {}
local AF = {
    ItemLevel = {
        Request = function(unit)
            itemLevelUnit = unit
        end,
    },
    RegisterCallback = function(event, callback)
        callbacks[event] = callback
    end,
    SetHeight = function(region, height)
        region.height = height
    end,
    SetSize = function(region, width, height)
        region.width = width
        region.height = height
    end,
    UIParent = {},
    UpdateMoverSave = function()
    end,
}
function AF.CreateMover(region)
    region.mover = {
        Hide = function(self)
            self.hidden = true
        end,
    }
end

local tooltipModule = {
    config = {
        anchorMode = "fixed",
        anchorPoint = "BOTTOMRIGHT",
        cursorAnchor = {x = 10, y = -5},
        enabled = true,
        healthBar = {
            colorMode = "class",
            enabled = true,
            height = 4,
        },
        hideUnitTooltipsInCombat = false,
        itemLevel = {enabled = false},
        levelDifficultyColor = true,
        mythicPlus = {enabled = false},
        position = {"BOTTOMRIGHT", -10, 10},
    },
    RegisterEvent = function()
    end,
}

local BFI = {
    L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    }),
    funcs = {
        isValueNonSecret = function(value)
            return value ~= secretValue
        end,
        LoadPosition = function()
        end,
    },
    modules = {
        Tooltip = tooltipModule,
    },
}

local classColor = makeColor(0.1, 0.2, 0.3)
local deathKnightColor = makeColor(0.77, 0.12, 0.23)
local factionColor = makeColor(0.4, 0.5, 0.6)
local difficultyColor = makeColor(1, 0.82, 0)
local greenColor = makeColor(0, 1, 0)
local unitLineType = {
    None = 0,
    UnitName = 2,
    UnitLevel = 47,
    UnitType = 48,
    UnitDead = 49,
}

local environment = {
    _G = false,
    AbstractFramework = AF,
    C_ChallengeMode = {
        GetDungeonScoreRarityColor = function()
        end,
        GetMapUIInfo = function()
        end,
    },
    C_ClassColor = {
        GetClassColor = function(requestedClassFilename)
            classColorCalls = classColorCalls + 1
            assertEqual(requestedClassFilename, classFilename, "rendered unit class")
            return requestedClassFilename == "DEATHKNIGHT" and deathKnightColor or classColor
        end,
    },
    C_MythicPlus = {
        RequestMapInfo = function()
        end,
    },
    C_PlayerInfo = {
        GetContentDifficultyCreatureForPlayer = function(unit)
            assertEqual(unit, renderedUnit, "difficulty unit token")
            return 2
        end,
        GetPlayerMythicPlusRatingSummary = function(unit)
            mythicPlusUnit = unit
        end,
    },
    CreateFrame = function()
        return {}
    end,
    DISABLED_FONT_COLOR = makeColor(0.5, 0.5, 0.5),
    Enum = {
        TooltipDataLineType = unitLineType,
        TooltipDataType = {Unit = 1},
        WorldCursorAnchorType = {
            Cursor = 1,
            Nameplate = 2,
        },
    },
    GameTooltip = gameTooltip,
    GameTooltipStatusBar = statusBar,
    GetDifficultyColor = function(difficulty)
        assertEqual(difficulty, 2, "Fair relative content difficulty")
        return difficultyColor
    end,
    GetFactionColor = function(faction)
        assertEqual(faction, "Alliance", "rendered unit faction")
        return factionColor
    end,
    GREEN_FONT_COLOR = greenColor,
    HIGHLIGHT_FONT_COLOR = makeColor(1, 1, 1),
    InCombatLockdown = function()
        return false
    end,
    IsAltKeyDown = function()
        return false
    end,
    IsPlayerInGuildFromGUID = function(guid)
        guildLookupCalls = guildLookupCalls + 1
        assertEqual(guid, renderedUnitGUID, "rendered unit guild GUID")
        return playerInGuildResult
    end,
    IsShiftKeyDown = function()
        return false
    end,
    NORMAL_FONT_COLOR = makeColor(1, 1, 1),
    OTHER = "Other",
    TooltipDataProcessor = TooltipDataProcessor,
    UNKNOWN = "Unknown",
    UnitClassBase = function(unit)
        assertEqual(unit, renderedUnit, "class unit token")
        return classFilename
    end,
    UnitExists = function(unit)
        assertEqual(unit, renderedUnit, "existing unit token")
        return true
    end,
    UnitFactionGroup = function(unit)
        assertEqual(unit, renderedUnit, "faction unit token")
        return "Alliance"
    end,
    UnitIsPVP = function(unit)
        assertEqual(unit, renderedUnit, "PvP unit token")
        return unitPVPResult
    end,
    UnitIsPlayer = function(unit)
        assertEqual(unit, renderedUnit, "player unit token")
        return playerResult
    end,
    format = string.format,
    hooksecurefunc = function()
    end,
    select = select,
    tostring = tostring,
    type = type,
    wipe = function(tableToClear)
        for key in pairs(tableToClear) do
            tableToClear[key] = nil
        end
    end,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local chunk, loadError = loadfile("Modules/Tooltip/Tooltip.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(callbacks.BFI_UpdateModule), "function", "module update callback")
callbacks.BFI_UpdateModule()

local preCall = tooltipPreCalls[environment.Enum.TooltipDataType.Unit]
local postCall = tooltipPostCalls[environment.Enum.TooltipDataType.Unit]
assertEqual(type(preCall), "function", "unit tooltip pre-call")
assertEqual(type(postCall), "function", "unit tooltip post-call")
assertEqual(type(tooltipScripts.OnHide), "function", "unit tooltip cleanup hook")
assertEqual(linePostCallCount, 0, "level styling belongs to the native tooltip pass")

local function clearColors()
    for _, fontString in ipairs(fontStrings) do
        fontString.color = nil
    end
    statusBar.color = nil
end

local function runPlayerFixture(
    lines,
    nameIndex,
    levelIndex,
    classIndex,
    factionIndex,
    guildIndex
)
    clearColors()
    playerResult = true
    classFilename = "MAGE"
    preCall(gameTooltip)
    postCall(gameTooltip, {lines = lines})

    assertColor(fontStrings[nameIndex], 0.1, 0.2, 0.3, "player name")
    assertColor(fontStrings[levelIndex], 1, 0.82, 0, "level 90 difficulty")
    assertColor(fontStrings[classIndex], 0.1, 0.2, 0.3, "class/specification")
    assertColor(fontStrings[factionIndex], 0.4, 0.5, 0.6, "Alliance faction")
    assertColor(statusBar, 0.1, 0.2, 0.3, "player health bar")
    if guildIndex then
        assertColor(fontStrings[guildIndex], 0, 1, 0, "player guild")
    end
end

runPlayerFixture({
    {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
    {lineIndex = 2, type = unitLineType.None},
    {lineIndex = 3, type = unitLineType.UnitLevel},
    {lineIndex = 4, type = unitLineType.UnitType},
    {lineIndex = 5, type = unitLineType.None},
}, 1, 3, 4, 5, 2)

local fourGenericPlayerLines = {
    {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
    {lineIndex = 2, type = unitLineType.None},
    {lineIndex = 3, type = unitLineType.None},
    {lineIndex = 4, type = unitLineType.None},
    {lineIndex = 5, type = unitLineType.None},
}

-- Four generic rows can mean guild/level/class/faction or a no-guild identity
-- block followed by a status. Without a public positive guild discriminator,
-- leave the ambiguous rows native.
clearColors()
playerResult = true
local priorGuildLookupCalls = guildLookupCalls
postCall(gameTooltip, {lines = fourGenericPlayerLines})
assertEqual(guildLookupCalls, priorGuildLookupCalls, "missing guild GUID is not queried")
assertColor(fontStrings[1], 0.1, 0.2, 0.3, "ambiguous generic player name")
assertColor(statusBar, 0.1, 0.2, 0.3, "ambiguous generic health bar")
for index = 2, 5 do
    assertEqual(fontStrings[index].color, nil, "ambiguous generic row " .. index)
end

-- Model the reported 12.1 symptom: a same-faction guilded Death Knight can
-- expose guild, level, class/specification, and faction as four generic rows
-- even though UnitLevel and UnitType exist in the enum table. A documented
-- positive guild GUID query disambiguates these rows.
clearColors()
classFilename = "DEATHKNIGHT"
postCall(gameTooltip, {
    guid = renderedUnitGUID,
    lines = fourGenericPlayerLines,
})
assertColor(fontStrings[1], 0.77, 0.12, 0.23, "12.1 Death Knight name")
assertColor(fontStrings[3], 1, 0.82, 0, "12.1 Death Knight level")
assertColor(fontStrings[4], 0.77, 0.12, 0.23, "12.1 Death Knight class/specification")
assertColor(fontStrings[5], 0.4, 0.5, 0.6, "12.1 same-faction Alliance")
assertColor(fontStrings[2], 0, 1, 0, "12.1 Death Knight guild")
classFilename = "MAGE"

-- Reported PTR layout: an unguilded PvP player adds a trailing generic PvP
-- status after the level, class/specification, and faction rows.
clearColors()
classFilename = "DEATHKNIGHT"
playerInGuildResult = false
unitPVPResult = true
local priorPvPGuildLookupCalls = guildLookupCalls
postCall(gameTooltip, {
    guid = renderedUnitGUID,
    lines = fourGenericPlayerLines,
})
assertEqual(guildLookupCalls, priorPvPGuildLookupCalls + 1,
    "unguilded PvP shape queries public guild state")
assertColor(fontStrings[1], 0.77, 0.12, 0.23, "unguilded PvP Death Knight name")
assertColor(fontStrings[2], 1, 0.82, 0, "unguilded PvP level")
assertColor(fontStrings[3], 0.77, 0.12, 0.23, "unguilded PvP class/specification")
assertColor(fontStrings[4], 0.4, 0.5, 0.6, "unguilded PvP same-faction Alliance")
assertEqual(fontStrings[5].color, nil, "unguilded PvP status remains native")

local fiveGenericPlayerLines = {
    {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
    {lineIndex = 2, type = unitLineType.None},
    {lineIndex = 3, type = unitLineType.None},
    {lineIndex = 4, type = unitLineType.None},
    {lineIndex = 5, type = unitLineType.None},
    {lineIndex = 6, type = unitLineType.None},
}
clearColors()
playerInGuildResult = true
priorPvPGuildLookupCalls = guildLookupCalls
postCall(gameTooltip, {
    guid = renderedUnitGUID,
    lines = fiveGenericPlayerLines,
})
assertEqual(guildLookupCalls, priorPvPGuildLookupCalls + 1,
    "guilded PvP shape queries public guild state")
assertColor(fontStrings[1], 0.77, 0.12, 0.23, "guilded PvP Death Knight name")
assertColor(fontStrings[2], 0, 1, 0, "guilded PvP guild")
assertColor(fontStrings[3], 1, 0.82, 0, "guilded PvP level")
assertColor(fontStrings[4], 0.77, 0.12, 0.23, "guilded PvP class/specification")
assertColor(fontStrings[5], 0.4, 0.5, 0.6, "guilded PvP same-faction Alliance")
assertEqual(fontStrings[6].color, nil, "guilded PvP status remains native")

-- Secret PvP state must not select the unguilded four-row interpretation.
clearColors()
playerInGuildResult = false
unitPVPResult = secretValue
postCall(gameTooltip, {
    guid = renderedUnitGUID,
    lines = fourGenericPlayerLines,
})
for index = 2, 5 do
    assertEqual(fontStrings[index].color, nil, "secret PvP row " .. index)
end

classFilename = "MAGE"
playerInGuildResult = true
unitPVPResult = false

-- Secret guild state must not select a row layout.
clearColors()
playerInGuildResult = secretValue
postCall(gameTooltip, {
    guid = renderedUnitGUID,
    lines = fourGenericPlayerLines,
})
for index = 2, 5 do
    assertEqual(fontStrings[index].color, nil, "secret guild row " .. index)
end

-- A public negative guild result also leaves the ambiguous block native.
clearColors()
playerInGuildResult = false
postCall(gameTooltip, {
    guid = renderedUnitGUID,
    lines = fourGenericPlayerLines,
})
for index = 2, 5 do
    assertEqual(fontStrings[index].color, nil, "non-guild row " .. index)
end

-- A secret GUID never reaches the guild predicate.
clearColors()
priorGuildLookupCalls = guildLookupCalls
postCall(gameTooltip, {
    guid = secretValue,
    lines = fourGenericPlayerLines,
})
assertEqual(guildLookupCalls, priorGuildLookupCalls, "secret guild GUID is not queried")
for index = 2, 5 do
    assertEqual(fontStrings[index].color, nil, "secret guild GUID row " .. index)
end
playerInGuildResult = true

-- The exact three-row no-guild legacy identity block is unambiguous.
runPlayerFixture({
    {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
    {lineIndex = 2, type = unitLineType.None},
    {lineIndex = 3, type = unitLineType.None},
    {lineIndex = 4, type = unitLineType.None},
}, 1, 2, 3, 4)

runPlayerFixture({
    {lineIndex = 1, type = unitLineType.None},
    {lineIndex = 2, type = unitLineType.UnitName, unitToken = renderedUnit},
    {lineIndex = 3, type = unitLineType.None},
    {lineIndex = 4, type = unitLineType.UnitLevel},
    {lineIndex = 5, type = unitLineType.UnitType},
    {lineIndex = 6, type = unitLineType.None},
}, 2, 4, 5, 6, 3)
assertEqual(fontStrings[1].color, nil, "content before the name remains native")

-- Typed anchors must not drift onto a later generic status line.
runPlayerFixture({
    {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
    {lineIndex = 2, type = unitLineType.None},
    {lineIndex = 3, type = unitLineType.UnitLevel},
    {lineIndex = 4, type = unitLineType.None},
    {lineIndex = 5, type = unitLineType.None},
    {lineIndex = 6, type = unitLineType.None},
}, 1, 3, 4, 5, 2)
assertEqual(fontStrings[6].color, nil, "trailing generic status remains native")

clearColors()
playerResult = true
postCall(gameTooltip, {
    lines = {
        {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
        {lineIndex = 2, type = unitLineType.None},
        {lineIndex = 3, type = unitLineType.UnitLevel},
        {lineIndex = 4, type = unitLineType.UnitType},
        {lineIndex = 5, type = unitLineType.UnitDead},
    },
})
assertColor(fontStrings[3], 1, 0.82, 0, "typed level before dead status")
assertColor(fontStrings[4], 0.1, 0.2, 0.3, "typed class before dead status")
assertEqual(fontStrings[5].color, nil, "typed dead status remains native")

clearColors()
playerResult = false
postCall(gameTooltip, {
    lines = {
        {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
        {lineIndex = 2, type = unitLineType.UnitLevel},
    },
})
assertColor(fontStrings[2], 1, 0.82, 0, "non-player level difficulty")
assertEqual(fontStrings[1].color, nil, "non-player name remains native")
assertEqual(statusBar.color, nil, "non-player status bar remains native")

local secretClassLines = {
    {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
    {lineIndex = 2, type = unitLineType.None},
    {lineIndex = 3, type = unitLineType.UnitLevel},
    {lineIndex = 4, type = unitLineType.UnitType},
    {lineIndex = 5, type = unitLineType.None},
}
clearColors()
playerResult = true
classFilename = "MAGE"
postCall(gameTooltip, {lines = secretClassLines})
assertColor(statusBar, 0.1, 0.2, 0.3, "public class before secret transition")

classFilename = secretValue
local priorClassColorCalls = classColorCalls
postCall(gameTooltip, {lines = secretClassLines})
assertEqual(classColorCalls, priorClassColorCalls, "secret class is not derived")
assertColor(fontStrings[1], 1, 1, 1, "secret class neutralizes player name")
assertColor(fontStrings[4], 1, 1, 1, "secret class neutralizes class line")
assertColor(statusBar, 1, 1, 1, "secret class neutralizes status bar")
assertColor(fontStrings[3], 1, 0.82, 0, "public level survives secret class")
assertColor(fontStrings[5], 0.4, 0.5, 0.6, "public faction survives secret class")
classFilename = "MAGE"

clearColors()
postCall(gameTooltip, {
    lines = {
        {lineIndex = 1, type = unitLineType.UnitName},
        {lineIndex = 2, type = unitLineType.UnitLevel},
    },
})
assertEqual(fontStrings[2].color, nil, "missing unit token fails closed")

postCall(gameTooltip, {
    lines = {
        {lineIndex = 1, type = unitLineType.UnitName, unitToken = secretValue},
        {lineIndex = 2, type = unitLineType.UnitLevel},
    },
})
assertEqual(fontStrings[2].color, nil, "secret unit token fails closed")

postCall(gameTooltip, {
    lines = {
        {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
        {lineIndex = 2, type = unitLineType.UnitName, unitToken = "party2"},
        {lineIndex = 3, type = unitLineType.UnitLevel},
    },
})
assertEqual(fontStrings[3].color, nil, "conflicting rendered units fail closed")

local typedPlayerLines = {
    {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
    {lineIndex = 2, type = unitLineType.None},
    {lineIndex = 3, type = unitLineType.UnitLevel},
    {lineIndex = 4, type = unitLineType.UnitType},
    {lineIndex = 5, type = unitLineType.None},
}

clearColors()
accessibleResult = false
postCall(gameTooltip, {lines = typedPlayerLines})
assertEqual(fontStrings[1].color, nil, "inaccessible tooltip fails closed")

accessibleResult = secretValue
postCall(gameTooltip, {lines = typedPlayerLines})
assertEqual(fontStrings[1].color, nil, "secret accessibility fails closed")
accessibleResult = true

local canBeAccessedInContext = gameTooltip.CanBeAccessedInContext
gameTooltip.CanBeAccessedInContext = nil
forbiddenResult = true
postCall(gameTooltip, {lines = typedPlayerLines})
assertEqual(fontStrings[1].color, nil, "legacy forbidden tooltip fails closed")

forbiddenResult = secretValue
postCall(gameTooltip, {lines = typedPlayerLines})
assertEqual(fontStrings[1].color, nil, "legacy secret forbidden result fails closed")
forbiddenResult = false
gameTooltip.CanBeAccessedInContext = canBeAccessedInContext

tooltipModule.config.mythicPlus.enabled = true
tooltipModule.config.itemLevel.enabled = true
tooltipModule.config.itemLevel.showOnAlt = false
postCall(gameTooltip, {lines = typedPlayerLines})
assertEqual(mythicPlusUnit, renderedUnit, "Mythic+ rendered unit token")
assertEqual(itemLevelUnit, renderedUnit, "item-level rendered unit token")

-- Simulate the 12.0.7 runtime, where the typed enum values are absent. The
-- generic level fallback must still reach the difficulty-color helper.
local getUnitTooltipLineInfo = findUpvalue(postCall, "GetUnitTooltipLineInfo")
assertEqual(type(getUnitTooltipLineInfo), "function", "unit line resolver upvalue")
assertEqual(setUpvalue(getUnitTooltipLineInfo, "UNIT_LEVEL_LINE", nil), true,
    "clear legacy UnitLevel enum")
assertEqual(setUpvalue(getUnitTooltipLineInfo, "UNIT_TYPE_LINE", nil), true,
    "clear legacy UnitType enum")
tooltipModule.config.mythicPlus.enabled = false
tooltipModule.config.itemLevel.enabled = false
clearColors()
postCall(gameTooltip, {lines = {
    {lineIndex = 1, type = unitLineType.UnitName, unitToken = renderedUnit},
    {lineIndex = 2, type = unitLineType.None},
    {lineIndex = 3, type = unitLineType.None},
    {lineIndex = 4, type = unitLineType.None},
}})
assertColor(fontStrings[2], 1, 0.82, 0, "12.0.7 generic level difficulty")

clearColors()
postCall(gameTooltip, {
    guid = renderedUnitGUID,
    lines = fourGenericPlayerLines,
})
assertColor(fontStrings[2], 0, 1, 0, "12.0.7 generic guild")
assertColor(fontStrings[3], 1, 0.82, 0, "12.0.7 guilded level difficulty")
assertColor(fontStrings[4], 0.1, 0.2, 0.3, "12.0.7 guilded class")
assertColor(fontStrings[5], 0.4, 0.5, 0.6, "12.0.7 guilded faction")
assertEqual(setUnitCalls, 0, "initial native pass does not rebuild the tooltip")

print("tooltip_unit_colors_test.lua: ok")
