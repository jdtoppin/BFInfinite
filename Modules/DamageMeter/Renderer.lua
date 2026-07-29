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

local TYPE_DEFINITIONS = {
    DamageDone = {
        title = _G.DAMAGE_METER_TYPE_DAMAGE_DONE or _G.DAMAGE or "Damage",
        enumName = "DamageDone",
    },
    Dps = {
        title = _G.DAMAGE_METER_TYPE_DPS or _G.DPS or "DPS",
        enumName = "Dps",
        valuePerSecondAsPrimary = true,
    },
    HealingDone = {
        title = _G.DAMAGE_METER_TYPE_HEALING_DONE
            or _G.HEALING
            or "Healing",
        enumName = "HealingDone",
    },
    Hps = {
        title = _G.DAMAGE_METER_TYPE_HPS or _G.HPS or "HPS",
        enumName = "Hps",
        valuePerSecondAsPrimary = true,
    },
    Absorbs = {
        title = _G.DAMAGE_METER_TYPE_ABSORBS or "Absorbs",
        enumName = "Absorbs",
    },
    Interrupts = {
        title = _G.DAMAGE_METER_TYPE_INTERRUPTS or "Interrupts",
        enumName = "Interrupts",
        suppressValuePerSecond = true,
    },
    Dispels = {
        title = _G.DAMAGE_METER_TYPE_DISPELS or "Dispels",
        enumName = "Dispels",
        suppressValuePerSecond = true,
    },
    DamageTaken = {
        title = _G.DAMAGE_METER_TYPE_DAMAGE_TAKEN
            or _G.DAMAGE_TAKEN
            or "Damage Taken",
        enumName = "DamageTaken",
    },
    AvoidableDamageTaken = {
        title = _G.DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN
            or "Avoidable Damage",
        enumName = "AvoidableDamageTaken",
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
        190,
        68,
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
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7)

    local totalLabel = AF.CreateFontString(card, nil, "gray")
    card.totalLabel = totalLabel
    totalLabel:SetText(_G.TOTAL or "Total")
    totalLabel:SetJustifyH("LEFT")
    totalLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

    local totalValue = AF.CreateFontString(card, nil, "white")
    card.totalValue = totalValue
    totalValue:SetJustifyH("RIGHT")
    totalValue:SetPoint("RIGHT", card, "RIGHT", -8, 2)

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
    perSecondValue:SetPoint(
        "RIGHT",
        card,
        "RIGHT",
        -8,
        -17
    )

    return card
end

local function CreateRow(parent)
    local row = AF.CreateFrame(parent)
    row:EnableMouse(true)

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

    return row
end

local function EnsureRows(window, count)
    for index = #window.rows + 1, count do
        window.rows[index] = CreateRow(window.body)
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
    row.hoverCard:SetHeight(
        definition.suppressValuePerSecond and 48 or 68
    )
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

local function SelectWindowType(index, typeName)
    if not TYPE_DEFINITIONS[typeName] then return end

    local config = GetConfig()
    config.windowTypes[index] = typeName
    Renderer.ApplySettings()
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
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetFrameStrata("LOW")
    AF.ApplyDefaultBackdrop_NoBackground(window)
    window:SetScript("OnSizeChanged", function(_, width, height)
        OnWindowSizeChanged(window, width, height)
    end)

    local header = AF.CreateFrame(
        window,
        nil,
        nil,
        nil,
        "BackdropTemplate"
    )
    window.header = header
    AF.ApplyDefaultBackdrop_NoBorder(header)
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
        SelectWindowType(index, typeName)
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
    if config.accentHeader then
        window.header:SetBackdropColor(AF.GetColorRGB("BFI", 0.94))
    else
        window.header:SetBackdropColor(AF.GetColorRGB("header", 0.94))
    end

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
        window.lock,
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
        row.hoverCard:Hide()
        row.highlight:Hide()
    end
end

local function HideUnusedRows(window, firstUnused)
    for index = firstUnused, #window.rows do
        local row = window.rows[index]
        row:Hide()
        row.hoverCard:Hide()
        row.highlight:Hide()
    end
end

local function UpdateRow(row, source, index, config)
    local r, g, b
    if config.classColor then
        r, g, b = AF.GetClassColor(source.classFilename)
    else
        r, g, b = AF.GetColorRGB("BFI")
    end

    row.bar:SetStatusBarColor(r, g, b, config.barAlpha)
    row.iconHolder:SetBackdropBorderColor(r, g, b, 1)
    row.hoverCard:SetBackdropBorderColor(r, g, b, 1)
    row.rank:SetText(index)
    row.icon:SetTexture(source.specIconID)
    row.name:SetText(_G.Ambiguate(source.name, "short"))
    row.hoverCard.title:SetText(_G.Ambiguate(source.name, "short"))

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

local function UpdateWindow(window, config)
    if window.minimized then return end

    local definition = GetWindowDefinition(window.index)
    local meterType = GetMeterType(definition)
    if meterType == nil then
        HideUnusedRows(window, 1)
        return
    end

    local session = DM.Data.GetCurrentSession(meterType)
    local used = 0

    for index, source in ipairs(session.combatSources) do
        if index > window.visibleRowCount then break end

        local row = window.rows[index]
        row.bar:SetMinMaxValues(0, session.maxAmount)
        row.bar:SetValue(source.totalAmount)
        UpdateRow(row, source, index, config)
        row:Show()
        used = index
    end

    HideUnusedRows(window, used + 1)
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
