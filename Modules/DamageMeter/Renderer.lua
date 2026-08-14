---@type BFI
local BFI = select(2, ...)
local F = BFI.funcs
local L = BFI.L
---@class DamageMeter
local DM = BFI.modules.DamageMeter
---@type AbstractFramework
local AF = _G.AbstractFramework

DM.Renderer = DM.Renderer or {}
local Renderer = DM.Renderer

-- API evidence: Retail PTR 12.1.0.68914, Gethe/wow-ui-source commit
-- d3915c78aba77a7a9be76acbfa35c674bbb6abe9,
-- Interface/AddOns/Blizzard_APIDocumentationGenerated/
-- DamageMeterDocumentation.lua, DamageMeterConstantsDocumentation.lua,
-- SimpleStatusBarAPIDocumentation.lua, SimpleFontStringAPIDocumentation.lua,
-- LocalizationDocumentation.lua, and PlayerScriptDocumentation.lua; type
-- presentation is also mirrored from Interface/AddOns/Blizzard_DamageMeter/
-- DamageMeterSessionWindow.lua and DamageMeterEntry.lua.
--
-- C_DamageMeter results can contain secret names and amounts in combat. This
-- renderer never hooks Blizzard_DamageMeter or retains those results. It
-- preserves the API order and passes secret payloads directly to the same
-- C-level sinks used by FrameXML: Ambiguate, AbbreviateNumbers through
-- AF.FormatSecretNumber, FontString:SetText, and StatusBar value methods.

local MAX_WINDOWS = 3
local WINDOW_INSET = 4
local WINDOW_GAP = 4
local OBJECTIVE_TRACKER_GAP = 8
local REFRESH_DELAY = 0.1
local NATIVE_RESTORE_KEY = "damageMeterNativeEnabledBeforeBFI"
local MIN_WINDOW_WIDTH = 220
local MAX_WINDOW_WIDTH = 520
local MIN_WINDOW_HEIGHT = 84
local MAX_WINDOW_HEIGHT = 520
local DEFAULT_SESSION_KEY = "current"
local SESSION_MODE_CURRENT = "current"
local SESSION_MODE_OVERALL = "overall"
local SESSION_MODE_HISTORY = "history"
local SESSION_DROPDOWN_WIDTH = 120
local MIN_SESSION_DROPDOWN_WIDTH = 60
local MIN_TYPE_DROPDOWN_WIDTH = 60
local TYPE_DEFINITIONS = {
    DamageDone = {
        title = _G.DAMAGE_METER_TYPE_DAMAGE_DONE or _G.DAMAGE or "Damage",
        enumName = "DamageDone",
        alwaysShowLocalPlayer = true,
    },
    Dps = {
        title = _G.DAMAGE_METER_TYPE_DPS or _G.DPS or "DPS",
        enumName = "Dps",
        alwaysShowLocalPlayer = true,
        valuePerSecondAsPrimary = true,
    },
    HealingDone = {
        title = _G.DAMAGE_METER_TYPE_HEALING_DONE
            or _G.HEALING
            or "Healing",
        enumName = "HealingDone",
        alwaysShowLocalPlayer = true,
    },
    Hps = {
        title = _G.DAMAGE_METER_TYPE_HPS or _G.HPS or "HPS",
        enumName = "Hps",
        alwaysShowLocalPlayer = true,
        valuePerSecondAsPrimary = true,
    },
    Absorbs = {
        title = _G.DAMAGE_METER_TYPE_ABSORBS or "Absorbs",
        enumName = "Absorbs",
        alwaysShowLocalPlayer = true,
    },
    Interrupts = {
        title = _G.DAMAGE_METER_TYPE_INTERRUPTS or "Interrupts",
        enumName = "Interrupts",
        alwaysShowLocalPlayer = true,
        suppressValuePerSecond = true,
    },
    Dispels = {
        title = _G.DAMAGE_METER_TYPE_DISPELS or "Dispels",
        enumName = "Dispels",
        alwaysShowLocalPlayer = true,
        suppressValuePerSecond = true,
    },
    DamageTaken = {
        title = _G.DAMAGE_METER_TYPE_DAMAGE_TAKEN
            or _G.DAMAGE_TAKEN
            or "Damage Taken",
        enumName = "DamageTaken",
        alwaysShowLocalPlayer = true,
    },
    AvoidableDamageTaken = {
        title = _G.DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN
            or "Avoidable Damage",
        enumName = "AvoidableDamageTaken",
        alwaysShowLocalPlayer = true,
    },
    Deaths = {
        title = _G.DAMAGE_METER_TYPE_DEATHS or _G.DEATHS or "Deaths",
        enumName = "Deaths",
        suppressValuePerSecond = true,
    },
    EnemyDamageTaken = {
        title = _G.DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN
            or "Enemy Damage Taken",
        enumName = "EnemyDamageTaken",
        suppressIcon = true,
    },
}

local TYPE_ORDER = {
    "DamageDone",
    "Dps",
    "DamageTaken",
    "AvoidableDamageTaken",
    "EnemyDamageTaken",
    "HealingDone",
    "Hps",
    "Absorbs",
    "Interrupts",
    "Dispels",
    "Deaths",
}

local DEFAULT_WINDOW_TYPES = {
    "DamageDone",
    "HealingDone",
    "DamageTaken",
}

local VALID_ANCHOR_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local windows = {}
local rendererEnabled
local eventFrame
local refreshTimer
local nativeOverrideActive
local nativeRestoreEnabled
local resetPositionPending
local activeDockTarget
local activeDockDirection
local lastObjectiveTrackerLaneBudget
local lastObjectiveTrackerLaneTarget
local ScrollWindow
local ScrollWindowDetails
local OpenWindowDetails
local CloseWindowDetails
local RefreshWindowDetails
local sessionItems = {}
local sessionSelections = {}
local sessionItemsDirty = true
local runtimeHistoricalSessionIDs = {}

local function GetConfig()
    return DM.config
end

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function GetMinimumWindowHeight(config)
    local function GetDimension(key, default)
        local value = config[key]
        if type(value) ~= "number" or value ~= value then
            return default
        end
        return value
    end

    return math.max(
        MIN_WINDOW_HEIGHT,
        GetDimension("headerHeight", 20)
            + (GetDimension("padding", 3) * 2)
            + GetDimension("barHeight", 18)
    )
end

local function GetDefaultAnchor(index)
    if index == 1 then
        return {
            relativeTo = 0,
            point = "TOPRIGHT",
            relativePoint = "TOPRIGHT",
            x = -WINDOW_INSET,
            y = -WINDOW_INSET,
        }
    end

    return {
        relativeTo = index - 1,
        point = "TOPRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = 0,
        y = -WINDOW_GAP,
    }
end

