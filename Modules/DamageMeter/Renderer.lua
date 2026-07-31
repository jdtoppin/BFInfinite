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
local REFRESH_DELAY = 0.1
local NATIVE_RESTORE_KEY = "damageMeterNativeEnabledBeforeBFI"
local MIN_WINDOW_WIDTH = 220
local MAX_WINDOW_WIDTH = 520
local MIN_WINDOW_HEIGHT = 120
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
local ScrollWindow
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

local function GetDefaultAnchor(index)
    if index == 1 then
        return {
            relativeTo = 0,
            point = "BOTTOMRIGHT",
            relativePoint = "BOTTOMRIGHT",
            x = -WINDOW_INSET,
            y = WINDOW_INSET,
        }
    end

    return {
        relativeTo = index - 1,
        point = "BOTTOMRIGHT",
        relativePoint = "TOPRIGHT",
        x = 0,
        y = WINDOW_GAP,
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
        MIN_WINDOW_HEIGHT,
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

local function SetButtonIcon(button, icon, color)
    button:SetTexture(icon, {12, 12}, {"CENTER", 0, 0})
    button:SetTextureColor(color or "white")
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
    recapHint:SetText(L["Click for Death Recap"])
    recapHint:SetJustifyH("LEFT")

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
    rank:SetJustifyH("RIGHT")
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

        local deathRecapID = row.deathRecapID
        if deathRecapID
            and deathRecapID ~= 0
            and type(_G.OpenDeathRecapUI) == "function"
        then
            _G.OpenDeathRecapUI(deathRecapID)
        end
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

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", config.padding, y)
    row:SetPoint("TOPRIGHT", row:GetParent(), "TOPRIGHT", -config.padding, y)
    row:SetHeight(barHeight)

    row.bar:SetStatusBarTexture(texture)

    row.rank:ClearAllPoints()
    row.rank:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.rank:SetWidth(20)

    local iconSize = barHeight - 4
    row.iconHolder:ClearAllPoints()
    row.iconHolder:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)
    row.iconHolder:SetSize(iconSize, iconSize)
    row.iconHolder:SetShown(showIcon)

    row.name:ClearAllPoints()
    if showIcon then
        row.name:SetPoint("LEFT", row.iconHolder, "RIGHT", 4, 0)
    else
        row.name:SetPoint("LEFT", row.rank, "RIGHT", 5, 0)
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
    row.hoverCard.groupTotalLabel:ClearAllPoints()
    row.hoverCard.groupTotalValue:ClearAllPoints()
    row.hoverCard.recapHint:ClearAllPoints()
    if definition.suppressValuePerSecond then
        row.hoverCard.groupTotalLabel:SetPoint(
            "TOPLEFT",
            row.hoverCard.totalLabel,
            "BOTTOMLEFT",
            0,
            -7
        )
        row.hoverCard.groupTotalValue:SetPoint(
            "TOPRIGHT",
            row.hoverCard,
            "TOPRIGHT",
            -8,
            -49
        )
        row.hoverCard.recapHint:SetPoint(
            "TOPLEFT",
            row.hoverCard.groupTotalLabel,
            "BOTTOMLEFT",
            0,
            -7
        )
        row.hoverCard:SetHeight(90)
    else
        row.hoverCard.groupTotalLabel:SetPoint(
            "TOPLEFT",
            row.hoverCard.perSecondLabel,
            "BOTTOMLEFT",
            0,
            -7
        )
        row.hoverCard.groupTotalValue:SetPoint(
            "TOPRIGHT",
            row.hoverCard,
            "TOPRIGHT",
            -8,
            -69
        )
        row.hoverCard.recapHint:SetPoint(
            "TOPLEFT",
            row.hoverCard.groupTotalLabel,
            "BOTTOMLEFT",
            0,
            -7
        )
        row.hoverCard:SetHeight(110)
    end
    row.hoverCard.shareBar:SetStatusBarTexture(texture)
    row.showTotal = showTotal
    row.showPerSecond = showPerSecond
    row.suppressValuePerSecond = definition.suppressValuePerSecond
