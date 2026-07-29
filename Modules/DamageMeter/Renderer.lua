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
-- DamageMeterDocumentation.lua, SimpleStatusBarAPIDocumentation.lua,
-- SimpleFontStringAPIDocumentation.lua, LocalizationDocumentation.lua, and
-- PlayerScriptDocumentation.lua; number presentation is also mirrored from
-- Interface/AddOns/Blizzard_DamageMeter/DamageMeterEntry.lua.
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

local TYPE_DEFINITIONS = {
    DamageDone = {
        title = _G.DAMAGE or "Damage",
        enumName = "DamageDone",
    },
    HealingDone = {
        title = _G.HEALING or "Healing",
        enumName = "HealingDone",
    },
    DamageTaken = {
        title = _G.DAMAGE_TAKEN or "Damage Taken",
        enumName = "DamageTaken",
    },
}

local DEFAULT_WINDOW_TYPES = {
    "DamageDone",
    "HealingDone",
    "DamageTaken",
}

local windows = {}
local rendererEnabled
local eventFrame
local refreshTimer
local nativeOverrideActive
local nativeRestoreEnabled
local resetPositionPending

local function GetConfig()
    return DM.config
end

local function GetWindowDefinition(index)
    local config = GetConfig()
    local typeName = config.windowTypes[index]
    return TYPE_DEFINITIONS[typeName]
        or TYPE_DEFINITIONS[DEFAULT_WINDOW_TYPES[index]]
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

local function SetButtonIcon(button, icon)
    button:SetTexture(icon, {12, 12}, {"CENTER", 0, 0})
    button:SetTextureColor("white")
end

local function CreateRow(parent)
    local row = AF.CreateFrame(parent)

    local bar = _G.CreateFrame("StatusBar", nil, row, "BackdropTemplate")
    row.bar = bar
    bar:SetAllPoints()
    AF.ApplyDefaultBackdrop_NoBorder(bar)
    bar:SetBackdropColor(0, 0, 0, 0.42)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local overlay = AF.CreateFrame(row)
    row.overlay = overlay
    overlay:SetAllPoints()
    overlay:SetFrameLevel(bar:GetFrameLevel() + 1)

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

    return row
end

local function EnsureRows(window, count)
    for index = #window.rows + 1, count do
        window.rows[index] = CreateRow(window.body)
    end
end

local function ApplyRowLayout(row, index, config, texture)
    local barHeight = config.barHeight
    local y = -config.padding
        - ((index - 1) * (barHeight + config.spacing))

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
    row.iconHolder:SetShown(config.showSpecIcon)

    row.name:ClearAllPoints()
    if config.showSpecIcon then
        row.name:SetPoint("LEFT", row.iconHolder, "RIGHT", 4, 0)
    else
        row.name:SetPoint("LEFT", row.rank, "RIGHT", 5, 0)
    end

    row.total:ClearAllPoints()
    row.perSecond:ClearAllPoints()
    if config.numberMode == "both" then
        row.total:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.total:SetWidth(62)
        row.perSecond:SetPoint("RIGHT", row.total, "LEFT", -5, 0)
        row.perSecond:SetWidth(62)
        row.name:SetPoint("RIGHT", row.perSecond, "LEFT", -5, 0)
        row.total:Show()
        row.perSecond:Show()
    elseif config.numberMode == "perSecond" then
        row.perSecond:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.perSecond:SetWidth(72)
        row.name:SetPoint("RIGHT", row.perSecond, "LEFT", -5, 0)
        row.total:Hide()
        row.perSecond:Show()
    else
        row.total:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.total:SetWidth(72)
        row.name:SetPoint("RIGHT", row.total, "LEFT", -5, 0)
        row.total:Show()
        row.perSecond:Hide()
    end
end

