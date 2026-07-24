---@type BFI
local BFI = select(2, ...)
local T = BFI.modules.Tooltip
local L = BFI.L
---@type AbstractFramework
local AF = _G.AbstractFramework

local GameTooltip = _G.GameTooltip
local GameTooltipStatusBar = _G.GameTooltipStatusBar
local DISABLED_FONT_COLOR = _G.DISABLED_FONT_COLOR
local HIGHLIGHT_FONT_COLOR = _G.HIGHLIGHT_FONT_COLOR
local InCombatLockdown = _G.InCombatLockdown
local IsShiftKeyDown = _G.IsShiftKeyDown
local NORMAL_FONT_COLOR = _G.NORMAL_FONT_COLOR

local NATIVE_STATUS_BAR_HEIGHT = 8
local MOUSEOVER_UNIT = "mouseover"
local DUNGEON_SCORE_LABEL = _G.DUNGEON_SCORE or L["Dungeon Score"]
local OVERTIME_LABEL = L["OT"]
local UNKNOWN_MAP_LABEL = _G.UNKNOWN

local cursorAnchors = {
    cursor = "ANCHOR_CURSOR",
    cursor_left = "ANCHOR_CURSOR_LEFT",
    cursor_right = "ANCHOR_CURSOR_RIGHT",
}

local oppositePoints = {
    TOP = "BOTTOM",
    TOPLEFT = "BOTTOMLEFT",
    TOPRIGHT = "BOTTOMRIGHT",
    BOTTOM = "TOP",
    BOTTOMLEFT = "TOPLEFT",
    BOTTOMRIGHT = "TOPRIGHT",
    LEFT = "RIGHT",
    RIGHT = "LEFT",
    CENTER = "CENTER",
}

local tooltipAnchor
local dungeonBests = {}

---------------------------------------------------------------------
-- anchor
---------------------------------------------------------------------
local function GetOwnerConfig(owner)
    if not owner then return end

    if type(owner.tooltip) == "table" then
        return owner.tooltip
    elseif type(owner.tooltipConfig) == "table" then
        return owner.tooltipConfig
    end
end

local function ApplyOwnerAnchor(tooltip, parent)
    local ownerConfig = GetOwnerConfig(parent)
    if not ownerConfig then return false end

    if ownerConfig.enabled == false or (ownerConfig.hideInCombat and InCombatLockdown()) then
        return true
    end

    local anchorTo = ownerConfig.anchorTo
    if anchorTo == "self_adaptive" then
        -- Keep placement inside the native anchor implementation. Reading the
        -- owner's screen geometry in Lua is not safe for restricted frames.
        tooltip:ClearAllPoints()
        tooltip:SetOwner(parent, "ANCHOR_TOP")
        return true
    elseif anchorTo == "self" then
        local position = ownerConfig.position
        if type(position) ~= "table" then return false end
        tooltip:ClearAllPoints()
        tooltip:SetPoint(position[1], parent, position[2], position[3], position[4])
        return true
    elseif anchorTo == "parent" then
        local position = ownerConfig.position
        if type(position) ~= "table" then return false end
        tooltip:ClearAllPoints()
        tooltip:SetPoint(position[1], parent:GetParent(), position[2], position[3], position[4])
        return true
    elseif anchorTo == "root" then
        local position = ownerConfig.position
        if type(position) ~= "table" or not parent.root then return false end
        tooltip:ClearAllPoints()
        tooltip:SetPoint(position[1], parent.root, position[2], position[3], position[4])
        return true
    end

    -- "default" and unknown values use the global BFI tooltip policy.
    return false
end

