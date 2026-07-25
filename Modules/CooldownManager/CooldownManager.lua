---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class CooldownManager
local CM = BFI.modules.CooldownManager
---@type AbstractFramework
local AF = _G.AbstractFramework

local _G = _G
local CheckAllowProtectedFunctions = C_RestrictedActions.CheckAllowProtectedFunctions
local GetCVar = GetCVar
local GetCVarBool = GetCVarBool
local InCombatLockdown = InCombatLockdown
local IsValueNonSecret = BFI.funcs.isValueNonSecret
local UnitAffectingCombat = UnitAffectingCombat
local ceil = math.ceil
local max = math.max
local min = math.min
local sort = table.sort
local tonumber = tonumber
local type = type
local unpack = unpack

-- Retail 12.0.7.68887, Gethe/wow-ui-source commit 4383ced30106:
-- https://github.com/Gethe/wow-ui-source/tree/4383ced30106d51b27e3e86d1987f1552f0d259d/Interface/AddOns/Blizzard_CooldownViewer
-- Compatibility checked against Retail 12.1.0.68914, commit d3915c78aba7:
-- https://github.com/Gethe/wow-ui-source/tree/d3915c78aba77a7a9be76acbfa35c674bbb6abe9/Interface/AddOns/Blizzard_CooldownViewer
--
-- Both builds process secret aura and totem values in the viewer/item Lua
-- mixins. Calling those mixins from addon execution (including RefreshLayout,
-- SetIsEditing, or a secure post-hook) contaminates Blizzard's pooled item
-- state and file-local caches. This module therefore has a strict boundary:
-- it never writes a Blizzard Lua field, hooks a Blizzard object, or calls a
-- Cooldown Viewer mixin. It reads only static pool/template state and applies
-- presentation through captured C widget methods. Protected geometry is
-- changed only outside combat and after CheckAllowProtectedFunctions.
local viewerDefinitions = {
    essential = {
        globalName = "EssentialCooldownViewer",
        holderName = "BFI_CooldownManagerEssentialHolder",
        moverName = L["Essential Cooldowns"],
        defaultPosition = {"BOTTOM", 0, 310},
        itemWidth = 50,
        itemHeight = 50,
        previewCount = 12,
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
        previewCount = 7,
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
        previewCount = 6,
        isBuff = true,
    },
    buffBar = {
        globalName = "BuffBarCooldownViewer",
        holderName = "BFI_CooldownManagerBuffBarHolder",
        moverName = L["Buff Bars"],
        defaultPosition = {"BOTTOM", 420, 430},
        itemWidth = 220,
        itemHeight = 30,
        previewCount = 4,
        isBuff = true,
        isBar = true,
    },
}

-- AbstractFramework captures these methods from plain widgets before any
-- addon can replace a method on a Blizzard frame. Use the captured closures
-- instead of method lookup on native Cooldown Viewer objects.
local FrameClearAllPoints = AF.FrameClearAllPoints
local FrameGetSize = AF.FrameGetSize
local FrameHide = AF.FrameHide
local FrameSetFrameLevel = AF.FrameSetFrameLevel
local FrameSetPoint = AF.FrameSetPoint
local FrameSetSize = AF.FrameSetSize
local FrameShow = AF.FrameShow
local TextureHide = AF.TextureHide

local methodFrame = CreateFrame("Frame")
local methodTexture = methodFrame:CreateTexture()
local methodMaskTexture = methodFrame:CreateMaskTexture()
local methodFontString = methodFrame:CreateFontString()
local methodCooldown = CreateFrame("Cooldown")
local methodStatusBar = CreateFrame("StatusBar")
-- Retail exposes several identically named methods through distinct receiver
-- families. A closure captured from Texture:GetAlpha, for example, rejects a
-- Frame even though Frame also implements GetAlpha. Keep every native call
-- paired with the concrete widget type declared by CooldownViewer.xml.
local FrameGetAlpha = methodFrame.GetAlpha
local FrameGetEffectiveScale = methodFrame.GetEffectiveScale
local FrameGetFrameLevel = methodFrame.GetFrameLevel
local FrameGetNumPoints = methodFrame.GetNumPoints
local FrameGetPoint = methodFrame.GetPoint
local FrameGetRegions = methodFrame.GetRegions
local FrameGetScale = methodFrame.GetScale
local FrameIsMouseMotionEnabled = methodFrame.IsMouseMotionEnabled
local FrameIsShown = methodFrame.IsShown
local FrameSetAlpha = methodFrame.SetAlpha
local FrameSetMouseMotionEnabled = methodFrame.SetMouseMotionEnabled
local FrameSetScale = methodFrame.SetScale
local FontStringGetAlpha = methodFontString.GetAlpha
local FontStringIsShown = methodFontString.IsShown
local FontStringSetAlpha = methodFontString.SetAlpha
local FontStringSetTextColor = methodFontString.SetTextColor
local FontStringHide = methodFontString.Hide
local FontStringShow = methodFontString.Show
local MaskTextureHide = methodMaskTexture.Hide
local MaskTextureIsObjectType = methodMaskTexture.IsObjectType
local TextureGetAtlas = methodTexture.GetAtlas
local TextureIsObjectType = methodTexture.IsObjectType
local TextureSetDrawLayer = methodTexture.SetDrawLayer
local TextureSetTexCoord = methodTexture.SetTexCoord
local CooldownGetHideCountdownNumbers = methodCooldown.GetHideCountdownNumbers
local CooldownSetCountdownFont = methodCooldown.SetCountdownFont
local CooldownSetHideCountdownNumbers = methodCooldown.SetHideCountdownNumbers
local StatusBarGetStatusBarTexture = methodStatusBar.GetStatusBarTexture
local StatusBarSetStatusBarTexture = methodStatusBar.SetStatusBarTexture
methodFrame:Hide()
methodStatusBar:Hide()

