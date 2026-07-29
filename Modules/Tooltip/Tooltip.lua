---@type BFI
local BFI = select(2, ...)
local T = BFI.modules.Tooltip
local L = BFI.L
---@type AbstractFramework
local AF = _G.AbstractFramework

local GameTooltip = _G.GameTooltip
local GameTooltipStatusBar = _G.GameTooltipStatusBar
local C_ClassColor_GetClassColor = C_ClassColor.GetClassColor
local C_PlayerInfo_GetContentDifficultyCreatureForPlayer =
    C_PlayerInfo.GetContentDifficultyCreatureForPlayer
local DISABLED_FONT_COLOR = _G.DISABLED_FONT_COLOR
local GetDifficultyColor = _G.GetDifficultyColor
local GetFactionColor = _G.GetFactionColor
local GetGuildInfo = _G.GetGuildInfo
local GREEN_FONT_COLOR = _G.GREEN_FONT_COLOR
local IsAltKeyDown = _G.IsAltKeyDown
local HIGHLIGHT_FONT_COLOR = _G.HIGHLIGHT_FONT_COLOR
local InCombatLockdown = _G.InCombatLockdown
local IsShiftKeyDown = _G.IsShiftKeyDown
local NORMAL_FONT_COLOR = _G.NORMAL_FONT_COLOR
local UnitClassBase = _G.UnitClassBase
local UnitExists = _G.UnitExists
local UnitFactionGroup = _G.UnitFactionGroup
local UnitIsPlayer = _G.UnitIsPlayer

local NATIVE_STATUS_BAR_HEIGHT = 8
local MOUSEOVER_UNIT = "mouseover"
local NONE_LINE = Enum.TooltipDataLineType.None
local UNIT_LEVEL_LINE = Enum.TooltipDataLineType.UnitLevel
local UNIT_TYPE_LINE = Enum.TooltipDataLineType.UnitType
local DUNGEON_SCORE_LABEL = _G.DUNGEON_SCORE or L["Dungeon Score"]
local ITEM_LEVEL_LABEL = _G.STAT_AVERAGE_ITEM_LEVEL or _G.ITEM_LEVEL or L["Item Level"]
local OVERTIME_LABEL = L["OT"]
local UNKNOWN_MAP_LABEL = _G.UNKNOWN
local RequestItemLevel = AF.ItemLevel and AF.ItemLevel.Request

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
local unitTooltipRefreshQueued
local refreshingUnitTooltip

local function GetPlayerIdentityLineIndices(data)
    if not data.lines then return end

    local previousNoneLineIndex
    local lastNoneLineIndex
    local unitTypeLineIndex

    for _, line in ipairs(data.lines) do
        if UNIT_TYPE_LINE and line.type == UNIT_TYPE_LINE then
            unitTypeLineIndex = line.lineIndex
        elseif not UNIT_TYPE_LINE and line.type == NONE_LINE and line.lineIndex then
            previousNoneLineIndex = lastNoneLineIndex
            lastNoneLineIndex = line.lineIndex
        end
    end

    if unitTypeLineIndex then
        -- Retail 12.1 gives the class/specification line its own type. The
        -- faction line is the following native identity line.
        return unitTypeLineIndex, unitTypeLineIndex + 1
    end

    -- Retail 12.0.7 (Gethe/wow-ui-source 4383ced) does not give the
    -- specialization/class line its own type. In the native player identity
    -- block it is the penultimate generic line, immediately before faction.
    -- Retail 12.1 adds TooltipDataLineType.UnitType, handled above.
    return previousNoneLineIndex, lastNoneLineIndex
end

