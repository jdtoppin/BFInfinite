---@type BFI
local BFI = select(2, ...)
---@class CooldownManager
local CM = BFI.modules.CooldownManager
---@type Style
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local _G = _G
local CheckAllowProtectedFunctions = C_RestrictedActions.CheckAllowProtectedFunctions
local InCombatLockdown = InCombatLockdown
local IsValueNonSecret = BFI.funcs.isValueNonSecret
local abs = math.abs
local max = math.max
local sort = table.sort

-- Retail 12.0.7.68887, Gethe/wow-ui-source commit 4383ced30106:
-- https://github.com/Gethe/wow-ui-source/tree/4383ced30106d51b27e3e86d1987f1552f0d259d/Interface/AddOns/Blizzard_CooldownViewer
-- Compatibility checked against Retail 12.1.0.68914, commit d3915c78aba7:
-- https://github.com/Gethe/wow-ui-source/tree/d3915c78aba77a7a9be76acbfa35c674bbb6abe9/Interface/AddOns/Blizzard_CooldownViewer
-- Blizzard_CooldownViewer/CooldownViewer.xml supplies these fixed template
-- extents. CooldownViewer.lua remains the sole reader of cooldown and aura
-- data; BFI only changes native viewer settings and widget presentation.
local viewerDefinitions = {
    essential = {
        globalName = "EssentialCooldownViewer",
        itemWidth = 50,
        itemHeight = 50,
        nativePaddingOffset = 4,
        hasIconLimit = true,
    },
    utility = {
        globalName = "UtilityCooldownViewer",
        itemWidth = 30,
        itemHeight = 30,
        nativePaddingOffset = 4,
        hasIconLimit = true,
    },
    buffIcon = {
        globalName = "BuffIconCooldownViewer",
        itemWidth = 40,
        itemHeight = 40,
        nativePaddingOffset = 4,
        isBuff = true,
    },
    buffBar = {
        globalName = "BuffBarCooldownViewer",
        itemWidth = 220,
        itemHeight = 30,
        nativePaddingOffset = 2,
        isBuff = true,
        isBar = true,
    },
}

local orientationValues = {
    horizontal = Enum.CooldownViewerOrientation.Horizontal,
    vertical = Enum.CooldownViewerOrientation.Vertical,
}

local directionValues = {
    left = Enum.CooldownViewerIconDirection.Left,
    right = Enum.CooldownViewerIconDirection.Right,
}

local visibilityValues = {
    always = Enum.CooldownViewerVisibleSetting.Always,
    combat = Enum.CooldownViewerVisibleSetting.InCombat,
    hidden = Enum.CooldownViewerVisibleSetting.Hidden,
}

local barContentValues = {
    icon_and_name = Enum.CooldownViewerBarContent.IconAndName,
    icon_only = Enum.CooldownViewerBarContent.IconOnly,
    name_only = Enum.CooldownViewerBarContent.NameOnly,
}

local FONT_NAME = "BFI_CooldownManagerCountdownFont"
local countdownFont = CreateFont(FONT_NAME)
local QUEUE_LAYOUT = 1
local QUEUE_SETTINGS = 2
local pendingViewers = {}
local deferredViewers = {}
local flushScheduled
local applying

local function ApplyFont(fontString, config)
    if not fontString or not config then return end
    AF.SetFont(fontString, config.font)
    fontString:SetTextColor(AF.UnpackColor(config.color))
end

local function GetIconMaskAndHideOverlay(iconParent)
    -- The fixed 12.0.7 templates declare Icon, MaskTexture, then the
    -- decorative round overlay in this order; 12.1.0 preserves that order.
    local _, mask, overlay = iconParent:GetRegions()
    if overlay
        and IsValueNonSecret(overlay)
        and overlay:IsObjectType("Texture")
        and overlay:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay"
    then
        overlay:Hide()
    end

    if not mask or not IsValueNonSecret(mask) or not mask:IsObjectType("MaskTexture") then
        mask = nil
    end
    return mask
end

local function StyleBuffBar(bar)
    if bar.BarBG then
        bar.BarBG:Hide()
    end

    S.CreateBackdrop(bar)
    bar.BFIBackdrop:SetBackdropColor(AF.GetColorRGB("widget_dark"))
    bar:SetStatusBarTexture(BFI.media.bar)
    bar:GetStatusBarTexture():SetDrawLayer("BORDER", -1)
end

