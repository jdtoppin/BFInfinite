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

local registeredEvents = {}
local eventHandler
local eventFrame = {}

function eventFrame:RegisterEvent(event)
    registeredEvents[event] = true
end

function eventFrame:SetScript(script, handler)
    assertEqual(script, "OnEvent", "quest automation script")
    eventHandler = handler
end

local calls = {}
local shiftDown = false
local pvpQuest = false
local nativeAutoAccept = false
local adventureMapQuest = false
local areaTriggerQuest = false
local completable = false
local numChoices = 0
local payment = 0
local activeQuests = {}
local availableQuests = {}
local greetingActiveComplete = {}
local greetingAvailableCount = 0

local function CountCalls(name)
    local count = 0
    for _, call in ipairs(calls) do
        if call[1] == name then
            count = count + 1
        end
    end
    return count
end

local C_GossipInfo = {
    GetActiveQuests = function()
        return activeQuests
    end,
    GetAvailableQuests = function()
        return availableQuests
    end,
    SelectActiveQuest = function(questID)
        calls[#calls + 1] = {"GossipSelectActiveQuest", questID}
    end,
    SelectAvailableQuest = function(questID)
        calls[#calls + 1] = {"GossipSelectAvailableQuest", questID}
    end,
}

local config = {
    enabled = true,
    autoAcceptQuests = false,
    autoTurnInQuests = false,
}
local W = {
    config = {
        objectiveTracker = config,
    },
}
local BFI = {
    modules = {
        UIWidgets = W,
    },
}

local environment = {
    _G = false,
    AcknowledgeAutoAcceptQuest = function()
        calls[#calls + 1] = {"AcknowledgeAutoAcceptQuest"}
    end,
    AcceptQuest = function()
        calls[#calls + 1] = {"AcceptQuest"}
    end,
    C_GossipInfo = C_GossipInfo,
    CompleteQuest = function()
        calls[#calls + 1] = {"CompleteQuest"}
    end,
    CreateFrame = function(frameType)
        assertEqual(frameType, "Frame", "quest automation frame type")
        return eventFrame
    end,
    GetNumQuestChoices = function()
        return numChoices
    end,
    GetNumActiveQuests = function()
        return #greetingActiveComplete
    end,
    GetNumAvailableQuests = function()
        return greetingAvailableCount
    end,
    GetQuestMoneyToGet = function()
        return payment
    end,
    GetQuestReward = function(choiceIndex)
        calls[#calls + 1] = {"GetQuestReward", choiceIndex}
    end,
    IsQuestCompletable = function()
        return completable
    end,
    IsShiftKeyDown = function()
        return shiftDown
    end,
    GetActiveTitle = function(index)
        return "Quest " .. index, greetingActiveComplete[index]
    end,
    QuestFlagsPVP = function()
        return pvpQuest
    end,
    QuestGetAutoAccept = function()
        return nativeAutoAccept
    end,
    QuestIsFromAdventureMap = function()
        return adventureMapQuest
    end,
    QuestIsFromAreaTrigger = function()
        return areaTriggerQuest
    end,
    SelectActiveQuest = function(index)
        calls[#calls + 1] = {"SelectActiveQuest", index}
    end,
    SelectAvailableQuest = function(index)
        calls[#calls + 1] = {"SelectAvailableQuest", index}
    end,
    ipairs = ipairs,
    select = select,
    tostring = tostring,
    type = type,
}
environment._G = environment

local chunk, loadError = loadfile("Modules/UIWidgets/QuestAutomation.lua")
assertEqual(type(chunk), "function", loadError or "quest automation load")
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertEqual(type(eventHandler), "function", "quest automation event handler")
for _, event in ipairs({
    "GOSSIP_SHOW",
    "QUEST_GREETING",
    "QUEST_DETAIL",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
}) do
    assertTrue(registeredEvents[event], event .. " registration")
end
assertEqual(registeredEvents.QUEST_AUTOCOMPLETE, nil,
    "remote completion remains Blizzard-owned")

local function Emit(event, ...)
    eventHandler(eventFrame, event, ...)
end

Emit("QUEST_DETAIL")
Emit("QUEST_PROGRESS")
Emit("QUEST_COMPLETE")
Emit("GOSSIP_SHOW")
Emit("QUEST_GREETING")
assertEqual(#calls, 0, "quest automation defaults remain opt-in")

config.autoAcceptQuests = true
config.autoTurnInQuests = true
config.enabled = false
activeQuests = {{questID = 7, isComplete = true}}
availableQuests = {{questID = 8}}
Emit("GOSSIP_SHOW")
assertEqual(#calls, 0, "disabled Objective Tracker stops automation")

config.enabled = true
shiftDown = true
Emit("GOSSIP_SHOW")
Emit("QUEST_GREETING")
Emit("QUEST_DETAIL")
Emit("QUEST_PROGRESS")
Emit("QUEST_COMPLETE")
assertEqual(#calls, 0, "Shift pauses every automation path")
shiftDown = false

greetingActiveComplete = {false, true}
greetingAvailableCount = 1
Emit("QUEST_GREETING")
assertEqual(calls[#calls][1], "SelectActiveQuest",
    "completed legacy greeting quest is prioritized")
assertEqual(calls[#calls][2], 2, "completed greeting quest index")

greetingActiveComplete = {false}
greetingAvailableCount = 2
Emit("QUEST_GREETING")
assertEqual(calls[#calls][1], "SelectAvailableQuest",
    "legacy greeting selects an available quest")
assertEqual(calls[#calls][2], 1, "first available greeting quest index")

activeQuests = {
    {questID = 10, isComplete = false},
    {questID = 11, isComplete = true},
}
availableQuests = {{questID = 12}}
Emit("GOSSIP_SHOW")
assertEqual(calls[#calls][1], "GossipSelectActiveQuest",
    "completed quests are prioritized at gossip NPCs")
assertEqual(calls[#calls][2], 11, "completed gossip quest ID")
assertEqual(CountCalls("GossipSelectAvailableQuest"), 0,
    "one gossip event makes at most one selection")

activeQuests = {{questID = 13, isComplete = false}}
availableQuests = {
    {questID = 14, isIgnored = true},
    {questID = 15, isIgnored = false},
}
Emit("GOSSIP_SHOW")
assertEqual(calls[#calls][1], "GossipSelectAvailableQuest",
    "available quest selected after incomplete active quests")
assertEqual(calls[#calls][2], 15, "ignored quest offer is skipped")

Emit("QUEST_DETAIL")
assertEqual(CountCalls("AcceptQuest"), 1,
    "ordinary quest details are accepted")
Emit("QUEST_DETAIL", 9001)
assertEqual(CountCalls("AcceptQuest"), 1,
    "item-started quest offers retain Blizzard's popup")

pvpQuest = true
Emit("QUEST_DETAIL")
pvpQuest = false
nativeAutoAccept = true
Emit("QUEST_DETAIL")
assertEqual(CountCalls("AcknowledgeAutoAcceptQuest"), 1,
    "native non-area auto-accept quest is acknowledged")
areaTriggerQuest = true
Emit("QUEST_DETAIL")
areaTriggerQuest = false
nativeAutoAccept = false
adventureMapQuest = true
Emit("QUEST_DETAIL")
adventureMapQuest = false
assertEqual(CountCalls("AcceptQuest"), 1,
    "special quest acceptance flows remain manual or native")
assertEqual(CountCalls("AcknowledgeAutoAcceptQuest"), 1,
    "area-trigger auto-accept remains Blizzard-owned")

completable = false
Emit("QUEST_PROGRESS")
assertEqual(CountCalls("CompleteQuest"), 0,
    "incomplete quest is not advanced")
completable = true
Emit("QUEST_PROGRESS")
assertEqual(CountCalls("CompleteQuest"), 1,
    "complete quest advances to rewards")

payment = 0
numChoices = 0
Emit("QUEST_COMPLETE")
assertEqual(calls[#calls][1], "GetQuestReward",
    "no-choice quest is turned in")
assertEqual(calls[#calls][2], 0, "no-choice reward index")

numChoices = 1
Emit("QUEST_COMPLETE")
assertEqual(calls[#calls][2], 1, "single-choice reward index")
assertEqual(CountCalls("GetQuestReward"), 2,
    "single reward choice is selected automatically")

numChoices = 2
Emit("QUEST_COMPLETE")
assertEqual(CountCalls("GetQuestReward"), 2,
    "multiple reward choices remain manual")

numChoices = 0
payment = 100
Emit("QUEST_COMPLETE")
assertEqual(CountCalls("GetQuestReward"), 2,
    "quests requiring payment retain Blizzard confirmation")

payment = 0
config.autoTurnInQuests = false
completable = true
activeQuests = {{questID = 16, isComplete = true}}
availableQuests = {}
Emit("GOSSIP_SHOW")
Emit("QUEST_PROGRESS")
Emit("QUEST_COMPLETE")
assertEqual(CountCalls("GossipSelectActiveQuest"), 1,
    "auto-turn-in toggle controls gossip selection")
assertEqual(CountCalls("CompleteQuest"), 1,
    "auto-turn-in toggle controls quest progress")
assertEqual(CountCalls("GetQuestReward"), 2,
    "auto-turn-in toggle controls reward claims")

config.autoAcceptQuests = false
activeQuests = {}
availableQuests = {{questID = 17}}
greetingActiveComplete = {}
greetingAvailableCount = 1
Emit("GOSSIP_SHOW")
Emit("QUEST_GREETING")
Emit("QUEST_DETAIL")
assertEqual(CountCalls("GossipSelectAvailableQuest"), 1,
    "auto-accept toggle controls gossip selection")
assertEqual(CountCalls("AcceptQuest"), 1,
    "auto-accept toggle controls quest acceptance")

W.config = nil
Emit("GOSSIP_SHOW")
Emit("QUEST_GREETING")
Emit("QUEST_DETAIL")
Emit("QUEST_PROGRESS")
Emit("QUEST_COMPLETE")
assertEqual(CountCalls("AcceptQuest"), 1,
    "missing profile config fails closed")

print("quest_automation_test.lua: ok")