local function GetFallbackAnchor()
    return {
        relativeTo = 0,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
end

local function IsDefaultAnchor(anchor, index)
    local default = GetDefaultAnchor(index)
    return anchor.relativeTo == default.relativeTo
        and anchor.point == default.point
        and anchor.relativePoint == default.relativePoint
        and anchor.x == default.x
        and anchor.y == default.y
end

local function IsDefaultRootAnchor(anchor)
    return IsDefaultAnchor(anchor, 1)
end

local function SetAnchorRecord(config, index, anchor)
    if type(config.windowAnchors) ~= "table" then
        config.windowAnchors = {}
    end

    config.windowAnchors[index] = {
        relativeTo = anchor.relativeTo,
        point = anchor.point,
        relativePoint = anchor.relativePoint,
        x = anchor.x,
        y = anchor.y,
    }
end

local function EnsureInteractionConfig(config)
    if type(config.locked) ~= "boolean" then
        config.locked = false
    end
    if type(config.dockToObjectiveTracker) ~= "boolean" then
        config.dockToObjectiveTracker = false
    end
    if type(config.windowHeights) ~= "table" then
        config.windowHeights = {}
    end
    for index = 1, MAX_WINDOWS do
        if type(config.windowHeights[index]) ~= "number" then
            config.windowHeights[index] = config.height or 220
        end
    end

    if type(config.windowAnchors) ~= "table" then
        config.windowAnchors = {}
    end
    for index = 1, MAX_WINDOWS do
        if type(config.windowAnchors[index]) ~= "table" then
            SetAnchorRecord(config, index, GetDefaultAnchor(index))
        end
    end
end

local function GetWindowHeight(config, index)
    EnsureInteractionConfig(config)
    return Clamp(
        config.windowHeights[index],
        GetMinimumWindowHeight(config),
        MAX_WINDOW_HEIGHT
    )
end

local function GetWindowDefinition(index)
    local config = GetConfig()
    local typeName = config.windowTypes[index]
    return TYPE_DEFINITIONS[typeName]
        or TYPE_DEFINITIONS[DEFAULT_WINDOW_TYPES[index]]
end

local function GetTypeItems()
    local items = {}
    for index, typeName in ipairs(TYPE_ORDER) do
        items[index] = {
            text = TYPE_DEFINITIONS[typeName].title,
            value = typeName,
        }
    end
    return items
end

local function GetMeterType(definition)
    local enums = _G.Enum
    local meterTypes = enums and enums.DamageMeterType
    if not meterTypes then return end

    return meterTypes[definition.enumName]
end

local function GetSessionKey(mode, sessionID)
    if mode == SESSION_MODE_HISTORY then
        return SESSION_MODE_HISTORY .. ":" .. sessionID
    end
    return mode
end

local function GetWindowSessionSelection(config, index)
    local runtimeSessionID = runtimeHistoricalSessionIDs[index]
    if type(runtimeSessionID) == "number" and runtimeSessionID > 0 then
        return SESSION_MODE_HISTORY, runtimeSessionID
    end

    local selections = config.windowSessions
    local selection = type(selections) == "table" and selections[index]
        or nil
    local mode = type(selection) == "table" and selection.mode or nil

    if mode == SESSION_MODE_OVERALL then
        return mode
    end
    return SESSION_MODE_CURRENT
end

local function SetWindowSessionState(config, index, mode, sessionID)
    if mode == SESSION_MODE_HISTORY then
        runtimeHistoricalSessionIDs[index] = sessionID
        return
    end

    runtimeHistoricalSessionIDs[index] = nil
    config.windowSessions = config.windowSessions or {}
    config.windowSessions[index] = {
        mode = mode,
    }
end

local function ClearRuntimeHistoricalSession(index)
    local sessionID = runtimeHistoricalSessionIDs[index]
    runtimeHistoricalSessionIDs[index] = nil
    if not sessionID or not windows[index] then return end

    local key = GetSessionKey(SESSION_MODE_HISTORY, sessionID)
    windows[index].scrollOffsets[key] = nil
    windows[index].maxScrollOffsets[key] = nil
end

local function GetSessionData(mode, sessionID, meterType)
    if mode == SESSION_MODE_OVERALL then
        return DM.Data.GetOverallSession(meterType)
    end
    if mode == SESSION_MODE_HISTORY then
        return DM.Data.GetHistoricalSession(sessionID, meterType)
    end
    return DM.Data.GetCurrentSession(meterType)
end

local function FormatSessionDuration(durationSeconds)
    if type(_G.SecondsToClock) == "function" then
        return _G.SecondsToClock(durationSeconds)
    end

    local seconds = math.max(0, math.floor(durationSeconds))
    return ("%d:%02d"):format(
        math.floor(seconds / 60),
        seconds % 60
    )
end

local function BuildSessionItems()
    local items = {
        {
            text = _G.DAMAGE_METER_CURRENT_SESSION or L["Current"],
            value = SESSION_MODE_CURRENT,
        },
        {
            text = _G.DAMAGE_METER_OVERALL_SESSION or L["Overall"],
            value = SESSION_MODE_OVERALL,
        },
    }
    local selections = {
        [SESSION_MODE_CURRENT] = {
            mode = SESSION_MODE_CURRENT,
        },
        [SESSION_MODE_OVERALL] = {
            mode = SESSION_MODE_OVERALL,
        },
    }
    local available = DM.Data.GetAvailableSessions()

    -- DamageMeterAvailableCombatSession fields are ordinary metadata in
    -- Retail PTR 12.1.0.68914. Only these session IDs, labels, and durations
    -- are formatted or retained; combat source payloads remain opaque.
    if type(available) == "table" then
        for _, availableSession in ipairs(available) do
            local sessionID = availableSession.sessionID
            local key = GetSessionKey(SESSION_MODE_HISTORY, sessionID)
            local text = availableSession.name
            if not text or text == "" then
                local pattern = _G.DAMAGE_METER_COMBAT_NUMBER or "Combat %d"
                text = pattern:format(sessionID)
            end
            if availableSession.durationSeconds then
                text = ("%s [%s]"):format(
                    text,
                    FormatSessionDuration(
                        availableSession.durationSeconds
                    )
                )
            end

            items[#items + 1] = {
                text = text,
                value = key,
            }
            selections[key] = {
                mode = SESSION_MODE_HISTORY,
                sessionID = sessionID,
            }
        end
    end

    for _, window in ipairs(windows) do
        for key in pairs(window.scrollOffsets) do
            if key ~= SESSION_MODE_CURRENT
                and key ~= SESSION_MODE_OVERALL
                and not selections[key]
            then
                window.scrollOffsets[key] = nil
            end
        end
        for key in pairs(window.maxScrollOffsets) do
            if key ~= SESSION_MODE_CURRENT
                and key ~= SESSION_MODE_OVERALL
                and not selections[key]
            then
                window.maxScrollOffsets[key] = nil
            end
        end
    end

    sessionItems = items
    sessionSelections = selections
    sessionItemsDirty = nil
end

local function EnsureSessionItems()
    if sessionItemsDirty then
        BuildSessionItems()
    end
end

local function ValidateHistoricalSelections(config)
    EnsureSessionItems()
    for index = 1, MAX_WINDOWS do
        local mode, sessionID = GetWindowSessionSelection(config, index)
        if mode == SESSION_MODE_HISTORY
            and not sessionSelections[GetSessionKey(mode, sessionID)]
        then
            ClearRuntimeHistoricalSession(index)
        end
    end
end

local function RefreshSessionDropdownItems()
    sessionItemsDirty = true
    local config = GetConfig()
    ValidateHistoricalSelections(config)
    for _, window in ipairs(windows) do
        local mode, sessionID =
            GetWindowSessionSelection(config, window.index)
        window.sessionKey = GetSessionKey(mode, sessionID)
        window.sessionDropdown:SetItems(sessionItems)
        window.sessionDropdown:SetSelectedValue(window.sessionKey)
    end
    if rendererEnabled then
        Renderer.Refresh()
    end
end

local function ResetHistoricalSelections()
    local config = GetConfig()
    for index = 1, MAX_WINDOWS do
        local mode = GetWindowSessionSelection(config, index)
        if mode == SESSION_MODE_HISTORY then
            ClearRuntimeHistoricalSession(index)
        end
    end
end

local function GetScrollBucket(storage, window)
    local sessionKey = window.sessionKey or DEFAULT_SESSION_KEY
    local bucket = storage[sessionKey]
    if not bucket then
        bucket = {}
        storage[sessionKey] = bucket
    end
    return bucket
end

local function GetScrollOffset(window, typeName)
    return GetScrollBucket(window.scrollOffsets, window)[typeName] or 0
end

local function SetScrollOffset(window, typeName, offset)
    GetScrollBucket(window.scrollOffsets, window)[typeName] = offset
end

local function GetMaximumScrollOffset(window, typeName)
    return GetScrollBucket(window.maxScrollOffsets, window)[typeName] or 0
end

local function SetMaximumScrollOffset(window, typeName, offset)
    GetScrollBucket(window.maxScrollOffsets, window)[typeName] = offset
end

local function ResetWindowScrollOffset(window, typeName)
    SetScrollOffset(window, typeName, 0)
    SetMaximumScrollOffset(window, typeName, 0)
end

local function GetNativeOverrideState()
    if type(_G.BFICVarBackup) ~= "table" then
        _G.BFICVarBackup = {}
    end
    return _G.BFICVarBackup
end

local function BeginNativeOverride()
    if nativeOverrideActive then return end

    local state = GetNativeOverrideState()
    local restoreEnabled
    if type(state[NATIVE_RESTORE_KEY]) == "boolean" then
        restoreEnabled = state[NATIVE_RESTORE_KEY]
    else
        restoreEnabled = DM.Native.GetEnabled() == true
    end

    local succeeded = DM.Native.SetEnabled(false)
    if not succeeded then return end

    nativeOverrideActive = true
    nativeRestoreEnabled = restoreEnabled
    state[NATIVE_RESTORE_KEY] = restoreEnabled
end

local function EndNativeOverride()
    local state = GetNativeOverrideState()
    local active = nativeOverrideActive
        or type(state[NATIVE_RESTORE_KEY]) == "boolean"
    if not active then return end

    local restoreEnabled = nativeRestoreEnabled
    if restoreEnabled == nil then
        restoreEnabled = state[NATIVE_RESTORE_KEY] == true
    end

    local succeeded = DM.Native.SetEnabled(restoreEnabled == true)
    if not succeeded then return end

    state[NATIVE_RESTORE_KEY] = nil
    nativeOverrideActive = nil
    nativeRestoreEnabled = nil
end

local function SetButtonIcon(button, icon, color, size)
    size = size or 12
    button:SetTexture(icon, {size, size}, {"CENTER", 0, 0})
    button:SetTextureColor(color or "white")
end

local function GetLockButtonIcon(locked)
    if AF.hasLockIcons and AF.GetAdaptiveIcon then
        return AF.GetAdaptiveIcon(locked and "Lock" or "Unlock")
    end

    return AF.GetIcon(locked and "Unavailable" or "Anchor_CENTER")
end

local function ApplyFlatDropdownStyle(dropdown)
    dropdown:SetBackdropColor(AF.GetColorRGB("none"))
    dropdown:SetBackdropBorderColor(AF.GetColorRGB("none"))

    local button = dropdown.button
    if not button then return end

    button:SetBackdropBorderColor(AF.GetColorRGB("none"))
    if button.bg then
        button.bg:Hide()
    end
end

local function CreateRowHoverCard(row)
    local card = AF.CreateFrame(
        _G.UIParent,
        nil,
        220,
        110,
        "BackdropTemplate"
    )
    row.hoverCard = card
    card:SetClampedToScreen(true)
    card:SetFrameStrata("TOOLTIP")
    AF.ApplyDefaultBackdrop(card)
    card:SetBackdropColor(AF.GetColorRGB("background", 0.96))
    card:SetBackdropBorderColor(AF.GetColorRGB("BFI"))
    card:Hide()

    local title = AF.CreateFontString(card, nil, "white")
    card.title = title
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -7)
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -42, -7)

    local playerBadge = AF.CreateFontString(card, nil, "gray")
    card.playerBadge = playerBadge
    playerBadge:SetText(_G.YOU or L["You"])
    playerBadge:SetJustifyH("RIGHT")
    playerBadge:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7)

    local totalLabel = AF.CreateFontString(card, nil, "gray")
    card.totalLabel = totalLabel
    totalLabel:SetText(_G.TOTAL or "Total")
    totalLabel:SetJustifyH("LEFT")
    totalLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

    local totalValue = AF.CreateFontString(card, nil, "white")
    card.totalValue = totalValue
    totalValue:SetJustifyH("RIGHT")
    totalValue:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -29)

    local perSecondLabel = AF.CreateFontString(card, nil, "gray")
    card.perSecondLabel = perSecondLabel
    perSecondLabel:SetText(_G.PER_SECOND or "Per second")
    perSecondLabel:SetJustifyH("LEFT")
    perSecondLabel:SetPoint(
        "TOPLEFT",
        totalLabel,
        "BOTTOMLEFT",
        0,
        -7
    )

    local perSecondValue = AF.CreateFontString(card, nil, "white")
    card.perSecondValue = perSecondValue
    perSecondValue:SetJustifyH("RIGHT")
    perSecondValue:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -49)

    local groupTotalLabel = AF.CreateFontString(card, nil, "gray")
    card.groupTotalLabel = groupTotalLabel
    groupTotalLabel:SetText(L["Group Total"])
    groupTotalLabel:SetJustifyH("LEFT")

    local groupTotalValue = AF.CreateFontString(card, nil, "white")
    card.groupTotalValue = groupTotalValue
    groupTotalValue:SetJustifyH("RIGHT")

    local recapHint = AF.CreateFontString(card, nil, "gray")
    card.recapHint = recapHint
    recapHint:SetJustifyH("LEFT")
    recapHint:SetWordWrap(true)

    local shareBar = _G.CreateFrame(
        "StatusBar",
        nil,
        card,
        "BackdropTemplate"
    )
    card.shareBar = shareBar
    shareBar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 8)
    shareBar:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 8)
    shareBar:SetHeight(4)
    AF.ApplyDefaultBackdrop_NoBorder(shareBar)
    shareBar:SetBackdropColor(0, 0, 0, 0.5)
    shareBar:SetMinMaxValues(0, 1)
    shareBar:SetValue(0)

    return card
end

local function ConfigureRowHoverCard(row)
    local card = row.hoverCard
    local inCombat = type(_G.InCombatLockdown) == "function"
        and _G.InCombatLockdown()

    card.totalLabel:SetShown(not inCombat)
    card.totalValue:SetShown(not inCombat)
    card.perSecondLabel:SetShown(
        not inCombat and not row.suppressValuePerSecond
    )
    card.perSecondValue:SetShown(
        not inCombat and not row.suppressValuePerSecond
    )
    card.groupTotalLabel:SetShown(not inCombat)
    card.groupTotalValue:SetShown(not inCombat)
    card.shareBar:SetShown(not inCombat)
    card.recapHint:Show()
    card.recapHint:ClearAllPoints()

    if inCombat then
        card.recapHint:SetText(
            L["Detailed information is secret while in combat."]
        )
        card.recapHint:SetPoint(
            "TOPLEFT",
            card.title,
            "BOTTOMLEFT",
            0,
            -10
        )
        card.recapHint:SetPoint(
            "TOPRIGHT",
            card,
            "TOPRIGHT",
            -8,
            -28
        )
        card:SetHeight(66)
        return
    end

    if row.isDeathMeter
        and (not row.deathRecapID or row.deathRecapID == 0)
    then
        card.recapHint:SetText(L["No death recap available."])
    else
        card.recapHint:SetText(L["Left-click for details."])
    end

    if row.suppressValuePerSecond then
        card.groupTotalLabel:ClearAllPoints()
        card.groupTotalLabel:SetPoint(
            "TOPLEFT",
            card.totalLabel,
            "BOTTOMLEFT",
            0,
            -7
        )
        card.groupTotalValue:ClearAllPoints()
        card.groupTotalValue:SetPoint(
            "TOPRIGHT",
            card,
            "TOPRIGHT",
            -8,
            -49
        )
        card.recapHint:SetPoint(
            "TOPLEFT",
            card.groupTotalLabel,
            "BOTTOMLEFT",
            0,
            -7
        )
        card.recapHint:SetPoint(
            "TOPRIGHT",
            card,
            "TOPRIGHT",
            -8,
            -68
        )
        card:SetHeight(104)
    else
        card.groupTotalLabel:ClearAllPoints()
        card.groupTotalLabel:SetPoint(
            "TOPLEFT",
            card.perSecondLabel,
            "BOTTOMLEFT",
            0,
            -7
        )
        card.groupTotalValue:ClearAllPoints()
        card.groupTotalValue:SetPoint(
            "TOPRIGHT",
            card,
            "TOPRIGHT",
            -8,
            -69
        )
        card.recapHint:SetPoint(
            "TOPLEFT",
            card.groupTotalLabel,
            "BOTTOMLEFT",
            0,
            -7
        )
        card.recapHint:SetPoint(
            "TOPRIGHT",
            card,
            "TOPRIGHT",
            -8,
            -88
        )
        card:SetHeight(124)
    end
