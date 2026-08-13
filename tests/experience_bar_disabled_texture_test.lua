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

local callback
local innerBar = {}

local function newTexture()
    return {
        Hide = function(self)
            self.visible = false
        end,
        Show = function(self)
            self.visible = true
        end,
        SetAllPoints = function(self, target)
            self.anchor = target
        end,
        SetHorizTile = function() end,
        SetTexture = function() end,
        SetVertexColor = function() end,
        SetVertTile = function() end,
    }
end

local experienceBar = {
    innerBar = innerBar,
    unfill = {
        Hide = function() end,
    },
    CreateFontString = function()
        return {}
    end,
    CreateTexture = function()
        return newTexture()
    end,
    Hide = function() end,
    GetBarWidth = function()
        return 100
    end,
    SetBarValue = function() end,
    SetMinMaxValues = function() end,
    SetScript = function() end,
}

local AF = {
    UIParent = {},
    AddEventHandler = function() end,
    CreateMover = function() end,
    CreateSimpleStatusBar = function()
        return experienceBar
    end,
    GetColorRGB = function()
        return 1, 1, 1, 1
    end,
    GetTexture = function()
        return "stripe"
    end,
    RegisterCallback = function(_, registeredCallback)
        callback = registeredCallback
    end,
}

local xpDisabled = false
local environment = {
    _G = false,
    AbstractFramework = AF,
    BreakUpLargeNumbers = function() end,
    C_QuestLog = {
        GetNumQuestLogEntries = function() end,
        GetQuestIDForLogIndex = function() end,
        IsComplete = function() end,
        ReadyForTurnIn = function() end,
    },
    CreateFrame = function()
        return {
            CreateFontString = function()
                return {}
            end,
            SetAllPoints = function() end,
        }
    end,
    GetXPExhaustion = function()
        return 0
    end,
    IsXPUserDisabled = function()
        return xpDisabled
    end,
    UnitXP = function()
        return 20
    end,
    UnitXPMax = function()
        return 100
    end,
    debug = debug,
    select = select,
    string = string,
    type = type,
}
setmetatable(environment, {__index = _G})
environment._G = environment

local BFI = {
    L = {
        ["Data Bars"] = "Data Bars",
        ["Experience Bar"] = "Experience Bar",
    },
    funcs = {},
    modules = {
        DataBars = {},
    },
}

local chunk, loadError = loadfile("Modules/DataBars/ExperienceBar.lua")
assertEqual(type(chunk), "function", loadError or "module load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(callback), "function", "module callback")
local createExperienceBar = findUpvalue(callback, "CreateExperienceBar")
assertEqual(type(createExperienceBar), "function", "experience bar creator upvalue")
local updateAll = findUpvalue(callback, "UpdateAll")
assertEqual(type(updateAll), "function", "experience bar update upvalue")
local updateXP = findUpvalue(updateAll, "UpdateXP")
assertEqual(type(updateXP), "function", "XP update upvalue")
createExperienceBar()

local disabledTexture = experienceBar.disabledTexture
assertEqual(disabledTexture.anchor, innerBar, "disabled texture anchor")
assertEqual(disabledTexture.visible, false, "disabled texture initial visibility")

xpDisabled = true
updateXP(experienceBar)
assertEqual(disabledTexture.visible, true, "XP-locked texture visibility")

xpDisabled = false
updateXP(experienceBar)
assertEqual(disabledTexture.visible, false, "XP-enabled texture visibility")

print("experience_bar_disabled_texture_test.lua: ok")