local function ApplyPlayerIdentityColors(tooltip, data, config)
    -- UnitIsPlayer remains non-secret in the generated 12.0.7 and 12.1 API
    -- contracts. UnitClassBase may return a secret in 12.1; pass that value
    -- directly through the C-level class-color API, then pass the resulting
    -- visual values directly to FontString:SetTextColor.
    if not UnitIsPlayer(MOUSEOVER_UNIT) then return end

    local color = C_ClassColor_GetClassColor(UnitClassBase(MOUSEOVER_UNIT))
    if not color then return end

    tooltip:GetLeftLine(1):SetTextColor(color.r, color.g, color.b)

    -- Player guilds occupy the second native unit-tooltip line. GetGuildInfo
    -- is used only to establish whether that line exists; its text remains
    -- entirely under Blizzard's control. The literal mouseover token is valid
    -- on both 12.0.7 and 12.1 (12.1 only rejects compound unit tokens).
    if GetGuildInfo(MOUSEOVER_UNIT) then
        tooltip:GetLeftLine(2):SetTextColor(GREEN_FONT_COLOR:GetRGB())
    end

    local classLineIndex, factionLineIndex = GetPlayerIdentityLineIndices(data)
    if classLineIndex then
        tooltip:GetLeftLine(classLineIndex):SetTextColor(color.r, color.g, color.b)
    end

    -- UnitFactionGroup is documented as non-secret in both versions. Use
    -- Blizzard's standard PLAYER_FACTION_COLORS mapping.
    local factionColor = GetFactionColor(UnitFactionGroup(MOUSEOVER_UNIT))
    if factionColor and factionLineIndex then
        tooltip:GetLeftLine(factionLineIndex):SetTextColor(
            factionColor.r,
            factionColor.g,
            factionColor.b
        )
    end

    -- StatusBar:SetStatusBarColor accepts secret visual values on both
    -- 12.0.7 and 12.1. Forward the C-side class color directly.
    if config.healthBar.enabled and config.healthBar.colorMode == "class" then
        GameTooltipStatusBar:SetStatusBarColor(color.r, color.g, color.b)
    end
end

local function ApplyUnitLevelDifficultyColor(tooltip, lineData)
    local config = T.config
    if tooltip ~= GameTooltip
        or tooltip:IsForbidden()
        or not config
        or not config.enabled
        or not config.levelDifficultyColor
        or not refreshingUnitTooltip
        or not UnitExists(MOUSEOVER_UNIT)
    then
        return
    end

    -- Blizzard explicitly recommends this C-side classifier instead of
    -- calculating relative difficulty from unit levels in Lua. Its returned
    -- enum is non-secret in both 12.0.7 and 12.1.
    local difficulty = C_PlayerInfo_GetContentDifficultyCreatureForPlayer(MOUSEOVER_UNIT)
    local color = GetDifficultyColor(difficulty)
    tooltip:GetLeftLine(lineData.lineIndex):SetTextColor(color.r, color.g, color.b)
end

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

local function RefreshActiveUnitTooltip()
    if unitTooltipActive
        and UnitExists(MOUSEOVER_UNIT)
        and GameTooltip:IsShown()
        and not GameTooltip:IsForbidden()
    then
        -- SetUnit is a native secure delegate intended to rebuild standard
        -- tooltips for addon callers without exposing the displayed unit.
        refreshingUnitTooltip = true
        GameTooltip:SetUnit(MOUSEOVER_UNIT)
        refreshingUnitTooltip = nil
    end
end

local function QueueInitialUnitTooltipRefresh()
    if refreshingUnitTooltip or unitTooltipRefreshQueued then return end

    unitTooltipRefreshQueued = true
    C_Timer.After(0, function()
        unitTooltipRefreshQueued = nil
        RefreshActiveUnitTooltip()
    end)
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

local function AddMythicPlus(tooltip, mythicPlus, extrasAdded)
    if not mythicPlus or not mythicPlus.enabled then return extrasAdded end

    -- Use the literal mouseover token throughout. Reading a displayed unit,
    -- name, GUID, or comparison result back into Lua is unnecessary. The
    -- native rating query returning a summary is the player classification.
    local rating = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(MOUSEOVER_UNIT)
    if not rating then return extrasAdded end

    local bestRunLevel = GetBestTimedRunLevel(rating.runs)
    if rating.currentSeasonScore <= 0 and bestRunLevel <= 0 then return extrasAdded end

    local scoreText = tostring(rating.currentSeasonScore)
    if mythicPlus.showBestRunLevel and bestRunLevel > 0 then
        scoreText = format("%s (+%d)", scoreText, bestRunLevel)
    end

    local scoreColor = C_ChallengeMode.GetDungeonScoreRarityColor(rating.currentSeasonScore)
        or HIGHLIGHT_FONT_COLOR
    if not extrasAdded then
        tooltip:AddLine(" ")
    end
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

    if not mythicPlus.showTimedRunsOnShift or not IsShiftKeyDown() then return true end

    CollectDungeonBests(rating.runs)
    if #dungeonBests == 0 then return true end

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
    return true