end

local function CreateRow(parent, window)
    local row = AF.CreateFrame(parent)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        ScrollWindow(window, delta)
    end)

    local bar = _G.CreateFrame("StatusBar", nil, row, "BackdropTemplate")
    row.bar = bar
    bar:SetAllPoints()
    AF.ApplyDefaultBackdrop_NoBorder(bar)
    bar:SetBackdropColor(0, 0, 0, 0.42)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local highlight = AF.CreateFrame(
        row,
        nil,
        nil,
        nil,
        "BackdropTemplate"
    )
    row.highlight = highlight
    highlight:SetAllPoints()
    highlight:SetFrameLevel(bar:GetFrameLevel() + 1)
    AF.ApplyDefaultBackdrop_NoBorder(highlight)
    highlight:SetBackdropColor(AF.GetColorRGB("BFI", 0.18))
    highlight:Hide()

    local overlay = AF.CreateFrame(row)
    row.overlay = overlay
    overlay:SetAllPoints()
    overlay:SetFrameLevel(bar:GetFrameLevel() + 2)

    local rank = AF.CreateFontString(overlay, nil, "gray")
    row.rank = rank
    rank:SetJustifyH("LEFT")
    rank:SetWordWrap(false)

    local iconHolder = AF.CreateFrame(
        overlay,
        nil,
        nil,
        nil,
        "BackdropTemplate"
    )
    row.iconHolder = iconHolder
    AF.ApplyDefaultBackdrop(iconHolder)
    iconHolder:SetBackdropColor(0, 0, 0, 0.8)
    iconHolder:SetFrameLevel(overlay:GetFrameLevel() + 1)

    local icon = AF.CreateTexture(iconHolder, nil, "white")
    row.icon = icon
    AF.SetOnePixelInside(icon, iconHolder)
    AF.ApplyDefaultTexCoord(icon)

    local name = AF.CreateFontString(overlay, nil, "white")
    row.name = name
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)

    local perSecond = AF.CreateFontString(overlay, nil, "gray")
    row.perSecond = perSecond
    perSecond:SetJustifyH("RIGHT")
    perSecond:SetWordWrap(false)

    local total = AF.CreateFontString(overlay, nil, "white")
    row.total = total
    total:SetJustifyH("RIGHT")
    total:SetWordWrap(false)

    CreateRowHoverCard(row)
    row:SetScript("OnEnter", function()
        row.highlight:Show()
        ConfigureRowHoverCard(row)
        row.hoverCard:ClearAllPoints()
        row.hoverCard:SetPoint(
            "TOPRIGHT",
            row,
            "TOPLEFT",
            -WINDOW_GAP,
            0
        )
        row.hoverCard:Show()
    end)
    row:SetScript("OnLeave", function()
        row.highlight:Hide()
        row.hoverCard:Hide()
    end)
    row:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        if row.isDeathMeter
            and (not row.deathRecapID or row.deathRecapID == 0)
        then
            return
        end
        OpenWindowDetails(window, row.sourceIndex)
    end)

    return row
end

local function EnsureRows(window, count)
    for index = #window.rows + 1, count do
        window.rows[index] = CreateRow(window.body, window)
    end
end

local function GetNumberVisibility(config, definition)
    if definition.suppressValuePerSecond then
        return true, false
    end
    if definition.valuePerSecondAsPrimary then
        return config.numberMode == "both", true
    end
    if config.numberMode == "both" then
        return true, true
    end
    return config.numberMode ~= "perSecond",
        config.numberMode == "perSecond"
end

local function ApplyRowLayout(row, index, config, texture, definition)
    local barHeight = config.barHeight
    local y = -config.padding
        - ((index - 1) * (barHeight + config.spacing))
    local showTotal, showPerSecond =
        GetNumberVisibility(config, definition)
    local showIcon = config.showSpecIcon and not definition.suppressIcon
    row.showIcon = showIcon

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", config.padding, y)
    row:SetPoint("TOPRIGHT", row:GetParent(), "TOPRIGHT", -config.padding, y)
    row:SetHeight(barHeight)

    row.bar:SetStatusBarTexture(texture)

    row.rank:ClearAllPoints()
    row.rank:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.rank:SetWidth(16)

    local iconSize = barHeight - 4
    row.iconHolder:ClearAllPoints()
    row.iconHolder:SetPoint("LEFT", row.rank, "RIGHT", 2, 0)
    row.iconHolder:SetSize(iconSize, iconSize)
    row.iconHolder:SetShown(showIcon)

    row.name:ClearAllPoints()
    if showIcon then
        row.name:SetPoint("LEFT", row.iconHolder, "RIGHT", 3, 0)
    else
        row.name:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)
    end

    row.total:ClearAllPoints()
    row.perSecond:ClearAllPoints()
    if showTotal and showPerSecond then
        if definition.valuePerSecondAsPrimary then
            row.perSecond:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            row.perSecond:SetWidth(62)
            row.total:SetPoint(
                "RIGHT",
                row.perSecond,
                "LEFT",
                -5,
                0
            )
            row.total:SetWidth(62)
            row.name:SetPoint("RIGHT", row.total, "LEFT", -5, 0)
        else
            row.total:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            row.total:SetWidth(62)
            row.perSecond:SetPoint(
                "RIGHT",
                row.total,
                "LEFT",
                -5,
                0
            )
            row.perSecond:SetWidth(62)
            row.name:SetPoint(
                "RIGHT",
                row.perSecond,
                "LEFT",
                -5,
                0
            )
        end
    elseif showPerSecond then
        row.perSecond:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.perSecond:SetWidth(72)
        row.name:SetPoint("RIGHT", row.perSecond, "LEFT", -5, 0)
    else
        row.total:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.total:SetWidth(72)
        row.name:SetPoint("RIGHT", row.total, "LEFT", -5, 0)
    end
    row.total:SetShown(showTotal)
    row.perSecond:SetShown(showPerSecond)
    row.hoverCard.perSecondLabel:SetShown(
        not definition.suppressValuePerSecond
    )
    row.hoverCard.perSecondValue:SetShown(
        not definition.suppressValuePerSecond
    )
    row.hoverCard.shareBar:SetStatusBarTexture(texture)
    row.showTotal = showTotal
    row.showPerSecond = showPerSecond
    row.suppressValuePerSecond = definition.suppressValuePerSecond
    row.isDeathMeter = definition.enumName == "Deaths"
    ConfigureRowHoverCard(row)
end

local function FormatDetailNumber(value)
    if type(_G.AbbreviateLargeNumbers) == "function" then
        return _G.AbbreviateLargeNumbers(value)
    end

    return tostring(math.floor(value + 0.5))
end

local function FormatDetailPercent(value, total)
    local amount = FormatDetailNumber(value)
    if total > 0 then
        return ("%s  %.1f%%"):format(
            amount,
            value / total * 100
        )
    end

    return amount
end

local function FormatDetailSpellValues(
    spell,
    sourceTotal,
    definition,
    duration
)
    local total = spell.totalAmount or 0
    if not definition.valuePerSecondAsPrimary then
        return FormatDetailPercent(total, sourceTotal), total
    end

    local rate = spell.amountPerSecond
    if rate == nil and duration and duration > 0 then
        rate = total / duration
    end
    rate = rate or 0

    local text = ("%s/s  %s"):format(
        FormatDetailNumber(rate),
        FormatDetailNumber(total)
    )
    if sourceTotal > 0 then
        text = ("%s  %.1f%%"):format(
            text,
            total / sourceTotal * 100
        )
    end

    return text, rate
end

local function GetDetailSpellName(spellID)
    if not spellID or spellID == 0 then return end

    local api = _G.C_Spell
    if type(api) ~= "table"
        or type(api.GetSpellName) ~= "function"
    then
        return
    end

    return api.GetSpellName(spellID)
end

local function GetDetailSpellTexture(spellID)
    if not spellID or spellID == 0 then return end

    local api = _G.C_Spell
    if type(api) ~= "table"
        or type(api.GetSpellTexture) ~= "function"
    then
        return
    end

    return api.GetSpellTexture(spellID)
end

local function GetDetailSourceData(
    sessionMode,
    sessionID,
    meterType,
    source
)
    if sessionMode == SESSION_MODE_CURRENT then
        return DM.Data.GetCurrentSource(
            meterType,
            source.sourceGUID,
            source.sourceCreatureID
        )
    end
    if sessionMode == SESSION_MODE_OVERALL then
        return DM.Data.GetOverallSource(
            meterType,
            source.sourceGUID,
            source.sourceCreatureID
        )
    end

    return DM.Data.GetHistoricalSource(
        sessionID,
        meterType,
        source.sourceGUID,
        source.sourceCreatureID
    )
end

-- Retail PTR 12.1.0.68914 / wow-ui-source d3915c78: source names can be
-- ConditionalSecret, and spell details do not expose a NeverSecret source ID.
-- Keep this in Blizzard's spell-by-spell shape instead of joining or grouping
-- names in Lua.
local function BuildStandardDetailEntries(
    sourceDetail,
    classFilename,
    definition,
    duration
)
    local entries = {}
    local spells = sourceDetail.combatSpells or {}
    local spellCount = #spells
    for index = 1, spellCount do
        local spell = spells[index]
        local spellID = spell.spellID
        local spellName = GetDetailSpellName(spellID)
        local valueText, barValue = FormatDetailSpellValues(
            spell,
            sourceDetail.totalAmount,
            definition,
            duration
        )

        if not spellName or spellName == "" then
            spellName = spell.creatureName
        end
        if not spellName or spellName == "" then
            spellName = _G.UNKNOWN or "Unknown"
        end

        entries[#entries + 1] = {
            classFilename = classFilename,
            icon = GetDetailSpellTexture(spellID),
            kind = "spell",
            label = spellName,
            maxValue = sourceDetail.maxAmount,
            spellID = spellID,
            total = barValue,
            valueText = valueText,
        }
    end

    return entries
end

local function GetDeathEventName(event)
    local name = event.spellName
    if name and name ~= "" then return name end

    if event.event == "SWING_DAMAGE" then
        return _G.ACTION_SWING or "Melee"
    end
    if event.event == "ENVIRONMENTAL_DAMAGE"
        and event.environmentalType
    then
        return event.environmentalType
    end

    return GetDetailSpellName(event.spellId)
        or _G.UNKNOWN
        or "Unknown"
end

