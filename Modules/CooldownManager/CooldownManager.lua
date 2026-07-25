---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class CooldownManager
local CM = BFI.modules.CooldownManager
---@type Style
local S = BFI.modules.Style
---@type AbstractFramework
local AF = _G.AbstractFramework

local _G = _G
local CheckAllowProtectedFunctions = C_RestrictedActions.CheckAllowProtectedFunctions
local GetCVar = GetCVar
local GetCVarBool = GetCVarBool
local InCombatLockdown = InCombatLockdown
local IsValueNonSecret = BFI.funcs.isValueNonSecret
local UnitAffectingCombat = UnitAffectingCombat
local abs = math.abs
local max = math.max
local min = math.min
local sort = table.sort
local tonumber = tonumber

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
        holderName = "BFI_CooldownManagerEssentialHolder",
        moverName = L["Essential Cooldowns"],
        defaultPosition = {"BOTTOM", 0, 310},
        itemWidth = 50,
        itemHeight = 50,
        nativePaddingOffset = 4,
        hasIconLimit = true,
        assistedHighlight = true,
    },
    utility = {
        globalName = "UtilityCooldownViewer",
        holderName = "BFI_CooldownManagerUtilityHolder",
        moverName = L["Utility Cooldowns"],
        defaultPosition = {"BOTTOM", 0, 240},
        itemWidth = 30,
        itemHeight = 30,
        nativePaddingOffset = 4,
        hasIconLimit = true,
        assistedHighlight = true,
    },
    buffIcon = {
        globalName = "BuffIconCooldownViewer",
        holderName = "BFI_CooldownManagerBuffIconHolder",
        moverName = L["Buff Icons"],
        defaultPosition = {"BOTTOM", 0, 370},
        itemWidth = 40,
        itemHeight = 40,
        nativePaddingOffset = 4,
        isBuff = true,
    },
    buffBar = {
        globalName = "BuffBarCooldownViewer",
        holderName = "BFI_CooldownManagerBuffBarHolder",
        moverName = L["Buff Bars"],
        defaultPosition = {"BOTTOM", 420, 430},
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
local QUEUE_ANCHOR = 1
local QUEUE_LAYOUT = 2
local QUEUE_SETTINGS = 3
local pendingViewers = {}
local deferredViewers = {}
local viewerStates = {}
local assistedHighlights = setmetatable({}, {__mode = "k"})
local assistedBaseSpellIDs = {}
local assistedHighlightController = CreateFrame("Frame")
local visibilityObserver = CreateFrame("Frame")
local assistedHighlightSpellID
local assistedHighlightBaseSpellID
local assistedHighlightUpdateTimeLeft = 0
local visibilityUpdateTimeLeft = 0
local flushScheduled
local applying
local QueueViewer
local SyncHolderSize
local ApplyViewerWithHolder
local ReleaseViewerHolder
local PrepareViewerPositionCaptures

---------------------------------------------------------------------
-- Assisted Combat highlight
---------------------------------------------------------------------
-- Retail 12.0.7.68887 and 12.1.0.68914 expose the same documented
-- C_AssistedCombat.GetNextCastSpell(false) contract and the same ordinary
-- ActionBarButtonAssistedCombatHighlightTemplate. Blizzard's manager polls
-- with true for action-button visibility, so CDM needs its own presentation
-- poll to include recommendations represented only by a cooldown viewer item.
local function GetNonSecretSpellID(spellID)
    if not IsValueNonSecret(spellID) or type(spellID) ~= "number" then
        return nil
    end
    return spellID
end

local function GetBaseSpellID(spellID)
    if not spellID then return nil end
    return GetNonSecretSpellID(C_Spell.GetBaseSpell(spellID))
end

local function EnsureAssistedHighlight(item, definition)
    if not definition.assistedHighlight then return nil end

    local highlight = assistedHighlights[item]
    if highlight then return highlight end

    highlight = CreateFrame("Frame", nil, item, "ActionBarButtonAssistedCombatHighlightTemplate")
    assistedHighlights[item] = highlight
    highlight:ClearAllPoints()
    highlight:SetPoint("CENTER")
    highlight:SetFrameLevel(item:GetFrameLevel() + 10)
    -- The native template is 45x45 with a 66x66 flipbook. CDM item extents
    -- are fixed in both audited builds; viewer scaling is inherited.
    highlight:SetScale(min(definition.itemWidth, definition.itemHeight) / 45)
    highlight.Flipbook.Anim:Play()
    highlight.Flipbook.Anim:Stop()
    -- Pre-create and retain the ordinary overlay so the combat polling path
    -- only adjusts alpha and animation state.
    highlight:SetAlpha(0)
    highlight:Show()
    return highlight
end

local function GetItemBaseSpellID(item)
    -- Avoid calling Blizzard's item mixins from tainted execution. Their
    -- RefreshData/GetSpellID paths branch on combat-secret aura and totem
    -- values in 12.0.7 and 12.1. The cooldown ID itself is static, and the
    -- documented C API returns its static cooldown definition.
    local cooldownID = GetNonSecretSpellID(item.cooldownID)
    if not cooldownID then return nil end

    if not C_CooldownViewer
        or type(C_CooldownViewer.GetCooldownViewerCooldownInfo) ~= "function"
    then
        return nil
    end

    local cached = assistedBaseSpellIDs[cooldownID]
    if cached then return cached end

    local cooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    if not IsValueNonSecret(cooldownInfo) or type(cooldownInfo) ~= "table" then
        return nil
    end

    local spellID = GetNonSecretSpellID(cooldownInfo.spellID)
    if not spellID then return nil end

    local baseSpellID = GetBaseSpellID(spellID) or spellID
    assistedBaseSpellIDs[cooldownID] = baseSpellID
    return baseSpellID
end

local function ItemMatchesAssistedHighlight(item)
    if not assistedHighlightSpellID then return false end

    local baseSpellID = GetItemBaseSpellID(item)
    return baseSpellID ~= nil
        and (baseSpellID == assistedHighlightSpellID or baseSpellID == assistedHighlightBaseSpellID)
end

local function UpdateItemAssistedHighlight(item)
    local highlight = assistedHighlights[item]
    if not highlight then return end

    local config = CM.config
    local shown = config
        and config.enabled
        and config.assistedHighlight
        and ItemMatchesAssistedHighlight(item)
    highlight:SetAlpha(shown and 1 or 0)

    local animation = highlight.Flipbook.Anim
    if shown and UnitAffectingCombat("player") then
        if not animation:IsPlaying() then
            animation:Play()
        end
    elseif animation:IsPlaying() then
        animation:Stop()
    end
end

local function RefreshAssistedHighlights()
    for viewer, state in next, viewerStates do
        if state.definition.assistedHighlight then
            for item in viewer.itemFramePool:EnumerateActive() do
                UpdateItemAssistedHighlight(item)
            end
        end
    end
end

local function SetAssistedHighlightSpell(spellID)
    spellID = GetNonSecretSpellID(spellID)
    local baseSpellID = GetBaseSpellID(spellID)
    if spellID == assistedHighlightSpellID and baseSpellID == assistedHighlightBaseSpellID then
        return
    end

    assistedHighlightSpellID = spellID
    assistedHighlightBaseSpellID = baseSpellID
end

local function PollAssistedHighlight(_, elapsed)
    assistedHighlightUpdateTimeLeft = assistedHighlightUpdateTimeLeft - elapsed
    if assistedHighlightUpdateTimeLeft > 0 then return end

    local updateRate = tonumber(GetCVar("assistedCombatIconUpdateRate")) or 0
    assistedHighlightUpdateTimeLeft = max(0, min(updateRate, 1))
    SetAssistedHighlightSpell(C_AssistedCombat.GetNextCastSpell(false))
    -- Item pools and cooldown definitions can change while the recommendation
    -- remains the same, so refresh from this independent BFI poll every time.
    RefreshAssistedHighlights()
end

local function UpdateAssistedHighlightPolling()
    local config = CM.config
    local enabled = config
        and config.enabled
        and config.assistedHighlight
        and GetCVarBool("assistedCombatHighlight")
        and C_AssistedCombat
        and type(C_AssistedCombat.GetNextCastSpell) == "function"
        and C_CooldownViewer
        and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function"

    if enabled then
        assistedHighlightUpdateTimeLeft = 0
        assistedHighlightController:SetScript("OnUpdate", PollAssistedHighlight)
    else
        assistedHighlightController:SetScript("OnUpdate", nil)
        SetAssistedHighlightSpell(nil)
        RefreshAssistedHighlights()
    end
end

local function OnAssistedHighlightEvent(_, event)
    if event == "COOLDOWN_VIEWER_DATA_LOADED" or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        wipe(assistedBaseSpellIDs)
    end
    assistedHighlightUpdateTimeLeft = 0
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        RefreshAssistedHighlights()
    end
end

assistedHighlightController:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
assistedHighlightController:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
assistedHighlightController:RegisterEvent("PLAYER_REGEN_DISABLED")
assistedHighlightController:RegisterEvent("PLAYER_REGEN_ENABLED")
assistedHighlightController:SetScript("OnEvent", OnAssistedHighlightEvent)
CVarCallbackRegistry:RegisterCallback(
    "assistedCombatHighlight",
    UpdateAssistedHighlightPolling,
    assistedHighlightController
)
CVarCallbackRegistry:RegisterCallback(
    "assistedCombatIconUpdateRate",
    UpdateAssistedHighlightPolling,
    assistedHighlightController
)

---------------------------------------------------------------------
-- Centered layout visibility observer
---------------------------------------------------------------------
-- Item data refreshes branch on secret aura/totem values in combat. Never
-- hook an item mixin method: a post-hook returns to Blizzard's native loop in
-- tainted execution. Sample ordinary shown state from BFI's own update stack
-- instead, and let the existing queue defer protected geometry as needed.
local function ClearVisibilitySample(state)
    state.visibilitySample = nil
    state.visibilitySamplePending = nil
end

local function SampleViewerVisibility(state)
    local sample = {}
    for item in state.viewer.itemFramePool:EnumerateActive() do
        local shown = item:IsShown()
        if not IsValueNonSecret(shown) or type(shown) ~= "boolean" then
            state.visibilitySamplePending = true
            return
        end
        sample[item] = shown
    end

    local previous = state.visibilitySample
    local changed = state.visibilitySamplePending or not previous
    if not changed then
        for item, shown in next, sample do
            if previous[item] ~= shown then
                changed = true
                break
            end
        end
    end
    if not changed then
        for item in next, previous do
            if sample[item] == nil then
                changed = true
                break
            end
        end
    end

    state.visibilitySample = sample
    state.visibilitySamplePending = nil
    if changed then
        QueueViewer(state.viewer, QUEUE_LAYOUT)
    end
end

local function PollViewerVisibility(_, elapsed)
    visibilityUpdateTimeLeft = visibilityUpdateTimeLeft - elapsed
    if visibilityUpdateTimeLeft > 0 then return end
    visibilityUpdateTimeLeft = 0.15

    local config = CM.config
    if not config or not config.enabled or not config.viewers then return end

    for _, state in next, viewerStates do
        local viewerConfig = config.viewers[state.key]
        if viewerConfig and viewerConfig.center then
            SampleViewerVisibility(state)
        else
            ClearVisibilitySample(state)
        end
    end
end

local function UpdateVisibilityObserver()
    local config = CM.config
    local enabled = false
    if config and config.enabled and config.viewers then
        for _, viewerConfig in next, config.viewers do
            if viewerConfig.center then
                enabled = true
                break
            end
        end
    end

    if enabled then
        visibilityUpdateTimeLeft = 0
        visibilityObserver:SetScript("OnUpdate", PollViewerVisibility)
    else
        visibilityObserver:SetScript("OnUpdate", nil)
        for _, state in next, viewerStates do
            ClearVisibilitySample(state)
        end
    end
end

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

    if definition.assistedHighlight then
        EnsureAssistedHighlight(item, definition)
        UpdateItemAssistedHighlight(item)
    end

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

    -- Blizzard applies iconScale with SetScale after calculating its grid in
    -- unscaled item coordinates. Keep custom anchors in those same units.
    local width = definition.itemWidth
    if definition.isBar then
        width = width * config.barWidthScale
    end
    local height = definition.itemHeight
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

local function StyleAndCenterViewer(viewer, definition, config)
    AF.SetFont(countdownFont, CM.config.cooldownText.font)
    countdownFont:SetTextColor(AF.UnpackColor(CM.config.cooldownText.color))

    local items = GetOrderedItems(viewer)
    for _, item in next, items do
        StyleItem(item, definition)
    end
    CenterVisibleItems(viewer, definition, config, items)
    SyncHolderSize(viewer)
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
    CM:RegisterEvent("PLAYER_REGEN_ENABLED", CM.RetryDeferredViewers)
    CM:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", CM.RetryDeferredViewers)
end

function CM.FlushPendingViewers()
    flushScheduled = false
    local current = pendingViewers
    pendingViewers = {}

    applying = true
    if not PrepareViewerPositionCaptures(current) then
        for viewer, mode in next, current do
            pendingViewers[viewer] = max(pendingViewers[viewer] or 0, mode)
        end
        applying = false
        return
    end

    for viewer, mode in next, current do
        local state = viewerStates[viewer]
        if state then
            local config = CM.config
            local viewerConfig = config and config.viewers and config.viewers[state.key]
            local shouldAttach = config and config.enabled and viewerConfig
            if not shouldAttach and state.holder then
                state.holder.enabled = false
                if state.holder.mover:IsShown() then
                    state.holder.mover:Hide()
                end
            end

            if not CanChangeGeometry(viewer) then
                DeferViewer(viewer, mode)
            elseif shouldAttach then
                ApplyViewerWithHolder(state, viewerConfig, mode)
            else
                ReleaseViewerHolder(state)
            end
        end
    end
    applying = false
end

function CM.RetryDeferredViewers(_, event, _, restrictionState)
    if event == "ADDON_RESTRICTION_STATE_CHANGED"
        and restrictionState ~= Enum.AddOnRestrictionState.Inactive
    then
        return
    end

    CM:UnregisterEvent("PLAYER_REGEN_ENABLED", CM.RetryDeferredViewers)
    CM:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED", CM.RetryDeferredViewers)

    for viewer, mode in next, deferredViewers do
        pendingViewers[viewer] = max(pendingViewers[viewer] or 0, mode)
    end
    deferredViewers = {}

    if next(pendingViewers) and not flushScheduled then
        flushScheduled = true
        C_Timer.After(0, CM.FlushPendingViewers)
    end
end

QueueViewer = function(viewer, mode)
    pendingViewers[viewer] = max(pendingViewers[viewer] or 0, mode)
    if not flushScheduled then
        flushScheduled = true
        C_Timer.After(0, CM.FlushPendingViewers)
    end
end

---------------------------------------------------------------------
-- BFI edit mode
---------------------------------------------------------------------
local function IsBlizzardEditModeActive()
    local editMode = _G.EditModeManagerFrame
    if not editMode then return false end
    if type(editMode.IsEditModeActive) == "function" then
        return editMode:IsEditModeActive()
    end
    return editMode:IsShown()
end

local function IsViewerAttached(state)
    local viewer = state.viewer
    if not state.holder or viewer:GetParent() ~= _G.UIParent or viewer:GetNumPoints() ~= 1 then
        return false
    end

    local point, relativeTo, relativePoint = viewer:GetPoint(1)
    return point == "CENTER" and relativeTo == state.holder and relativePoint == "CENTER"
end

SyncHolderSize = function(viewer)
    local state = viewerStates[viewer]
    local holder = state and state.holder
    if not holder then return end

    local width, height = viewer:GetSize()
    local viewerScale = viewer:GetEffectiveScale()
    local holderScale = holder:GetEffectiveScale()
    if not IsValueNonSecret(width)
        or not IsValueNonSecret(height)
        or not IsValueNonSecret(viewerScale)
        or not IsValueNonSecret(holderScale)
        or type(width) ~= "number"
        or type(height) ~= "number"
        or type(viewerScale) ~= "number"
        or type(holderScale) ~= "number"
        or holderScale <= 0
    then
        return
    end

    -- The native viewers remain parented to UIParent while BFI movers live
    -- under AF.UIParent, whose independent scale must be accounted for.
    local scaleRatio = viewerScale / holderScale
    holder:SetSize(max(1, width * scaleRatio), max(1, height * scaleRatio))
end

local function OnMoverVisibilityChanged(state)
    if not applying then
        QueueViewer(state.viewer, QUEUE_SETTINGS)
    end
end

local function EnsureHolder(state)
    if state.holder then return state.holder end

    local holder = CreateFrame("Frame", state.definition.holderName, AF.UIParent)
    holder:SetSize(1, 1)
    holder.enabled = false
    holder:Show()

    state.holder = holder
    AF.CreateMover(holder, "BFI: " .. L["Cooldown Manager"], state.definition.moverName)
    holder.mover:HookScript("OnShow", function()
        OnMoverVisibilityChanged(state)
    end)
    holder.mover:HookScript("OnHide", function()
        OnMoverVisibilityChanged(state)
    end)

    return holder
end

local function UpdateViewerPreview(state)
    local viewer = state.viewer
    local holder = state.holder
    local previewWanted = holder
        and holder.enabled
        and holder.mover:IsShown()
        and not IsBlizzardEditModeActive()

    if previewWanted then
        if not viewer:IsEditing() then
            state.previewForced = true
            viewer:SetIsEditing(true)
        end
    elseif state.previewForced then
        if not IsBlizzardEditModeActive() and viewer:IsEditing() then
            viewer:SetIsEditing(false)
        end
        state.previewForced = nil
    end
end

local function RestoreNativeAnchor(state)
    if not state.attached and not IsViewerAttached(state) then
        return true
    end

    local viewer = state.viewer
    if type(viewer.ApplySystemAnchor) ~= "function"
        or (type(viewer.IsInitialized) == "function" and not viewer:IsInitialized())
    then
        return false
    end

    state.attached = false
    state.reconciling = true
    state.restoring = true
    -- ApplySystemAnchor receives no secret values. pcall only guarantees that
    -- our reconciliation guards are cleared if Blizzard's geometry call fails.
    local success, errorMessage = pcall(viewer.ApplySystemAnchor, viewer)
    state.restoring = nil
    state.reconciling = nil
    if not success then
        state.attached = IsViewerAttached(state)
        if not state.restoreErrorReported then
            state.restoreErrorReported = true
            geterrorhandler()(errorMessage)
        end
        return false
    end

    -- Default managed viewers are ignored while hidden. Treat a native
    -- restore as incomplete if Blizzard left our holder anchor in place.
    if IsViewerAttached(state) then
        state.attached = true
        return false
    end

    state.restoreErrorReported = nil
    return true
end

local function AttachViewer(state)
    if IsViewerAttached(state) then
        state.attached = true
        return
    end

    local viewer = state.viewer
    local holder = state.holder
    state.reconciling = true

    if type(viewer.BreakFromFrameManager) == "function" then
        viewer:BreakFromFrameManager()
    end
    if viewer:GetParent() ~= _G.UIParent then
        viewer:SetParent(_G.UIParent)
    end

    -- Bypass Blizzard Edit Mode's tracking overrides. Its saved layout remains
    -- untouched and can be restored when BFI releases the viewer.
    if type(viewer.ClearFrameSnap) == "function" then
        viewer:ClearFrameSnap()
    end
    local clearAllPoints = viewer.ClearAllPointsBase or viewer.ClearAllPoints
    local setPoint = viewer.SetPointBase or viewer.SetPoint
    clearAllPoints(viewer)
    setPoint(viewer, "CENTER", holder, "CENTER", 0, 0)

    state.attached = true
    state.reconciling = nil
end

local function NeedsPositionCapture(config)
    return config.captureNativePosition
        or type(config.position) ~= "table"
        or not next(config.position)
end

local function IsViewerInitialized(viewer)
    return type(viewer.IsInitialized) ~= "function" or viewer:IsInitialized()
end

local function CaptureViewerPosition(state, config)
    local viewer = state.viewer
    local holder = state.holder
    local centerX, centerY = viewer:GetCenter()

    local position
    if IsValueNonSecret(centerX)
        and IsValueNonSecret(centerY)
        and type(centerX) == "number"
        and type(centerY) == "number"
    then
        AF.ClearPoints(holder)
        AF.SetPoint(holder, "CENTER", viewer, "CENTER")
        local holderX, holderY = holder:GetCenter()
        local parentX, parentY = AF.UIParent:GetCenter()
        if IsValueNonSecret(holderX)
            and IsValueNonSecret(holderY)
            and IsValueNonSecret(parentX)
            and IsValueNonSecret(parentY)
            and type(holderX) == "number"
            and type(holderY) == "number"
            and type(parentX) == "number"
            and type(parentY) == "number"
        then
            -- Store a center-relative position directly so AF's optional
            -- mover anchor lock cannot reinterpret this temporary anchor.
            position = {
                "CENTER",
                AF.RoundToDecimal(holderX - parentX, 1),
                AF.RoundToDecimal(holderY - parentY, 1),
            }
        end
    end
    if not position then
        position = AF.Copy(state.definition.defaultPosition)
    end

    config.position = position
    config.captureNativePosition = nil
    return position
end

local function StopPositionCapturePreviews(captures)
    for _, capture in next, captures do
        if capture.editingForced then
            capture.editingForced = nil
            local viewer = capture[1].viewer
            if not IsBlizzardEditModeActive() and viewer:IsEditing() then
                viewer:SetIsEditing(false)
            end
        end
    end
end

PrepareViewerPositionCaptures = function(current)
    local config = CM.config
    if not config or not config.enabled or not config.viewers then return true end

    local captures = {}
    for viewer, state in next, viewerStates do
        local viewerConfig = config.viewers[state.key]
        if viewerConfig and NeedsPositionCapture(viewerConfig) then
            local holder = EnsureHolder(state)
            holder.enabled = false
            if holder.mover:IsShown() then
                holder.mover:Hide()
            end

            captures[#captures + 1] = {state, viewerConfig}
        end
    end

    -- Validate the complete capture set before changing any viewer state.
    for _, capture in next, captures do
        local viewer = capture[1].viewer
        if not CanChangeGeometry(viewer) then
            DeferViewer(viewer, QUEUE_SETTINGS)
            return false
        end
        if not IsViewerInitialized(viewer) then
            return false
        end
    end

    -- Hidden default-managed viewers are skipped by Blizzard's frame manager.
    -- Show only those viewers temporarily so ApplySystemAnchor can restore
    -- their native managed position before it is measured.
    for _, capture in next, captures do
        local state = capture[1]
        local viewer = state.viewer
        UpdateViewerPreview(state)

        local isShown = viewer:IsShown()
        if not IsValueNonSecret(isShown) then
            StopPositionCapturePreviews(captures)
            DeferViewer(viewer, QUEUE_SETTINGS)
            return false
        end
        if not isShown and not viewer:IsEditing() then
            capture.editingForced = true
            viewer:SetIsEditing(true)
        end
    end

    -- Restore every native anchor before taking any measurements; removing
    -- one managed viewer can synchronously reflow the remaining viewers.
    for _, capture in next, captures do
        if not RestoreNativeAnchor(capture[1]) then
            StopPositionCapturePreviews(captures)
            DeferViewer(capture[1].viewer, QUEUE_SETTINGS)
            return false
        end
    end

    -- Snapshot every native position before detaching any managed viewer.
    for _, capture in next, captures do
        CaptureViewerPosition(capture[1], capture[2])
    end
    StopPositionCapturePreviews(captures)

    for _, capture in next, captures do
        local viewer = capture[1].viewer
        current[viewer] = max(current[viewer] or 0, QUEUE_SETTINGS)
    end
    return true
end

local function BindHolderPosition(state, position)
    if state.position == position then return end

    state.position = position
    AF.UpdateMoverSave(state.holder, position)
    AF.LoadPosition(state.holder, position, AF.UIParent)
end

ApplyViewerWithHolder = function(state, config, mode)
    local viewer = state.viewer
    local holder = EnsureHolder(state)
    holder:Show()

    local capturePosition = NeedsPositionCapture(config)
    if capturePosition then
        holder.enabled = false
        if holder.mover:IsShown() then
            holder.mover:Hide()
        end
        UpdateViewerPreview(state)

        -- Legacy profiles have no BFI position. Wait until Blizzard has
        -- applied the active native layout, then inherit that exact location.
        if not IsViewerInitialized(viewer) then return end
        if not RestoreNativeAnchor(state) then
            DeferViewer(viewer, mode)
            return
        end
    end

    local position = capturePosition and CaptureViewerPosition(state, config) or config.position
    if not position then return end
    BindHolderPosition(state, position)
    AttachViewer(state)
    holder.enabled = true
    UpdateViewerPreview(state)

    if mode == QUEUE_SETTINGS then
        ApplyViewerSettings(viewer, state.definition, config)
    elseif mode == QUEUE_LAYOUT then
        StyleAndCenterViewer(viewer, state.definition, config)
    end

    SyncHolderSize(viewer)
end

ReleaseViewerHolder = function(state)
    local holder = state.holder
    if not holder then return end

    holder.enabled = false
    UpdateViewerPreview(state)
    if holder.mover:IsShown() then
        holder.mover:Hide()
    end

    if not RestoreNativeAnchor(state) then
        DeferViewer(state.viewer, QUEUE_ANCHOR)
        return
    end
    holder:Hide()
    state.position = nil
end

function CM.StopEditModePreviews(_, _, _, restrictionState)
    if restrictionState ~= Enum.AddOnRestrictionState.Activating then return end

    AF.HideMovers()
    for _, state in next, viewerStates do
        local holder = state.holder
        if holder and holder.mover:IsShown() then
            holder.mover:Hide()
        end
        if state.previewForced then
            if not IsBlizzardEditModeActive() and state.viewer:IsEditing() then
                state.viewer:SetIsEditing(false)
            end
            state.previewForced = nil
        end
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
    local state = viewerStates[viewer]
    if not applying and state and ((config and config.enabled) or state.attached) then
        local viewerConfig = config and config.viewers and config.viewers[state.key]
        local mode = viewerConfig and ViewerSettingsMatch(viewer, state.definition, viewerConfig)
            and QUEUE_LAYOUT or QUEUE_SETTINGS
        QueueViewer(viewer, mode)
    end
end

local function OnViewerAnchorApplied(viewer)
    local state = viewerStates[viewer]
    local config = CM.config
    if not applying
        and state
        and not state.reconciling
        and not state.restoring
        and ((config and config.enabled) or state.attached)
    then
        QueueViewer(viewer, QUEUE_ANCHOR)
    end
end

local function OnViewerShown(viewer)
    OnViewerAnchorApplied(viewer)
end

local function SuppressNativeEditModeHighlight(viewer)
    local state = viewerStates[viewer]
    local config = CM.config
    if state and state.attached and config and config.enabled then
        viewer:ClearHighlight()
    end
end

local function InitializeViewers(which)
    for key, definition in next, viewerDefinitions do
        if not which or key == which then
            local viewer = _G[definition.globalName]
            if viewer then
                local state = viewerStates[viewer]
                if not state then
                    state = {
                        viewer = viewer,
                        definition = definition,
                        key = key,
                    }
                    viewerStates[viewer] = state
                    EnsureHolder(state)
                end

                if not state.hooksInstalled then
                    state.hooksInstalled = true
                    hooksecurefunc(viewer, "RefreshLayout", OnViewerLayout)
                    hooksecurefunc(viewer, "Layout", OnViewerLayout)
                    hooksecurefunc(viewer, "ApplySystemAnchor", OnViewerAnchorApplied)
                    hooksecurefunc(viewer, "HighlightSystem", SuppressNativeEditModeHighlight)
                    viewer:HookScript("OnShow", OnViewerShown)
                end
                QueueViewer(viewer, QUEUE_SETTINGS)
            end
        end
    end
end

local function UpdateCooldownManager(_, module, which)
    if module and module ~= "cooldownManager" then return end

    local config = CM.config
    if config and config.enabled then
        InitializeViewers(which)
    else
        for viewer, state in next, viewerStates do
            if not which or state.key == which then
                QueueViewer(viewer, QUEUE_ANCHOR)
            end
        end
    end
    UpdateAssistedHighlightPolling()
    UpdateVisibilityObserver()
end

CM:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", CM.StopEditModePreviews)
EventUtil.ContinueOnAddOnLoaded("Blizzard_CooldownViewer", function()
    UpdateCooldownManager(nil, "cooldownManager")
end)
AF.RegisterCallback("BFI_UpdateModule", UpdateCooldownManager)
AF.RegisterCallback("AF_SCALE_CHANGED", function()
    local config = CM.config
    if not config or not config.enabled then return end
    for viewer in next, viewerStates do
        QueueViewer(viewer, QUEUE_ANCHOR)
    end
end)
AF.RegisterCallback("BFI_UpdateProfile", function()
    UpdateAssistedHighlightPolling()
    UpdateVisibilityObserver()
    RefreshAssistedHighlights()
    for _, state in next, viewerStates do
        local mover = state.holder and state.holder.mover
        if mover and (mover:IsShown() or mover._original) then
            -- Close the active mover transaction before its save table changes
            -- to the newly selected profile.
            AF.HideMovers()
            return
        end
    end
end, "low")