local function UpdateAnchor(tooltip, parent)
    if tooltip ~= GameTooltip or tooltip:IsForbidden() then return end

    if ApplyOwnerAnchor(tooltip, parent) then return end

    local config = T.config
    if not config or not config.enabled then return end

    parent = parent or AF.UIParent

    local mode = config.anchorMode
    if mode == "default" then
        return
    elseif mode == "fixed" then
        local point = oppositePoints[config.anchorPoint] and config.anchorPoint or "BOTTOMRIGHT"
        -- Native world-cursor tooltips may arrive with ANCHOR_CURSOR or a
        -- nameplate position. Reset the owner mode before applying the fixed
        -- BFI point so the native anchor cannot continue moving the tooltip.
        tooltip:SetOwner(parent, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint(point, tooltipAnchor, oppositePoints[point])
        return
    end

    local anchorType = cursorAnchors[mode]
    if not anchorType then return end

    tooltip:ClearAllPoints()
    if mode == "cursor" then
        -- ANCHOR_CURSOR intentionally ignores offsets.
        tooltip:SetOwner(parent, anchorType)
    else
        tooltip:SetOwner(parent, anchorType, config.cursorAnchor.x, config.cursorAnchor.y)
    end
end

---------------------------------------------------------------------
-- unit visibility
---------------------------------------------------------------------
local unitTooltipActive

local function OnUnitTooltipPreCall(tooltip)
    local config = T.config
    if tooltip ~= GameTooltip or tooltip:IsForbidden() or not config or not config.enabled then return end

    unitTooltipActive = true

    -- This callback never inspects tooltip data. Blizzard remains the sole
    -- renderer of unit identity, health, and other potentially secret values.
    if config.hideUnitTooltipsInCombat and InCombatLockdown() then
        tooltip:Hide()
        return true
    end
end

---------------------------------------------------------------------
-- Mythic+
---------------------------------------------------------------------
local function GetBestTimedRunLevel(runs)
    local bestRunLevel = 0

    for _, run in ipairs(runs) do
        if run.finishedSuccess and run.bestRunLevel > bestRunLevel then
            bestRunLevel = run.bestRunLevel
        end
    end

    return bestRunLevel
end

local function CollectDungeonBests(runs)
    wipe(dungeonBests)

    for _, run in ipairs(runs) do
        -- The remote summary exposes one score-bearing result per dungeon.
        -- Keep overtime results because they may hide a lower timed run.
        if run.bestRunLevel > 0 then
            local mapName = C_ChallengeMode.GetMapUIInfo(run.challengeModeID) or UNKNOWN_MAP_LABEL
            dungeonBests[#dungeonBests + 1] = {
                finishedSuccess = run.finishedSuccess,
                level = run.bestRunLevel,
                mapScore = run.mapScore,
                name = mapName,
            }
        end
    end

    table.sort(dungeonBests, function(a, b)
        if a.mapScore == b.mapScore then
            return a.name < b.name
        end
        return a.mapScore > b.mapScore
    end)
end

local function OnUnitTooltipPostCall(tooltip)
    local config = T.config
    local mythicPlus = config and config.mythicPlus
    if tooltip ~= GameTooltip
        or tooltip:IsForbidden()
        or not config
        or not config.enabled
        or not mythicPlus
        or not mythicPlus.enabled
        or (config.hideUnitTooltipsInCombat and InCombatLockdown())
    then
        return
    end

    -- Use the literal mouseover token throughout. Reading a displayed unit,
    -- name, GUID, or comparison result back into Lua is unnecessary. The
    -- native rating query returning a summary is the player classification.
    local rating = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(MOUSEOVER_UNIT)
    if not rating then return end

    local bestRunLevel = GetBestTimedRunLevel(rating.runs)
    if rating.currentSeasonScore <= 0 and bestRunLevel <= 0 then return end

    local scoreText = tostring(rating.currentSeasonScore)
    if mythicPlus.showBestRunLevel and bestRunLevel > 0 then
        scoreText = format("%s (+%d)", scoreText, bestRunLevel)
    end

    local scoreColor = C_ChallengeMode.GetDungeonScoreRarityColor(rating.currentSeasonScore)
        or HIGHLIGHT_FONT_COLOR
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(
        DUNGEON_SCORE_LABEL,
        scoreText,
        NORMAL_FONT_COLOR.r,
        NORMAL_FONT_COLOR.g,
        NORMAL_FONT_COLOR.b,
        scoreColor.r,
        scoreColor.g,
        scoreColor.b
    )

    if not mythicPlus.showTimedRunsOnShift or not IsShiftKeyDown() then return end

    CollectDungeonBests(rating.runs)
    if #dungeonBests == 0 then return end

    tooltip:AddLine(
        L["Mythic+ Dungeon Bests"],
        HIGHLIGHT_FONT_COLOR.r,
        HIGHLIGHT_FONT_COLOR.g,
        HIGHLIGHT_FONT_COLOR.b
    )
    for _, run in ipairs(dungeonBests) do
        local levelColor = run.finishedSuccess and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR
        local levelText = run.finishedSuccess
            and format("+%d", run.level)
            or format("+%d (%s)", run.level, OVERTIME_LABEL)
        tooltip:AddDoubleLine(
            run.name,
            levelText,
            HIGHLIGHT_FONT_COLOR.r,
            HIGHLIGHT_FONT_COLOR.g,
            HIGHLIGHT_FONT_COLOR.b,
            levelColor.r,
            levelColor.g,
            levelColor.b
        )
    end
end

local function RefreshActiveUnitTooltip()
    if unitTooltipActive and GameTooltip:IsShown() and not GameTooltip:IsForbidden() then
        -- SetUnit is a native secure delegate intended to rebuild standard
        -- tooltips for addon callers without exposing the displayed unit.
        GameTooltip:SetUnit(MOUSEOVER_UNIT)
    end
end

local function MODIFIER_STATE_CHANGED(_, _, key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end

    local config = T.config
    local mythicPlus = config and config.mythicPlus
    if config and config.enabled and mythicPlus and mythicPlus.enabled and mythicPlus.showTimedRunsOnShift then
        RefreshActiveUnitTooltip()
    end
end

local function CHALLENGE_MODE_MAPS_UPDATE()
    local config = T.config
    local mythicPlus = config and config.mythicPlus
    if config and config.enabled
        and mythicPlus and mythicPlus.enabled and mythicPlus.showTimedRunsOnShift
        and IsShiftKeyDown()
    then
        RefreshActiveUnitTooltip()
    end
end

local function ClearUnitTooltipState()
    unitTooltipActive = nil
end

local function OnTooltipShow(tooltip)
    if tooltip ~= GameTooltip or tooltip:IsForbidden() then return end

    local owner = tooltip:GetOwner()
    local ownerConfig = GetOwnerConfig(owner)
    if ownerConfig
        and (ownerConfig.enabled == false or (ownerConfig.hideInCombat and InCombatLockdown()))
    then
        tooltip:Hide()
    end
end

local function PLAYER_REGEN_DISABLED()
    if GameTooltip:IsForbidden() then return end

    local owner = GameTooltip:GetOwner()
    local ownerConfig = GetOwnerConfig(owner)
    local hideOwnerTooltip = ownerConfig and ownerConfig.hideInCombat
    local config = T.config
    local hideUnitTooltip = unitTooltipActive
        and config and config.enabled and config.hideUnitTooltipsInCombat

    if hideOwnerTooltip or hideUnitTooltip then
        GameTooltip:Hide()
    end
end

---------------------------------------------------------------------
-- setup
---------------------------------------------------------------------
local initialized
local function Initialize()
    if initialized then return end
    initialized = true

    tooltipAnchor = CreateFrame("Frame", "BFI_TooltipAnchor", AF.UIParent)
    AF.SetSize(tooltipAnchor, 150, 30)
    AF.CreateMover(tooltipAnchor, "BFI: " .. _G.OTHER, L["Tooltip"])

    hooksecurefunc("GameTooltip_SetDefaultAnchor", UpdateAnchor)
    hooksecurefunc(GameTooltip, "SetWorldCursor", function(tooltip, anchorType, parent)
        -- SetWorldCursor only delegates its Default mode through
        -- GameTooltip_SetDefaultAnchor. Cursor and Nameplate are positioned
        -- directly, so reapply the selected global policy after the native
        -- method completes. None is a leave-state update and must not move a
        -- GameTooltip that may already have another owner.
        if anchorType == Enum.WorldCursorAnchorType.Cursor
            or anchorType == Enum.WorldCursorAnchorType.Nameplate
        then
            UpdateAnchor(tooltip, parent)
        end
    end)
    GameTooltip:HookScript("OnShow", OnTooltipShow)
    GameTooltip:HookScript("OnHide", ClearUnitTooltipState)
    GameTooltip:HookScript("OnTooltipCleared", ClearUnitTooltipState)
    TooltipDataProcessor.AddTooltipPreCall(Enum.TooltipDataType.Unit, OnUnitTooltipPreCall)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltipPostCall)
    T:RegisterEvent("PLAYER_REGEN_DISABLED", PLAYER_REGEN_DISABLED)
    T:RegisterEvent("MODIFIER_STATE_CHANGED", MODIFIER_STATE_CHANGED)
    T:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", CHALLENGE_MODE_MAPS_UPDATE)
    C_MythicPlus.RequestMapInfo()
end

---------------------------------------------------------------------
-- update
---------------------------------------------------------------------
local function UpdateTooltip(_, module)
    if module and module ~= "tooltip" then return end

    Initialize()

    local config = T.config
    AF.UpdateMoverSave(tooltipAnchor, config.position)
    AF.LoadPosition(tooltipAnchor, config.position)
    tooltipAnchor.enabled = config.enabled and config.anchorMode == "fixed"
    if not tooltipAnchor.enabled then
        tooltipAnchor.mover:Hide()
    end

    if config.enabled then
        GameTooltipStatusBar:SetAlpha(config.healthBar.enabled and 1 or 0)
        AF.SetHeight(GameTooltipStatusBar, config.healthBar.height)
    else
        GameTooltipStatusBar:SetAlpha(1)
        AF.SetHeight(GameTooltipStatusBar, NATIVE_STATUS_BAR_HEIGHT)
    end
end
AF.RegisterCallback("BFI_UpdateModule", UpdateTooltip)