local function BuildDeathDetailEntries(source)
    local recapID = source.deathRecapID
    local api = _G.C_DeathRecap
    if not recapID or recapID == 0 or type(api) ~= "table"
        or type(api.GetRecapEvents) ~= "function"
    then
        return {}
    end

    local events = api.GetRecapEvents(recapID)
    if not events then return {} end

    local maxHealth = 0
    if type(api.GetRecapMaxHealth) == "function" then
        maxHealth = api.GetRecapMaxHealth(recapID) or 0
    end

    local deathTimestamp = 0
    for _, event in ipairs(events) do
        if event.timestamp and event.timestamp > deathTimestamp then
            deathTimestamp = event.timestamp
        end
    end

    local entries = {}
    local eventCount = #events
    for displayIndex = 1, eventCount do
        local event = events[eventCount - displayIndex + 1]
        local timeBeforeDeath = deathTimestamp
            - (event.timestamp or deathTimestamp)
        local eventName = GetDeathEventName(event)
        local label = ("-%.1fs  %s"):format(
            timeBeforeDeath,
            eventName
        )
        local amount = event.amount or 0
        local isHeal = event.event == "SPELL_HEAL"
            or event.event == "SPELL_PERIODIC_HEAL"
        local valueText = (isHeal and "+" or "-")
            .. FormatDetailNumber(math.abs(amount))

        if maxHealth > 0 and event.currentHP then
            valueText = ("%s  %.0f%%"):format(
                valueText,
                event.currentHP / maxHealth * 100
            )
        end
        if event.overkill and event.overkill > 0 then
            valueText = ("%s  (+%s)"):format(
                valueText,
                FormatDetailNumber(event.overkill)
            )
        end

        entries[displayIndex] = {
            color = isHeal
                and {0.10, 0.50, 0.10}
                or {0.60, 0.08, 0.08},
            icon = GetDetailSpellTexture(event.spellId),
            kind = "death",
            label = label,
            maxValue = maxHealth > 0 and maxHealth or 1,
            spellID = event.spellId,
            total = event.currentHP or 0,
            valueText = valueText,
        }
    end

    return entries
end

local function CreateDetailRow(parent, window)
    local row = AF.CreateFrame(parent)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)

    local bar = _G.CreateFrame("StatusBar", nil, row, "BackdropTemplate")
    row.bar = bar
    bar:SetAllPoints()
    AF.ApplyDefaultBackdrop_NoBorder(bar)
    bar:SetBackdropColor(0, 0, 0, 0.42)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local highlight = AF.CreateFrame(
        row,
        nil,
        nil,
        nil,
        "BackdropTemplate"
    )
    row.highlight = highlight
    highlight:SetAllPoints()
    highlight:SetFrameLevel(bar:GetFrameLevel() + 1)
    AF.ApplyDefaultBackdrop_NoBorder(highlight)
    highlight:SetBackdropColor(AF.GetColorRGB("BFI", 0.18))
    highlight:Hide()

    local overlay = AF.CreateFrame(row)
    row.overlay = overlay
    overlay:SetAllPoints()
    overlay:SetFrameLevel(bar:GetFrameLevel() + 2)

    local rank = AF.CreateFontString(overlay, nil, "gray")
    row.rank = rank
    rank:SetJustifyH("LEFT")
    rank:SetWordWrap(false)

    local iconHolder = AF.CreateFrame(
        overlay,
        nil,
        nil,
        nil,
        "BackdropTemplate"
    )
    row.iconHolder = iconHolder
    AF.ApplyDefaultBackdrop(iconHolder)
    iconHolder:SetBackdropColor(0, 0, 0, 0.8)
    iconHolder:SetFrameLevel(overlay:GetFrameLevel() + 1)

    local icon = AF.CreateTexture(iconHolder, nil, "white")
    row.icon = icon
    AF.SetOnePixelInside(icon, iconHolder)
    AF.ApplyDefaultTexCoord(icon)

    local label = AF.CreateFontString(overlay, nil, "white")
    row.label = label
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    local value = AF.CreateFontString(overlay, nil, "white")
    row.value = value
    value:SetJustifyH("RIGHT")
    value:SetWordWrap(false)

    row:SetScript("OnMouseWheel", function(_, delta)
        ScrollWindowDetails(window, delta)
    end)
    row:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            CloseWindowDetails(window)
        end
    end)
    row:SetScript("OnEnter", function()
        row.highlight:Show()
        if not row.spellID
            or type(_G.InCombatLockdown) == "function"
                and _G.InCombatLockdown()
        then
            return
        end

        local tooltip = _G.GameTooltip
        if not tooltip then return end
        tooltip:SetOwner(row, "ANCHOR_LEFT")
        tooltip:SetSpellByID(row.spellID)
        tooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        row.highlight:Hide()
        if _G.GameTooltip then
            _G.GameTooltip:Hide()
        end
    end)

    return row
end

local function CreateDetailPanel(window)
    local panel = AF.CreateFrame(
        window.body,
        nil,
        nil,
        nil,
        "BackdropTemplate"
    )
    window.detailPanel = panel
    panel:SetAllPoints()
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:Hide()
    panel:SetScript("OnMouseWheel", function(_, delta)
        ScrollWindowDetails(window, delta)
    end)
    panel:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            CloseWindowDetails(window)
        end
    end)

    local title = AF.CreateFontString(panel, nil, "white")
    window.detailTitle = title
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    local hint = AF.CreateFontString(panel, nil, "gray")
    window.detailHint = hint
    hint:SetText(L["Right-click to return"])
    hint:SetJustifyH("RIGHT")
    hint:SetWordWrap(false)

    local empty = AF.CreateFontString(panel, nil, "gray")
    window.detailEmpty = empty
    empty:SetText(L["No detailed information available."])
    empty:SetPoint("CENTER")
    empty:SetJustifyH("CENTER")
    empty:Hide()

    window.detailRows = {}
end

local function EnsureDetailRows(window, count)
    for index = #window.detailRows + 1, count do
        window.detailRows[index] = CreateDetailRow(
            window.detailPanel,
            window
        )
    end
end

local function ApplyDetailRowLayout(
    row,
    slotIndex,
    config,
    texture,
    titleRowCount
)
    local y = -config.padding
        - (titleRowCount * (config.barHeight + config.spacing))
        - ((slotIndex - 1) * (config.barHeight + config.spacing))
    row:ClearAllPoints()
    row:SetPoint(
        "TOPLEFT",
        row:GetParent(),
        "TOPLEFT",
        config.padding,
        y
    )
    row:SetPoint(
        "TOPRIGHT",
        row:GetParent(),
        "TOPRIGHT",
        -config.padding,
        y
    )
    row:SetHeight(config.barHeight)
    row.bar:SetStatusBarTexture(texture)

    row.rank:ClearAllPoints()
    row.rank:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.rank:SetWidth(16)

    local iconSize = config.barHeight - 4
    row.iconHolder:ClearAllPoints()
    row.iconHolder:SetPoint("LEFT", row.rank, "RIGHT", 2, 0)
    row.iconHolder:SetSize(iconSize, iconSize)

    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    row.value:SetWidth(104)

    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row.iconHolder, "RIGHT", 3, 0)
    row.label:SetPoint("RIGHT", row.value, "LEFT", -5, 0)
end

local function ApplyDetailLayout(window, config, texture)
    local titleRowCount = window.visibleRowCount > 1 and 1 or 0
    local visibleRows = math.max(
        1,
        window.visibleRowCount - titleRowCount
    )
    window.visibleDetailRowCount = visibleRows
    window.detailTitleRowCount = titleRowCount
    EnsureDetailRows(window, visibleRows)

    window.detailPanel:ClearAllPoints()
    window.detailPanel:SetAllPoints(window.body)

    window.detailTitle:ClearAllPoints()
    window.detailTitle:SetPoint(
        "TOPLEFT",
        window.detailPanel,
        "TOPLEFT",
        config.padding + 3,
        -config.padding
    )
    window.detailTitle:SetPoint(
        "RIGHT",
        window.detailHint,
        "LEFT",
        -5,
        0
    )

    window.detailHint:ClearAllPoints()
    window.detailHint:SetPoint(
        "TOPRIGHT",
        window.detailPanel,
        "TOPRIGHT",
        -config.padding - 3,
        -config.padding
    )
    window.detailHint:SetWidth(110)
    window.detailTitle:SetShown(titleRowCount == 1)
    window.detailHint:SetShown(titleRowCount == 1)

    for index, row in ipairs(window.detailRows) do
        if index <= visibleRows then
            ApplyDetailRowLayout(
                row,
                index,
                config,
                texture,
                titleRowCount
            )
        else
            row:Hide()
        end
    end
end

local function UpdateDetailRow(row, entry, index, config)
    if entry.kind == "section" then
        row.rank:SetText("")
        row.iconHolder:Hide()
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.label:SetText(entry.label)
        row.value:SetText("")
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(0)
        row.bar:SetStatusBarColor(0, 0, 0, 0.22)
        row.spellID = nil
        row:Show()
        return
    end

    local r, g, b
    if entry.color then
        r, g, b = entry.color[1], entry.color[2], entry.color[3]
    elseif config.classColor and entry.classFilename
        and entry.classFilename ~= ""
    then
        r, g, b = AF.GetClassColor(entry.classFilename)
    else
        r, g, b = AF.GetColorRGB("BFI")
    end

    row.rank:SetText(index)
    row.iconHolder:SetShown(entry.icon ~= nil and entry.icon ~= 0)
    row.icon:SetTexture(entry.icon)
    row.iconHolder:SetBackdropBorderColor(r, g, b, 1)
    row.label:ClearAllPoints()
    if entry.icon ~= nil and entry.icon ~= 0 then
        row.label:SetPoint("LEFT", row.iconHolder, "RIGHT", 3, 0)
    else
        row.label:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)
    end
    row.label:SetPoint("RIGHT", row.value, "LEFT", -5, 0)
    row.label:SetText(entry.label)
    row.value:SetText(entry.valueText)
    row.bar:SetMinMaxValues(0, entry.maxValue or 1)
    row.bar:SetValue(entry.total or 0)
    row.bar:SetStatusBarColor(r, g, b, config.barAlpha)
    row.spellID = entry.spellID
    row:Show()
end

