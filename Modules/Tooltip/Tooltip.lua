---@type BFI
local BFI = select(2, ...)
local T = BFI.modules.Tooltip
local F = BFI.funcs
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
local GREEN_FONT_COLOR = _G.GREEN_FONT_COLOR
local IsAltKeyDown = _G.IsAltKeyDown
local HIGHLIGHT_FONT_COLOR = _G.HIGHLIGHT_FONT_COLOR
local InCombatLockdown = _G.InCombatLockdown
local IsPlayerInGuildFromGUID = _G.IsPlayerInGuildFromGUID
local IsShiftKeyDown = _G.IsShiftKeyDown
local NORMAL_FONT_COLOR = _G.NORMAL_FONT_COLOR
local UnitClassBase = _G.UnitClassBase
local UnitExists = _G.UnitExists
local UnitFactionGroup = _G.UnitFactionGroup
local UnitIsPVP = _G.UnitIsPVP
local UnitIsPlayer = _G.UnitIsPlayer

local NATIVE_STATUS_BAR_HEIGHT = 8
local NONE_LINE = Enum.TooltipDataLineType.None
local UNIT_NAME_LINE = Enum.TooltipDataLineType.UnitName
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

local function IsObjectAccessible(object)
    if not F.isValueNonSecret(object) then return false end
    if object == nil then return true end

    -- Retail 12.1.0.68914 adds CanBeAccessedInContext. Its result and the
    -- 12.0.7 IsForbidden fallback are ObjectSecurity-secret, so both must be
    -- sanitized before control flow or object access.
    local canBeAccessedInContext = object.CanBeAccessedInContext
    if canBeAccessedInContext then
        local accessible = canBeAccessedInContext(object)
        return F.isValueNonSecret(accessible) and accessible or false
    end

    local forbidden = object:IsForbidden()
    return F.isValueNonSecret(forbidden) and not forbidden or false
end

local function IsAccessibleGameTooltip(tooltip)
    if not F.isValueNonSecret(tooltip) or tooltip ~= GameTooltip then return false end
    return IsObjectAccessible(tooltip)
end

local function GetOwnerConfig(owner)
    if not IsObjectAccessible(owner) or owner == nil then return end

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
        local anchorParent = parent:GetParent()
        if not IsObjectAccessible(anchorParent) then return true end
        tooltip:ClearAllPoints()
        tooltip:SetPoint(position[1], anchorParent, position[2], position[3], position[4])
        return true
    elseif anchorTo == "root" then
        local position = ownerConfig.position
        if type(position) ~= "table" then return false end
        local root = parent.root
        if not IsObjectAccessible(root) then return true end
        if root == nil then return false end
        tooltip:ClearAllPoints()
        tooltip:SetPoint(position[1], root, position[2], position[3], position[4])
        return true
    end

    -- "default" and unknown values use the global BFI tooltip policy.
    return false
end

local function UpdateAnchor(tooltip, parent, resetCursorOwner)
    if not IsAccessibleGameTooltip(tooltip) then return end
    if not IsObjectAccessible(parent) then return end

    if ApplyOwnerAnchor(tooltip, parent) then return end

    local config = T.config
    if not config or not config.enabled then return end

    local mode = config.anchorMode
    if mode == "default" then
        return
    elseif mode == "fixed" then
        local point = oppositePoints[config.anchorPoint] and config.anchorPoint or "BOTTOMRIGHT"
        -- Preserve native Default/Nameplate ownership. Only Cursor needs its
        -- UIParent owner mode reset before applying a fixed BFI point.
        if resetCursorOwner then
            tooltip:SetOwner(AF.UIParent, "ANCHOR_NONE")
        end
        tooltip:ClearAllPoints()
        tooltip:SetPoint(point, tooltipAnchor, oppositePoints[point])
        return
    end

    local anchorType = cursorAnchors[mode]
    if not anchorType then return end

    parent = parent or AF.UIParent
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
local unitTooltipUnit