local function StyleItem(item, definition)
    local config = CM.config
    if not config then return end

    if config.skin then
        local iconParent = definition.isBar and item.Icon or item
        local icon = definition.isBar and item.Icon.Icon or item.Icon
        if icon then
            local mask = GetIconMaskAndHideOverlay(iconParent)
            S.StyleSquareIcon(icon, mask, true)
        end

        if definition.isBar and item.Bar then
            StyleBuffBar(item.Bar)
        end
    end

    if item.Cooldown then
        item.Cooldown:SetCountdownFont(FONT_NAME)
    end

    local countText
    if definition.isBar then
        countText = item.Icon and item.Icon.Applications
    elseif definition.isBuff then
        countText = item.Applications and item.Applications.Applications
    else
        countText = item.ChargeCount and item.ChargeCount.Current
    end
    ApplyFont(countText, config.countText)

    if definition.isBar and item.Bar then
        ApplyFont(item.Bar.Name, config.barText)
        ApplyFont(item.Bar.Duration, config.barText)
    end
end

local function GetOrderedItems(viewer)
    local items = {}
    for item in viewer.itemFramePool:EnumerateActive() do
        items[#items + 1] = item
    end
    sort(items, function(a, b)
        return a.layoutIndex < b.layoutIndex
    end)
    return items
end

local function CenterVisibleItems(viewer, definition, config, items)
    if not config.center then return end

    local visibleItems = {}
    for _, item in next, items do
        local isShown = item:IsShown()
        if not IsValueNonSecret(isShown) then
            -- Shown-aspect restrictions must never be inspected. Retaining the
            -- item is the stable fallback until Blizzard exposes the state.
            visibleItems[#visibleItems + 1] = item
        elseif isShown then
            visibleItems[#visibleItems + 1] = item
        end
    end

    local visibleCount = #visibleItems
    if visibleCount == 0 then return end

    local isHorizontal = config.orientation == "horizontal"
    local capacity = definition.hasIconLimit and config.iconLimit or #items
    capacity = max(1, math.min(capacity, #items))

    local scale = config.scale
    local width = definition.itemWidth
    if definition.isBar then
        width = width * config.barWidthScale
    end
    width = width * scale
    local height = definition.itemHeight * scale
    local padding = config.padding
    local primarySize = isHorizontal and width or height
    local stepX = width + padding
    local stepY = height + padding
    local fullLineSize = capacity * primarySize + (capacity - 1) * padding

    for index, item in ipairs(visibleItems) do
        local line = math.floor((index - 1) / capacity)
        local position = (index - 1) % capacity
        local lineCount = math.min(capacity, visibleCount - line * capacity)
        local lineSize = lineCount * primarySize + (lineCount - 1) * padding
        local offset = (fullLineSize - lineSize) / 2

        item:ClearAllPoints()
        if isHorizontal then
            if config.direction == "left" then
                item:SetPoint("TOPRIGHT", viewer, "TOPRIGHT", -offset - position * stepX, -line * stepY)
            else
                item:SetPoint("TOPLEFT", viewer, "TOPLEFT", offset + position * stepX, -line * stepY)
            end
        elseif config.direction == "right" then
            item:SetPoint("BOTTOMLEFT", viewer, "BOTTOMLEFT", line * stepX, offset + position * stepY)
        else
            item:SetPoint("TOPLEFT", viewer, "TOPLEFT", line * stepX, -offset - position * stepY)
        end
    end
end

local function OnItemShownStateUpdated(item)
    local viewer = item:GetViewerFrame()
    if viewer and not applying then
        pendingViewers[viewer] = max(pendingViewers[viewer] or 0, QUEUE_LAYOUT)
        if not flushScheduled then
            flushScheduled = true
            C_Timer.After(0, CM.FlushPendingViewers)
        end
    end
end

local function StyleAndCenterViewer(viewer, definition, config)
    AF.SetFont(countdownFont, CM.config.cooldownText.font)
    countdownFont:SetTextColor(AF.UnpackColor(CM.config.cooldownText.color))

    local items = GetOrderedItems(viewer)
    for _, item in next, items do
        StyleItem(item, definition)
        if not item._BFICooldownManagerShownHooked then
            item._BFICooldownManagerShownHooked = true
            hooksecurefunc(item, "UpdateShownState", OnItemShownStateUpdated)
        end
    end
    CenterVisibleItems(viewer, definition, config, items)
end

local function ApplyViewerSettings(viewer, definition, config)
    viewer.orientationSetting = orientationValues[config.orientation]
    viewer.iconDirection = directionValues[config.direction]
    if definition.hasIconLimit then
        viewer.iconLimit = config.iconLimit
    end
    viewer.iconScale = config.scale
    viewer.iconPadding = config.padding + definition.nativePaddingOffset
    viewer:SetAlpha(config.opacity)
    viewer.visibleSetting = visibilityValues[config.visibility]

    if definition.isBuff then
        viewer:SetHideWhenInactive(config.hideWhenInactive)
    end
    viewer:SetTimerShown(config.showTimer)
    viewer:SetTooltipsShown(config.showTooltips)

    if definition.isBar then
        viewer:SetBarContent(barContentValues[config.barContent])
        viewer:SetBarWidthScale(config.barWidthScale)
    end

    viewer:UpdateShownState()
    viewer:RefreshLayout()
    StyleAndCenterViewer(viewer, definition, config)
end

local function CanChangeGeometry(viewer)
    local allowed = CheckAllowProtectedFunctions(viewer, true)
    return allowed and not InCombatLockdown()
end

local function DeferViewer(viewer, mode)
    deferredViewers[viewer] = max(deferredViewers[viewer] or 0, mode)
    if not CM:IsEventRegistered("PLAYER_REGEN_ENABLED") then
        CM:RegisterEvent("PLAYER_REGEN_ENABLED", CM.RetryDeferredViewers)
    end
end

function CM.FlushPendingViewers()
    flushScheduled = false
    local current = pendingViewers
    pendingViewers = {}

    local config = CM.config
    if not config or not config.enabled then return end

    applying = true
    for viewer, mode in next, current do
        local definition = viewer._BFICooldownManagerDefinition
        local viewerConfig = definition and config.viewers[viewer._BFICooldownManagerKey]
        if definition and viewerConfig then
            if not CanChangeGeometry(viewer) then
                DeferViewer(viewer, mode)
            elseif mode == QUEUE_SETTINGS then
                ApplyViewerSettings(viewer, definition, viewerConfig)
            else
                StyleAndCenterViewer(viewer, definition, viewerConfig)
            end
        end
    end
    applying = false
end

function CM.RetryDeferredViewers()
    CM:UnregisterEvent("PLAYER_REGEN_ENABLED", CM.RetryDeferredViewers)
    for viewer, mode in next, deferredViewers do
        pendingViewers[viewer] = max(pendingViewers[viewer] or 0, mode)
    end
    deferredViewers = {}

    if next(pendingViewers) and not flushScheduled then
        flushScheduled = true
        C_Timer.After(0, CM.FlushPendingViewers)
    end
end

local function QueueViewer(viewer, mode)
    pendingViewers[viewer] = max(pendingViewers[viewer] or 0, mode)
    if not flushScheduled then
        flushScheduled = true
        C_Timer.After(0, CM.FlushPendingViewers)
    end
end

local function NearlyEqual(a, b)
    return abs(a - b) < 0.001
end

local function ViewerSettingsMatch(viewer, definition, config)
    if viewer.orientationSetting ~= orientationValues[config.orientation]
        or viewer.iconDirection ~= directionValues[config.direction]
        or not NearlyEqual(viewer.iconScale, config.scale)
        or viewer.iconPadding ~= config.padding + definition.nativePaddingOffset
        or viewer.visibleSetting ~= visibilityValues[config.visibility]
        or viewer.timerShown ~= config.showTimer
        or viewer.tooltipsShown ~= config.showTooltips
    then
        return false
    end

    if definition.hasIconLimit and viewer.iconLimit ~= config.iconLimit then
        return false
    end

    if definition.isBuff and viewer.hideWhenInactive ~= config.hideWhenInactive then
        return false
    end

    if definition.isBar
        and (viewer.barContent ~= barContentValues[config.barContent]
            or not NearlyEqual(viewer.barWidthScale, config.barWidthScale))
    then
        return false
    end

    local alpha = viewer:GetAlpha()
    if not IsValueNonSecret(alpha) then
        return false
    end
    return NearlyEqual(alpha, config.opacity)
end

local function OnViewerLayout(viewer)
    local config = CM.config
    if not applying and config and config.enabled then
        local definition = viewer._BFICooldownManagerDefinition
        local viewerConfig = definition and config.viewers[viewer._BFICooldownManagerKey]
        local mode = viewerConfig and ViewerSettingsMatch(viewer, definition, viewerConfig)
            and QUEUE_LAYOUT or QUEUE_SETTINGS
        QueueViewer(viewer, mode)
    end
end

local function InitializeViewers(which)
    for key, definition in next, viewerDefinitions do
        if not which or key == which then
            local viewer = _G[definition.globalName]
            if viewer then
                viewer._BFICooldownManagerDefinition = definition
                viewer._BFICooldownManagerKey = key
                if not viewer._BFICooldownManagerHooksInstalled then
                    viewer._BFICooldownManagerHooksInstalled = true
                    hooksecurefunc(viewer, "RefreshLayout", OnViewerLayout)
                    hooksecurefunc(viewer, "Layout", OnViewerLayout)
                end
                QueueViewer(viewer, QUEUE_SETTINGS)
            end
        end
    end
end

local function UpdateCooldownManager(_, module, which)
    if module and module ~= "cooldownManager" then return end

    local config = CM.config
    if not config or not config.enabled then return end

    InitializeViewers(which)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_CooldownViewer", function()
    if CM.config and CM.config.enabled then
        InitializeViewers()
    end
end)
AF.RegisterCallback("BFI_UpdateModule", UpdateCooldownManager)