local function RenderDetailEntries(window, entries, source, config)
    local maximumOffset = math.max(
        0,
        #entries - window.visibleDetailRowCount
    )
    window.detailOffset = Clamp(
        window.detailOffset or 0,
        0,
        maximumOffset
    )
    window.detailMaxOffset = maximumOffset
    window.detailTitle:SetText(_G.Ambiguate(source.name, "short"))
    window.detailEmpty:SetShown(#entries == 0)

    for slotIndex = 1, window.visibleDetailRowCount do
        local row = window.detailRows[slotIndex]
        local entryIndex = window.detailOffset + slotIndex
        local entry = entries[entryIndex]
        if entry then
            UpdateDetailRow(row, entry, entryIndex, config)
        else
            row.spellID = nil
            row:Hide()
        end
    end
end

RefreshWindowDetails = function(window)
    if not window.detailOpen then return false end
    if type(_G.InCombatLockdown) == "function"
        and _G.InCombatLockdown()
    then
        return false
    end

    local config = GetConfig()
    local definition = GetWindowDefinition(window.index)
    local meterType = GetMeterType(definition)
    if meterType == nil then return false end

    local sessionMode, sessionID = GetWindowSessionSelection(
        config,
        window.index
    )
    local session = GetSessionData(sessionMode, sessionID, meterType)
    if not session or not session.combatSources then return false end

    local source = session.combatSources[window.detailSourceIndex]
    if not source then return false end

    local entries
    if definition.enumName == "Deaths" then
        entries = BuildDeathDetailEntries(source)
    else
        local sourceDetail = GetDetailSourceData(
            sessionMode,
            sessionID,
            meterType,
            source
        )
        if not sourceDetail then return false end

        entries = BuildStandardDetailEntries(
            sourceDetail,
            source.classFilename,
            definition,
            session.durationSeconds
        )
    end

    RenderDetailEntries(window, entries, source, config)
    return true
end

CloseWindowDetails = function(window, skipRefresh)
    if not window then return false end

    local wasOpen = window.detailOpen == true
    window.detailOpen = nil
    window.detailSourceIndex = nil
    window.detailOffset = 0
    window.detailMaxOffset = 0
    if window.detailPanel then
        window.detailPanel:Hide()
    end
    if window.detailTitle then
        window.detailTitle:SetText("")
    end
    if window.detailEmpty then
        window.detailEmpty:Hide()
    end
    for _, row in ipairs(window.detailRows or {}) do
        row.spellID = nil
        row.icon:SetTexture(nil)
        row.label:SetText("")
        row.value:SetText("")
        row:Hide()
        row.highlight:Hide()
    end

    if wasOpen and not skipRefresh and rendererEnabled then
        Renderer.Refresh()
    end
    return wasOpen
end

OpenWindowDetails = function(window, sourceIndex)
    if not rendererEnabled or type(sourceIndex) ~= "number" then
        return false
    end
    if type(_G.InCombatLockdown) == "function"
        and _G.InCombatLockdown()
    then
        return false
    end

    window.detailOpen = true
    window.detailSourceIndex = sourceIndex
    window.detailOffset = 0
    window.detailPanel:Show()
    for _, row in ipairs(window.rows) do
        row:Hide()
        row.hoverCard:Hide()
        row.highlight:Hide()
    end

    if not RefreshWindowDetails(window) then
        CloseWindowDetails(window, true)
        Renderer.Refresh()
        return false
    end
    return true
end

ScrollWindowDetails = function(window, delta)
    if not rendererEnabled or not window.detailOpen then return end
    if type(_G.InCombatLockdown) == "function"
        and _G.InCombatLockdown()
    then
        return
    end

    local offset = window.detailOffset or 0
    local nextOffset = offset
    if delta < 0 then
        nextOffset = offset + 1
    elseif delta > 0 then
        nextOffset = offset - 1
    end
    nextOffset = Clamp(
        nextOffset,
        0,
        window.detailMaxOffset or 0
    )
    if nextOffset == offset then return end

    window.detailOffset = nextOffset
    RefreshWindowDetails(window)
end

local function ToggleMinimized(window)
    -- A space-constrained body expands automatically when objectives release
    -- room. Do not turn that temporary state into a user collapse.
    if window.runtimeMinimized and not window.minimized then return end

    window.minimized = not window.minimized
    Renderer.ApplySettings()
end

local function IsValidAnchorRecord(anchor, index)
    return type(anchor) == "table"
        and type(anchor.relativeTo) == "number"
        and anchor.relativeTo >= 0
        and anchor.relativeTo <= MAX_WINDOWS
        and anchor.relativeTo ~= index
        and VALID_ANCHOR_POINTS[anchor.point] == true
        and VALID_ANCHOR_POINTS[anchor.relativePoint] == true
        and type(anchor.x) == "number"
        and type(anchor.y) == "number"
end

local function AnchorChainIsCyclic(config, startIndex)
    local visited = {}
    local index = startIndex
    while index ~= 0 do
        if visited[index] then return true end
        visited[index] = true

        local anchor = config.windowAnchors[index]
        if not IsValidAnchorRecord(anchor, index) then return true end
        index = anchor.relativeTo
    end
    return false
end

local function AnchorChainReaches(config, startIndex, targetIndex)
    local visited = {}
    local index = startIndex
    while index ~= 0 do
        if index == targetIndex then return true end
        if visited[index] then return true end
        visited[index] = true

        local anchor = config.windowAnchors[index]
        if not IsValidAnchorRecord(anchor, index) then return true end
        index = anchor.relativeTo
    end
    return false
end

local function GetObjectiveTrackerDockTarget(tracker)
    local widgets = BFI.modules.UIWidgets
    return widgets and widgets.objectiveTrackerDockFrame
        or tracker.NineSlice
        or tracker
end

local function ApplyAllAnchors(config)
    EnsureInteractionConfig(config)
    for index = 1, MAX_WINDOWS do
        local anchor = config.windowAnchors[index]
        if not IsValidAnchorRecord(anchor, index)
            or AnchorChainIsCyclic(config, index)
        then
            SetAnchorRecord(config, index, GetFallbackAnchor())
        end
    end

    for index = 1, MAX_WINDOWS do
        local anchor = config.windowAnchors[index]
        local point = anchor.point
        local relativeTo = anchor.relativeTo == 0
            and _G.UIParent
            or windows[anchor.relativeTo]
        local relativePoint = anchor.relativePoint
        local x = anchor.x
        local y = anchor.y
        if config.dockToObjectiveTracker
            and IsDefaultRootAnchor(anchor)
            and _G.ObjectiveTrackerFrame
        then
            local tracker = _G.ObjectiveTrackerFrame
            -- Retail PTR 12.1.0.68914, jdtoppin/wow-ui-source commit
            -- d3915c78: ObjectiveTrackerContainerMixin owns native custom
            -- height. BFI's owned dock frame observes that extent while the
            -- tracker is expanded/custom-positioned, and otherwise follows
            -- its compact content surface. A declarative anchor keeps one
            -- right-side lane without taking ownership of native geometry.
            relativeTo = GetObjectiveTrackerDockTarget(tracker)
            point = "TOPRIGHT"
            relativePoint = "BOTTOMRIGHT"
            x = 0
            y = -OBJECTIVE_TRACKER_GAP
        end
        local window = windows[index]
        window:ClearAllPoints()
        window:SetPoint(
            point,
            relativeTo,
            relativePoint,
            x,
            y
        )
    end
end

local function ClearDockPreview()
    for _, window in ipairs(windows) do
        if window.dockPreview then
            window.dockPreview:Hide()
            window.dockPreview:ClearAllPoints()
        end
    end
    activeDockTarget = nil
    activeDockDirection = nil
end

local function ShowDockPreview(target, direction)
    if activeDockTarget == target then
        -- Keep the insertion side as internal drop state, but present the
        -- target as one window instead of two competing visual zones.
        activeDockDirection = direction
        return
    end

    ClearDockPreview()
    local preview = target.dockPreview
    preview:SetAllPoints(target)
    preview:Show()
    activeDockTarget = target
    activeDockDirection = direction
end

local function UpdateDockPreview(draggedWindow)
    local config = GetConfig()
    for index = 1, config.windowCount do
        local target = windows[index]
        if target ~= draggedWindow
            and target:IsShown()
            and target:IsMouseOver()
            and not AnchorChainReaches(
                config,
                target.index,
                draggedWindow.index
            )
        then
            local _, cursorY = _G.GetCursorPosition()
            local _, targetY = target:GetCenter()
            local scale = target:GetEffectiveScale()
            if cursorY and targetY and scale then
                local direction = (cursorY / scale) >= targetY
                    and "above"
                    or "below"
                ShowDockPreview(target, direction)
                return
            end
        end
    end
    ClearDockPreview()
end

local function CaptureFreeAnchor(window)
    local left = window:GetLeft()
    local bottom = window:GetBottom()
    local anchor
    if type(left) == "number" and type(bottom) == "number" then
        anchor = {
            relativeTo = 0,
            point = "BOTTOMLEFT",
            relativePoint = "BOTTOMLEFT",
            x = left,
            y = bottom,
        }
    else
        anchor = GetFallbackAnchor()
    end
    SetAnchorRecord(GetConfig(), window.index, anchor)
end

local function GetDockAnchor(targetIndex, direction)
    if direction == "above" then
        return {
            relativeTo = targetIndex,
            point = "BOTTOMRIGHT",
            relativePoint = "TOPRIGHT",
            x = 0,
            y = WINDOW_GAP,
        }
    end

    return {
        relativeTo = targetIndex,
        point = "TOPRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = 0,
        y = -WINDOW_GAP,
    }
end

local function IsDockedOnSide(anchor, targetIndex, direction)
    local expected = GetDockAnchor(targetIndex, direction)
    return anchor.relativeTo == expected.relativeTo
        and anchor.point == expected.point
        and anchor.relativePoint == expected.relativePoint
        and anchor.x == expected.x
        and anchor.y == expected.y
end

local function GetDockDirection(anchor)
    if IsDockedOnSide(anchor, anchor.relativeTo, "above") then
        return "above"
    end
    if IsDockedOnSide(anchor, anchor.relativeTo, "below") then
        return "below"
    end
end

local function FindDockedNeighbor(config, targetIndex, direction, excluded)
    for index = 1, MAX_WINDOWS do
        if index ~= excluded
            and IsDockedOnSide(
                config.windowAnchors[index],
                targetIndex,
                direction
            )
        then
            return index
        end
    end
end

local function CloseOldDockGap(config, window)
    local origin = window.dragOriginAnchor
    if not origin then return end

    if origin.relativeTo ~= 0 then
        local direction = GetDockDirection(origin)
        if not direction then return end

        local neighbor = FindDockedNeighbor(
            config,
            window.index,
            direction,
            window.index
        )
        if neighbor then
            SetAnchorRecord(config, neighbor, origin)
        end
        return
    end

    local above = FindDockedNeighbor(
        config,
        window.index,
        "above",
        window.index
    )
    local below = FindDockedNeighbor(
        config,
        window.index,
        "below",
        window.index
    )
    local replacement = above or below
    if not replacement then return end

    SetAnchorRecord(config, replacement, origin)
    local other
    if replacement == above then
        other = below
    else
        other = above
    end
    if other then
        SetAnchorRecord(
            config,
            other,
            GetDockAnchor(
                replacement,
                other == above and "above" or "below"
            )
        )
    end
end

local function InsertDockedWindow(config, window, target, direction)
    local targetAnchor = config.windowAnchors[target.index]
    local targetDirection = GetDockDirection(targetAnchor)
    if targetDirection and targetDirection ~= direction then
        SetAnchorRecord(config, window.index, targetAnchor)
        SetAnchorRecord(
            config,
            target.index,
            GetDockAnchor(window.index, targetDirection)
        )
        return
    end

    for index = 1, MAX_WINDOWS do
        local anchor = config.windowAnchors[index]
        if index ~= window.index
            and IsDockedOnSide(anchor, target.index, direction)
        then
            SetAnchorRecord(
                config,
                index,
                GetDockAnchor(window.index, direction)
            )
            break
        end
    end

    SetAnchorRecord(
        config,
        window.index,
        GetDockAnchor(target.index, direction)
    )
end

local function FinishWindowDrag(window)
    if not window.isDragging then return end

    local target = activeDockTarget
    local direction = activeDockDirection
    window.isDragging = nil
    window:SetScript("OnUpdate", nil)
    window:StopMovingOrSizing()

    local config = GetConfig()
    if target and direction then
        InsertDockedWindow(config, window, target, direction)
    else
        CaptureFreeAnchor(window)
    end
    window.dragOriginAnchor = nil

    ClearDockPreview()
    if rendererEnabled then
        Renderer.ApplySettings()
    else
        ApplyAllAnchors(config)
    end
end

local function BeginWindowDrag(window)
    local config = GetConfig()
    if config.locked then return end

    if type(AF.CloseDropdown) == "function" then
        AF.CloseDropdown()
    end
    ClearDockPreview()
    local anchor = config.windowAnchors[window.index]
    window.dragOriginAnchor = {
        relativeTo = anchor.relativeTo,
        point = anchor.point,
        relativePoint = anchor.relativePoint,
        x = anchor.x,
        y = anchor.y,
    }
    CloseOldDockGap(config, window)
    ApplyAllAnchors(config)
    window.isDragging = true
    window:SetScript("OnUpdate", function()
        UpdateDockPreview(window)
    end)
    window:StartMoving()
end

local function ApplySharedWidth(sourceWindow, width)
    local config = GetConfig()
    local sharedWidth = Clamp(
        math.floor(width + 0.5),
        MIN_WINDOW_WIDTH,
        MAX_WINDOW_WIDTH
    )
    config.width = sharedWidth

    for _, window in ipairs(windows) do
        if window ~= sourceWindow then
            window.applyingLayout = true
            window:SetWidth(sharedWidth)
            window.applyingLayout = nil
        end
    end
end

local function OnWindowSizeChanged(window, width, height)
    if window.applyingLayout
        or window.minimized
        or window.runtimeConstrained
        or window.runtimeHidden
    then
        return
    end

    local config = GetConfig()
    EnsureInteractionConfig(config)
    ApplySharedWidth(window, width)
    config.windowHeights[window.index] = Clamp(
        math.floor(height + 0.5),
        GetMinimumWindowHeight(config),
        MAX_WINDOW_HEIGHT
    )
end

local function FinishWindowResize(window)
    if GetConfig().locked
        or window.minimized
        or window.runtimeConstrained
        or window.runtimeHidden
    then
        return
    end
    OnWindowSizeChanged(window, window:GetWidth(), window:GetHeight())
    Renderer.ApplySettings()
    AF.Fire("BFI_RefreshOptions", "damageMeter")
end

local function ToggleLocked()
    local config = GetConfig()
    config.locked = not config.locked
    ClearDockPreview()
    Renderer.ApplySettings()
end

function Renderer.SetWindowType(index, typeName, options)
    if type(index) ~= "number"
        or index < 1
        or index > MAX_WINDOWS
        or index ~= math.floor(index)
        or not TYPE_DEFINITIONS[typeName]
    then
        return false
    end

    options = type(options) == "table" and options or {}
    local config = GetConfig()
    if windows[index] then
        CloseWindowDetails(windows[index], true)
    end
    config.windowTypes[index] = typeName
    if windows[index] then
        ResetWindowScrollOffset(windows[index], typeName)
    end
    if options.refresh ~= false and rendererEnabled then
        Renderer.ApplySettings()
    end
    return true
end

function Renderer.GetWindowSession(index)
    if type(index) ~= "number"
        or index < 1
        or index > MAX_WINDOWS
        or index ~= math.floor(index)
    then
        return
    end

    return GetWindowSessionSelection(GetConfig(), index)
end

function Renderer.ClearRuntimeSessions()
    for index = 1, MAX_WINDOWS do
        runtimeHistoricalSessionIDs[index] = nil
        if windows[index] then
            windows[index].scrollOffsets = {}
            windows[index].maxScrollOffsets = {}
        end
    end
end

function Renderer.SetWindowSession(
    index,
    mode,
    sessionID,
    options
)
    if type(index) ~= "number"
        or index < 1
        or index > MAX_WINDOWS
        or index ~= math.floor(index)
    then
        return false
    end
    if mode ~= SESSION_MODE_CURRENT
        and mode ~= SESSION_MODE_OVERALL
        and mode ~= SESSION_MODE_HISTORY
    then
        return false
    end

    EnsureSessionItems()
    if mode == SESSION_MODE_HISTORY then
        if type(sessionID) ~= "number"
            or not sessionSelections[GetSessionKey(mode, sessionID)]
        then
            return false
        end
    else
        sessionID = nil
    end

    options = type(options) == "table" and options or {}
    local config = GetConfig()
    local syncSettings = config.windowSyncSessions
    local shouldSync = options.sync ~= false
        and type(syncSettings) == "table"
        and syncSettings[index] == true

    for targetIndex = 1, MAX_WINDOWS do
        if targetIndex == index
            or shouldSync and syncSettings[targetIndex] == true
        then
            if windows[targetIndex] then
                CloseWindowDetails(windows[targetIndex], true)
            end
            SetWindowSessionState(
                config,
                targetIndex,
                mode,
                sessionID
            )
            if windows[targetIndex] then
                windows[targetIndex].sessionKey =
                    GetSessionKey(mode, sessionID)
                windows[targetIndex].sessionDropdown:SetSelectedValue(
                    windows[targetIndex].sessionKey
                )
            end
        end
    end

    if options.refresh ~= false and rendererEnabled then
        Renderer.Refresh()
    end
    return true
end

local function SelectWindowSession(index, key)
    EnsureSessionItems()
    local selection = sessionSelections[key]
    if not selection then return end

    Renderer.SetWindowSession(
        index,
        selection.mode,
        selection.sessionID
    )
end

ScrollWindow = function(window, delta)
    if not rendererEnabled or window.minimized then return end

    local definition = GetWindowDefinition(window.index)
    local typeName = definition.enumName
    local offset = GetScrollOffset(window, typeName)
    local maximum = GetMaximumScrollOffset(window, typeName)
    local nextOffset = offset
    if delta < 0 then
        nextOffset = offset + 1
    elseif delta > 0 then
        nextOffset = offset - 1
    end
    nextOffset = Clamp(nextOffset, 0, maximum)
    if nextOffset == offset then return end

    SetScrollOffset(window, typeName, nextOffset)
    Renderer.Refresh()
end

local function CreateWindow(index)
    local window = AF.CreateBorderedFrame(
        _G.UIParent,
        "BFIDamageMeterWindow" .. index,
        300,
        220,
        "background",
        "border"
    )
    window.index = index
    window.rows = {}
    window.sessionKey = DEFAULT_SESSION_KEY
    window.scrollOffsets = {}
    window.maxScrollOffsets = {}
    window.detailOffset = 0
    window.detailMaxOffset = 0
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetFrameStrata("LOW")
    window:SetScript("OnSizeChanged", function(_, width, height)
        OnWindowSizeChanged(window, width, height)
    end)

    local header = AF.CreateFrame(window)
    window.header = header
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        BeginWindowDrag(window)
    end)
    header:SetScript("OnDragStop", function()
        FinishWindowDrag(window)
    end)

    local typeDropdown = AF.CreateDropdown(header, 140, 11)
    window.typeDropdown = typeDropdown
    ApplyFlatDropdownStyle(typeDropdown)
    typeDropdown:SetItems(GetTypeItems())
    typeDropdown:SetOnSelect(function(typeName)
        Renderer.SetWindowType(index, typeName)
    end)

    local sessionDropdown = AF.CreateDropdown(
        header,
        SESSION_DROPDOWN_WIDTH,
        11
    )
    window.sessionDropdown = sessionDropdown
    ApplyFlatDropdownStyle(sessionDropdown)
    EnsureSessionItems()
    sessionDropdown:SetItems(sessionItems)
    sessionDropdown:SetOnSelect(function(key)
        SelectWindowSession(index, key)
    end)
    sessionDropdown.button:HookScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            RefreshSessionDropdownItems()
        end
    end)

    local dragGrip = AF.CreateButton(
        header,
        nil,
        "BFI_hover",
        18,
        18,
        nil,
        "",
        ""
    )
    window.dragGrip = dragGrip
    SetButtonIcon(dragGrip, AF.GetIcon("Link"), "gray")
    dragGrip:RegisterForDrag("LeftButton")
    dragGrip:SetScript("OnDragStart", function()
        BeginWindowDrag(window)
    end)
    dragGrip:SetScript("OnDragStop", function()
        FinishWindowDrag(window)
    end)
    AF.SetTooltip(
        dragGrip,
        "TOPLEFT",
        0,
        2,
        L["Dock Meter"],
        L[
            "Drag this window on top to another highlighted window and release to anchor it"
        ]
    )

    local minimize = AF.CreateButton(
        header,
        nil,
        "BFI_hover",
        18,
        18,
        nil,
        "",
        ""
    )
    window.minimize = minimize
    SetButtonIcon(minimize, AF.GetIcon("Minus_Small"))
    AF.SetTooltip(
        minimize,
        "TOPRIGHT",
        0,
        2,
        _G.MINIMIZE or "Minimize",
        L["Collapse or expand this meter."]
    )
    minimize:SetOnClick(function()
        ToggleMinimized(window)
    end)

    local settings = AF.CreateButton(
        header,
        nil,
        "BFI_hover",
        18,
        18,
        nil,
        "",
        ""
    )
    window.settings = settings
    SetButtonIcon(settings, AF.GetIcon("Settings"))
    AF.SetTooltip(
        settings,
        "TOPRIGHT",
        0,
        2,
        _G.SETTINGS or "Settings",
        L["Open BFI Damage Meter Settings"]
    )
    settings:SetOnClick(function()
        if type(F.OpenOptionsFrame) == "function" then
            F.OpenOptionsFrame("damageMeter")
        end
    end)

    local lock = AF.CreateButton(
        header,
        nil,
        "BFI_hover",
        18,
        18,
        nil,
        "",
        ""
    )
    window.lock = lock
    SetButtonIcon(lock, GetLockButtonIcon(false))
    AF.SetTooltip(
        lock,
        "TOPRIGHT",
        0,
        2,
        L["Lock Meters"],
        L[
            "Prevent moving, docking, and resizing meter windows."
        ]
    )
    lock:SetOnClick(ToggleLocked)

    local body = AF.CreateFrame(window)
    window.body = body
    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(_, delta)
        ScrollWindow(window, delta)
    end)
    CreateDetailPanel(window)

    local resize = AF.CreateResizeButton(
        window,
        MIN_WINDOW_WIDTH,
        MIN_WINDOW_HEIGHT,
        MAX_WINDOW_WIDTH,
        MAX_WINDOW_HEIGHT
    )
    window.resize = resize
    AF.SetTooltip(
        resize,
        "TOPRIGHT",
        0,
        2,
        L["Resize Meter"],
        L[
            "Drag to resize this meter. Width is shared; height is saved per window."
        ]
    )
    resize:HookScript("OnMouseDown", function()
        window.isResizing = true
    end)
    resize:HookScript("OnMouseUp", function()
        window.isResizing = nil
        FinishWindowResize(window)
    end)

    local dockPreview = AF.CreateFrame(
        _G.UIParent,
        nil,
        nil,
        nil,
        "BackdropTemplate"
    )
    window.dockPreview = dockPreview
    dockPreview:SetFrameStrata("TOOLTIP")
    AF.ApplyDefaultBackdrop(dockPreview)
    dockPreview:SetBackdropColor(AF.GetColorRGB("BFI", 0.24))
    dockPreview:SetBackdropBorderColor(AF.GetColorRGB("BFI"))
    dockPreview:Hide()

    windows[index] = window
    return window