end

---------------------------------------------------------------------
-- item level
---------------------------------------------------------------------
local function AddItemLevel(tooltip, itemLevel, extrasAdded)
    if not itemLevel or not itemLevel.enabled or (itemLevel.showOnAlt and not IsAltKeyDown()) then
        return extrasAdded
    end

    if not RequestItemLevel then return extrasAdded end

    -- AbstractFramework passes this literal token through Blizzard's native
    -- inspection APIs and returns only the documented non-secret item level.
    -- No unit GUID or equipment tooltip data enters BFI.
    local equippedItemLevel = RequestItemLevel(MOUSEOVER_UNIT)
    if not equippedItemLevel then return extrasAdded end

    if not extrasAdded then
        tooltip:AddLine(" ")
    end
    tooltip:AddDoubleLine(
        ITEM_LEVEL_LABEL,
        format("%.1f", equippedItemLevel),
        NORMAL_FONT_COLOR.r,
        NORMAL_FONT_COLOR.g,
        NORMAL_FONT_COLOR.b,
        HIGHLIGHT_FONT_COLOR.r,
        HIGHLIGHT_FONT_COLOR.g,
        HIGHLIGHT_FONT_COLOR.b
    )
    return true
end

local function OnUnitTooltipPostCall(tooltip, data)
    local config = T.config
    if tooltip ~= GameTooltip
        or tooltip:IsForbidden()
        or not config
        or not config.enabled
        or (config.hideUnitTooltipsInCombat and InCombatLockdown())
    then
        return
    end

    -- Native unit tooltip processing reaches its post-call before Show().
    -- On the first world mouseover, the literal mouseover token may not yet
    -- describe the rendered unit. Leave that pass untouched and rebuild once
    -- on the next frame. The synchronous refresh guard prevents recursion and
    -- ensures identity colors are only derived from the settled token.
    if not refreshingUnitTooltip then
        QueueInitialUnitTooltipRefresh()
        return
    end

    ApplyPlayerIdentityColors(tooltip, data, config)

    local extrasAdded = AddMythicPlus(tooltip, config.mythicPlus)
    AddItemLevel(tooltip, config.itemLevel, extrasAdded)
end

local function MODIFIER_STATE_CHANGED(_, _, key)
    local config = T.config
    if not config or not config.enabled then return end

    local mythicPlus = config and config.mythicPlus
    local itemLevel = config and config.itemLevel
    local refreshMythicPlus = (key == "LSHIFT" or key == "RSHIFT")
        and mythicPlus and mythicPlus.enabled and mythicPlus.showTimedRunsOnShift
    local refreshItemLevel = (key == "LALT" or key == "RALT")
        and itemLevel and itemLevel.enabled and itemLevel.showOnAlt

    if refreshMythicPlus or refreshItemLevel then
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

local function AF_UNIT_ITEM_LEVEL_READY(_, unit)
    if unit ~= MOUSEOVER_UNIT then return end

    local config = T.config
    local itemLevel = config and config.itemLevel
    if config and config.enabled
        and itemLevel and itemLevel.enabled
        and (not itemLevel.showOnAlt or IsAltKeyDown())
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
    if UNIT_LEVEL_LINE then
        TooltipDataProcessor.AddLinePostCall(UNIT_LEVEL_LINE, ApplyUnitLevelDifficultyColor)
    end
    T:RegisterEvent("PLAYER_REGEN_DISABLED", PLAYER_REGEN_DISABLED)
    T:RegisterEvent("MODIFIER_STATE_CHANGED", MODIFIER_STATE_CHANGED)
    T:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", CHALLENGE_MODE_MAPS_UPDATE)
    AF.RegisterCallback("AF_UNIT_ITEM_LEVEL_READY", AF_UNIT_ITEM_LEVEL_READY)
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
    BFI.funcs.LoadPosition(tooltipAnchor, config.position)
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

    RefreshActiveUnitTooltip()
end
AF.RegisterCallback("BFI_UpdateModule", UpdateTooltip)