end

local function ToggleMinimized(window)
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
        local relativeTo = anchor.relativeTo == 0
            and _G.UIParent
            or windows[anchor.relativeTo]
        local window = windows[index]
        window:ClearAllPoints()
        window:SetPoint(
            anchor.point,
            relativeTo,
            anchor.relativePoint,
            anchor.x,
            anchor.y
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
    if activeDockTarget == target
        and activeDockDirection == direction
    then
        return
    end

    ClearDockPreview()
    local preview = target.dockPreview
    if direction == "above" then
        preview:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        preview:SetPoint("BOTTOMRIGHT", target, "RIGHT", 0, 0)
    else
        preview:SetPoint("TOPLEFT", target, "LEFT", 0, 0)
        preview:SetPoint(
            "BOTTOMRIGHT",
            target,
            "BOTTOMRIGHT",
            0,
            0
        )
    end
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
    ApplyAllAnchors(config)
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
    if window.applyingLayout or window.minimized then return end

    local config = GetConfig()
    EnsureInteractionConfig(config)
    ApplySharedWidth(window, width)
    config.windowHeights[window.index] = Clamp(
        math.floor(height + 0.5),
        MIN_WINDOW_HEIGHT,
        MAX_WINDOW_HEIGHT
    )
end

local function FinishWindowResize(window)
    if GetConfig().locked or window.minimized then return end
    OnWindowSizeChanged(window, window:GetWidth(), window:GetHeight())
    Renderer.ApplySettings()
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
    local window = AF.CreateFrame(
        _G.UIParent,
        "BFIDamageMeterWindow" .. index,
        300,
        220,
        "BackdropTemplate"
    )
    window.index = index
    window.rows = {}
    window.sessionKey = DEFAULT_SESSION_KEY
    window.scrollOffsets = {}
    window.maxScrollOffsets = {}
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetFrameStrata("LOW")
    AF.ApplyDefaultBackdrop_NoBackground(window)
    window:SetScript("OnSizeChanged", function(_, width, height)
        OnWindowSizeChanged(window, width, height)
    end)

    local header = AF.CreateBorderedFrame(
        window,
        nil,
        nil,
        nil,
        "header",
        "border"
    )
    window.header = header
    header.tex = AF.CreateGradientTexture(
        header,
        "HORIZONTAL",
        AF.GetColorTable("BFI", 0.4),
        AF.GetColorTable("BFI", 0),
        nil,
        "ARTWORK"
    )
    AF.SetOnePixelInside(header.tex, header)
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
    SetButtonIcon(dragGrip, AF.GetIcon("Menu3"), "gray")
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
            "Release to anchor this meter to the highlighted window."
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
    SetButtonIcon(lock, AF.GetIcon("SmallLock"))
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

    local body = AF.CreateFrame(
        window,
        nil,
        nil,
        nil,
        "BackdropTemplate"
    )
    window.body = body
    AF.ApplyDefaultBackdrop_NoBorder(body)
    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(_, delta)
        ScrollWindow(window, delta)
    end)

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
    resize:HookScript("OnMouseUp", function()
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

local function ApplyWindowLayout(window, config)
    local definition = GetWindowDefinition(window.index)
    local sessionMode, sessionID =
        GetWindowSessionSelection(config, window.index)
    local controlSize = math.max(14, math.min(20, config.headerHeight - 4))
    local windowHeight = GetWindowHeight(config, window.index)
    local visibleRows = GetVisibleRowCount(config, windowHeight)
    local texture = AF.LSM_GetBarTexture(config.texture)
    if not texture then
        texture = (BFI.media and BFI.media.bar) or AF.GetPlainTexture()
    end

    window.visibleRowCount = visibleRows
    window.applyingLayout = true
    window:SetSize(
        config.width,
        window.minimized and config.headerHeight or windowHeight
    )
    window.applyingLayout = nil
    window:SetResizable(not config.locked and not window.minimized)
    window:SetBackdropBorderColor(AF.GetColorRGB("border"))

    window.header:ClearAllPoints()
    window.header:SetPoint("TOPLEFT")
    window.header:SetPoint("TOPRIGHT")
    window.header:SetHeight(config.headerHeight)
    window.header:SetBackdropColor(AF.GetColorRGB("header"))
    window.header:SetBackdropBorderColor(AF.GetColorRGB("border"))
    window.header.tex:SetShown(config.accentHeader)

    window.minimize:SetSize(controlSize, controlSize)
    window.minimize:ClearAllPoints()
    window.minimize:SetPoint("RIGHT", window.header, "RIGHT", -2, 0)
    SetButtonIcon(
        window.minimize,
        AF.GetIcon(window.minimized and "Plus_Small" or "Minus_Small")
    )

    window.settings:SetSize(controlSize, controlSize)
    window.settings:ClearAllPoints()
    window.settings:SetPoint("RIGHT", window.minimize, "LEFT", -2, 0)

    window.lock:SetSize(controlSize, controlSize)
    window.lock:ClearAllPoints()
    window.lock:SetPoint("RIGHT", window.settings, "LEFT", -2, 0)
    SetButtonIcon(
        window.lock,
        AF.GetIcon("SmallLock"),
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
        AF.GetIcon("Menu3"),
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

    window.resize:SetShown(not config.locked and not window.minimized)

    window.body:ClearAllPoints()
    window.body:SetPoint("TOPLEFT", window.header, "BOTTOMLEFT")
    window.body:SetPoint("BOTTOMRIGHT")
    window.body:SetBackdropColor(
        AF.GetColorRGB("background", config.backgroundAlpha)
    )
    window.body:SetShown(not window.minimized)

    EnsureRows(window, visibleRows)
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

local function HideWindowTransient(window)
    for _, row in ipairs(window.rows) do
        row.deathRecapID = nil
        row.hoverCard:Hide()
        row.highlight:Hide()
    end
end

local function HideUnusedRows(window, firstUnused)
    for index = firstUnused, #window.rows do
        local row = window.rows[index]
        row.deathRecapID = nil
        row:Hide()
        row.hoverCard:Hide()
        row.highlight:Hide()
    end
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
    row.icon:SetTexture(source.specIconID)
    row.name:SetText(_G.Ambiguate(source.name, "short"))
    row.hoverCard.title:SetText(_G.Ambiguate(source.name, "short"))
    row.hoverCard.playerBadge:SetShown(source.isLocalPlayer == true)
    row.deathRecapID = source.deathRecapID
    row.hoverCard.recapHint:SetShown(
        row.deathRecapID ~= nil and row.deathRecapID ~= 0
    )
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
    if window.minimized then return end

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

function Renderer.ResetPosition()
    local config = GetConfig()
    EnsureInteractionConfig(config)
    for index = 1, MAX_WINDOWS do
        SetAnchorRecord(config, index, GetDefaultAnchor(index))
    end

    if not windows[1] then
        resetPositionPending = true
        return true
    end

    ClearDockPreview()
    ApplyAllAnchors(config)
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
        if index > config.windowCount then
            HideWindowTransient(windows[index])
        end
        windows[index]:SetShown(index <= config.windowCount)
    end
    for index = 1, config.windowCount do
        UpdateWindow(windows[index], config)
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
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGOUT" then
            EndNativeOverride()
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
                ResetCurrentSessionScrollOffsets()
            end
            if event == "DAMAGE_METER_RESET" then
                sessionItemsDirty = true
                ResetHistoricalSelections()
                ResetScrollOffsets()
            end
            ScheduleRefresh()
        end
    end)
end

local function RegisterEvents()
    EnsureEventFrame()
    eventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    eventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
    eventFrame:RegisterEvent("DAMAGE_METER_RESET")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
    for index = 1, MAX_WINDOWS do
        local window = windows[index]
        ApplyWindowLayout(window, config)
        window:Hide()
    end
    ApplyAllAnchors(config)
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