end

local function EnsureWindows()
    for index = 1, MAX_WINDOWS do
        if not windows[index] then
            CreateWindow(index)
        end
    end
end

local function GetVisibleRowCount(config, windowHeight)
    local bodyHeight = windowHeight - config.headerHeight
        - (config.padding * 2)
    return math.max(
        1,
        math.floor(
            (bodyHeight + config.spacing)
                / (config.barHeight + config.spacing)
        )
    )
end

local function GetHeightForRowCount(config, rowCount)
    if rowCount <= 0 then
        return config.headerHeight
    end

    return config.headerHeight
        + (config.padding * 2)
        + (rowCount * config.barHeight)
        + ((rowCount - 1) * config.spacing)
end

local function GetObjectiveTrackerLaneHeight(config)
    if not config.dockToObjectiveTracker
        or not _G.ObjectiveTrackerFrame
    then
        return false
    end

    for index = 1, config.windowCount do
        if not IsDefaultAnchor(config.windowAnchors[index], index) then
            return false
        end
    end

    local target = GetObjectiveTrackerDockTarget(
        _G.ObjectiveTrackerFrame
    )
    local uiParent = _G.UIParent
    if not target
        or type(target.GetBottom) ~= "function"
        or not uiParent
        or type(uiParent.GetEffectiveScale) ~= "function"
    then
        return true, nil, target
    end

    local bottom = target:GetBottom()
    local uiScale = uiParent:GetEffectiveScale()
    local targetScale
    if type(target.GetEffectiveScale) == "function" then
        targetScale = target:GetEffectiveScale()
    else
        targetScale = uiScale
    end
    if not F.isValueNonSecret(bottom)
        or not F.isValueNonSecret(uiScale)
        or not F.isValueNonSecret(targetScale)
        or type(bottom) ~= "number"
        or type(uiScale) ~= "number"
        or uiScale <= 0
        or type(targetScale) ~= "number"
        or targetScale <= 0
    then
        return true, nil, target
    end

    local uiBottom = 0
    if type(uiParent.GetBottom) == "function" then
        uiBottom = uiParent:GetBottom()
    end
    if not F.isValueNonSecret(uiBottom)
        or type(uiBottom) ~= "number"
    then
        return true, nil, target
    end

    return true, math.max(
        0,
        math.floor(
            (bottom * targetScale / uiScale)
                - uiBottom
                - OBJECTIVE_TRACKER_GAP
        )
    ), target
