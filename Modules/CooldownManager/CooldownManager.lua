---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class CooldownManager
local CM = BFI.modules.CooldownManager
---@type AbstractFramework
local AF = _G.AbstractFramework

local _G = _G
local CheckAllowProtectedFunctions = C_RestrictedActions.CheckAllowProtectedFunctions
local GetBindingKey = GetBindingKey
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

local ACTION_BUTTONS_PER_PAGE = 12
local directActionPageBindings = {
    [3] = "MULTIACTIONBAR3BUTTON",
    [4] = "MULTIACTIONBAR4BUTTON",
    [5] = "MULTIACTIONBAR2BUTTON",
    [6] = "MULTIACTIONBAR1BUTTON",
    [13] = "MULTIACTIONBAR5BUTTON",
    [14] = "MULTIACTIONBAR6BUTTON",
    [15] = "MULTIACTIONBAR7BUTTON",
}
local bfiActionBarPriority = {
    "bar1",
    "bar2",
    "bar3",
    "bar4",
    "bar5",
    "bar6",
    "bar7",
    "bar8",
    "bar9",
    "classbar1",
    "classbar2",
    "classbar3",
    "classbar4",
}
local anchorPoints = {
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
local horizontalJustification = {
    TOPLEFT = "LEFT",
    LEFT = "LEFT",
    BOTTOMLEFT = "LEFT",
    TOPRIGHT = "RIGHT",
    RIGHT = "RIGHT",
    BOTTOMRIGHT = "RIGHT",
}
local verticalJustification = {
    TOPLEFT = "TOP",
    TOP = "TOP",
    TOPRIGHT = "TOP",
    BOTTOMLEFT = "BOTTOM",
    BOTTOM = "BOTTOM",
    BOTTOMRIGHT = "BOTTOM",
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
local FrameCreateTexture = methodFrame.CreateTexture
local FrameGetEffectiveScale = methodFrame.GetEffectiveScale
local FrameGetFrameLevel = methodFrame.GetFrameLevel
local FrameGetNumPoints = methodFrame.GetNumPoints
local FrameGetPoint = methodFrame.GetPoint
local FrameGetRegions = methodFrame.GetRegions
local FrameGetScale = methodFrame.GetScale
local FrameIsMouseMotionEnabled = methodFrame.IsMouseMotionEnabled
local FrameIsShown = methodFrame.IsShown
local FrameSetAlpha = methodFrame.SetAlpha
local FrameSetAllPoints = methodFrame.SetAllPoints
local FrameCreateFontString = methodFrame.CreateFontString
local FrameSetMouseMotionEnabled = methodFrame.SetMouseMotionEnabled
local FrameSetScale = methodFrame.SetScale
local FontStringClearAllPoints = methodFontString.ClearAllPoints
local FontStringGetAlpha = methodFontString.GetAlpha
local FontStringIsShown = methodFontString.IsShown
local FontStringSetAlpha = methodFontString.SetAlpha
local FontStringSetDrawLayer = methodFontString.SetDrawLayer
local FontStringSetJustifyH = methodFontString.SetJustifyH
local FontStringSetJustifyV = methodFontString.SetJustifyV
local FontStringSetPoint = methodFontString.SetPoint
local FontStringSetText = methodFontString.SetText
local FontStringSetTextColor = methodFontString.SetTextColor
local FontStringSetWidth = methodFontString.SetWidth
local FontStringHide = methodFontString.Hide
local FontStringShow = methodFontString.Show
local MaskTextureHide = methodMaskTexture.Hide
local MaskTextureIsObjectType = methodMaskTexture.IsObjectType
local TextureGetAtlas = methodTexture.GetAtlas
local TextureIsObjectType = methodTexture.IsObjectType
local TextureSetColorTexture = methodTexture.SetColorTexture
local TextureSetDrawLayer = methodTexture.SetDrawLayer
local TextureSetHeight = methodTexture.SetHeight
local TextureSetPoint = methodTexture.SetPoint
local TextureSetTexCoord = methodTexture.SetTexCoord
local TextureSetWidth = methodTexture.SetWidth
local CooldownGetHideCountdownNumbers = methodCooldown.GetHideCountdownNumbers
local CooldownSetHideCountdownNumbers = methodCooldown.SetHideCountdownNumbers
local CooldownSetSwipeTexture = methodCooldown.SetSwipeTexture
local StatusBarGetStatusBarTexture = methodStatusBar.GetStatusBarTexture
local StatusBarSetStatusBarTexture = methodStatusBar.SetStatusBarTexture
-- Both audited builds expose Cooldown:GetCountdownFontString without secret
-- return annotations. The returned FontString's color and anchor getters can
-- still yield secret aspects, so their receiver-correct captures are guarded
-- together and styling fails closed if any part is unsafe.
local PresentationMethods = {
    GetCountdownFontString = methodCooldown.GetCountdownFontString,
    GetFontObject = methodFontString.GetFontObject,
    GetJustifyH = methodFontString.GetJustifyH,
    GetJustifyV = methodFontString.GetJustifyV,
    GetNumPoints = methodFontString.GetNumPoints,
    GetPoint = methodFontString.GetPoint,
    GetShadowColor = methodFontString.GetShadowColor,
    GetShadowOffset = methodFontString.GetShadowOffset,
    GetTextColor = methodFontString.GetTextColor,
    SetFontObject = methodFontString.SetFontObject,
    SetShadowColor = methodFontString.SetShadowColor,
    SetShadowOffset = methodFontString.SetShadowOffset,
}
methodFrame:Hide()
methodStatusBar:Hide()

local nativeSkinBorderColor = {AF.GetColorRGB("border")}
local nativeSkinBackgroundColor = {AF.GetColorRGB("widget_dark")}
-- Blizzard's CDM swipe has rounded alpha corners. Swap only its texture so
-- Blizzard remains authoritative for each cooldown's live swipe color.
local nativeCooldownSwipeTexture =
    "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local squareCooldownSwipeTexture = AF.GetPlainTexture()
local viewerStates = {}
local viewerStateByKey = {}
local itemStates = setmetatable({}, {__mode = "k"})
local iconSkins = setmetatable({}, {__mode = "k"})
local barSkins = setmetatable({}, {__mode = "k"})
local hotkeyOverlays = setmetatable({}, {__mode = "k"})
local bfiActionButtonActions = setmetatable({}, {__mode = "k"})
local assistedHighlights = setmetatable({}, {__mode = "k"})
local assistedBaseSpellIDs = {}
local presentationController = CreateFrame("Frame")
local assistedHighlightController = CreateFrame("Frame")
local assistedHighlightSpellID
local assistedHighlightBaseSpellID
local assistedHighlightUpdateTimeLeft = 0
local presentationUpdateTimeLeft = 0
local presentationGeneration = 1
local hotkeyGeneration = 1
local fallbackOrder = 0
local ApplyFont

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
    highlight:SetAllPoints(item)

    local itemLevel = FrameGetFrameLevel(item)
    if IsSafeNumber(itemLevel) then
        FrameSetFrameLevel(highlight, min(itemLevel + 10, 10000))
    end

    -- Match BFI action buttons: keep the highlight frame square with the
    -- cooldown item and size the higher-resolution ants atlas around its
    -- actual edges instead of scaling the 45x45 template as a whole.
    local scaleX = definition.itemWidth / 45
    local scaleY = definition.itemHeight / 45
    local flipbookWidth = 66 * scaleX
    local flipbookHeight = 66 * scaleY
    local offsetX = (definition.itemWidth - flipbookWidth) / 2 - 1
    local offsetY = (definition.itemHeight - flipbookHeight) / 2 - 1

    highlight.Flipbook:SetAtlas("RotationHelper_Ants_Flipbook_2x")
    highlight.Flipbook:ClearAllPoints()
    highlight.Flipbook:SetPoint("TOPLEFT", highlight, offsetX, -offsetY)
    highlight.Flipbook:SetPoint("BOTTOMRIGHT", highlight, -offsetX, offsetY)
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

    -- Retail 12.1 permits category/equipment/buff records without a spellID.
    -- Those entries have no safe action-slot lookup and intentionally fail
    -- closed instead of consulting mutable item mixin state.
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
    hotkeyGeneration = hotkeyGeneration + 1
    presentationUpdateTimeLeft = 0
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
-- Assigned action-bar hotkeys
---------------------------------------------------------------------
-- Retail 12.0.7 and 12.1 expose the same FindSpellActionButtons
-- contract: it accepts a base spell and returns action slots. Resolve those
-- slots against BFI-owned buttons first so secure paging and custom class
-- bars remain authoritative. Every returned value is rejected unless it is
-- non-secret; no GetActionInfo scan or Cooldown Viewer item mixin is used.
local function GetFormattedBinding(command)
    if not IsSafeString(command) then return nil end

    local key = GetBindingKey(command)
    if not IsSafeString(key) or key == "" then
        return nil
    end

    -- Cooldown Manager loads before Action Bars, so resolve the canonical
    -- formatter only when presentation is applied.
    local actionBars = BFI.modules.ActionBars
    local formatter = actionBars and actionBars.GetHotkey
    if IsValueNonSecret(formatter) and type(formatter) == "function" then
        local hotkey = formatter(key)
        if IsSafeString(hotkey) and hotkey ~= "" then
            return hotkey
        end
        return nil
    end
    return key
end

local function ValidateActionSlots(slots)
    if slots == nil then
        return {}
    end
    if not IsValueNonSecret(slots) or type(slots) ~= "table" then
        return nil
    end

    local safeSlots = {}
    for _, slot in ipairs(slots) do
        if not IsSafeNumber(slot)
            or slot < 1
            or slot ~= math.floor(slot)
        then
            return nil
        end
        safeSlots[#safeSlots + 1] = slot
    end
    sort(safeSlots)
    return safeSlots
end

local function GetSpellActionSlots(baseSpellID)
    if not baseSpellID
        or not C_ActionBar
        or type(C_ActionBar.FindSpellActionButtons) ~= "function"
    then
        return {}
    end
    return ValidateActionSlots(C_ActionBar.FindSpellActionButtons(baseSpellID))
end

local function GetAssistedCombatActionSlots()
    if not C_ActionBar
        or type(C_ActionBar.FindAssistedCombatActionButtons) ~= "function"
    then
        return {}
    end
    return ValidateActionSlots(C_ActionBar.FindAssistedCombatActionButtons())
end

local function GetBFIActionBarHotkey(slots)
    local actionBars = BFI.modules.ActionBars
    local bars = actionBars and actionBars.bars
    if not IsValueNonSecret(bars) or type(bars) ~= "table" then
        return nil
    end

    local wantedSlots = {}
    for _, slot in ipairs(slots) do
        wantedSlots[slot] = true
    end

    for _, barName in ipairs(bfiActionBarPriority) do
        local bar = bars[barName]
        if IsValueNonSecret(bar) and bar then
            local enabled = bar.enabled
            local buttons = bar.buttons
            if IsSafeBoolean(enabled)
                and enabled
                and IsValueNonSecret(buttons)
                and type(buttons) == "table"
            then
                for _, button in ipairs(buttons) do
                    if IsValueNonSecret(button) and button then
                        local action = button.action
                        local command = button.keyBoundTarget
                        if IsSafeNumber(action)
                            and wantedSlots[action]
                            and IsSafeString(command)
                        then
                            local hotkey = GetFormattedBinding(command)
                            if hotkey then
                                return hotkey
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function GetStandardActionBarHotkey(slots)
    local currentPage
    if C_ActionBar and type(C_ActionBar.GetActionBarPage) == "function" then
        local page = C_ActionBar.GetActionBarPage()
        if IsSafeNumber(page) then
            currentPage = page
        end
    end

    for _, slot in ipairs(slots) do
        local page = math.floor((slot - 1) / ACTION_BUTTONS_PER_PAGE) + 1
        local buttonIndex = (slot - 1) % ACTION_BUTTONS_PER_PAGE + 1
        local prefix = directActionPageBindings[page]
        if prefix then
            local hotkey = GetFormattedBinding(prefix .. buttonIndex)
            if hotkey then
                return hotkey
            end
        end
        if currentPage and page == currentPage then
            local hotkey = GetFormattedBinding("ACTIONBUTTON" .. buttonIndex)
            if hotkey then
                return hotkey
            end
        end
    end
    return nil
end

local function ResolveSlotsHotkey(slots)
    if not slots or #slots == 0 then return nil end
    return GetBFIActionBarHotkey(slots) or GetStandardActionBarHotkey(slots)
end

local function ResolveItemHotkey(item)
    local baseSpellID = GetItemBaseSpellID(item)
    if not baseSpellID then return nil end

    local slots = GetSpellActionSlots(baseSpellID)
    if not slots then return nil end

    local hotkey = ResolveSlotsHotkey(slots)
    if hotkey then return hotkey end

    local matchesAssisted = assistedHighlightSpellID
        and (baseSpellID == assistedHighlightSpellID
            or baseSpellID == assistedHighlightBaseSpellID)
    if matchesAssisted then
        return ResolveSlotsHotkey(GetAssistedCombatActionSlots())
    end
    return nil
end

local function OnBFIActionButtonUpdate(_event, button)
    if not IsValueNonSecret(button) or not button then return end

    local action = button.action
    action = IsSafeNumber(action) and action or false
    if bfiActionButtonActions[button] == action then return end

    bfiActionButtonActions[button] = action
    hotkeyGeneration = hotkeyGeneration + 1
    presentationUpdateTimeLeft = 0
end

-- BFI bars support arbitrary secure paging conditions that do not always
-- produce ACTIONBAR_PAGE_CHANGED. LibActionButton reports its guarded active
-- slot after every state update; caching the slot keeps routine updates cheap.
local LAB = BFI.libs and BFI.libs.LAB
if IsValueNonSecret(LAB)
    and type(LAB) == "table"
    and type(LAB.RegisterCallback) == "function"
then
    LAB.RegisterCallback(CM, "OnButtonUpdate", OnBFIActionButtonUpdate)
end

local function GetHotkeyTarget(item, definition)
    if definition.isBar then
        return GetSafeField(item, "Icon")
    end
    return item
end

local function EnsureHotkeyOverlay(item, definition)
    local target = GetHotkeyTarget(item, definition)
    if not target then
        return nil, target
    end

    local overlay = hotkeyOverlays[item]
    if overlay and overlay.frame and overlay.text and overlay.anchored then
        return overlay, target
    end
    if not CanChangeGeometry(item) or not CanChangeGeometry(target) then
        return nil, target
    end

    if not overlay then
        overlay = {}
        hotkeyOverlays[item] = overlay
    end

    if not overlay.frame then
        local itemLevel = FrameGetFrameLevel(item)
        local targetLevel = FrameGetFrameLevel(target)
        if not IsSafeNumber(itemLevel) or not IsSafeNumber(targetLevel) then
            return nil, target
        end

        local frame = CreateFrame("Frame", nil, item)
        overlay.frame = frame
        if not CanChangeGeometry(frame) then
            return nil, target
        end
        FrameSetFrameLevel(frame, min(max(itemLevel, targetLevel) + 20, 10000))
    end

    if not overlay.text then
        if not CanChangeGeometry(overlay.frame) then
            return nil, target
        end
        local text = FrameCreateFontString(overlay.frame, nil, "OVERLAY")
        if not IsValueNonSecret(text) or not text then
            return nil, target
        end
        overlay.text = text
        if not CanChangeGeometry(text) then
            return nil, target
        end
        FontStringSetDrawLayer(text, "OVERLAY", 7)
        FontStringSetWidth(text, 0)
        FontStringHide(text)
    end

    if not overlay.anchored then
        if not CanChangeGeometry(overlay.frame)
            or not CanChangeGeometry(item)
        then
            return nil, target
        end
        -- Commit the native-size anchor only after the script-free overlay is
        -- complete, matching the skin primitive's secret-safe layout path.
        FrameSetAllPoints(overlay.frame, item)
        FrameShow(overlay.frame)
        overlay.anchored = true
    end

    return overlay, target
end

function PresentationMethods.GetTextPosition(
    position,
    defaultPoint,
    defaultRelativePoint,
    defaultX,
    defaultY
)
    if not IsValueNonSecret(position) or type(position) ~= "table" then
        return defaultPoint, defaultRelativePoint, defaultX, defaultY
    end

    local point = position[1]
    if not IsSafeString(point) or not anchorPoints[point] then
        point = defaultPoint
    end
    local relativePoint = position[2]
    if not IsSafeString(relativePoint) or not anchorPoints[relativePoint] then
        relativePoint = defaultRelativePoint
    end
    local x = ClampNumber(position[3], defaultX, -100, 100)
    local y = ClampNumber(position[4], defaultY, -100, 100)
    return point, relativePoint, x, y
end

function PresentationMethods.PositionText(
    text,
    target,
    position,
    defaultPoint,
    defaultRelativePoint,
    defaultX,
    defaultY,
    scale
)
    local point, relativePoint, x, y = PresentationMethods.GetTextPosition(
        position,
        defaultPoint,
        defaultRelativePoint,
        defaultX,
        defaultY
    )
    scale = scale or 1
    FontStringSetJustifyH(text, horizontalJustification[point] or "CENTER")
    FontStringSetJustifyV(text, verticalJustification[point] or "MIDDLE")
    FontStringClearAllPoints(text)
    FontStringSetPoint(text, point, target, relativePoint, x * scale, y * scale)
end

local function PositionHotkey(text, target, config, scale)
    PresentationMethods.PositionText(
        text,
        target,
        config.hotkeyPosition,
        "TOPRIGHT",
        "TOPRIGHT",
        0,
        0,
        scale
    )
end

local function HideItemHotkey(item)
    local overlay = hotkeyOverlays[item]
    if not overlay or not overlay.text then
        return true
    end
    if not CanChangeGeometry(overlay.text) then
        return false
    end
    FontStringHide(overlay.text)
    return true
end

---------------------------------------------------------------------
-- BFI-owned holders and edit-mode previews
---------------------------------------------------------------------
local function MarkPresentationDirty()
    presentationGeneration = presentationGeneration + 1
    hotkeyGeneration = hotkeyGeneration + 1
    presentationUpdateTimeLeft = 0
end

local function EnsureHolder(state)
    if state.holder then return state.holder end

    local holder = CreateFrame("Frame", state.definition.holderName, AF.UIParent)
    holder:SetSize(1, 1)
    holder.enabled = false
    holder:Hide()

    local position = state.definition.defaultPosition
    BFI.funcs.LoadPosition(holder, position, AF.UIParent)
    state.holder = holder
    state.previewFrames = {}
    AF.CreateMover(holder, "BFI: " .. L["Cooldown Manager"], state.definition.moverName)
    holder.mover:HookScript("OnShow", MarkPresentationDirty)
    holder.mover:HookScript("OnHide", MarkPresentationDirty)
    return holder
end

local function GetViewerPosition(config, definition)
    local position = config.position
    local point
    local x
    local y
    local usesRelativePoint
    if type(position) == "table" then
        point = position[1]
        usesRelativePoint = IsSafeString(position[2])
        if usesRelativePoint then
            x = position[3]
            y = position[4]
        else
            x = position[2]
            y = position[3]
        end
    end

    if not IsSafeString(point)
        or not anchorPoints[point]
        or not IsSafeNumber(x)
        or not IsSafeNumber(y)
    then
        position = AF.Copy(definition.defaultPosition)
        config.position = position
    elseif usesRelativePoint
        or not IsValueNonSecret(position[4])
        or position[4] ~= nil
    then
        -- AF movers persist {point, x, y}. Collapse any legacy four-field
        -- anchor before handing the same table back to the mover save path.
        position = {point, x, y}
        config.position = position
    end

    -- A pre-release implementation marked legacy profiles for a native
    -- position capture. Native viewer geometry is intentionally no longer
    -- inspected, so retire the marker and use the stable BFI default.
    config.captureNativePosition = nil
    return position
end

local function HolderPositionMatches(holder, position, ignoreOffsets)
    local numPoints = FrameGetNumPoints(holder)
    if not IsSafeNumber(numPoints) or numPoints ~= 1 then
        return false
    end

    local point, relativeTo, relativePoint, x, y =
        FrameGetPoint(holder, 1)
    return IsSafeString(point)
        and IsValueNonSecret(relativeTo)
        and relativeTo == AF.UIParent
        and IsSafeString(relativePoint)
        and IsSafeNumber(x)
        and IsSafeNumber(y)
        and point == position[1]
        and relativePoint == position[1]
        and (ignoreOffsets
            or (NearlyEqual(x, position[2])
                and NearlyEqual(y, position[3])))
end

local function BindHolderPosition(state, config)
    local holder = EnsureHolder(state)
    local position = GetViewerPosition(config, state.definition)
    local isDragging = holder.mover and holder.mover.isDragging
    local positioned = HolderPositionMatches(holder, position, isDragging)
    if not isDragging
        and (state.position ~= position or not positioned)
    then
        AF.UpdateMoverSave(holder, position)
        BFI.funcs.LoadPosition(holder, position, AF.UIParent)
        positioned = HolderPositionMatches(holder, position)
        state.position = positioned and position or nil
    end

    holder.enabled = positioned
    if not positioned then
        holder:Hide()
        return nil
    end
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

function PresentationMethods.GetPixelSnappedScale(
    item,
    itemHeight,
    configuredScale
)
    local currentScale = FrameGetScale(item)
    local effectiveScale = FrameGetEffectiveScale(item)
    if not IsSafeNumber(currentScale)
        or currentScale <= 0
        or not IsSafeNumber(effectiveScale)
        or effectiveScale <= 0
    then
        return configuredScale
    end

    local parentScale = effectiveScale / currentScale
    if parentScale <= 0 then return configuredScale end
    local renderedHeight = itemHeight * configuredScale
    local snappedHeight = AF.GetNearestPixelSize(renderedHeight, parentScale, 1)
    if not IsSafeNumber(snappedHeight) or snappedHeight <= 0 then
        return configuredScale
    end

    local snappedScale = snappedHeight / itemHeight
    if IsSafeNumber(snappedScale) and snappedScale > 0 then
        return snappedScale
    end
    return configuredScale
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
    preview.timer = AF.CreateFontString(preview, nil, nil, nil, "OVERLAY")
    preview.timer:SetWidth(0)
    preview.timer:Hide()
    preview.hotkey = AF.CreateFontString(preview, nil, nil, nil, "OVERLAY")
    preview.hotkey:SetWidth(0)
    preview.hotkey:Hide()
    preview.count = AF.CreateFontString(preview, nil, nil, nil, "OVERLAY")
    preview.count:SetWidth(0)
    preview.count:Hide()
    preview.timerTarget = CreateFrame("Frame", nil, preview)
    if state.definition.isBar then
        preview.hotkeyTarget = CreateFrame("Frame", nil, preview)
        preview.name = AF.CreateFontString(preview, nil, nil, nil, "OVERLAY")
        preview.name:SetWidth(0)
        preview.name:Hide()
    end
    state.previewFrames[index] = preview
    return preview
end

local function UpdateHolderPreview(state, layout, firstItem, config)
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
        local hotkeyTarget = preview.hotkeyTarget or preview
        if preview.hotkeyTarget then
            FrameSetSize(
                preview.hotkeyTarget,
                layout.height * scaleRatio,
                layout.height * scaleRatio
            )
            FrameClearAllPoints(preview.hotkeyTarget)
            FrameSetPoint(preview.hotkeyTarget, "LEFT", preview, "LEFT", 0, 0)
            local nameOnly = config.barContent == "name_only"
            FrameSetSize(
                preview.timerTarget,
                (layout.width - (nameOnly and 0 or 32)) * scaleRatio,
                19 * scaleRatio
            )
            FrameClearAllPoints(preview.timerTarget)
            FrameSetPoint(
                preview.timerTarget,
                "LEFT",
                nameOnly and preview or preview.hotkeyTarget,
                nameOnly and "LEFT" or "RIGHT",
                nameOnly and 0 or 2 * scaleRatio,
                0
            )
        else
            FrameClearAllPoints(preview.timerTarget)
            local pixel = CM.config.skin
                and PresentationMethods.GetOnePixelForFrame(
                    preview.timerTarget
                )
            if pixel then
                FrameSetPoint(
                    preview.timerTarget,
                    "TOPLEFT",
                    preview,
                    "TOPLEFT",
                    pixel,
                    -pixel
                )
                FrameSetPoint(
                    preview.timerTarget,
                    "BOTTOMRIGHT",
                    preview,
                    "BOTTOMRIGHT",
                    -pixel,
                    pixel
                )
            else
                FrameSetAllPoints(preview.timerTarget, preview)
            end
        end
        if config.showHotkeys ~= false then
            ApplyFont(preview.hotkey, config.hotkeyText, scaleRatio)
            PositionHotkey(preview.hotkey, hotkeyTarget, config, scaleRatio)
            FontStringSetText(preview.hotkey, "1")
            FontStringShow(preview.hotkey)
        else
            FontStringHide(preview.hotkey)
        end
        local countTarget = preview.hotkeyTarget or preview
        local showCount = not state.definition.isBar
            or config.barContent ~= "name_only"
        if showCount then
            local countX = state.definition.isBar and -5 or -2
            local countY = state.definition.isBar and 5 or 2
            ApplyFont(preview.count, config.countText, scaleRatio)
            PresentationMethods.PositionText(
                preview.count,
                countTarget,
                nil,
                "BOTTOMRIGHT",
                "BOTTOMRIGHT",
                countX,
                countY,
                scaleRatio
            )
            FontStringSetText(preview.count, "2")
            FontStringShow(preview.count)
        else
            FontStringHide(preview.count)
        end
        if preview.name then
            if config.barContent ~= "icon_only" then
                ApplyFont(preview.name, config.barText, scaleRatio)
                PresentationMethods.PositionText(
                    preview.name,
                    preview.timerTarget,
                    nil,
                    "LEFT",
                    "LEFT",
                    5,
                    0,
                    scaleRatio
                )
                FontStringSetText(preview.name, L["Cooldown"])
                FontStringShow(preview.name)
            else
                FontStringHide(preview.name)
            end
        end
        if config.showTimer ~= false then
            local timerConfig = state.definition.isBar
                and config.durationText
                or config.cooldownText
            local defaultPoint = state.definition.isBar and "RIGHT" or "CENTER"
            local defaultX = state.definition.isBar and -8 or 0
            ApplyFont(preview.timer, timerConfig, scaleRatio)
            PresentationMethods.PositionText(
                preview.timer,
                preview.timerTarget or preview,
                timerConfig.position,
                defaultPoint,
                defaultPoint,
                defaultX,
                0,
                scaleRatio
            )
            FontStringSetText(preview.timer, "30")
            FontStringShow(preview.timer)
        else
            FontStringHide(preview.timer)
        end
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

function PresentationMethods.CaptureFontStringPoints(fontString)
    local numPoints = PresentationMethods.GetNumPoints(fontString)
    if not IsSafeNumber(numPoints) or numPoints < 0 then
        return nil
    end

    local points = {}
    for index = 1, numPoints do
        local point, relativeTo, relativePoint, x, y = PresentationMethods.GetPoint(
            fontString,
            index
        )
        if not IsSafeString(point)
            or not IsValueNonSecret(relativeTo)
            or not relativeTo
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

function PresentationMethods.CaptureFontStringPresentation(fontString)
    if not IsValueNonSecret(fontString) or not fontString then
        return nil
    end

    local fontObject = PresentationMethods.GetFontObject(fontString)
    local justifyH = PresentationMethods.GetJustifyH(fontString)
    local justifyV = PresentationMethods.GetJustifyV(fontString)
    local textR, textG, textB, textA =
        PresentationMethods.GetTextColor(fontString)
    local shadowR, shadowG, shadowB, shadowA =
        PresentationMethods.GetShadowColor(fontString)
    local shadowX, shadowY = PresentationMethods.GetShadowOffset(fontString)
    local points = PresentationMethods.CaptureFontStringPoints(fontString)
    if not IsValueNonSecret(fontObject)
        or not fontObject
        or not IsSafeString(justifyH)
        or not IsSafeString(justifyV)
        or not IsSafeNumber(textR)
        or not IsSafeNumber(textG)
        or not IsSafeNumber(textB)
        or not IsSafeNumber(textA)
        or not IsSafeNumber(shadowR)
        or not IsSafeNumber(shadowG)
        or not IsSafeNumber(shadowB)
        or not IsSafeNumber(shadowA)
        or not IsSafeNumber(shadowX)
        or not IsSafeNumber(shadowY)
        or not points
    then
        return nil
    end

    return {
        fontString = fontString,
        fontObject = fontObject,
        justifyH = justifyH,
        justifyV = justifyV,
        textColor = {textR, textG, textB, textA},
        shadowColor = {shadowR, shadowG, shadowB, shadowA},
        shadowOffset = {shadowX, shadowY},
        points = points,
    }
end

function PresentationMethods.RestoreFontStringPresentation(
    presentation,
    fontString
)
    local capturedFontString = presentation and presentation.fontString
    if not IsValueNonSecret(fontString)
        or not fontString
        or not IsValueNonSecret(capturedFontString)
        or fontString ~= capturedFontString
    then
        return
    end

    PresentationMethods.SetFontObject(fontString, presentation.fontObject)
    FontStringSetTextColor(fontString, unpack(presentation.textColor))
    PresentationMethods.SetShadowColor(
        fontString,
        unpack(presentation.shadowColor)
    )
    PresentationMethods.SetShadowOffset(
        fontString,
        unpack(presentation.shadowOffset)
    )
    FontStringSetJustifyH(fontString, presentation.justifyH)
    FontStringSetJustifyV(fontString, presentation.justifyV)
    FontStringClearAllPoints(fontString)
    for _, point in ipairs(presentation.points) do
        FontStringSetPoint(fontString, unpack(point))
    end
end

function PresentationMethods.GetCooldownCountdownText(cooldown)
    if not IsValueNonSecret(cooldown) or not cooldown then return nil end
    local fontString = PresentationMethods.GetCountdownFontString(cooldown)
    if IsValueNonSecret(fontString) and fontString then
        return fontString
    end
    return nil
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

local GetCountText

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
    itemState.nativeCooldownPoints = nil
    itemState.nativeCountdownText = nil
    itemState.nativeCountText = nil
    itemState.nativeBarPoints = nil
    itemState.nativeIconShown = nil
    itemState.nativeIconAlpha = nil
    itemState.nativeNameShown = nil
    itemState.nativeNameAlpha = nil
    itemState.nativeNameText = nil
    itemState.nativeDurationShown = nil
    itemState.nativeDurationAlpha = nil
    itemState.nativeDurationText = nil
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
        if itemState.cooldownSwipeStyled then
            CooldownSetSwipeTexture(cooldown, nativeCooldownSwipeTexture)
            itemState.cooldownSwipeStyled = nil
        end
        if itemState.nativeHideCountdownNumbers ~= nil then
            CooldownSetHideCountdownNumbers(cooldown, itemState.nativeHideCountdownNumbers)
        end
        if itemState.nativeCooldownPoints then
            RestorePoints(cooldown, itemState.nativeCooldownPoints)
        end
        PresentationMethods.RestoreFontStringPresentation(
            itemState.nativeCountdownText,
            PresentationMethods.GetCooldownCountdownText(cooldown)
        )
    end

    PresentationMethods.RestoreFontStringPresentation(
        itemState.nativeCountText,
        GetCountText(item, definition)
    )

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
            PresentationMethods.RestoreFontStringPresentation(
                itemState.nativeNameText,
                name
            )
            PresentationMethods.RestoreFontStringPresentation(
                itemState.nativeDurationText,
                duration
            )
        end
    end

    local highlight = assistedHighlights[item]
    if highlight then
        highlight:SetAlpha(0)
    end
    HideItemHotkey(item)
    itemState.hotkeyGeneration = nil
    itemState.hotkeyStyleGeneration = nil
    itemState.hotkeyCooldownID = nil
    itemState.presentationGeneration = nil
end

local function CanRestoreItemPresentation(item, definition)
    local hotkey = hotkeyOverlays[item]
    if hotkey and hotkey.text and not CanChangeGeometry(hotkey.text) then
        return false
    end

    local cooldown = GetSafeField(item, "Cooldown")
    if cooldown and not CanChangeGeometry(cooldown) then
        return false
    end
    local countdownText = cooldown
        and PresentationMethods.GetCooldownCountdownText(cooldown)
    if countdownText and not CanChangeGeometry(countdownText) then
        return false
    end
    local countText = GetCountText(item, definition)
    if countText and not CanChangeGeometry(countText) then
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
local function CreateNativeSkinLayer(parent, target, levelOffset)
    -- Do not use BackdropTemplate here. This layer inherits secret dimensions
    -- from the native cooldown widget; BackdropMixin's Lua OnSizeChanged path
    -- performs arithmetic on those values and is unsafe in addon execution.
    if not CanChangeGeometry(parent) or not CanChangeGeometry(target) then
        return nil
    end

    local parentLevel = FrameGetFrameLevel(parent)
    if not IsSafeNumber(parentLevel) then
        return nil
    end

    local layer = CreateFrame("Frame", nil, parent)
    if not CanChangeGeometry(layer) then
        return nil
    end
    FrameSetFrameLevel(layer, max(0, min(10000, parentLevel + levelOffset)))
    return layer
end

local function CreateSolidTexture(parent, drawLayer, subLevel, color)
    if not CanChangeGeometry(parent) then
        return nil
    end

    local texture = FrameCreateTexture(parent, nil, drawLayer, nil, subLevel)
    if not CanChangeGeometry(texture) then
        return nil
    end
    TextureSetColorTexture(texture, unpack(color))
    return texture
end

function PresentationMethods.GetOnePixelForFrame(frame)
    local effectiveScale = FrameGetEffectiveScale(frame)
    if not IsSafeNumber(effectiveScale) or effectiveScale <= 0 then
        return nil
    end

    local pixel = AF.GetNearestPixelSize(1, effectiveScale, 1)
    if IsSafeNumber(pixel) and pixel > 0 then
        return pixel
    end
    return nil
end

function PresentationMethods.UpdateNativeChildSkinPixels(skin)
    if not skin
        or not skin.border
        or not skin.top
        or not skin.bottom
        or not skin.left
        or not skin.right
        or not CanChangeGeometry(skin.border)
        or not CanChangeGeometry(skin.top)
        or not CanChangeGeometry(skin.bottom)
        or not CanChangeGeometry(skin.left)
        or not CanChangeGeometry(skin.right)
    then
        return false
    end

    local pixel = PresentationMethods.GetOnePixelForFrame(skin.border)
    if not pixel then return false end
    TextureSetHeight(skin.top, pixel)
    TextureSetHeight(skin.bottom, pixel)
    TextureSetWidth(skin.left, pixel)
    TextureSetWidth(skin.right, pixel)
    return true
end

local function CreateNativeChildSkin(parent, target, withBackground)
    local skin = {border = CreateNativeSkinLayer(parent, target, 1)}
    if not skin.border then return nil end

    local top = CreateSolidTexture(
        skin.border,
        "OVERLAY",
        7,
        nativeSkinBorderColor
    )
    if not top then return nil end
    TextureSetPoint(top, "TOPLEFT", skin.border, "TOPLEFT", 0, 0)
    TextureSetPoint(top, "TOPRIGHT", skin.border, "TOPRIGHT", 0, 0)
    skin.top = top

    local bottom = CreateSolidTexture(
        skin.border,
        "OVERLAY",
        7,
        nativeSkinBorderColor
    )
    if not bottom then return nil end
    TextureSetPoint(bottom, "BOTTOMLEFT", skin.border, "BOTTOMLEFT", 0, 0)
    TextureSetPoint(bottom, "BOTTOMRIGHT", skin.border, "BOTTOMRIGHT", 0, 0)
    skin.bottom = bottom

    local left = CreateSolidTexture(
        skin.border,
        "OVERLAY",
        7,
        nativeSkinBorderColor
    )
    if not left then return nil end
    TextureSetPoint(left, "TOPLEFT", skin.border, "TOPLEFT", 0, 0)
    TextureSetPoint(left, "BOTTOMLEFT", skin.border, "BOTTOMLEFT", 0, 0)
    skin.left = left

    local right = CreateSolidTexture(
        skin.border,
        "OVERLAY",
        7,
        nativeSkinBorderColor
    )
    if not right then return nil end
    TextureSetPoint(right, "TOPRIGHT", skin.border, "TOPRIGHT", 0, 0)
    TextureSetPoint(right, "BOTTOMRIGHT", skin.border, "BOTTOMRIGHT", 0, 0)
    skin.right = right

    if withBackground then
        skin.background = CreateNativeSkinLayer(parent, target, -1)
        if not skin.background then return nil end
        local background = CreateSolidTexture(
            skin.background,
            "BACKGROUND",
            -8,
            nativeSkinBackgroundColor
        )
        if not background then return nil end
        TextureSetPoint(background, "TOPLEFT", skin.background, "TOPLEFT", 0, 0)
        TextureSetPoint(background, "BOTTOMRIGHT", skin.background, "BOTTOMRIGHT", 0, 0)
    end

    -- The layers are complete while still zero-sized. Commit the native
    -- anchors last so secret dimensions propagate only through C layout.
    if not CanChangeGeometry(target)
        or not CanChangeGeometry(skin.border)
        or (skin.background and not CanChangeGeometry(skin.background))
    then
        return nil
    end
    if skin.background then
        FrameSetAllPoints(skin.background, target)
    end
    FrameSetAllPoints(skin.border, target)
    PresentationMethods.UpdateNativeChildSkinPixels(skin)
    return skin
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
        skin = CreateNativeChildSkin(iconParent, icon, false)
        if not skin then return end
        skin.mask = mask
        skin.overlay = overlay
        iconSkins[icon] = skin
    end

    TextureSetTexCoord(icon, AF.GetDefaultTexCoord())
    if skin.mask then MaskTextureHide(skin.mask) end
    if skin.overlay then TextureHide(skin.overlay) end
    PresentationMethods.UpdateNativeChildSkinPixels(skin)
    FrameShow(skin.border)
end

local function SkinBar(bar)
    if not IsValueNonSecret(bar) then return end

    local skin = barSkins[bar]
    if not skin then
        skin = CreateNativeChildSkin(bar, bar, true)
        if not skin then return end
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
    if skin.background then
        FrameShow(skin.background)
    end
    PresentationMethods.UpdateNativeChildSkinPixels(skin)
    FrameShow(skin.border)
end

ApplyFont = function(fontString, config, scale)
    if not IsValueNonSecret(fontString) or not fontString or not config then return end
    local font = config.font
    if scale and scale ~= 1 then
        font = {font[1], font[2] * scale, font[3], font[4]}
    end
    AF.SetFont(fontString, font)
    FontStringSetTextColor(fontString, AF.UnpackColor(config.color))
end

local function ApplyHotkeyPresentation(item, definition, config, itemState)
    local cooldownID = GetNonSecretSpellID(item.cooldownID)
    local cooldownKey = cooldownID or false
    if config.showHotkeys == false then
        local existing = hotkeyOverlays[item]
        if existing and existing.text then
            FontStringSetText(existing.text, "")
        end
        itemState.hotkeyGeneration = hotkeyGeneration
        itemState.hotkeyCooldownID = cooldownKey
        return true
    end

    local overlay, target = EnsureHotkeyOverlay(item, definition)
    if not overlay
        or not overlay.text
        or not target
    then
        return false
    end

    if itemState.hotkeyStyleGeneration ~= presentationGeneration then
        if not CanChangeGeometry(overlay.text)
            or not CanChangeGeometry(target)
        then
            return false
        end
        ApplyFont(overlay.text, config.hotkeyText)
        PositionHotkey(overlay.text, target, config)
        FontStringShow(overlay.text)
        itemState.hotkeyStyleGeneration = presentationGeneration
    end

    if itemState.hotkeyGeneration == hotkeyGeneration
        and itemState.hotkeyCooldownID == cooldownKey
    then
        return true
    end

    local hotkey = cooldownID and ResolveItemHotkey(item)
    -- SetText accepts tainted execution in both audited clients; unlike
    -- geometry/visibility methods it is safe here because the resolver only
    -- returns guarded, non-secret strings. Keep bindings current in combat.
    FontStringSetText(overlay.text, hotkey or "")
    itemState.hotkeyGeneration = hotkeyGeneration
    itemState.hotkeyCooldownID = cooldownKey
    return true
end

GetCountText = function(item, definition)
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

function PresentationMethods.CaptureStaticPresentationDefaults(
    item,
    definition,
    itemState
)
    local countText = GetCountText(item, definition)
    if countText and not itemState.nativeCountText then
        itemState.nativeCountText =
            PresentationMethods.CaptureFontStringPresentation(countText)
    end
    if countText and not itemState.nativeCountText then
        return false
    end

    local cooldown = GetSafeField(item, "Cooldown")
    if cooldown then
        if not itemState.nativeCooldownPoints then
            itemState.nativeCooldownPoints = CapturePoints(cooldown)
        end
        if not itemState.nativeCooldownPoints then
            return false
        end

        local countdownText =
            PresentationMethods.GetCooldownCountdownText(cooldown)
        if countdownText and not itemState.nativeCountdownText then
            itemState.nativeCountdownText =
                PresentationMethods.CaptureFontStringPresentation(countdownText)
        end
        if countdownText and not itemState.nativeCountdownText then
            return false
        end
    end

    if definition.isBar then
        local bar = GetSafeField(item, "Bar")
        local name = bar and GetSafeField(bar, "Name")
        if name and not itemState.nativeNameText then
            itemState.nativeNameText =
                PresentationMethods.CaptureFontStringPresentation(name)
        end
        if name and not itemState.nativeNameText then
            return false
        end
        local duration = bar and GetSafeField(bar, "Duration")
        if duration and not itemState.nativeDurationText then
            itemState.nativeDurationText =
                PresentationMethods.CaptureFontStringPresentation(duration)
        end
        if duration and not itemState.nativeDurationText then
            return false
        end
    end
    return true
end

function PresentationMethods.PositionCooldownInside(cooldown, target)
    local pixel = PresentationMethods.GetOnePixelForFrame(cooldown)
    if not pixel then return false end
    FrameClearAllPoints(cooldown)
    FrameSetPoint(cooldown, "TOPLEFT", target, "TOPLEFT", pixel, -pixel)
    FrameSetPoint(
        cooldown,
        "BOTTOMRIGHT",
        target,
        "BOTTOMRIGHT",
        -pixel,
        pixel
    )
    return true
end

local function CanApplyStaticPresentation(item, state, itemState)
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
    local countdownText = cooldown
        and PresentationMethods.GetCooldownCountdownText(cooldown)
    local countText = GetCountText(item, definition)
    if (iconParent and not CanChangeGeometry(iconParent))
        or (icon and not CanChangeGeometry(icon))
        or (cooldown and not CanChangeGeometry(cooldown))
        or (countdownText and not CanChangeGeometry(countdownText))
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
    return PresentationMethods.CaptureStaticPresentationDefaults(
        item,
        definition,
        itemState
    )
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

    local cooldown = GetSafeField(item, "Cooldown")
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

        if cooldown and iconParent then
            PresentationMethods.PositionCooldownInside(cooldown, iconParent)
            CooldownSetSwipeTexture(cooldown, squareCooldownSwipeTexture)
            itemState.cooldownSwipeStyled = true
        end
    else
        if cooldown and itemState.cooldownSwipeStyled then
            CooldownSetSwipeTexture(cooldown, nativeCooldownSwipeTexture)
            itemState.cooldownSwipeStyled = nil
        end
    end

    if cooldown and itemState.nativeHideCountdownNumbers ~= nil then
        CooldownSetHideCountdownNumbers(cooldown, config.showTimer == false)
    end
    local countdownText = cooldown
        and PresentationMethods.GetCooldownCountdownText(cooldown)
    if countdownText
        and itemState.nativeCountdownText
        and countdownText == itemState.nativeCountdownText.fontString
    then
        ApplyFont(countdownText, config.cooldownText)
        PresentationMethods.PositionText(
            countdownText,
            cooldown,
            config.cooldownText.position,
            "CENTER",
            "CENTER",
            0,
            0
        )
    end

    ApplyFont(GetCountText(item, state.definition), config.countText)

    local bar = state.definition.isBar and GetSafeField(item, "Bar")
    if bar then
        ApplyFont(GetSafeField(bar, "Name"), config.barText)
        local duration = GetSafeField(bar, "Duration")
        ApplyFont(duration, config.durationText)
        if duration
            and itemState.nativeDurationText
            and duration == itemState.nativeDurationText.fontString
        then
            PresentationMethods.PositionText(
                duration,
                bar,
                config.durationText.position,
                "RIGHT",
                "RIGHT",
                -8,
                0
            )
        end
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
    ApplyHotkeyPresentation(item, itemState.definition, config, itemState)
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
    if not BindHolderPosition(state, config) then
        return false
    end
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
        UpdateHolderPreview(state, previewLayout, nil, config)
        return restored
    end

    RestoreMissingItems(state, activeSet)

    local layoutCount = #visibleItems
    local displayCount = layoutCount > 0 and layoutCount or state.definition.previewCount
    local layout = BuildLayout(state.definition, config, displayCount)

    if layoutCount == 0 then
        if CM.config.skin then
            layout.scale = PresentationMethods.GetPixelSnappedScale(
                _G.UIParent,
                layout.height,
                layout.scale
            )
        end
        UpdateHolderPreview(state, layout, nil, config)
        return true
    end

    layout.count = layoutCount
    -- Fractional rendered icon dimensions put opposite border edges between
    -- physical pixels. Snap the requested scale by the fixed native height so
    -- all four one-pixel skin edges remain crisp at values such as Essential's
    -- default 0.75 scale.
    if CM.config.skin then
        layout.scale = PresentationMethods.GetPixelSnappedScale(
            visibleItems[1].item,
            layout.height,
            layout.scale
        )
    end
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
            UpdateHolderPreview(state, layout, visibleItems[1].item, config)
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
                UpdateHolderPreview(state, layout, visibleItems[1].item, config)
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
            if not CanApplyStaticPresentation(
                entry.item,
                state,
                entry.itemState
            ) then
                needsStaticPresentation = false
                break
            end
        end
    end

    if needsStaticPresentation then
        for _, entry in ipairs(visibleItems) do
            if entry.needsGeometry
                or entry.itemState.presentationGeneration ~= presentationGeneration
            then
                ApplyStaticPresentation(entry.item, state, config, entry.itemState)
            end
        end
    end

    UpdateHolderPreview(state, layout, visibleItems[1].item, config)
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
    if module == "actionBars" then
        hotkeyGeneration = hotkeyGeneration + 1
        StartPresentationPolling()
        return
    end
    if module and module ~= "cooldownManager" then return end

    MarkPresentationDirty()
    StartPresentationPolling()
    UpdateAssistedHighlightPolling()
end

local hotkeyRefreshEvents = {
    PLAYER_REGEN_ENABLED = true,
    ADDON_RESTRICTION_STATE_CHANGED = true,
    UPDATE_BINDINGS = true,
    ACTIONBAR_SLOT_CHANGED = true,
    ACTIONBAR_PAGE_CHANGED = true,
    UPDATE_BONUS_ACTIONBAR = true,
    UPDATE_OVERRIDE_ACTIONBAR = true,
    UPDATE_VEHICLE_ACTIONBAR = true,
    UPDATE_POSSESS_BAR = true,
    UPDATE_SHAPESHIFT_FORM = true,
    SPELLS_CHANGED = true,
    PLAYER_SPECIALIZATION_CHANGED = true,
    COOLDOWN_VIEWER_DATA_LOADED = true,
    COOLDOWN_VIEWER_TABLE_HOTFIXED = true,
}

local function OnPresentationEvent(_, event)
    if hotkeyRefreshEvents[event] then
        hotkeyGeneration = hotkeyGeneration + 1
    end
    StartPresentationPolling()
end

for event in next, hotkeyRefreshEvents do
    presentationController:RegisterEvent(event)
end
presentationController:SetScript("OnEvent", OnPresentationEvent)

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
