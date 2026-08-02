---@type BFI
local BFI = select(2, ...)
---@class UIWidgets
local W = BFI.modules.UIWidgets

local C_GossipInfo = _G.C_GossipInfo

local function GetConfig()
    return W.config and W.config.objectiveTracker
end

local function AutomationIsPaused(config)
    return not config
        or config.enabled ~= true
        or _G.IsShiftKeyDown()
end

local function SelectGossipQuest(config)
    if not C_GossipInfo then return end

    if config.autoTurnInQuests == true then
        for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
            if quest.isComplete == true then
                C_GossipInfo.SelectActiveQuest(quest.questID)
                return
            end
        end
    end

    if config.autoAcceptQuests == true then
        for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
            if quest.isIgnored ~= true then
                C_GossipInfo.SelectAvailableQuest(quest.questID)
                return
            end
        end
    end
end

local function SelectGreetingQuest(config)
    if config.autoTurnInQuests == true then
        for index = 1, _G.GetNumActiveQuests() do
            local _, isComplete = _G.GetActiveTitle(index)
            if isComplete == true then
                _G.SelectActiveQuest(index)
                return
            end
        end
    end

    if config.autoAcceptQuests == true
        and _G.GetNumAvailableQuests() > 0
    then
        _G.SelectAvailableQuest(1)
    end
end

local function AcceptCurrentQuest(config, questStartItemID)
    if config.autoAcceptQuests ~= true
        or (questStartItemID and questStartItemID ~= 0)
        or _G.QuestFlagsPVP()
        or _G.QuestIsFromAdventureMap()
        or _G.QuestIsFromAreaTrigger()
    then
        return
    end

    if _G.QuestGetAutoAccept() then
        _G.AcknowledgeAutoAcceptQuest()
        return
    end

    _G.AcceptQuest()
end

local function AdvanceCurrentQuest(config)
    if config.autoTurnInQuests == true and _G.IsQuestCompletable() then
        _G.CompleteQuest()
    end
end

local function ClaimCurrentQuestReward(config)
    if config.autoTurnInQuests ~= true then return end

    local payment = _G.GetQuestMoneyToGet()
    if payment and payment > 0 then return end

    local numChoices = _G.GetNumQuestChoices()
    if numChoices == 0 or numChoices == 1 then
        _G.GetQuestReward(numChoices)
    end
end

local function OnEvent(_, event, ...)
    local config = GetConfig()
    if AutomationIsPaused(config) then return end

    if event == "GOSSIP_SHOW" then
        SelectGossipQuest(config)
    elseif event == "QUEST_GREETING" then
        SelectGreetingQuest(config)
    elseif event == "QUEST_DETAIL" then
        AcceptCurrentQuest(config, ...)
    elseif event == "QUEST_PROGRESS" then
        AdvanceCurrentQuest(config)
    elseif event == "QUEST_COMPLETE" then
        ClaimCurrentQuestReward(config)
    end
end

-- Retail PTR 12.1.0.68914, jdtoppin/wow-ui-source commit d3915c78:
-- Blizzard_UIPanels_Game/Mainline/QuestFrame.lua uses these same quest APIs;
-- Blizzard_APIDocumentationGenerated/GossipInfoDocumentation.lua exposes the
-- questID-backed gossip selectors. QUEST_AUTOCOMPLETE is deliberately left to
-- Blizzard's native popup so remote completion remains player-driven.
local eventFrame = _G.CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("QUEST_GREETING")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")