end

local function GetRuntimeWindowLayout(config)
    local usesTrackerLane, availableHeight, target =
        GetObjectiveTrackerLaneHeight(config)
    local layout = {
        availableHeight = availableHeight,
        target = target,
        usesTrackerLane = usesTrackerLane
            and type(availableHeight) == "number",
        windows = {},
    }
    local desiredTotal = math.max(0, config.windowCount - 1)
        * WINDOW_GAP

    for index = 1, MAX_WINDOWS do
        local window = windows[index]
        local savedHeight = GetWindowHeight(config, index)
        local minimized = window.minimized == true
        local height = minimized and config.headerHeight or savedHeight
        local rows = minimized and 0
            or GetVisibleRowCount(config, savedHeight)
        layout.windows[index] = {
            height = height,
            hidden = false,
            rows = rows,
        }
        if index <= config.windowCount then
            desiredTotal = desiredTotal + height
        end
    end

    if type(availableHeight) ~= "number"
        or desiredTotal <= availableHeight
    then
        return layout
    end

    -- Retail PTR 12.1.0.68914, jdtoppin/wow-ui-source commit
    -- d3915c78: a default-position Objective Tracker owns nearly the full
    -- right-managed column and ignores its Edit Mode height value. Fit only
    -- BFI-owned meter rows into the remaining lane; saved dimensions and
    -- Blizzard's protected tracker geometry remain untouched.
    local activeCount = config.windowCount
    local baseHeight = activeCount * config.headerHeight
        + math.max(0, activeCount - 1) * WINDOW_GAP
    while activeCount > 0 and baseHeight > availableHeight do
        activeCount = activeCount - 1
        baseHeight = activeCount * config.headerHeight
            + math.max(0, activeCount - 1) * WINDOW_GAP
    end

    for index = 1, config.windowCount do
        local runtime = layout.windows[index]
        runtime.height = config.headerHeight
        runtime.hidden = index > activeCount
        runtime.rows = 0
    end

    local remainingHeight = math.max(0, availableHeight - baseHeight)
    local allocated
    repeat
        allocated = false
        for index = 1, activeCount do
            local window = windows[index]
            local runtime = layout.windows[index]
            local desiredRows = window.minimized and 0
                or GetVisibleRowCount(
                    config,
                    GetWindowHeight(config, index)
                )
            if runtime.rows < desiredRows then
                local rowCost = runtime.rows == 0
                    and (config.padding * 2) + config.barHeight
                    or config.barHeight + config.spacing
                if rowCost <= remainingHeight then
                    runtime.rows = runtime.rows + 1
                    remainingHeight = remainingHeight - rowCost
                    allocated = true
                end
            end
        end
    until not allocated

    for index = 1, activeCount do
        local runtime = layout.windows[index]
        runtime.height = GetHeightForRowCount(config, runtime.rows)
    end

    return layout
end

local function ApplyWindowLayout(window, config, runtime)
    local definition = GetWindowDefinition(window.index)
    local sessionMode, sessionID =
        GetWindowSessionSelection(config, window.index)
    local controlSize = math.max(14, math.min(20, config.headerHeight - 4))
    local savedHeight = GetWindowHeight(config, window.index)
    local windowHeight = runtime and runtime.height or savedHeight
    local visibleRows = runtime and runtime.rows
        or GetVisibleRowCount(config, windowHeight)
    local effectiveMinimized = window.minimized or visibleRows == 0
    local texture = AF.LSM_GetBarTexture(config.texture)
    if not texture then
        texture = (BFI.media and BFI.media.bar) or AF.GetPlainTexture()
    end

    window.runtimeHidden = runtime and runtime.hidden or false
    window.runtimeMinimized = not window.minimized and visibleRows == 0
    window.runtimeConstrained = not window.minimized
        and (window.runtimeHidden or windowHeight < savedHeight)
    window.visibleRowCount = visibleRows
    if window.resize
        and type(window.resize.SetMinHeight) == "function" then
        window.resize:SetMinHeight(GetMinimumWindowHeight(config))
    end
    window.applyingLayout = true
    window:SetSize(
        config.width,
        effectiveMinimized and config.headerHeight or windowHeight
    )
    window.applyingLayout = nil
    window:SetResizable(
        not config.locked
            and not effectiveMinimized
            and not window.runtimeConstrained
    )
    window:SetBackdropColor(
        AF.GetColorRGB("background", config.backgroundAlpha)
    )
    window:SetBackdropBorderColor(AF.GetColorRGB("border"))

    window.header:ClearAllPoints()
    window.header:SetPoint("TOPLEFT")
    window.header:SetPoint("TOPRIGHT")
    window.header:SetHeight(config.headerHeight)

    window.minimize:SetSize(controlSize, controlSize)
    window.minimize:ClearAllPoints()
    window.minimize:SetPoint("RIGHT", window.header, "RIGHT", -2, 0)
    SetButtonIcon(
        window.minimize,
        AF.GetIcon(effectiveMinimized and "Plus_Small" or "Minus_Small")
    )

    window.settings:SetSize(controlSize, controlSize)
    window.settings:ClearAllPoints()
    window.settings:SetPoint("RIGHT", window.minimize, "LEFT", -2, 0)

    window.lock:SetSize(controlSize, controlSize)
    window.lock:ClearAllPoints()
    window.lock:SetPoint("RIGHT", window.settings, "LEFT", -2, 0)
    SetButtonIcon(
        window.lock,
        GetLockButtonIcon(config.locked),
        config.locked and "white" or "gray"
    )
    AF.SetTooltip(
        window.lock,
        "TOPRIGHT",
        0,
        2,
        config.locked and L["Unlock Meters"] or L["Lock Meters"],
        config.locked
            and L[
                "Allow moving, docking, and resizing meter windows."
            ]
            or L[
                "Prevent moving, docking, and resizing meter windows."
            ]
    )

    window.dragGrip:SetSize(controlSize, controlSize)
    window.dragGrip:ClearAllPoints()
    window.dragGrip:SetPoint("LEFT", window.header, "LEFT", 2, 0)
    SetButtonIcon(
        window.dragGrip,
        AF.GetIcon("Link"),
        config.locked and "gray" or "white"
    )

    window.sessionKey = GetSessionKey(sessionMode, sessionID)
    window.sessionDropdown:SetItems(sessionItems)
    local availableDropdownWidth = config.width
        - 17
        - (controlSize * 4)
    window.sessionDropdown:SetWidth(Clamp(
        availableDropdownWidth - MIN_TYPE_DROPDOWN_WIDTH,
        MIN_SESSION_DROPDOWN_WIDTH,
        SESSION_DROPDOWN_WIDTH
    ))
    window.sessionDropdown:ClearAllPoints()
    window.sessionDropdown:SetPoint(
        "RIGHT",
        window.lock,
        "LEFT",
        -3,
        0
    )
    window.sessionDropdown:SetHeight(controlSize)
    window.sessionDropdown:SetSelectedValue(window.sessionKey)

    window.typeDropdown:ClearAllPoints()
    window.typeDropdown:SetPoint(
        "LEFT",
        window.dragGrip,
        "RIGHT",
        3,
        0
    )
    window.typeDropdown:SetPoint(
        "RIGHT",
        window.sessionDropdown,
        "LEFT",
        -3,
        0
    )
    window.typeDropdown:SetHeight(controlSize)
    window.typeDropdown:SetSelectedValue(definition.enumName)

    window.resize:SetShown(
        not config.locked
            and not effectiveMinimized
            and not window.runtimeConstrained
    )

    window.body:ClearAllPoints()
    window.body:SetPoint("TOPLEFT", window.header, "BOTTOMLEFT")
    window.body:SetPoint("BOTTOMRIGHT")
    window.body:SetShown(not effectiveMinimized)

    EnsureRows(window, visibleRows)
    ApplyDetailLayout(window, config, texture)
    window.detailPanel:SetShown(
        window.detailOpen == true and not effectiveMinimized
    )
    for index, row in ipairs(window.rows) do
        row.hoverCard:Hide()
        row.highlight:Hide()
        if index <= visibleRows then
            ApplyRowLayout(row, index, config, texture, definition)
        else
            row:Hide()
        end
    end
end

local function ReflowWindows(config, closeDetails)
    local runtimeLayout = GetRuntimeWindowLayout(config)
    lastObjectiveTrackerLaneBudget = runtimeLayout.usesTrackerLane
        and runtimeLayout.availableHeight
        or false
    lastObjectiveTrackerLaneTarget = runtimeLayout.target
    for index = 1, MAX_WINDOWS do
        local window = windows[index]
        if closeDetails then
            CloseWindowDetails(window, true)
        end
        ApplyWindowLayout(
            window,
            config,
            runtimeLayout.windows[index]
        )
        window:SetClampedToScreen(
            not (
                runtimeLayout.usesTrackerLane
                    and index <= config.windowCount
            )
        )
    end
    ApplyAllAnchors(config)
end

local function RefreshObjectiveTrackerLane()
    local config = GetConfig()
    if not rendererEnabled or not config.dockToObjectiveTracker then return end

    for _, window in ipairs(windows) do
        if window.isDragging or window.isResizing then return end
    end

    local usesTrackerLane, availableHeight, target =
        GetObjectiveTrackerLaneHeight(config)
    local budget = usesTrackerLane
        and type(availableHeight) == "number"
        and availableHeight
        or false
    if budget == lastObjectiveTrackerLaneBudget
        and target == lastObjectiveTrackerLaneTarget
    then
        return
    end

    ReflowWindows(config)
    Renderer.Refresh()
end

local function HideWindowTransient(window)
    CloseWindowDetails(window, true)
    for _, row in ipairs(window.rows) do
        row.deathRecapID = nil
        row.sourceIndex = nil
        row.hoverCard:Hide()
        row.highlight:Hide()
    end
end

local function HideUnusedRows(window, firstUnused)
    for index = firstUnused, #window.rows do
        local row = window.rows[index]
        row.deathRecapID = nil
        row.sourceIndex = nil
        row:Hide()
        row.hoverCard:Hide()
        row.highlight:Hide()
    end
end

local function UpdateSourceIcon(row, specIconID, classFilename)
    if row.showIcon ~= true then
        row.icon:SetTexture(nil)
        row.iconHolder:Hide()
        return
    end

    if specIconID and specIconID ~= 0 then
        row.icon:SetTexture(specIconID)
        AF.ApplyDefaultTexCoord(row.icon)
        row.iconHolder:Show()
        return
    end

    local getClassAtlas = _G.GetClassAtlas
    if classFilename and classFilename ~= ""
        and type(getClassAtlas) == "function"
    then
        local classAtlas = getClassAtlas(classFilename)
        if classAtlas then
            row.icon:SetAtlas(classAtlas, false, nil, true)
            row.iconHolder:Show()
            return
        end
    end

    row.icon:SetTexture(nil)
    row.iconHolder:Hide()