local FONT_NAME = "BFI_CooldownManagerCountdownFont"
local countdownFont = CreateFont(FONT_NAME)
local viewerStates = {}
local viewerStateByKey = {}
local itemStates = setmetatable({}, {__mode = "k"})
local iconSkins = setmetatable({}, {__mode = "k"})
local barSkins = setmetatable({}, {__mode = "k"})
local assistedHighlights = setmetatable({}, {__mode = "k"})
local assistedBaseSpellIDs = {}
local presentationController = CreateFrame("Frame")
local assistedHighlightController = CreateFrame("Frame")
local assistedHighlightSpellID
local assistedHighlightBaseSpellID
local assistedHighlightUpdateTimeLeft = 0
local presentationUpdateTimeLeft = 0
local presentationGeneration = 1
local fallbackOrder = 0

local function IsSafeBoolean(value)
    return IsValueNonSecret(value) and type(value) == "boolean"
end

local function IsSafeNumber(value)
    return IsValueNonSecret(value) and type(value) == "number"
end

local function IsSafeString(value)
    return IsValueNonSecret(value) and type(value) == "string"
end

local function GetSafeField(owner, key)
    local value = owner[key]
    if not IsValueNonSecret(value) then
        return nil
    end
    return value
end

local function IsWidgetObjectType(region, objectType, isObjectType)
    local matches = isObjectType(region, objectType)
    return IsSafeBoolean(matches) and matches
end

local function NearlyEqual(a, b)
    return math.abs(a - b) < 0.001
end

local function ClampNumber(value, fallback, lower, upper)
    value = type(value) == "number" and value or fallback
    return max(lower, min(value, upper))
end

local function CanChangeGeometry(frame)
    local locked = InCombatLockdown()
    if not IsValueNonSecret(locked) or locked then
        return false
    end

    local allowed = CheckAllowProtectedFunctions(frame, true)
    return IsSafeBoolean(allowed) and allowed
end