local function ToggleMinimized(window)
    window.minimized = not window.minimized
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
        if not _G.InCombatLockdown() then
            window:StartMoving()
        end
    end)
    header:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
    end)

    local title = AF.CreateFontString(header, nil, "white")
    window.title = title
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

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

    local body = AF.CreateFrame(
        window,
        nil,
        nil,
        nil,
        "BackdropTemplate"
    )
    window.body = body
    AF.ApplyDefaultBackdrop_NoBorder(body)

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

local function GetVisibleRowCount(config)
    local bodyHeight = config.height - config.headerHeight
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
    local visibleRows = GetVisibleRowCount(config)
    local texture = AF.LSM_GetBarTexture(config.texture)
    if not texture then
        texture = (BFI.media and BFI.media.bar) or AF.GetPlainTexture()
    end

    window.visibleRowCount = visibleRows
    window:SetSize(
        config.width,
        window.minimized and config.headerHeight or config.height
    )
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

    window.title:SetText(definition.title)
    window.title:ClearAllPoints()
    window.title:SetPoint("LEFT", window.header, "LEFT", 6, 0)
    window.title:SetPoint("RIGHT", window.settings, "LEFT", -5, 0)

    window.body:ClearAllPoints()
    window.body:SetPoint("TOPLEFT", window.header, "BOTTOMLEFT")
    window.body:SetPoint("BOTTOMRIGHT")
    window.body:SetBackdropColor(
        AF.GetColorRGB("background", config.backgroundAlpha)
    )
    window.body:SetShown(not window.minimized)

    EnsureRows(window, visibleRows)
    for index, row in ipairs(window.rows) do
        if index <= visibleRows then
            ApplyRowLayout(row, index, config, texture)
        else
            row:Hide()
        end
    end
end

local function HideUnusedRows(window, firstUnused)
    for index = firstUnused, #window.rows do
        window.rows[index]:Hide()
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
    row.rank:SetText(index)
    row.icon:SetTexture(source.specIconID)
    row.name:SetText(_G.Ambiguate(source.name, "short"))

    if config.numberMode == "both" then
        row.total:SetText(AF.FormatSecretNumber(source.totalAmount))
        row.perSecond:SetText(
            AF.FormatSecretNumber(source.amountPerSecond)
        )
    elseif config.numberMode == "perSecond" then
        row.perSecond:SetText(
            AF.FormatSecretNumber(source.amountPerSecond)
        )
    else
        row.total:SetText(AF.FormatSecretNumber(source.totalAmount))
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
    if not windows[1] then
        resetPositionPending = true
        return true
    end

    for index = 1, MAX_WINDOWS do
        windows[index]:ClearAllPoints()
        if index == 1 then
            windows[index]:SetPoint(
                "BOTTOMRIGHT",
                _G.UIParent,
                "BOTTOMRIGHT",
                -WINDOW_INSET,
                WINDOW_INSET
            )
        else
            windows[index]:SetPoint(
                "BOTTOMRIGHT",
                windows[index - 1],
                "BOTTOMLEFT",
                -WINDOW_GAP,
                0
            )
        end
    end
    resetPositionPending = nil
    return true
end

function Renderer.Refresh()
    if not rendererEnabled then return false end
    if not DM.Data.IsAvailable() then
        for _, window in ipairs(windows) do
            window:Hide()
        end
        EndNativeOverride()
        return false
    end

    BeginNativeOverride()
    local config = GetConfig()
    for index = 1, MAX_WINDOWS do
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
    for index = 1, MAX_WINDOWS do
        local window = windows[index]
        ApplyWindowLayout(window, config)
        window:Hide()
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
        local hadWindows = windows[1] ~= nil
        EnsureWindows()
        if not hadWindows or resetPositionPending then
            Renderer.ResetPosition()
        end
        RegisterEvents()
        Renderer.ApplySettings()
        return true
    end

    rendererEnabled = nil
    UnregisterEvents()
    for _, window in ipairs(windows) do
        window:Hide()
    end
    EndNativeOverride()
    return true
end

function Renderer.IsEnabled()
    return rendererEnabled == true
end