end

local function UpdateRow(row, source, index, session, config)
    local r, g, b
    if config.classColor then
        r, g, b = AF.GetClassColor(source.classFilename)
    else
        r, g, b = AF.GetColorRGB("BFI")
    end

    row.bar:SetStatusBarColor(r, g, b, config.barAlpha)
    row.hoverCard.shareBar:SetStatusBarColor(r, g, b, config.barAlpha)
    row.iconHolder:SetBackdropBorderColor(r, g, b, 1)
    row.hoverCard:SetBackdropBorderColor(r, g, b, 1)
    row.rank:SetText(index)
    UpdateSourceIcon(row, source.specIconID, source.classFilename)
    row.name:SetText(_G.Ambiguate(source.name, "short"))
    row.hoverCard.title:SetText(_G.Ambiguate(source.name, "short"))
    row.hoverCard.playerBadge:SetShown(source.isLocalPlayer == true)
    row.deathRecapID = source.deathRecapID
    row.sourceIndex = index
    row.hoverCard.groupTotalValue:SetText(
        AF.FormatSecretNumber(session.totalAmount)
    )
    row.hoverCard.shareBar:SetMinMaxValues(0, session.totalAmount)
    row.hoverCard.shareBar:SetValue(source.totalAmount)

    if row.showTotal then
        row.total:SetText(AF.FormatSecretNumber(source.totalAmount))
        row.hoverCard.totalValue:SetText(
            AF.FormatSecretNumber(source.totalAmount)
        )
    else
        row.hoverCard.totalValue:SetText(
            AF.FormatSecretNumber(source.totalAmount)
        )
    end
    if row.showPerSecond then
        row.perSecond:SetText(
            AF.FormatSecretNumber(source.amountPerSecond)
        )
        row.hoverCard.perSecondValue:SetText(
            AF.FormatSecretNumber(source.amountPerSecond)
        )
    elseif not row.suppressValuePerSecond then
        row.hoverCard.perSecondValue:SetText(
            AF.FormatSecretNumber(source.amountPerSecond)
        )
    end
end

local function GetSourceDisplayState(session, alwaysShowLocalPlayer)
    local sourceCount = 0
    local localPlayerIndex
    for index, source in ipairs(session.combatSources) do
        sourceCount = index
        -- Retail PTR 12.1.0.68914 marks isLocalPlayer NeverSecret in
        -- DamageMeterDocumentation.lua (Gethe commit d3915c78). Only this
        -- boolean and the non-secret iteration index are retained.
        if alwaysShowLocalPlayer and source.isLocalPlayer then
            localPlayerIndex = index
        end
    end
    return sourceCount, localPlayerIndex
end

local function ShowSourceRow(
    window,
    rowIndex,
    session,
    sourceIndex,
    config
)
    local row = window.rows[rowIndex]
    local source = session.combatSources[sourceIndex]
    row.bar:SetMinMaxValues(0, session.maxAmount)
    row.bar:SetValue(source.totalAmount)
    UpdateRow(row, source, sourceIndex, session, config)
    row:Show()
end

local function UpdateWindow(window, config)
    if window.minimized or window.runtimeMinimized then return end

    if window.detailOpen then
        if RefreshWindowDetails(window) then
            return
        end
        CloseWindowDetails(window, true)
    end

    local definition = GetWindowDefinition(window.index)
    local meterType = GetMeterType(definition)
    if meterType == nil then
        HideUnusedRows(window, 1)
        return
    end

    local sessionMode, sessionID =
        GetWindowSessionSelection(config, window.index)
    window.sessionKey = GetSessionKey(sessionMode, sessionID)
    window.sessionDropdown:SetSelectedValue(window.sessionKey)
    local session = GetSessionData(sessionMode, sessionID, meterType)
    if (not session or not session.combatSources)
        and sessionMode == SESSION_MODE_HISTORY
    then
        ClearRuntimeHistoricalSession(window.index)
        sessionMode, sessionID = GetWindowSessionSelection(
            config,
            window.index
        )
        window.sessionKey = GetSessionKey(sessionMode, sessionID)
        window.sessionDropdown:SetSelectedValue(window.sessionKey)
        session = GetSessionData(sessionMode, sessionID, meterType)
    end
    if not session or not session.combatSources then
        HideUnusedRows(window, 1)
        return
    end
    local sourceCount, localPlayerIndex = GetSourceDisplayState(
        session,
        config.alwaysShowPlayer == true
            and definition.alwaysShowLocalPlayer
            and window.visibleRowCount > 1
    )
    local typeName = definition.enumName
    local maximumOffset = math.max(
        0,
        sourceCount - window.visibleRowCount
    )
    if localPlayerIndex and localPlayerIndex <= maximumOffset then
        maximumOffset = maximumOffset + 1
    end
    local offset = Clamp(
        GetScrollOffset(window, typeName),
        0,
        maximumOffset
    )
    SetScrollOffset(window, typeName, offset)
    SetMaximumScrollOffset(window, typeName, maximumOffset)

    local firstSource = offset + 1
    local naturalLastSource = math.min(
        sourceCount,
        firstSource + window.visibleRowCount - 1
    )
    local pinBefore = localPlayerIndex
        and localPlayerIndex < firstSource
    local pinAfter = localPlayerIndex
        and localPlayerIndex > naturalLastSource
    local sourceSlots = window.visibleRowCount
        - ((pinBefore or pinAfter) and 1 or 0)
    local lastSource = math.min(
        sourceCount,
        firstSource + sourceSlots - 1
    )
    local used = 0

    if pinBefore then
        used = used + 1
        ShowSourceRow(
            window,
            used,
            session,
            localPlayerIndex,
            config
        )
    end

    for sourceIndex = firstSource, lastSource do
        used = used + 1
        ShowSourceRow(window, used, session, sourceIndex, config)
    end

    if pinAfter then
        used = used + 1
        ShowSourceRow(
            window,
            used,
            session,
            localPlayerIndex,
            config
        )
    end

    HideUnusedRows(window, used + 1)
end

local function ResetScrollOffsets()
    for _, window in ipairs(windows) do
        window.scrollOffsets = {}
        window.maxScrollOffsets = {}
    end
end

local function ResetCurrentSessionScrollOffsets()
    for _, window in ipairs(windows) do
        window.scrollOffsets[SESSION_MODE_CURRENT] = nil
        window.maxScrollOffsets[SESSION_MODE_CURRENT] = nil
    end
end

local function CloseAllWindowDetails()
    for _, window in ipairs(windows) do
        CloseWindowDetails(window, true)
    end
end

function Renderer.ResetPosition()
    local config = GetConfig()
    EnsureInteractionConfig(config)
    config.dockToObjectiveTracker = true
    for index = 1, MAX_WINDOWS do
        SetAnchorRecord(config, index, GetDefaultAnchor(index))
    end

    if not windows[1] then
        resetPositionPending = true
        return true
    end

    ClearDockPreview()
    if rendererEnabled then
        Renderer.ApplySettings()
    else
        ApplyAllAnchors(config)
    end
    resetPositionPending = nil
    return true
end

function Renderer.Refresh()
    if not rendererEnabled then return false end
    if not DM.Data.IsAvailable() then
        for _, window in ipairs(windows) do
            FinishWindowDrag(window)
            HideWindowTransient(window)
            window:Hide()
        end
        ClearDockPreview()
        EndNativeOverride()
        return false
    end

    BeginNativeOverride()
    local config = GetConfig()
    if sessionItemsDirty then
        ValidateHistoricalSelections(config)
        for _, window in ipairs(windows) do
            window.sessionDropdown:SetItems(sessionItems)
        end
    end
    for index = 1, MAX_WINDOWS do
        local window = windows[index]
        local shouldShow = index <= config.windowCount
            and not window.runtimeHidden
        if not shouldShow then
            HideWindowTransient(windows[index])
        end
        window:SetShown(shouldShow)
    end
    for index = 1, config.windowCount do
        local window = windows[index]
        if not window.runtimeHidden then
            UpdateWindow(window, config)
        end
    end
    return true
end

local function ScheduleRefresh()
    if refreshTimer then return end

    refreshTimer = _G.C_Timer.NewTimer(REFRESH_DELAY, function()
        refreshTimer = nil
        Renderer.Refresh()
    end)
end

local function EnsureEventFrame()
    if eventFrame then return end

    eventFrame = _G.CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" then
            local addonName = ...
            if addonName == "Blizzard_ObjectiveTracker"
                and GetConfig().dockToObjectiveTracker
            then
                RefreshObjectiveTrackerLane()
            end
        elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
            RefreshObjectiveTrackerLane()
        elseif event == "PLAYER_LOGOUT" then
            CloseAllWindowDetails()
            EndNativeOverride()
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Source-detail APIs become secret in combat. Tear down every
            -- report before returning to the combat-safe aggregate renderer.
            CloseAllWindowDetails()
            Renderer.Refresh()
        else
            -- Retail PTR 12.1.0.68914 FrameXML retains scroll for
            -- DAMAGE_METER_COMBAT_SESSION_UPDATED, but discards Current
            -- scroll when DAMAGE_METER_CURRENT_SESSION_UPDATED replaces the
            -- active session identity (Gethe commit d3915c78).
            if event == "DAMAGE_METER_CURRENT_SESSION_UPDATED"
                or event == "PLAYER_ENTERING_WORLD"
            then
                sessionItemsDirty = true
            end
            if event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
                CloseAllWindowDetails()
                ResetCurrentSessionScrollOffsets()
            end
            if event == "DAMAGE_METER_RESET" then
                CloseAllWindowDetails()
                sessionItemsDirty = true
                ResetHistoricalSelections()
                ResetScrollOffsets()
            end
            if event == "PLAYER_ENTERING_WORLD" then
                CloseAllWindowDetails()
            end
            ScheduleRefresh()
        end
    end)
end

local function RegisterEvents()
    EnsureEventFrame()
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    eventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    eventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
    eventFrame:RegisterEvent("DAMAGE_METER_RESET")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
end

local function UnregisterEvents()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if refreshTimer then
        refreshTimer:Cancel()
        refreshTimer = nil
    end
end

function Renderer.ApplySettings()
    if not rendererEnabled then return false end

    EnsureWindows()
    local config = GetConfig()
    EnsureInteractionConfig(config)
    ValidateHistoricalSelections(config)
    ReflowWindows(config, true)
    for index = 1, MAX_WINDOWS do
        windows[index]:Hide()
    end
    Renderer.Refresh()
    return true
end

function Renderer.SetEnabled(enabled)
    if enabled then
        if rendererEnabled then
            return Renderer.ApplySettings()
        end

        rendererEnabled = true
        sessionItemsDirty = true
        EnsureWindows()
        EnsureInteractionConfig(GetConfig())
        if resetPositionPending then
            Renderer.ResetPosition()
        end
        RegisterEvents()
        Renderer.ApplySettings()
        return true
    end

    rendererEnabled = nil
    UnregisterEvents()
    for _, window in ipairs(windows) do
        FinishWindowDrag(window)
        HideWindowTransient(window)
        window:Hide()
    end
    ClearDockPreview()
    EndNativeOverride()
    return true
end

function Renderer.IsEnabled()
    return rendererEnabled == true
end

AF.RegisterCallback("BFI_ObjectiveTrackerDockFrameChanged", function()
    RefreshObjectiveTrackerLane()
end)