-- Both audited clients expose item pools through ObjectPoolProxyMixin. The
-- backing SecureMap is private, so the proxy's read-only EnumerateActive
-- method is the sole supported way to discover items. Unlike Cooldown Viewer
-- mixins, this method only returns the SecureMap iterator and performs no
-- assignment, acquisition, release, reset, or item callback.
local function GetActiveItems(viewer)
    local pool = viewer.itemFramePool
    if not IsValueNonSecret(pool) or type(pool) ~= "table" then
        return nil
    end

    local enumerateActive = pool.EnumerateActive
    if not IsValueNonSecret(enumerateActive) or type(enumerateActive) ~= "function" then
        return nil
    end

    local iterator, invariant, control = enumerateActive(pool)
    if not IsValueNonSecret(iterator)
        or type(iterator) ~= "function"
        or not IsValueNonSecret(invariant)
        or not IsValueNonSecret(control)
    then
        return nil
    end

    local items = {}
    while true do
        local item = iterator(invariant, control)
        if not IsValueNonSecret(item) then
            return nil
        end
        if item == nil then
            break
        end
        items[#items + 1] = item
        control = item
    end
    return items
end

---------------------------------------------------------------------
-- Assisted Combat highlight
---------------------------------------------------------------------
-- Retail 12.0.7 and 12.1 expose the same documented
-- C_AssistedCombat.GetNextCastSpell(false) contract and the same ordinary
-- ActionBarButtonAssistedCombatHighlightTemplate. The recommendation poll is
-- BFI-owned and never calls a Cooldown Viewer item mixin.
local function GetNonSecretSpellID(spellID)
    if not IsSafeNumber(spellID) then
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

    local itemLevel = FrameGetFrameLevel(item)
    if IsSafeNumber(itemLevel) then
        FrameSetFrameLevel(highlight, min(itemLevel + 10, 10000))
    end

    highlight:SetScale(min(definition.itemWidth, definition.itemHeight) / 45)
    highlight.Flipbook.Anim:Play()
    highlight.Flipbook.Anim:Stop()
    highlight:SetAlpha(0)
    highlight:Show()
    return highlight
end

local function GetItemBaseSpellID(item)
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

    local inCombat = UnitAffectingCombat("player")
    inCombat = IsSafeBoolean(inCombat) and inCombat
    local animation = highlight.Flipbook.Anim
    if shown and inCombat then
        if not animation:IsPlaying() then
            animation:Play()
        end
    elseif animation:IsPlaying() then
        animation:Stop()
    end
end

local function RefreshAssistedHighlights()
    for _, state in next, viewerStates do
        if state.definition.assistedHighlight then
            local activeItems = GetActiveItems(state.viewer)
            if activeItems then
                for _, item in ipairs(activeItems) do
                    UpdateItemAssistedHighlight(item)
                end
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
    RefreshAssistedHighlights()
end

local function UpdateAssistedHighlightPolling()
    local config = CM.config
    local cvarEnabled = GetCVarBool("assistedCombatHighlight")
    local enabled = config
        and config.enabled
        and config.assistedHighlight
        and IsSafeBoolean(cvarEnabled)
        and cvarEnabled
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
-- BFI-owned holders and edit-mode previews
---------------------------------------------------------------------
local function MarkPresentationDirty()
    presentationGeneration = presentationGeneration + 1
    presentationUpdateTimeLeft = 0
end

local function EnsureHolder(state)
    if state.holder then return state.holder end

    local holder = CreateFrame("Frame", state.definition.holderName, AF.UIParent)
    holder:SetSize(1, 1)
    holder.enabled = false
    holder:Hide()

    state.holder = holder
    state.previewFrames = {}
    AF.CreateMover(holder, "BFI: " .. L["Cooldown Manager"], state.definition.moverName)
    holder.mover:HookScript("OnShow", MarkPresentationDirty)
    holder.mover:HookScript("OnHide", MarkPresentationDirty)
    return holder
end

local function GetViewerPosition(config, definition)
    local position = config.position
    if type(position) ~= "table" or not next(position) then
        position = AF.Copy(definition.defaultPosition)
        config.position = position
    end

    -- A pre-release implementation marked legacy profiles for a native
    -- position capture. Native viewer geometry is intentionally no longer
    -- inspected, so retire the marker and use the stable BFI default.
    config.captureNativePosition = nil
    return position
end

local function BindHolderPosition(state, config)
    local holder = EnsureHolder(state)
    local position = GetViewerPosition(config, state.definition)
    if state.position ~= position then
        state.position = position
        AF.UpdateMoverSave(holder, position)
        AF.LoadPosition(holder, position, AF.UIParent)
    end

    holder.enabled = true
    holder:Show()
    return holder
end

local function IsBlizzardEditModeActive()
    local editMode = _G.EditModeManagerFrame
    if not editMode then return false end

    local shown = FrameIsShown(editMode)
    return IsSafeBoolean(shown) and shown
end

local function BuildLayout(definition, config, count)
    local orientation = config.orientation == "vertical" and "vertical" or "horizontal"
    local direction = config.direction == "left" and "left" or "right"
    local width = definition.itemWidth
    if definition.isBar then
        width = width * ClampNumber(config.barWidthScale, 1, 0.5, 2)
    end

    local capacity
    if definition.hasIconLimit then
        capacity = ClampNumber(config.iconLimit, definition.previewCount, 1, 20)
        capacity = min(capacity, max(1, count))
    else
        capacity = max(1, count)
    end

    return {
        count = count,
        orientation = orientation,
        direction = direction,
        center = config.center ~= false,
        width = width,
        height = definition.itemHeight,
        padding = ClampNumber(config.padding, 2, 0, 14),
        scale = ClampNumber(config.scale, 1, 0.5, 2),
        capacity = capacity,
    }
end

local function GetLayoutBounds(layout)
    local count = max(1, layout.count)
    local lines = ceil(count / layout.capacity)
    if layout.orientation == "horizontal" then
        return layout.capacity * layout.width + (layout.capacity - 1) * layout.padding,
            lines * layout.height + (lines - 1) * layout.padding
    end
    return lines * layout.width + (lines - 1) * layout.padding,
        layout.capacity * layout.height + (layout.capacity - 1) * layout.padding
end

local function GetLayoutPosition(layout, index)
    local line = math.floor((index - 1) / layout.capacity)
    local position = (index - 1) % layout.capacity
    local lineCount = min(layout.capacity, layout.count - line * layout.capacity)
    local stepX = layout.width + layout.padding
    local stepY = layout.height + layout.padding

    if layout.orientation == "horizontal" then
        local fullWidth = layout.capacity * layout.width
            + (layout.capacity - 1) * layout.padding
        local lineWidth = lineCount * layout.width
            + (lineCount - 1) * layout.padding
        local span = layout.center and lineWidth or fullWidth
        local x
        if layout.direction == "left" then
            x = span / 2 - layout.width / 2 - position * stepX
        else
            x = -span / 2 + layout.width / 2 + position * stepX
        end

        local _, totalHeight = GetLayoutBounds(layout)
        local y = totalHeight / 2 - layout.height / 2 - line * stepY
        return x, y
    end

    local fullHeight = layout.capacity * layout.height
        + (layout.capacity - 1) * layout.padding
    local lineHeight = lineCount * layout.height
        + (lineCount - 1) * layout.padding
    local span = layout.center and lineHeight or fullHeight
    local y
    if layout.direction == "right" then
        y = -span / 2 + layout.height / 2 + position * stepY
    else
        y = span / 2 - layout.height / 2 - position * stepY
    end

    local totalWidth = GetLayoutBounds(layout)
    local x = -totalWidth / 2 + layout.width / 2 + line * stepX
    return x, y
end

local function GetHolderScaleRatio(holder, item, configuredScale)
    local holderScale = FrameGetEffectiveScale(holder)
    if not IsSafeNumber(holderScale) or holderScale <= 0 then
        return configuredScale
    end

    local effectiveScale
    if item then
        effectiveScale = FrameGetEffectiveScale(item)
    else
        effectiveScale = FrameGetEffectiveScale(_G.UIParent)
        if IsSafeNumber(effectiveScale) then
            effectiveScale = effectiveScale * configuredScale
        end
    end

    if not IsSafeNumber(effectiveScale) or effectiveScale <= 0 then
        return configuredScale
    end
    return effectiveScale / holderScale
end

local function EnsurePreviewFrame(state, index)
    local preview = state.previewFrames[index]
    if preview then return preview end

    preview = AF.CreateBorderedFrame(state.holder)
    preview:SetBackdropColor(AF.GetColorRGB("widget_dark", 0.65))
    preview:SetBackdropBorderColor(AF.GetColorRGB("BFI", 0.8))
    preview:EnableMouse(false)
    state.previewFrames[index] = preview
    return preview
end

local function UpdateHolderPreview(state, layout, firstItem)
    local holder = state.holder
    local scaleRatio = GetHolderScaleRatio(holder, firstItem, layout.scale)
    local width, height = GetLayoutBounds(layout)
    FrameSetSize(holder, max(1, width * scaleRatio), max(1, height * scaleRatio))

    local moverShown = FrameIsShown(holder.mover)
    moverShown = IsSafeBoolean(moverShown) and moverShown
    local previewCount = moverShown and layout.count or 0

    for index = 1, previewCount do
        local preview = EnsurePreviewFrame(state, index)
        local x, y = GetLayoutPosition(layout, index)
        FrameSetSize(preview, layout.width * scaleRatio, layout.height * scaleRatio)
        FrameClearAllPoints(preview)
        FrameSetPoint(preview, "CENTER", holder, "CENTER", x * scaleRatio, y * scaleRatio)
        FrameShow(preview)
    end
    for index = previewCount + 1, #state.previewFrames do
        FrameHide(state.previewFrames[index])
    end
end

---------------------------------------------------------------------
-- Guarded geometry capture and restoration
---------------------------------------------------------------------
local function CapturePoints(frame)
    local numPoints = FrameGetNumPoints(frame)
    if not IsSafeNumber(numPoints) or numPoints < 0 then
        return nil
    end

    local points = {}
    for index = 1, numPoints do
        local point, relativeTo, relativePoint, x, y = FrameGetPoint(frame, index)
        if not IsSafeString(point)
            or not IsValueNonSecret(relativeTo)
            or not IsSafeString(relativePoint)
            or not IsSafeNumber(x)
            or not IsSafeNumber(y)
        then
            return nil
        end
        points[index] = {point, relativeTo, relativePoint, x, y}
    end
    return points
end

local function RestorePoints(frame, points)
    FrameClearAllPoints(frame)
    for _, point in ipairs(points) do
        FrameSetPoint(frame, unpack(point))
    end
end

local function CaptureNativeGeometry(item, itemState)
    local points = CapturePoints(item)
    local width, height = FrameGetSize(item)
    local scale = FrameGetScale(item)
    if not points
        or not IsSafeNumber(width)
        or not IsSafeNumber(height)
        or not IsSafeNumber(scale)
    then
        return false
    end

    itemState.nativePoints = points
    itemState.nativeWidth = width
    itemState.nativeHeight = height
    itemState.nativeScale = scale
    return true
end

local function CaptureShown(region, getShown)
    if not IsValueNonSecret(region) or not region then return nil end
    local shown = getShown(region)
    if IsSafeBoolean(shown) then
        return shown
    end
    return nil
end

local function CaptureAlpha(region, getAlpha)
    if not IsValueNonSecret(region) or not region then return nil end
    local alpha = getAlpha(region)
    if IsSafeNumber(alpha) then
        return alpha
    end
    return nil
end

local function CapturePresentationDefaults(item, definition, itemState)
    if itemState.presentationCaptured then return end
    itemState.presentationCaptured = true

    itemState.nativeAlpha = CaptureAlpha(item, FrameGetAlpha)
    local mouseMotion = FrameIsMouseMotionEnabled(item)
    if IsSafeBoolean(mouseMotion) then
        itemState.nativeMouseMotion = mouseMotion
    end

    local cooldown = GetSafeField(item, "Cooldown")
    if cooldown then
        local hideNumbers = CooldownGetHideCountdownNumbers(cooldown)
        if IsSafeBoolean(hideNumbers) then
            itemState.nativeHideCountdownNumbers = hideNumbers
        end

        local cooldownFont = item.cooldownFont
        if IsSafeString(cooldownFont) then
            itemState.nativeCooldownFont = cooldownFont
        end
    end

    if definition.isBar then
        local icon = GetSafeField(item, "Icon")
        local bar = GetSafeField(item, "Bar")
        if icon then
            itemState.nativeIconShown = CaptureShown(icon, FrameIsShown)
            itemState.nativeIconAlpha = CaptureAlpha(icon, FrameGetAlpha)
        end
        if bar then
            itemState.nativeBarPoints = CapturePoints(bar)
            local name = GetSafeField(bar, "Name")
            local duration = GetSafeField(bar, "Duration")
            itemState.nativeNameShown = CaptureShown(name, FontStringIsShown)
            itemState.nativeNameAlpha = CaptureAlpha(name, FontStringGetAlpha)
            itemState.nativeDurationShown = CaptureShown(duration, FontStringIsShown)
            itemState.nativeDurationAlpha = CaptureAlpha(duration, FontStringGetAlpha)
        end
    end
end

local function RecapturePresentationDefaults(item, definition, itemState)
    itemState.presentationCaptured = nil
    itemState.nativeAlpha = nil
    itemState.nativeMouseMotion = nil
    itemState.nativeHideCountdownNumbers = nil
    itemState.nativeCooldownFont = nil
    itemState.nativeBarPoints = nil
    itemState.nativeIconShown = nil
    itemState.nativeIconAlpha = nil
    itemState.nativeNameShown = nil
    itemState.nativeNameAlpha = nil
    itemState.nativeDurationShown = nil
    itemState.nativeDurationAlpha = nil
    CapturePresentationDefaults(item, definition, itemState)
    itemState.recapturePresentation = nil
end

local function SetShown(region, shown, show, hide)
    if shown == nil or not IsValueNonSecret(region) or not region then return end
    if shown then
        show(region)
    else
        hide(region)
    end
end

local function RestoreItemPresentation(item, definition, itemState)
    if itemState.nativeAlpha ~= nil then
        FrameSetAlpha(item, itemState.nativeAlpha)
    end
    if itemState.nativeMouseMotion ~= nil then
        FrameSetMouseMotionEnabled(item, itemState.nativeMouseMotion)
    end

    local cooldown = GetSafeField(item, "Cooldown")
    if cooldown then
        if itemState.nativeHideCountdownNumbers ~= nil then
            CooldownSetHideCountdownNumbers(cooldown, itemState.nativeHideCountdownNumbers)
        end
        if itemState.nativeCooldownFont then
            CooldownSetCountdownFont(cooldown, itemState.nativeCooldownFont)
        end
    end

    if definition.isBar then
        local icon = GetSafeField(item, "Icon")
        local bar = GetSafeField(item, "Bar")
        if icon then
            SetShown(icon, itemState.nativeIconShown, FrameShow, FrameHide)
            if itemState.nativeIconAlpha ~= nil then
                FrameSetAlpha(icon, itemState.nativeIconAlpha)
            end
        end
        if bar then
            local name = GetSafeField(bar, "Name")
            local duration = GetSafeField(bar, "Duration")
            SetShown(name, itemState.nativeNameShown, FontStringShow, FontStringHide)
            SetShown(duration, itemState.nativeDurationShown, FontStringShow, FontStringHide)
            if itemState.nativeNameAlpha ~= nil then
                FontStringSetAlpha(name, itemState.nativeNameAlpha)
            end
            if itemState.nativeDurationAlpha ~= nil then
                FontStringSetAlpha(duration, itemState.nativeDurationAlpha)
            end
        end
    end

    local highlight = assistedHighlights[item]
    if highlight then
        highlight:SetAlpha(0)
    end
    itemState.presentationGeneration = nil
end

local function CanRestoreItemPresentation(item, definition)
    local cooldown = GetSafeField(item, "Cooldown")
    if cooldown and not CanChangeGeometry(cooldown) then
        return false
    end

    if definition.isBar then
        local icon = GetSafeField(item, "Icon")
        local bar = GetSafeField(item, "Bar")
        local name = bar and GetSafeField(bar, "Name")
        local duration = bar and GetSafeField(bar, "Duration")
        if (icon and not CanChangeGeometry(icon))
            or (bar and not CanChangeGeometry(bar))
            or (name and not CanChangeGeometry(name))
            or (duration and not CanChangeGeometry(duration))
        then
            return false
        end
    end
    return true
end

local function RestoreItem(item, itemState)
    if not itemState.applied and itemState.presentationRestored then
        return true
    end
    if not CanChangeGeometry(item) then
        return false
    end
    if not CanRestoreItemPresentation(item, itemState.definition) then
        return false
    end
    if not itemState.applied then
        RestoreItemPresentation(item, itemState.definition, itemState)
        itemState.presentationRestored = true
        itemState.recapturePresentation = true
        return true
    end
    local bar = itemState.definition.isBar and GetSafeField(item, "Bar")
    if bar and not CanChangeGeometry(bar) then
        return false
    end

    FrameSetSize(item, itemState.nativeWidth, itemState.nativeHeight)
    FrameSetScale(item, itemState.nativeScale)
    RestorePoints(item, itemState.nativePoints)
    if bar and itemState.nativeBarPoints then
        RestorePoints(bar, itemState.nativeBarPoints)
    end

    RestoreItemPresentation(item, itemState.definition, itemState)
    itemState.applied = nil
    itemState.expected = nil
    itemState.presentationRestored = true
    itemState.recapturePresentation = true
    return true
end

---------------------------------------------------------------------
-- Hook-free skin and direct widget presentation
---------------------------------------------------------------------
local function CreateNativeChildBackdrop(parent, target, withBackground, levelOffset)
    local backdrop = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if withBackground then
        AF.ApplyDefaultBackdropWithColors(backdrop, "widget_dark", "border")
    else
        AF.ApplyDefaultBackdrop_NoBackground(backdrop)
    end
    backdrop:SetAllPoints(target)
    backdrop:EnableMouse(false)

    local parentLevel = FrameGetFrameLevel(parent)
    if IsSafeNumber(parentLevel) then
        FrameSetFrameLevel(backdrop, max(0, min(10000, parentLevel + levelOffset)))
    end
    return backdrop
end

local function GetIconMaskAndOverlay(iconParent)
    local _, mask, overlay = FrameGetRegions(iconParent)

    if IsValueNonSecret(mask) and mask then
        if not IsWidgetObjectType(mask, "MaskTexture", MaskTextureIsObjectType) then
            mask = nil
        end
    else
        mask = nil
    end

    if IsValueNonSecret(overlay) and overlay then
        if not IsWidgetObjectType(overlay, "Texture", TextureIsObjectType) then
            overlay = nil
        else
            local atlas = TextureGetAtlas(overlay)
            if not IsSafeString(atlas)
                or atlas ~= "UI-HUD-CoolDownManager-IconOverlay"
            then
                overlay = nil
            end
        end
    else
        overlay = nil
    end
    return mask, overlay
end

local function SkinIcon(iconParent, icon)
    if not IsValueNonSecret(iconParent) or not IsValueNonSecret(icon) then return end

    local skin = iconSkins[icon]
    if not skin then
        local mask, overlay = GetIconMaskAndOverlay(iconParent)
        skin = {
            mask = mask,
            overlay = overlay,
            border = CreateNativeChildBackdrop(iconParent, icon, false, 1),
        }
        iconSkins[icon] = skin
    end

    TextureSetTexCoord(icon, AF.GetDefaultTexCoord())
    if skin.mask then MaskTextureHide(skin.mask) end
    if skin.overlay then TextureHide(skin.overlay) end
    FrameShow(skin.border)
end

local function SkinBar(bar)
    if not IsValueNonSecret(bar) then return end

    local skin = barSkins[bar]
    if not skin then
        skin = {
            backdrop = CreateNativeChildBackdrop(bar, bar, true, -1),
        }
        barSkins[bar] = skin
    end

    local background = GetSafeField(bar, "BarBG")
    if background then
        TextureHide(background)
    end
    StatusBarSetStatusBarTexture(bar, BFI.media.bar)
    local fill = StatusBarGetStatusBarTexture(bar)
    if IsValueNonSecret(fill) and fill then
        TextureSetDrawLayer(fill, "BORDER", -1)
    end
    FrameShow(skin.backdrop)
end

local function ApplyFont(fontString, config)
    if not IsValueNonSecret(fontString) or not fontString or not config then return end
    AF.SetFont(fontString, config.font)
    FontStringSetTextColor(fontString, AF.UnpackColor(config.color))
end

local function GetCountText(item, definition)
    if definition.isBar then
        local icon = GetSafeField(item, "Icon")
        return icon and GetSafeField(icon, "Applications")
    elseif definition.isBuff then
        local applications = GetSafeField(item, "Applications")
        return applications and GetSafeField(applications, "Applications")
    end

    local chargeCount = GetSafeField(item, "ChargeCount")
    return chargeCount and GetSafeField(chargeCount, "Current")
end

local function CanApplyStaticPresentation(item, state)
    if not CanChangeGeometry(item) then
        return false
    end

    local definition = state.definition
    local itemIcon = GetSafeField(item, "Icon")
    local iconParent = definition.isBar and itemIcon or item
    local icon = definition.isBar
        and itemIcon
        and GetSafeField(itemIcon, "Icon")
        or itemIcon
    local cooldown = GetSafeField(item, "Cooldown")
    local countText = GetCountText(item, definition)
    if (iconParent and not CanChangeGeometry(iconParent))
        or (icon and not CanChangeGeometry(icon))
        or (cooldown and not CanChangeGeometry(cooldown))
        or (countText and not CanChangeGeometry(countText))
    then
        return false
    end

    if CM.config.skin and iconParent then
        local mask, overlay = GetIconMaskAndOverlay(iconParent)
        if (mask and not CanChangeGeometry(mask))
            or (overlay and not CanChangeGeometry(overlay))
        then
            return false
        end
    end

    if definition.isBar then
        local bar = GetSafeField(item, "Bar")
        local name = bar and GetSafeField(bar, "Name")
        local duration = bar and GetSafeField(bar, "Duration")
        local background = bar and GetSafeField(bar, "BarBG")
        local fill = bar and StatusBarGetStatusBarTexture(bar)
        if (bar and not CanChangeGeometry(bar))
            or (name and not CanChangeGeometry(name))
            or (duration and not CanChangeGeometry(duration))
            or (background and not CanChangeGeometry(background))
            or (IsValueNonSecret(fill) and fill and not CanChangeGeometry(fill))
        then
            return false
        end
        if not IsValueNonSecret(fill) then
            return false
        end
    end
    return true
end

local function ApplyBarContent(item, config, itemState)
    local icon = GetSafeField(item, "Icon")
    local bar = GetSafeField(item, "Bar")
    if not icon
        or not bar
        or not itemState.nativeBarPoints
        or itemState.nativeIconShown == nil
        or itemState.nativeNameShown == nil
        or itemState.nativeDurationShown == nil
    then
        return
    end
    local name = GetSafeField(bar, "Name")
    local duration = GetSafeField(bar, "Duration")
    if not name or not duration then return end

    local content = config.barContent
    if content == "icon_only" then
        FrameShow(icon)
        FontStringHide(name)
    elseif content == "name_only" then
        FrameHide(icon)
        FontStringShow(name)
    else
        FrameShow(icon)
        FontStringShow(name)
    end

    if config.showTimer == false then
        FontStringHide(duration)
    else
        FontStringShow(duration)
    end

    local nameOnly = content == "name_only"
    FrameClearAllPoints(bar)
    FrameSetPoint(
        bar,
        "LEFT",
        icon,
        nameOnly and "LEFT" or "RIGHT",
        nameOnly and 0 or 2,
        0
    )
    FrameSetPoint(bar, "RIGHT", item, "RIGHT", 0, 0)
    itemState.barExpectedNameOnly = nameOnly
end

local function ApplyStaticPresentation(item, state, config, itemState)
    CapturePresentationDefaults(item, state.definition, itemState)

    if state.definition.assistedHighlight and CM.config.assistedHighlight then
        EnsureAssistedHighlight(item, state.definition)
    end

    if CM.config.skin then
        local itemIcon = GetSafeField(item, "Icon")
        local iconParent = state.definition.isBar and itemIcon or item
        local icon = state.definition.isBar
            and itemIcon
            and GetSafeField(itemIcon, "Icon")
            or itemIcon
        if iconParent and icon then
            SkinIcon(iconParent, icon)
        end
        local bar = state.definition.isBar and GetSafeField(item, "Bar")
        if bar then
            SkinBar(bar)
        end
    end

    local cooldown = GetSafeField(item, "Cooldown")
    if cooldown
        and itemState.nativeHideCountdownNumbers ~= nil
        and itemState.nativeCooldownFont
    then
        CooldownSetCountdownFont(cooldown, FONT_NAME)
        CooldownSetHideCountdownNumbers(cooldown, config.showTimer == false)
    end

    ApplyFont(GetCountText(item, state.definition), CM.config.countText)

    local bar = state.definition.isBar and GetSafeField(item, "Bar")
    if bar then
        ApplyFont(GetSafeField(bar, "Name"), CM.config.barText)
        ApplyFont(GetSafeField(bar, "Duration"), CM.config.barText)
        ApplyBarContent(item, config, itemState)
    end

    itemState.presentationGeneration = presentationGeneration
    itemState.presentationRestored = nil
    UpdateItemAssistedHighlight(item)
end

local function GetPresentationAlpha(config)
    local alpha = ClampNumber(config.opacity, 1, 0.5, 1)
    if config.visibility == "hidden" then
        return 0
    end
    if config.visibility == "combat" then
        local inCombat = UnitAffectingCombat("player")
        if IsSafeBoolean(inCombat) and not inCombat then
            return 0
        end
    end
    return alpha
end

local function ApplyRuntimePresentation(item, config, itemState)
    CapturePresentationDefaults(item, itemState.definition, itemState)

    if itemState.nativeAlpha ~= nil then
        local desiredAlpha = GetPresentationAlpha(config)
        local currentAlpha = FrameGetAlpha(item)
        if IsSafeNumber(currentAlpha) and not NearlyEqual(currentAlpha, desiredAlpha) then
            FrameSetAlpha(item, desiredAlpha)
        end
    end

    if itemState.nativeMouseMotion ~= nil then
        local tooltips = config.showTooltips ~= false
        local mouseMotion = FrameIsMouseMotionEnabled(item)
        if IsSafeBoolean(mouseMotion)
            and mouseMotion ~= tooltips
            and CanChangeGeometry(item)
        then
            FrameSetMouseMotionEnabled(item, tooltips)
        end
    end
    itemState.presentationRestored = nil
    UpdateItemAssistedHighlight(item)
end

---------------------------------------------------------------------
-- Independent presentation reconciliation
---------------------------------------------------------------------
local function GetOrCreateItemState(item, state, layoutIndex)
    local itemState = itemStates[item]
    if not itemState then
        fallbackOrder = fallbackOrder + 1
        itemState = {
            definition = state.definition,
            owner = state,
            fallbackOrder = fallbackOrder,
        }
        itemStates[item] = itemState
    end

    itemState.layoutIndex = layoutIndex
    return itemState
end

local function GetOrderedItems(state)
    local activeItems = GetActiveItems(state.viewer)
    if not activeItems then
        return {}, {}
    end

    local allItems = {}
    local visibleItems = {}
    for _, item in ipairs(activeItems) do
        if IsValueNonSecret(item) and item then
            local layoutIndex = item.layoutIndex
            if IsSafeNumber(layoutIndex) then
                local itemState = GetOrCreateItemState(item, state, layoutIndex)
                local entry = {
                    item = item,
                    itemState = itemState,
                    layoutIndex = layoutIndex,
                    fallbackOrder = itemState.fallbackOrder,
                }
                allItems[#allItems + 1] = entry

                local shown = FrameIsShown(item)
                if not IsSafeBoolean(shown) or shown then
                    visibleItems[#visibleItems + 1] = entry
                end
            end
        end
    end

    local function SortItems(a, b)
        if a.layoutIndex == b.layoutIndex then
            return a.fallbackOrder < b.fallbackOrder
        end
        return a.layoutIndex < b.layoutIndex
    end
    sort(allItems, SortItems)
    sort(visibleItems, SortItems)
    return allItems, visibleItems
end

local function CurrentGeometryMatches(item, holder, desired)
    local numPoints = FrameGetNumPoints(item)
    local width, height = FrameGetSize(item)
    local scale = FrameGetScale(item)
    if not IsSafeNumber(numPoints)
        or not IsSafeNumber(width)
        or not IsSafeNumber(height)
        or not IsSafeNumber(scale)
    then
        return nil
    end
    if numPoints ~= 1
        or not NearlyEqual(width, desired.width)
        or not NearlyEqual(height, desired.height)
        or not NearlyEqual(scale, desired.scale)
    then
        return false
    end

    local point, relativeTo, relativePoint, x, y = FrameGetPoint(item, 1)
    if not IsSafeString(point)
        or not IsValueNonSecret(relativeTo)
        or not IsSafeString(relativePoint)
        or not IsSafeNumber(x)
        or not IsSafeNumber(y)
    then
        return nil
    end
    return point == "CENTER"
        and relativeTo == holder
        and relativePoint == "CENTER"
        and NearlyEqual(x, desired.x)
        and NearlyEqual(y, desired.y)
end

local function IsAnchoredToHolder(item, holder)
    local numPoints = FrameGetNumPoints(item)
    if not IsSafeNumber(numPoints) then
        return nil
    end
    if numPoints ~= 1 then
        return false
    end

    local point, relativeTo, relativePoint, x, y = FrameGetPoint(item, 1)
    if not IsSafeString(point)
        or not IsValueNonSecret(relativeTo)
        or not IsSafeString(relativePoint)
        or not IsSafeNumber(x)
        or not IsSafeNumber(y)
    then
        return nil
    end
    return relativeTo == holder
end

local function PrepareItemGeometry(entry, state, desired)
    local item = entry.item
    local itemState = entry.itemState
    if itemState.applied then
        local stillAnchored = IsAnchoredToHolder(item, state.holder)
        if stillAnchored == nil then
            return false
        end
        if not stillAnchored then
            itemState.applied = nil
            itemState.expected = nil
        end
    end

    if not itemState.applied and not CaptureNativeGeometry(item, itemState) then
        return false
    end

    local matches = CurrentGeometryMatches(item, state.holder, desired)
    if matches == nil then
        return false
    end

    entry.desired = desired
    entry.needsGeometry = not matches or not itemState.applied
    return true
end

local function ApplyItemGeometry(entry, state)
    if not entry.needsGeometry then return end

    local item = entry.item
    local desired = entry.desired
    FrameSetSize(item, desired.width, desired.height)
    FrameSetScale(item, desired.scale)
    FrameClearAllPoints(item)
    FrameSetPoint(item, "CENTER", state.holder, "CENTER", desired.x, desired.y)

    local itemState = entry.itemState
    itemState.applied = true
    itemState.expected = desired
    itemState.presentationRestored = nil
end

local function RestoreMissingItems(state, activeSet)
    local restored = true
    for item, itemState in next, itemStates do
        if itemState.owner == state and itemState.applied and not activeSet[item] then
            restored = RestoreItem(item, itemState) and restored
        end
    end
    return restored
end

local function ReconcileViewer(state, config)
    BindHolderPosition(state, config)
    local allItems, visibleItems = GetOrderedItems(state)
    local activeSet = {}
    for _, entry in ipairs(allItems) do
        activeSet[entry.item] = true
    end

    if IsBlizzardEditModeActive() then
        local restored = true
        for _, entry in ipairs(allItems) do
            restored = RestoreItem(entry.item, entry.itemState) and restored
        end
        RestoreMissingItems(state, activeSet)

        local previewLayout = BuildLayout(state.definition, config, state.definition.previewCount)
        UpdateHolderPreview(state, previewLayout)
        return restored
    end

    RestoreMissingItems(state, activeSet)

    local layoutCount = #visibleItems
    local displayCount = layoutCount > 0 and layoutCount or state.definition.previewCount
    local layout = BuildLayout(state.definition, config, displayCount)

    if layoutCount == 0 then
        UpdateHolderPreview(state, layout)
        return true
    end

    layout.count = layoutCount
    local needsGeometry = false
    for index, entry in ipairs(visibleItems) do
        local x, y = GetLayoutPosition(layout, index)
        local desired = {
            x = x,
            y = y,
            width = layout.width,
            height = layout.height,
            scale = layout.scale,
        }
        if not PrepareItemGeometry(entry, state, desired) then
            UpdateHolderPreview(state, layout, visibleItems[1].item)
            return false
        end
        needsGeometry = needsGeometry or entry.needsGeometry
    end

    for _, entry in ipairs(allItems) do
        if entry.itemState.recapturePresentation then
            RecapturePresentationDefaults(
                entry.item,
                state.definition,
                entry.itemState
            )
        end
        ApplyRuntimePresentation(entry.item, config, entry.itemState)
    end

    if needsGeometry then
        for _, entry in ipairs(visibleItems) do
            local bar = state.definition.isBar and GetSafeField(entry.item, "Bar")
            if entry.needsGeometry and (not CanChangeGeometry(entry.item)
                or (bar and not CanChangeGeometry(bar)))
            then
                UpdateHolderPreview(state, layout, visibleItems[1].item)
                return false
            end
        end
        for _, entry in ipairs(visibleItems) do
            ApplyItemGeometry(entry, state)
        end
    end

    local needsStaticPresentation = false
    for _, entry in ipairs(visibleItems) do
        if entry.needsGeometry
            or entry.itemState.presentationGeneration ~= presentationGeneration
        then
            needsStaticPresentation = true
            if not CanApplyStaticPresentation(entry.item, state) then
                needsStaticPresentation = false
                break
            end
        end
    end

    if needsStaticPresentation then
        AF.SetFont(countdownFont, CM.config.cooldownText.font)
        countdownFont:SetTextColor(AF.UnpackColor(CM.config.cooldownText.color))
        for _, entry in ipairs(visibleItems) do
            if entry.needsGeometry
                or entry.itemState.presentationGeneration ~= presentationGeneration
            then
                ApplyStaticPresentation(entry.item, state, config, entry.itemState)
            end
        end
    end

    UpdateHolderPreview(state, layout, visibleItems[1].item)
    return true
end

local function RestoreViewer(state)
    local restored = true
    for item, itemState in next, itemStates do
        if itemState.owner == state then
            restored = RestoreItem(item, itemState) and restored
        end
    end

    local holder = state.holder
    if holder and restored then
        holder.enabled = false
        if FrameIsShown(holder.mover) then
            FrameHide(holder.mover)
        end
        for _, preview in ipairs(state.previewFrames) do
            FrameHide(preview)
        end
        FrameHide(holder)
        state.position = nil
    end
    return restored
end

local function InitializeViewers()
    for key, definition in next, viewerDefinitions do
        if not viewerStateByKey[key] then
            local viewer = _G[definition.globalName]
            if IsValueNonSecret(viewer) and viewer then
                local state = {
                    viewer = viewer,
                    definition = definition,
                    key = key,
                }
                viewerStates[#viewerStates + 1] = state
                viewerStateByKey[key] = state
            end
        end
    end
end

local function PollPresentation(_, elapsed)
    presentationUpdateTimeLeft = presentationUpdateTimeLeft - elapsed
    if presentationUpdateTimeLeft > 0 then return end
    presentationUpdateTimeLeft = 0.15

    InitializeViewers()
    local config = CM.config
    local enabled = config and config.enabled and type(config.viewers) == "table"
    local allRestored = true

    for _, state in ipairs(viewerStates) do
        local viewerConfig = enabled and config.viewers[state.key]
        if type(viewerConfig) == "table" then
            ReconcileViewer(state, viewerConfig)
        else
            allRestored = RestoreViewer(state) and allRestored
        end
    end

    if not enabled and allRestored then
        presentationController:SetScript("OnUpdate", nil)
    end
end

local function StartPresentationPolling()
    presentationUpdateTimeLeft = 0
    presentationController:SetScript("OnUpdate", PollPresentation)
end

local function UpdateCooldownManager(_, module)
    if module and module ~= "cooldownManager" then return end

    MarkPresentationDirty()
    StartPresentationPolling()
    UpdateAssistedHighlightPolling()
end

presentationController:RegisterEvent("PLAYER_REGEN_ENABLED")
presentationController:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
presentationController:SetScript("OnEvent", StartPresentationPolling)

EventUtil.ContinueOnAddOnLoaded("Blizzard_CooldownViewer", function()
    UpdateCooldownManager(nil, "cooldownManager")
end)
AF.RegisterCallback("BFI_UpdateModule", UpdateCooldownManager)
AF.RegisterCallback("AF_SCALE_CHANGED", UpdateCooldownManager)
AF.RegisterCallback("BFI_UpdateProfile", function()
    for _, state in ipairs(viewerStates) do
        local mover = state.holder and state.holder.mover
        if mover and (FrameIsShown(mover) or mover._original) then
            AF.HideMovers()
            break
        end
    end
    UpdateCooldownManager(nil, "cooldownManager")
end, "low")