local function GetUnitTooltipLineInfo(data)
    if not data.lines then return end

    local unit
    local unitNameLineIndex
    local conflictingUnit
    local unitLevelLineIndex
    local unitTypeLineIndex
    local lineTypesByIndex = {}
    local noneLineIndices = {}

    for _, line in ipairs(data.lines) do
        local lineType = line.type
        local lineIndex = line.lineIndex
        if F.isValueNonSecret(lineType) and F.isValueNonSecret(lineIndex) and lineIndex then
            lineTypesByIndex[lineIndex] = lineType
            if lineType == UNIT_NAME_LINE then
                local lineUnit = line.unitToken
                if F.isValueNonSecret(lineUnit) and lineUnit ~= nil then
                    if unit == nil then
                        unit = lineUnit
                        unitNameLineIndex = lineIndex
                    elseif unit ~= lineUnit then
                        conflictingUnit = true
                    end
                end
            elseif UNIT_LEVEL_LINE and lineType == UNIT_LEVEL_LINE then
                unitLevelLineIndex = lineIndex
            elseif UNIT_TYPE_LINE and lineType == UNIT_TYPE_LINE then
                unitTypeLineIndex = lineIndex
            elseif lineType == NONE_LINE then
                noneLineIndices[#noneLineIndices + 1] = lineIndex
            end
        end
    end

    if conflictingUnit then
        unit = nil
        unitNameLineIndex = nil
    end

    return unit,
        unitNameLineIndex,
        unitLevelLineIndex,
        unitTypeLineIndex,
        lineTypesByIndex,
        noneLineIndices
end

local function GetTooltipPlayerGuildState(data)
    local guid = data.guid
    if not F.isValueNonSecret(guid) or type(guid) ~= "string" then return end

    -- Retail 12.0.7 and 12.1.0.68914 document this GUID query as returning
    -- an ordinary boolean. Sanitize it defensively before using it to resolve
    -- the otherwise ambiguous four/five-row generic player identity block.
    local isInGuild = IsPlayerInGuildFromGUID(guid)
    if F.isValueNonSecret(isInGuild) and type(isInGuild) == "boolean" then
        return isInGuild
    end
end

local function GetUnitPVPState(unit)
    -- Retail 12.1.0.68914 makes UnitIsPVP secret with restricted unit
    -- identity. Preserve public true and false as distinct layout facts and
    -- return nil for a secret or unavailable result.
    local isPVP = UnitIsPVP(unit)
    if F.isValueNonSecret(isPVP) and type(isPVP) == "boolean" then
        return isPVP
    end
end

local function GetPlayerIdentityLineIndices(
    unitNameLineIndex,
    unitLevelLineIndex,
    unitTypeLineIndex,
    lineTypesByIndex,
    noneLineIndices,
    playerInGuildState,
    unitPVPState
)
    local levelLineIndex = unitLevelLineIndex
    local classLineIndex = unitTypeLineIndex
    local factionLineIndex

    if unitTypeLineIndex then
        if not levelLineIndex and lineTypesByIndex[unitTypeLineIndex - 1] == NONE_LINE then
            levelLineIndex = unitTypeLineIndex - 1
        end
        if lineTypesByIndex[unitTypeLineIndex + 1] == NONE_LINE then
            factionLineIndex = unitTypeLineIndex + 1
        end
    elseif unitLevelLineIndex then
        if lineTypesByIndex[unitLevelLineIndex + 1] == NONE_LINE then
            classLineIndex = unitLevelLineIndex + 1
        end
        if classLineIndex and lineTypesByIndex[classLineIndex + 1] == NONE_LINE then
            factionLineIndex = classLineIndex + 1
        end
    else
        local count = #noneLineIndices
        local identityRowCount
        if count == 3 then
            identityRowCount = 3
        elseif count == 4 then
            if playerInGuildState == true and unitPVPState == false then
                identityRowCount = 4
            elseif playerInGuildState == false and unitPVPState == true then
                identityRowCount = 3
            end
        elseif count == 5
            and playerInGuildState == true
            and unitPVPState == true
        then
            identityRowCount = 4
        end

        local rowsAreContiguous = identityRowCount and unitNameLineIndex ~= nil
        if rowsAreContiguous then
            for index, lineIndex in ipairs(noneLineIndices) do
                if lineIndex ~= unitNameLineIndex + index then
                    rowsAreContiguous = false
                    break
                end
            end
        end

        if rowsAreContiguous then
            local guildOffset = identityRowCount == 4 and 1 or 0
            levelLineIndex = noneLineIndices[1 + guildOffset]
            classLineIndex = noneLineIndices[2 + guildOffset]
            factionLineIndex = noneLineIndices[3 + guildOffset]
        end
    end

    local guildLineIndex
    if unitNameLineIndex
        and levelLineIndex == unitNameLineIndex + 2
        and lineTypesByIndex[unitNameLineIndex + 1] == NONE_LINE
    then
        guildLineIndex = unitNameLineIndex + 1
    end

    -- Retail 12.1.0.68914 (wow-ui-source d3915c78) adds UnitLevel and UnitType
    -- enum values, but the native producer can still emit a generic identity
    -- block. Exact public guild and PvP state disambiguate the reported
    -- four/five-row variants; their trailing PvP status row remains native.
    return levelLineIndex, classLineIndex, factionLineIndex, guildLineIndex
end

local function ApplyPlayerIdentityColors(
    tooltip,
    unit,
    nameLineIndex,
    guildLineIndex,
    classLineIndex,
    factionLineIndex,
    config
)
    -- Retail 12.1 can hide unit identity. Project policy requires a neutral
    -- presentation when the class token is secret, so sanitize at the
    -- UnitClassBase boundary before deriving a class color.
    local color
    local classFilename = UnitClassBase(unit)
    if F.isValueNonSecret(classFilename) and classFilename then
        color = C_ClassColor_GetClassColor(classFilename)
    end

    -- Neutralize all class-derived presentation when identity is secret or
    -- unavailable so a previous unit's class color cannot survive the pass.
    color = color or HIGHLIGHT_FONT_COLOR
    local nameLine = nameLineIndex and tooltip:GetLeftLine(nameLineIndex)
    if nameLine then
        nameLine:SetTextColor(color.r, color.g, color.b)
    end

    if classLineIndex then
        local classLine = tooltip:GetLeftLine(classLineIndex)
        if classLine then
            classLine:SetTextColor(color.r, color.g, color.b)
        end
    end

    if config.healthBar.enabled and config.healthBar.colorMode == "class" then
        GameTooltipStatusBar:SetStatusBarColor(color.r, color.g, color.b)
    end

    -- A guild line is accepted only after the documented GUID query and the
    -- exact public name/guild/level topology agree, avoiding undocumented
    -- GetGuildInfo return behavior.
    if guildLineIndex then
        local guildLine = tooltip:GetLeftLine(guildLineIndex)
        if guildLine then
            guildLine:SetTextColor(GREEN_FONT_COLOR:GetRGB())
        end
    end

    -- UnitFactionGroup is documented as non-secret in both versions. Use
    -- Blizzard's standard PLAYER_FACTION_COLORS mapping.
    local factionColor = GetFactionColor(UnitFactionGroup(unit))
    if factionColor and factionLineIndex then
        local factionLine = tooltip:GetLeftLine(factionLineIndex)
        if factionLine then
            factionLine:SetTextColor(factionColor.r, factionColor.g, factionColor.b)
        end
    end
end

local function ApplyUnitLevelDifficultyColor(tooltip, unit, lineIndex)
    local config = T.config
    if not lineIndex
        or not config
        or not config.enabled
        or not config.levelDifficultyColor
        or not UnitExists(unit)
    then
        return
    end

    -- Retail 12.1.0.68914 TargetFrame (wow-ui-source d3915c78) uses this
    -- C-side classifier. Its returned enum is non-secret in 12.0.7 and 12.1.
    local difficulty = C_PlayerInfo_GetContentDifficultyCreatureForPlayer(unit)
    local color = GetDifficultyColor(difficulty)
    local levelLine = tooltip:GetLeftLine(lineIndex)
    if levelLine then
        levelLine:SetTextColor(color.r, color.g, color.b)
    end
end

local function OnUnitTooltipPreCall(tooltip)
    local config = T.config
    if not IsAccessibleGameTooltip(tooltip) or not config or not config.enabled then return end

    unitTooltipActive = true
    unitTooltipUnit = nil

    -- This callback never inspects tooltip data. Blizzard remains the sole
    -- renderer of unit identity, health, and other potentially secret values.
    if config.hideUnitTooltipsInCombat and InCombatLockdown() then
        tooltip:Hide()
        return true
    end
end

local function RefreshActiveUnitTooltip()
    local unit = unitTooltipUnit
    if not unitTooltipActive
        or not F.isValueNonSecret(unit)
        or unit == nil
        or not UnitExists(unit)
        or not IsAccessibleGameTooltip(GameTooltip)
    then
        return
    end

    local shown = GameTooltip:IsShown()
    if not F.isValueNonSecret(shown) or not shown then return end

    -- A public unit token can remap before a delayed refresh. Use it only as a
    -- best-effort native refresh handle, never as an identity comparison.
    GameTooltip:SetUnit(unit)
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

local function AddMythicPlus(tooltip, unit, mythicPlus, extrasAdded)
    if not mythicPlus or not mythicPlus.enabled then return extrasAdded end

    -- Query the same public token Blizzard attached to this rendered tooltip.
    -- The native rating query returning a summary is the player classification.
    local rating = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
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
local function AddItemLevel(tooltip, unit, itemLevel, extrasAdded)
    if not itemLevel or not itemLevel.enabled or (itemLevel.showOnAlt and not IsAltKeyDown()) then
        return extrasAdded
    end

    if not RequestItemLevel then return extrasAdded end

    -- AbstractFramework passes the rendered public token through Blizzard's
    -- native inspection APIs and returns only the documented non-secret item
    -- level. No unit GUID or equipment tooltip data enters BFI.
    local equippedItemLevel = RequestItemLevel(unit)
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
    if not IsAccessibleGameTooltip(tooltip)
        or not config
        or not config.enabled
        or (config.hideUnitTooltipsInCombat and InCombatLockdown())
    then
        return
    end

    -- Style the exact unit Blizzard rendered in this native tooltip pass.
    -- Rebuilding with GameTooltip:SetUnit("mouseover") is both unnecessary
    -- and unreliable in 12.1 restricted contexts.
    local unit,
        unitNameLineIndex,
        unitLevelLineIndex,
        unitTypeLineIndex,
        lineTypesByIndex,
        noneLineIndices = GetUnitTooltipLineInfo(data)
    if not unit or not UnitExists(unit) then return end
    unitTooltipUnit = unit

    local isPlayer = UnitIsPlayer(unit)
    if not F.isValueNonSecret(isPlayer) then return end

    local levelLineIndex = unitLevelLineIndex
    if isPlayer then
        local classLineIndex
        local factionLineIndex
        local guildLineIndex
        local playerInGuildState
        local unitPVPState
        local genericLineCount = #noneLineIndices
        if not unitLevelLineIndex
            and not unitTypeLineIndex
            and genericLineCount >= 4
            and genericLineCount <= 5
        then
            playerInGuildState = GetTooltipPlayerGuildState(data)
            unitPVPState = GetUnitPVPState(unit)
        end
        levelLineIndex,
            classLineIndex,
            factionLineIndex,
            guildLineIndex = GetPlayerIdentityLineIndices(
            unitNameLineIndex,
            unitLevelLineIndex,
            unitTypeLineIndex,
            lineTypesByIndex,
            noneLineIndices,
            playerInGuildState,
            unitPVPState
        )
        ApplyPlayerIdentityColors(
            tooltip,
            unit,
            unitNameLineIndex,
            guildLineIndex,
            classLineIndex,
            factionLineIndex,
            config
        )
    end

    ApplyUnitLevelDifficultyColor(tooltip, unit, levelLineIndex)

    local extrasAdded = AddMythicPlus(tooltip, unit, config.mythicPlus)
    AddItemLevel(tooltip, unit, config.itemLevel, extrasAdded)
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
    if not F.isValueNonSecret(unit) or unit ~= unitTooltipUnit then return end

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
    unitTooltipUnit = nil
end

local function OnTooltipShow(tooltip)
    if not IsAccessibleGameTooltip(tooltip) then return end

    local owner = tooltip:GetOwner()
    if not IsObjectAccessible(owner) then return end
    local ownerConfig = GetOwnerConfig(owner)
    if ownerConfig
        and (ownerConfig.enabled == false or (ownerConfig.hideInCombat and InCombatLockdown()))
    then
        tooltip:Hide()
    end
end

local function PLAYER_REGEN_DISABLED()
    if not IsAccessibleGameTooltip(GameTooltip) then return end

    local owner = GameTooltip:GetOwner()
    local ownerConfig
    if IsObjectAccessible(owner) then
        ownerConfig = GetOwnerConfig(owner)
    end
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
        if anchorType == Enum.WorldCursorAnchorType.Cursor then
            UpdateAnchor(tooltip, AF.UIParent, true)
        elseif anchorType == Enum.WorldCursorAnchorType.Nameplate then
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
