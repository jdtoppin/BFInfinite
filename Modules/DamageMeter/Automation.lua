---@type BFI
local BFI = select(2, ...)
---@class DamageMeter
local DM = BFI.modules.DamageMeter

DM.Automation = DM.Automation or {}
local Automation = DM.Automation

local MAX_WINDOWS = 3
local eventFrame
local active

local function GetConfig()
    return DM.config
end

local function GetWindowSession(index)
    local renderer = DM.Renderer
    if renderer and type(renderer.GetWindowSession) == "function" then
        return renderer.GetWindowSession(index)
    end

    local config = GetConfig()
    local selection = config.windowSessions[index]
    return type(selection) == "table" and selection.mode or "current"
end

local function SetWindowSession(index, mode)
    local renderer = DM.Renderer
    if renderer and type(renderer.SetWindowSession) == "function" then
        return renderer.SetWindowSession(index, mode, nil, {
            refresh = false,
            sync = false,
        })
    end

    local config = GetConfig()
    config.windowSessions = config.windowSessions or {}
    config.windowSessions[index] = {mode = mode}
    return true
end

local function SetWindowType(index, typeName)
    local renderer = DM.Renderer
    if renderer and type(renderer.SetWindowType) == "function" then
        return renderer.SetWindowType(index, typeName, {
            refresh = false,
        })
    end

    local config = GetConfig()
    config.windowTypes[index] = typeName
    return true
end

local function RefreshRenderer(layoutChanged)
    local renderer = DM.Renderer
    if not renderer then return end

    if layoutChanged and type(renderer.ApplySettings) == "function" then
        renderer.ApplySettings()
    elseif type(renderer.Refresh) == "function" then
        renderer.Refresh()
    end
end

local function ReturnHistoricalWindowsToCurrent()
    local config = GetConfig()
    local changed

    for index = 1, MAX_WINDOWS do
        local mode = GetWindowSession(index)
        if config.windowAutoCurrentOnCombat[index]
            and mode == "history"
        then
            changed = SetWindowSession(index, "current") or changed
        end
    end

    if changed then
        RefreshRenderer(false)
    end
end

local function HandleMythicPlusStart()
    local config = GetConfig()
    local changed
    local layoutChanged

    if config.resetOnMythicPlusStart then
        DM.Data.Reset()
    end

    for index = 1, MAX_WINDOWS do
        if config.windowAutoCurrentOnMythicPlusStart[index] then
            changed = SetWindowSession(index, "current") or changed
        end

        local typeName = config.mythicPlusWindowTypes[index]
        if typeName then
            local typeChanged = SetWindowType(index, typeName)
            changed = typeChanged or changed
            layoutChanged = typeChanged or layoutChanged
        end
    end

    if changed then
        RefreshRenderer(layoutChanged)
    end
end

local function HandleMythicPlusComplete()
    local config = GetConfig()
    local changed

    for index = 1, MAX_WINDOWS do
        if config.windowAutoOverallOnMythicPlusComplete[index] then
            changed = SetWindowSession(index, "overall") or changed
        end
    end

    if changed then
        RefreshRenderer(false)
    end
end

local function OnEvent(_, event)
    if not active then return end

    if event == "PLAYER_REGEN_DISABLED" then
        ReturnHistoricalWindowsToCurrent()
    elseif event == "CHALLENGE_MODE_START" then
        HandleMythicPlusStart()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        HandleMythicPlusComplete()
    end
end

local function EnsureEventFrame()
    if eventFrame then return end

    eventFrame = _G.CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
end

function Automation.SetEnabled(enabled)
    EnsureEventFrame()
    active = enabled == true

    eventFrame:UnregisterAllEvents()
    if not active then return end

    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
end

function Automation.IsEnabled()
    return active == true
end
