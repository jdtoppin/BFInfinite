#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module="${CDM_MODULE:-$repo_root/Modules/CooldownManager/CooldownManager.lua}"
harness="$(mktemp)"
trap 'rm -f "$harness"' EXIT

if [[ ! -f "$module" ]]; then
    echo "Cooldown Manager module not found: $module" >&2
    exit 1
fi

lua_interpreter="${LUA_INTERPRETER:-}"
if [[ -n "$lua_interpreter" ]] && ! command -v "$lua_interpreter" >/dev/null 2>&1; then
    echo "LUA_INTERPRETER does not name an executable: $lua_interpreter" >&2
    exit 127
fi
if [[ -z "$lua_interpreter" ]]; then
    for candidate in lua5.1 lua-5.1 lua luajit; do
        if command -v "$candidate" >/dev/null 2>&1; then
            lua_interpreter="$candidate"
            break
        fi
    done
fi
if [[ -z "$lua_interpreter" ]]; then
    echo "A Lua 5.1-compatible interpreter is required." >&2
    exit 127
fi

{
    cat <<'LUA'
local SECRET = {}
local function IsValueNonSecret(value)
    return value ~= SECRET
end
local function IsSafeBoolean(value)
    return IsValueNonSecret(value) and type(value) == "boolean"
end
local function IsSafeNumber(value)
    return IsValueNonSecret(value) and type(value) == "number"
end
local function IsSafeString(value)
    return IsValueNonSecret(value) and type(value) == "string"
end
local function NearlyEqual(left, right)
    return math.abs(left - right) < 0.001
end
local function GetSafeField(owner, key)
    local value = owner and owner[key]
    return IsValueNonSecret(value) and value or nil
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
    return IsSafeNumber(alpha) and alpha or nil
end

local FrameGetAlpha = function(region) return region.alpha end
local FrameSetAlpha = function(region, alpha)
    region.alpha = alpha
    region.alphaWrites = (region.alphaWrites or 0) + 1
end
local FrameGetNumPoints = function(region) return #region.points end
local FrameGetPoint = function(region, index)
    return unpack(region.points[index])
end
local FrameGetSize = function(region) return region.width, region.height end
local FrameGetScale = function(region) return region.scale end
local FrameGetEffectiveScale = function(region)
    if region.parentEffectiveScale then
        return region.parentEffectiveScale * region.scale
    end
    return region.effectiveScale or region.scale
end
local FrameSetSize = function(region, width, height)
    region.width = width
    region.height = height
end
local FrameSetScale = function(region, scale) region.scale = scale end
local FrameClearAllPoints = function(region) region.points = {} end
local FrameSetPoint = function(region, ...)
    region.points[#region.points + 1] = {...}
end
local FontStringClearAllPoints = FrameClearAllPoints
local FontStringSetPoint = FrameSetPoint
local FrameIsMouseMotionEnabled = function(region) return region.mouseMotion end
FrameSetMouseMotionEnabled = function(region, enabled)
    region.mouseMotion = enabled
end
local FrameIsShown = function(region) return region.shown end
local FontStringIsShown = FrameIsShown
local FontStringGetAlpha = FrameGetAlpha
local methodTexture = {
    GetAlpha = FrameGetAlpha,
    SetAlpha = function(region, alpha) region.alpha = alpha end,
}
local CooldownGetHideCountdownNumbers = function(cooldown)
    return cooldown.hideCountdownNumbers
end
local CapturePoints = function(region)
    for _, point in ipairs(region.points) do
        for _, value in ipairs(point) do
            if value == SECRET then return nil end
        end
    end
    return region.points
end
local RestorePoints = function(region, points)
    region.points = points
end

local presentationGeneration = 17
local CM = {
    config = {
        enabled = true,
        skin = true,
        assistedHighlight = false,
        viewers = {},
    },
}
local HighlightState = {
    assisted = setmetatable({}, {__mode = "k"}),
    proc = {
        Ensure = function() return true end,
        Restore = function() return true end,
        SetShown = function(region, shown) region.shown = shown end,
    },
}
local EnsureAssistedHighlight = function() return true end
local iconSkins = setmetatable({}, {__mode = "k"})
local barSkins = setmetatable({}, {__mode = "k"})
local BFI = {media = {bar = "BFI bar"}}
local AF = {
    GetDefaultTexCoord = function() return 0, 1, 0, 1 end,
    GetNearestPixelSize = function(size) return size end,
}
local GetIconMaskAndOverlay = function(iconParent)
    return iconParent.mask, iconParent.overlay
end
local TextureIsObjectType = function() return true end
local IsWidgetObjectType = function(region, objectType, isObjectType)
    return region ~= nil and objectType == "Texture" and isObjectType(region)
end
local CreateNativeChildSkin = function(_parent, target, withBackground)
    return {
        border = {},
        background = withBackground and {} or nil,
        pixelReady = target.pixelReady ~= false,
    }
end
local MaskTextureHide = function(region) region.hidden = true end
local TextureHide = MaskTextureHide
local TextureSetTexCoord = function() end
local TextureSetTexture = function(region, asset)
    if region.textureReady == false then return false end
    region.asset = asset
    return true
end
local FrameShow = function(region) region.shown = true end
FrameHide = function(region) region.shown = false end
local StatusBarGetStatusBarTexture = function(bar) return bar.fill end
local TextureSetDrawLayer = function(region, layer, subLevel)
    region.drawLayer = layer
    region.subLevel = subLevel
end
local fontScaleCalls = {}
local textScaleCalls = {}
local hotkeyPositionScaleCalls = {}
local PresentationMethods = {
    PositionCooldownInside = function() return true end,
    GetCooldownCountdownText = function(cooldown)
        return cooldown and cooldown.countdownText
    end,
    PositionText = function(_, _, _, _, _, _, _, scale)
        textScaleCalls[#textScaleCalls + 1] = scale
    end,
    UpdateNativeChildSkinPixels = function(skin) return skin.pixelReady end,
    RestoreFontStringPresentation = function() end,
}
local CooldownSetSwipeTexture = function() end
local CooldownSetHideCountdownNumbers = function() end
local squareCooldownSwipeTexture = "square"
local nativeCooldownSwipeTexture = "native"
local ApplyFont = function(_, _, scale)
    fontScaleCalls[#fontScaleCalls + 1] = scale
end
local GetCountText = function(item) return item and item.Count end
local ApplyBarContent
local UpdateItemAssistedHighlight = function() end
local hotkeyOverlays = setmetatable({}, {__mode = "k"})
local GetNonSecretSpellID = function(value)
    return IsSafeNumber(value) and value or nil
end
local EnsureHotkeyOverlay = function(item)
    local overlay = hotkeyOverlays[item]
    if not overlay then
        overlay = {text = {}}
        hotkeyOverlays[item] = overlay
    end
    return overlay, item
end
local PositionHotkey = function(_, _, _, scale)
    hotkeyPositionScaleCalls[#hotkeyPositionScaleCalls + 1] = scale
end
local FontStringSetText = function(region, value) region.text = value end
local FontStringShow = function(region) region.shown = true end
FontStringHide = function(region) region.shown = false end
FontStringSetAlpha = function(region, alpha) region.alpha = alpha end
HideItemHotkey = function() end
local ResolveItemHotkey = function() return "1" end
local ceil = math.ceil
local max = math.max
local min = math.min
local sort = table.sort
local itemStates = setmetatable({}, {__mode = "k"})
local fallbackOrder = 0
local GetActiveItems = function(viewer) return viewer.items end
local viewerStates = {}
local presentationOnUpdate
local presentationUpdateSchedules = 0
local presentationController = {
    buffVisibility = {
        Update = function() end,
    },
    SetScript = function(_, script, handler)
        if script == "OnUpdate" then
            presentationOnUpdate = handler
            if handler then
                presentationUpdateSchedules = presentationUpdateSchedules + 1
            end
        end
    end,
}
local presentationDirtyMarks = 0
local InitializeViewers = function() end
local blizzardEditModeActive = false
local IsBlizzardEditModeActive = function()
    return blizzardEditModeActive
end
local inCombat = false
local InCombatLockdown = function() return inCombat end
local CanChangeGeometry = function(region)
    return not inCombat and region.changeable ~= false
end
local ReconcileViewer = function(state)
    return state.complete, state.geometryChanged
end
local RestoreViewer = function(state)
    return state.restored ~= false
end
local RefreshAssistedHighlightState = function() end
local BindHolderPosition
local BuildLayout
local UpdateHolderPreview
local ApplyRuntimePresentation
local CanApplyStaticPresentation
local RestoreItem
local QueuePresentationUpdate
local hotkeyRefreshEvents = {}
local hotkeyGeneration = 1
local MarkPresentationDirty = function()
    presentationDirtyMarks = presentationDirtyMarks + 1
    presentationGeneration = presentationGeneration + 1
    hotkeyGeneration = hotkeyGeneration + 1
    QueuePresentationUpdate()
end
LUA

    sed -n \
        '/^local function SkinIcon(/,/^ApplyFont =/p' \
        "$module" | sed '$d'
    sed -n \
        '/^function PresentationMethods.GetPixelSnappedScale/,/^local function GetLayoutBounds(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function CaptureNativeGeometry(/,/^local function CaptureShown(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function CapturePresentationDefaults(/,/^local function RecapturePresentationDefaults(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function SetShown(/,/^function PresentationMethods.RefreshNativeItemGeometry/p' \
        "$module" | sed '$d;
            s/^local function SetShown(/SetShown = function(/;
            s/^local function RestoreItemPresentation(/RestoreItemPresentation = function(/;
            s/^local function CanRestoreItemPresentation(/CanRestoreItemPresentation = function(/'
    sed -n \
        '/^function PresentationMethods.RefreshNativeItemGeometry/,/^local function RestoreItem(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function RestoreItem(/,/^local function CreateNativeSkinLayer/p' \
        "$module" | sed '$d; s/^local function RestoreItem(/RestoreItem = function(/'
    sed -n \
        '/^local function ApplyBarContent(/,/^local function ApplyStaticPresentation(/p' \
        "$module" | sed '$d; s/^local function ApplyBarContent(/ApplyBarContent = function(/'
    sed -n \
        '/^local function ApplyStaticPresentation(/,/^local function GetPresentationAlpha(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function ApplyHotkeyPresentation(/,/^GetCountText = function/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function GetOrCreateItemState(/,/^local function CurrentGeometryMatches(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function CurrentGeometryMatches(/,/^local function RestoreMissingItems(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function GetLayoutBounds(/,/^local function EnsurePreviewFrame(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^function presentationController:ReleaseCombatBlock/,/^local function ProcessPresentationUpdate/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function ProcessPresentationUpdate/,/^QueuePresentationUpdate = function/p' \
        "$module" | sed '$d'
    sed -n \
        '/^QueuePresentationUpdate = function/,/^local function UpdateCooldownManager/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function OnPresentationEvent(/,/^for event in next, hotkeyRefreshEvents/p' \
        "$module" | sed '$d'
    sed -n \
        '/^function PresentationMethods.OnCooldownDataChanged/,/^EventRegistry:RegisterCallback/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function RestoreMissingItems(/,/^local function RestoreViewer(/p' \
        "$module" | sed '$d'

    cat <<'LUA'
local function check(condition, message)
    if not condition then
        error(message, 2)
    end
end

-- A viewer can exist before all of its child regions are initialized. A
-- partial native-default capture must not be marked complete or styled, and a
-- later pass must retain already-captured defaults while filling the gaps.
local iconFrame = {
    shown = true,
    alpha = 1,
    width = 30,
    height = 30,
    points = {{"LEFT", nil, "LEFT", 0, 0}},
    Icon = {},
}
local cooldown = {hideCountdownNumbers = false}
local item = {
    alpha = 1,
    mouseMotion = true,
    Cooldown = cooldown,
    Icon = iconFrame,
}
iconFrame.points[1][2] = item
local state = {definition = {isBar = true}}
local config = {
    showTimer = true,
    cooldownText = {},
    countText = {},
    barText = {},
    durationText = {},
}
local itemState = {}
itemState.expected = {visualWidth = 220, visualHeight = 30}

check(not ApplyStaticPresentation(item, state, config, itemState, 1),
    "incomplete startup capture unexpectedly succeeded")
check(itemState.presentationGeneration == nil,
    "incomplete startup capture was marked current")
check(itemState.presentationCaptured == nil,
    "incomplete startup capture was marked complete")
check(itemState.nativeAlpha == 1,
    "available startup defaults were not captured")

item.alpha = 0.25
item.Bar = {
    width = 188,
    height = 19,
    points = {
        {"LEFT", iconFrame, "RIGHT", 2, 0},
        {"RIGHT", item, "RIGHT", 0, 0},
    },
    Name = {shown = true, alpha = 1, points = {{"LEFT", nil, "LEFT", 5, 0}}},
    Duration = {shown = true, alpha = 1, points = {{"RIGHT", nil, "RIGHT", -8, 0}}},
    fill = {},
}
check(not ApplyStaticPresentation(item, state, config, itemState, 1),
    "missing icon regions unexpectedly marked presentation complete")
check(itemState.presentationGeneration == nil,
    "missing icon regions were not scheduled for retry")
check(itemState.nativeAlpha == 1,
    "retry overwrote an already-captured native default")

iconFrame.mask = {}
iconFrame.overlay = {}
check(not ApplyStaticPresentation(item, state, config, itemState, 1),
    "missing bar background unexpectedly marked presentation complete")
check(itemState.presentationGeneration == nil,
    "missing bar background was not scheduled for retry")

item.Bar.BarBG = {}
check(not ApplyStaticPresentation(item, state, config, itemState, 1),
    "missing tracked-bar pip unexpectedly marked presentation complete")
check(itemState.presentationGeneration == nil,
    "missing tracked-bar pip was not scheduled for retry")

item.Bar.Pip = {shown = true, alpha = 1}
local nativeTrackedBarFill = item.Bar.fill
item.Bar.fill.textureReady = false
check(not ApplyStaticPresentation(item, state, config, itemState, 1),
    "failed tracked-bar fill swap unexpectedly marked presentation complete")
check(itemState.presentationGeneration == nil,
    "failed tracked-bar fill swap was not scheduled for retry")
check(item.Bar.BarBG.hidden ~= true,
    "failed tracked-bar fill swap hid the native background")

item.Bar.fill.textureReady = true
itemState.nativeNameText = {
    fontString = item.Bar.Name,
    points = item.Bar.Name.points,
}
itemState.nativeDurationText = {
    fontString = item.Bar.Duration,
    points = item.Bar.Duration.points,
}
check(ApplyStaticPresentation(item, state, config, itemState, 1),
    "completed startup presentation did not succeed on retry")
check(itemState.presentationGeneration == presentationGeneration,
    "successful retry was not marked current")
check(itemState.presentationCaptured == true,
    "successful retry did not complete native-default capture")
check(item.Bar.BarBG.hidden == true,
    "tracked-bar native background remained visible")
check(item.Bar.fill.asset == BFI.media.bar,
    "tracked-bar fill did not use BFI bar media")
check(item.Bar.fill == nativeTrackedBarFill,
    "tracked-bar skin replaced Blizzard's managed fill object")
check(item.Bar.fill.drawLayer == "BORDER" and item.Bar.fill.subLevel == -1,
    "tracked-bar fill draw layer did not match AF")
local trackedBarSkin = barSkins[item.Bar]
check(trackedBarSkin
    and trackedBarSkin.background.shown == true
    and trackedBarSkin.border.shown == true,
    "tracked-bar AF background or border was not shown")
check(item.Bar.Pip.alpha == 0,
    "tracked-bar native pip alpha was not suppressed")
item.Bar.Pip.shown = true
check(item.Bar.Pip.alpha == 0,
    "native pip visibility update restored Blizzard styling")
check(PresentationMethods.RestoreTrackedBarPip(item.Bar, itemState),
    "tracked-bar native pip could not be restored")
check(item.Bar.Pip.alpha == 1,
    "tracked-bar native pip alpha was not restored")

-- BuffBar OnAcquire always reapplies Blizzard's outer item width. BFI must
-- leave that footprint native and center its scaled visual children inside it,
-- otherwise an in-combat full RefreshLayout can expand the bar until regen.
barCase = {}
barCase.holder = {scale = 1, effectiveScale = 1}
barCase.viewer = {scale = 1, parentEffectiveScale = 1}
barCase.definition = {isBar = true}
barCase.viewerState = {
    holder = barCase.holder,
    viewer = barCase.viewer,
    definition = barCase.definition,
}
barCase.nativeItemPoints = {
    {"CENTER", barCase.viewer, "CENTER", 0, 0},
}
item.width = 220
item.height = 30
item.scale = 1
item.points = barCase.nativeItemPoints
itemState.owner = barCase.viewerState
itemState.definition = barCase.definition
itemState.nativePoints = barCase.nativeItemPoints
itemState.nativeWidth = 220
itemState.nativeHeight = 30
itemState.nativeScale = 1
itemState.applied = true
barCase.desired = {
    x = 0,
    y = 0,
    width = 220,
    height = 30,
    visualWidth = 176,
    visualHeight = 24,
    scale = 1,
    presentationRatio = 0.8,
}
barCase.entry = {
    item = item,
    itemState = itemState,
    desired = barCase.desired,
    needsGeometry = true,
}
ApplyItemGeometry(barCase.entry, barCase.viewerState)
check(item.width == 220 and item.height == 30,
    "tracked-bar geometry changed Blizzard's native outer footprint")
check(ApplyStaticPresentation(
    item,
    barCase.viewerState,
    config,
    itemState,
    0.8
), "tracked-bar visual geometry did not apply")
check(iconFrame.width == 24 and iconFrame.height == 24
    and iconFrame.points[1][2] == item
    and iconFrame.points[1][3] == "CENTER"
    and NearlyEqual(iconFrame.points[1][4], -88),
    "tracked-bar icon was not centered inside the native outer item")
check(item.Bar.points[2][2] == item
    and item.Bar.points[2][3] == "CENTER"
    and NearlyEqual(item.Bar.points[2][4], 88)
    and NearlyEqual(item.Bar.height, 15.2),
    "tracked-bar visual right edge or height missed the configured scale")

-- Model BuffBar OnAcquire in combat: SetBarWidth restores the same native
-- outer width, while SetBarContent rewrites only the Bar's LEFT point. The
-- centered icon edge and explicit visual right edge must survive unchanged.
item.width = 220
item.points = {{"CENTER", barCase.viewer, "CENTER", 0, 0}}
item.Bar.points[1] = {"LEFT", iconFrame, "RIGHT", 2, 0}
inCombat = true
barCase.combatEntry = {item = item, itemState = itemState}
check(PrepareItemGeometry(
    barCase.combatEntry,
    barCase.viewerState,
    barCase.desired
) and barCase.combatEntry.needsGeometry,
    "in-combat tracked-bar native reacquire was not detected")
check(not CanChangeGeometry(item)
    and item.width == 220
    and NearlyEqual(iconFrame.points[1][4], -88)
    and NearlyEqual(item.Bar.points[2][4], 88),
    "native tracked-bar reacquire reset BFI's rendered visual width")
inCombat = false
ApplyItemGeometry(barCase.combatEntry, barCase.viewerState)

-- A width option change must refresh child geometry even though the native
-- outer item and centered holder anchor are intentionally unchanged.
barCase.widerDesired = {
    x = 0,
    y = 0,
    width = 220,
    height = 30,
    visualWidth = 264,
    visualHeight = 24,
    scale = 1,
    presentationRatio = 0.8,
}
barCase.widerEntry = {item = item, itemState = itemState}
check(PrepareItemGeometry(
    barCase.widerEntry,
    barCase.viewerState,
    barCase.widerDesired
) and barCase.widerEntry.needsGeometry,
    "tracked-bar visual width change was hidden by stable outer geometry")
ApplyItemGeometry(barCase.widerEntry, barCase.viewerState)
check(ApplyStaticPresentation(
    item,
    barCase.viewerState,
    config,
    itemState,
    0.8
), "wider tracked-bar visual geometry did not apply")
check(NearlyEqual(iconFrame.points[1][4], -132)
    and NearlyEqual(item.Bar.points[2][4], 132),
    "tracked-bar child edges retained stale visual width")

check(RestoreItem(item, itemState),
    "tracked-bar native geometry could not be restored")
check(item.width == 220 and item.height == 30
    and item.points[1][2] == barCase.viewer,
    "tracked-bar restore lost the native outer footprint or anchor")
check(iconFrame.width == 30 and iconFrame.height == 30
    and iconFrame.points[1][2] == item
    and iconFrame.points[1][3] == "LEFT",
    "tracked-bar restore lost native icon geometry")
check(item.Bar.width == 188 and item.Bar.height == 19
    and item.Bar.points[1][2] == iconFrame
    and item.Bar.points[2][3] == "RIGHT",
    "tracked-bar restore lost native bar geometry")

-- Inverse raw-geometry compensation also has to reach fonts and text offsets;
-- otherwise retained native item scale makes labels visually diverge from the
-- configured icon size.
fontScaleCalls = {}
textScaleCalls = {}
CM.config.skin = false
local scaledCountdown = {points = {{"CENTER", nil, "CENTER", 0, 0}}}
local scaledCount = {points = {{"BOTTOMRIGHT", nil, "BOTTOMRIGHT", -2, 2}}}
local scaledItem = {
    alpha = 1,
    mouseMotion = true,
    Cooldown = {
        hideCountdownNumbers = false,
        countdownText = scaledCountdown,
    },
    Count = scaledCount,
}
local scaledState = {definition = {}}
local scaledItemState = {
    nativeCountdownText = {
        fontString = scaledCountdown,
        points = scaledCountdown.points,
    },
    nativeCountText = {
        fontString = scaledCount,
        points = scaledCount.points,
    },
}
local scaledConfig = {
    showTimer = true,
    cooldownText = {position = {}},
    countText = {},
}
check(ApplyStaticPresentation(
    scaledItem,
    scaledState,
    scaledConfig,
    scaledItemState,
    1.2
), "scaled icon text presentation did not complete")
check(#fontScaleCalls == 2
    and NearlyEqual(fontScaleCalls[1], 1.2)
    and NearlyEqual(fontScaleCalls[2], 1.2),
    "cooldown or count font missed the item presentation ratio")
check(#textScaleCalls == 1 and NearlyEqual(textScaleCalls[1], 1.2),
    "cooldown text offsets missed the item presentation ratio")
CM.config.skin = true

fontScaleCalls = {}
hotkeyPositionScaleCalls = {}
local scaledHotkeyItem = {cooldownID = 123}
check(ApplyHotkeyPresentation(
    scaledHotkeyItem,
    {},
    {showHotkeys = true, hotkeyText = {}, hotkeyPosition = {}},
    {},
    1.2
), "scaled hotkey presentation did not complete")
check(#fontScaleCalls == 1 and NearlyEqual(fontScaleCalls[1], 1.2),
    "hotkey font missed the item presentation ratio")
check(#hotkeyPositionScaleCalls == 1
    and NearlyEqual(hotkeyPositionScaleCalls[1], 1.2),
    "hotkey offsets missed the item presentation ratio")

-- Blizzard 12.1 briefly hides assigned items during a target refresh. Those
-- items remain layout children natively and must remain in BFI's centered
-- layout, while unassigned minimum-count placeholders remain excluded.
local visible = {
    layoutIndex = 1,
    shown = true,
    cooldownID = 101,
    includeAsLayoutChildWhenHidden = true,
}
local assignedHidden = {
    layoutIndex = 2,
    shown = false,
    cooldownID = 102,
    includeAsLayoutChildWhenHidden = true,
}
local placeholder = {
    layoutIndex = 3,
    shown = false,
    includeAsLayoutChildWhenHidden = true,
}
local excludedHidden = {
    layoutIndex = 4,
    shown = false,
    cooldownID = 104,
    includeAsLayoutChildWhenHidden = false,
}
local secretAssigned = {
    layoutIndex = 5,
    shown = false,
    cooldownID = SECRET,
    includeAsLayoutChildWhenHidden = true,
}
local unknownShown = {
    layoutIndex = 6,
    shown = SECRET,
}
local viewerState = {
    definition = {},
    viewer = {
        items = {
            unknownShown,
            placeholder,
            assignedHidden,
            excludedHidden,
            secretAssigned,
            visible,
        },
    },
}

local allItems, layoutItems = GetOrderedItems(viewerState)
check(#allItems == 6, "active item accounting changed")
check(#layoutItems == 4, "hidden layout membership changed")
check(layoutItems[1].item == visible
    and layoutItems[2].item == assignedHidden
    and layoutItems[3].item == secretAssigned
    and layoutItems[4].item == unknownShown,
    "layout items were filtered or sorted incorrectly")

local function GetPositions(items, center)
    local layout = {
        count = #items,
        capacity = 3,
        orientation = "horizontal",
        direction = "right",
        center = center,
        width = 40,
        height = 40,
        padding = 2,
    }
    local positions = {}
    for index = 1, #items do
        positions[index] = {GetLayoutPosition(layout, index)}
    end
    return positions
end

local centeredPositions = GetPositions(layoutItems, true)
local edgePositions = GetPositions(layoutItems, false)

visible.shown = false
local _, targetRefreshLayout = GetOrderedItems(viewerState)
check(#targetRefreshLayout == 4
    and targetRefreshLayout[1].item == visible
    and targetRefreshLayout[2].item == assignedHidden,
    "target refresh compacted assigned hidden items")
local targetCenteredPositions = GetPositions(targetRefreshLayout, true)
local targetEdgePositions = GetPositions(targetRefreshLayout, false)
for index = 1, #layoutItems do
    check(centeredPositions[index][1] == targetCenteredPositions[index][1]
        and centeredPositions[index][2] == targetCenteredPositions[index][2],
        "target refresh shifted a centered layout position")
    check(edgePositions[index][1] == targetEdgePositions[index][1]
        and edgePositions[index][2] == targetEdgePositions[index][2],
        "target refresh shifted a non-centered layout position")
end

assignedHidden.cooldownID = nil
local _, releasedLayout = GetOrderedItems(viewerState)
check(#releasedLayout == 3,
    "released placeholder remained in the centered layout")

-- Retail 12.1 uses the native viewer root as its GridLayout container. BFI
-- keeps that root centered on its holder, but leaves Blizzard's root and item
-- scales untouched. Raw item dimensions and offsets are inverse-compensated,
-- and the stable item anchor belongs directly to the BFI holder.
local holder = {scale = 1, effectiveScale = 0.8}
local nativeContainer = {}
local viewerRoot = {
    alpha = 0.7,
    scale = 1,
    parentEffectiveScale = 1,
    points = {{"BOTTOM", nativeContainer, "BOTTOM", 0, 100}},
}
local geometryViewerState = {
    holder = holder,
    viewer = viewerRoot,
    definition = {},
}
local expectedRatio = 1.2
local desired = {
    x = -21 * expectedRatio,
    y = 0,
    width = 40 * expectedRatio,
    height = 40 * expectedRatio,
    scale = 0.5,
    presentationRatio = expectedRatio,
}
local geometryItem = {
    width = desired.width,
    height = desired.height,
    scale = desired.scale,
    points = {{"CENTER", holder, "CENTER", desired.x, desired.y}},
}
local geometryState = {
    owner = geometryViewerState,
    definition = {},
    applied = true,
    expected = desired,
    nativePoints = {{"TOPLEFT", viewerRoot, "TOPLEFT", 0, 0}},
    nativeWidth = 40,
    nativeHeight = 40,
    nativeScale = 0.5,
}
local geometryEntry = {
    item = geometryItem,
    itemState = geometryState,
}

-- A native RefreshLayout restores viewer-relative points but does not reset
-- raw icon dimensions. Preserve that native restoration point, detect the
-- ownership change, and repair the stable holder anchor without touching scale.
geometryItem.points = {{"TOPLEFT", viewerRoot, "TOPLEFT", 8, -8}}
check(PrepareItemGeometry(
    geometryEntry,
    geometryViewerState,
    desired
), "native target-refresh anchor reset could not be reconciled")
check(geometryEntry.needsGeometry == true,
    "native target-refresh anchor reset was not detected")
check(geometryState.applied == true and geometryState.expected == desired,
    "native child relayout discarded reversible BFI geometry state")
check(geometryState.nativePoints[1][2] == viewerRoot,
    "viewer-relative native child geometry was not captured")

ApplyItemGeometry(geometryEntry, geometryViewerState)
check(CurrentGeometryMatches(geometryItem, holder, desired) == true,
    "BFI holder anchor was not restored in the reconciliation pass")
check(geometryItem.scale == 0.5,
    "holder-anchor repair changed Blizzard's native item scale")
check(geometryState.applied == true and geometryState.expected == desired,
    "restored BFI geometry state was not recorded")

local stableEntry = {item = geometryItem, itemState = geometryState}
check(PrepareItemGeometry(stableEntry, geometryViewerState, desired),
    "stable holder geometry could not be verified")
check(not stableEntry.needsGeometry,
    "stable holder geometry was needlessly reapplied")

-- If a geometry aspect becomes secret, the pass must stop without clearing
-- the last known BFI state or attempting a write.
geometryItem.points = {{"CENTER", holder, "CENTER", SECRET, desired.y}}
local guardedEntry = {item = geometryItem, itemState = geometryState}
check(not PrepareItemGeometry(guardedEntry, geometryViewerState, desired),
    "secret target-refresh geometry did not fail closed")
check(geometryState.applied == true and geometryState.expected == desired,
    "secret geometry invalidated the last known BFI state")

-- Restore-time refresh accepts only the latest viewer-relative native anchor.
-- A full pool reacquire restores the native scale BFI already retained, so it
-- must not replace the original native raw dimensions with compensated ones.
local refreshItem = {
    width = desired.width,
    height = desired.height,
    scale = 0.5,
    points = {{"TOPLEFT", viewerRoot, "TOPLEFT", 3, -4}},
}
local refreshState = {
    owner = geometryViewerState,
    definition = {},
    expected = desired,
    nativePoints = {{"TOPLEFT", viewerRoot, "TOPLEFT", 0, 0}},
    nativeWidth = 40,
    nativeHeight = 40,
    nativeScale = 0.5,
}
check(PresentationMethods.RefreshNativeItemGeometry(
    refreshItem,
    refreshState
), "point-only native child relayout was unsafe to capture")
check(refreshState.nativePoints[1][4] == 3
    and refreshState.nativeScale == 0.5
    and refreshState.nativeWidth == 40
    and refreshState.nativeHeight == 40,
    "viewer-relative child relayout replaced captured native geometry")

refreshItem.points = {{"TOPLEFT", viewerRoot, "TOPLEFT", 7, -8}}
check(PresentationMethods.RefreshNativeItemGeometry(
    refreshItem,
    refreshState
), "full native child acquisition was unsafe to capture")
check(refreshState.nativePoints[1][4] == 7
    and refreshState.nativeWidth == 40
    and refreshState.nativeHeight == 40
    and refreshState.nativeScale == 0.5,
    "full native child acquisition captured compensated dimensions as native")

local rootState = geometryViewerState
local rootBound, rootChanged =
    PresentationMethods.BindViewerGeometry(rootState)
check(rootBound and rootChanged,
    "native viewer root was not bound on first enable")
check(NearlyEqual(viewerRoot.scale, 1),
    "viewer root did not preserve its managed native scale")
local presentationRatio, nativeItemScale =
    PresentationMethods.GetItemPresentationRatio(
        rootState,
        geometryItem,
        geometryState,
        0.75
    )
check(NearlyEqual(presentationRatio, expectedRatio)
    and NearlyEqual(nativeItemScale, 0.5),
    "inverse item presentation ratio did not retain native scale")
check(viewerRoot.points[1][1] == "CENTER"
    and viewerRoot.points[1][2] == holder
    and viewerRoot.points[1][3] == "CENTER",
    "viewer root did not land on the BFI holder")
check((viewerRoot.alphaWrites or 0) == 0 and viewerRoot.alpha == 0.7,
    "root binding used an alpha curtain")

local stableRoot, stableRootChanged =
    PresentationMethods.BindViewerGeometry(rootState)
check(stableRoot and not stableRootChanged,
    "stable viewer-root geometry was needlessly rewritten")

viewerRoot.points = {
    {"TOPLEFT", nativeContainer, "TOPLEFT", 0, 0},
    {"BOTTOMRIGHT", nativeContainer, "BOTTOMRIGHT", 0, 0},
}
local multiPointRoot, multiPointChanged =
    PresentationMethods.BindViewerGeometry(rootState)
check(multiPointRoot and multiPointChanged
    and #viewerRoot.points == 1
    and viewerRoot.points[1][2] == holder,
    "managed multi-point root rewrite was not repaired")

-- Model the full form-driven native rebuild: pooled child points return to
-- the root's native grid and OnAcquire reapplies the same native scale BFI has
-- retained all along. The compensated raw size must therefore remain visually
-- unchanged even before the safe holder-anchor repair runs.
geometryItem.points = {{"TOPLEFT", viewerRoot, "TOPLEFT", 0, 0}}
geometryItem.width = desired.width
geometryItem.height = desired.height
geometryItem.scale = 0.5
check(viewerRoot.points[1][2] == holder
    and NearlyEqual(viewerRoot.scale, 1),
    "native child rebuild displaced the persistent viewer root")
check(NearlyEqual(geometryItem.width * geometryItem.scale, 24)
    and NearlyEqual(geometryItem.height * geometryItem.scale, 24),
    "full native reacquire changed the configured rendered item size")
check((viewerRoot.alphaWrites or 0) == 0,
    "native child rebuild triggered an alpha write")
local formEntry = {item = geometryItem, itemState = geometryState}
check(PrepareItemGeometry(formEntry, geometryViewerState, desired)
    and formEntry.needsGeometry,
    "form-driven native child layout was not detected")
ApplyItemGeometry(formEntry, geometryViewerState)
check(CurrentGeometryMatches(geometryItem, holder, desired),
    "exact holder-centered child layout was not restored after form rebuild")
check(geometryItem.scale == 0.5
    and NearlyEqual(geometryItem.width * geometryItem.scale, 24),
    "form repair changed native scale or configured rendered size")

-- A managed-frame overwrite in combat fails open. Once restrictions lift,
-- the same finite reconciliation restores the root without recapturing the
-- overwritten native position as BFI's reversible baseline.
viewerRoot.scale = 1
viewerRoot.points = {{"BOTTOM", nativeContainer, "BOTTOM", 0, 100}}
inCombat = true
local combatBound, combatChanged =
    PresentationMethods.BindViewerGeometry(rootState)
check(not combatBound and not combatChanged,
    "protected viewer root was moved during combat")
inCombat = false
local rebound, reboundChanged =
    PresentationMethods.BindViewerGeometry(rootState)
check(rebound and reboundChanged and viewerRoot.points[1][2] == holder,
    "viewer root did not recover after restrictions lifted")

local latestRestoreContainer = {}
viewerRoot.points = {
    {"TOP", latestRestoreContainer, "TOP", 0, -80},
}
check(PresentationMethods.RestoreViewerGeometry(rootState),
    "viewer root native geometry could not be restored")
check(viewerRoot.scale == 1
    and viewerRoot.points[1][1] == "TOP"
    and viewerRoot.points[1][2] == latestRestoreContainer,
    "viewer root restoration overwrote a newer native managed layout")

-- Exercise the complete non-empty reconciliation path with deliberately mixed
-- native item scales. Each item keeps its Blizzard scale; its raw geometry and
-- presentation ratio differ so both render at the same configured BFI size.
local integrationStaticCalls = 0
local integrationRuntimeCalls = 0
local integrationStaticRatios = {}
local integrationRuntimeRatios = {}
local integrationRestoreOrder = {}
local originalApplyStaticPresentation = ApplyStaticPresentation
local originalRestoreViewerGeometry =
    PresentationMethods.RestoreViewerGeometry

BindHolderPosition = function(state)
    return state.holder
end
BuildLayout = function(definition, config, count)
    return {
        count = count,
        orientation = config.orientation,
        direction = config.direction,
        center = config.center,
        width = definition.itemWidth,
        height = definition.itemHeight,
        padding = config.padding,
        scale = config.scale,
        capacity = min(config.iconLimit, count),
    }
end
UpdateHolderPreview = function() end
ApplyRuntimePresentation = function(_, _, _, presentationRatio)
    integrationRuntimeCalls = integrationRuntimeCalls + 1
    integrationRuntimeRatios[#integrationRuntimeRatios + 1] = presentationRatio
end
CanApplyStaticPresentation = function()
    return true
end
ApplyStaticPresentation = function(_, _, _, itemState, presentationRatio)
    integrationStaticCalls = integrationStaticCalls + 1
    integrationStaticRatios[#integrationStaticRatios + 1] = presentationRatio
    itemState.presentationGeneration = presentationGeneration
    return true
end
RestoreItem = function(item, itemState)
    integrationRestoreOrder[#integrationRestoreOrder + 1] =
        "child-" .. item.layoutIndex
    FrameSetSize(item, itemState.nativeWidth, itemState.nativeHeight)
    RestorePoints(item, itemState.nativePoints)
    itemState.applied = nil
    itemState.expected = nil
    return true
end
PresentationMethods.RestoreViewerGeometry = function(state)
    integrationRestoreOrder[#integrationRestoreOrder + 1] = "root"
    return originalRestoreViewerGeometry(state)
end

local integrationNativeContainer = {}
local integrationHolder = {scale = 1, effectiveScale = 0.8}
local integrationViewer = {
    scale = 1,
    parentEffectiveScale = 1,
    shown = true,
    points = {{"BOTTOM", integrationNativeContainer, "BOTTOM", 0, 120}},
}
local integrationItemA = {
    layoutIndex = 1,
    shown = true,
    cooldownID = 201,
    width = 40,
    height = 40,
    scale = 1,
    points = {{"TOPLEFT", integrationViewer, "TOPLEFT", 0, 0}},
}
local integrationItemB = {
    layoutIndex = 2,
    shown = true,
    cooldownID = 202,
    width = 40,
    height = 40,
    scale = 0.8,
    points = {{"TOPLEFT", integrationViewer, "TOPLEFT", 42, 0}},
}
integrationViewer.items = {integrationItemB, integrationItemA}

local integrationState = {
    holder = integrationHolder,
    viewer = integrationViewer,
    definition = {
        itemWidth = 40,
        itemHeight = 40,
        previewCount = 2,
        hasIconLimit = true,
    },
}
local integrationConfig = {
    orientation = "horizontal",
    direction = "right",
    center = true,
    padding = 2,
    scale = 0.75,
    iconLimit = 2,
}

local integrationComplete, integrationChanged =
    ReconcileViewer(integrationState, integrationConfig)
check(integrationComplete and integrationChanged,
    "non-empty first reconciliation did not apply geometry")
check(NearlyEqual(integrationViewer.scale, 1),
    "non-empty reconciliation changed managed root scale")
check(NearlyEqual(integrationItemA.scale, 1)
    and NearlyEqual(integrationItemB.scale, 0.8),
    "mixed Blizzard item scales were mutated")
check(NearlyEqual(integrationItemA.width, 24)
    and NearlyEqual(integrationItemB.width, 30)
    and NearlyEqual(integrationItemA.width * integrationItemA.scale, 24)
    and NearlyEqual(integrationItemB.width * integrationItemB.scale, 24),
    "inverse raw dimensions did not preserve uniform rendered size")
check(integrationItemA.points[1][2] == integrationHolder
    and integrationItemB.points[1][2] == integrationHolder
    and NearlyEqual(integrationItemA.points[1][4], -12.6)
    and NearlyEqual(integrationItemB.points[1][4], 15.75),
    "mixed native scales did not produce compensated holder offsets")
check(integrationStaticCalls == 2 and integrationRuntimeCalls == 2,
    "non-empty reconciliation skipped runtime or static presentation")
check(NearlyEqual(integrationStaticRatios[1], 0.6)
    and NearlyEqual(integrationStaticRatios[2], 0.75)
    and NearlyEqual(integrationRuntimeRatios[1], 0.6)
    and NearlyEqual(integrationRuntimeRatios[2], 0.75),
    "reconciliation did not propagate each item's presentation ratio")

-- Model a managed root rewrite and a full native child GridLayout in the same
-- lifecycle turn. One reconciliation must recover both without alpha writes.
local integrationLatestContainer = {}
integrationViewer.scale = 1
integrationViewer.points = {
    {"TOPLEFT", integrationLatestContainer, "TOPLEFT", 0, 0},
    {"BOTTOMRIGHT", integrationLatestContainer, "BOTTOMRIGHT", 0, 0},
}
integrationItemA.points =
    {{"TOPLEFT", integrationViewer, "TOPLEFT", 0, 0}}
integrationItemB.points =
    {{"TOPLEFT", integrationViewer, "TOPLEFT", 42, 0}}

integrationComplete, integrationChanged =
    ReconcileViewer(integrationState, integrationConfig)
check(integrationComplete and integrationChanged,
    "native root and child rewrites were not detected")
check(#integrationViewer.points == 1
    and integrationViewer.points[1][2] == integrationHolder
    and NearlyEqual(integrationViewer.scale, 1),
    "native root rewrite was not repaired by reconciliation")
check(integrationItemA.points[1][2] == integrationHolder
    and integrationItemB.points[1][2] == integrationHolder
    and NearlyEqual(integrationItemA.points[1][4], -12.6)
    and NearlyEqual(integrationItemB.points[1][4], 15.75)
    and NearlyEqual(integrationItemA.scale, 1)
    and NearlyEqual(integrationItemB.scale, 0.8),
    "native child rewrite was not repaired on the stable holder")
check(integrationStaticCalls == 4 and integrationRuntimeCalls == 4,
    "geometry recovery did not reapply static presentation")

local stableAX = integrationItemA.points[1][4]
local stableBX = integrationItemB.points[1][4]
presentationGeneration = presentationGeneration + 1
integrationComplete, integrationChanged =
    ReconcileViewer(integrationState, integrationConfig)
check(integrationComplete and not integrationChanged,
    "presentation-only generation change rewrote geometry")
check(integrationStaticCalls == 6 and integrationRuntimeCalls == 6,
    "presentation generation change did not reapply static styling")
check(integrationItemA.points[1][4] == stableAX
    and integrationItemB.points[1][4] == stableBX,
    "presentation-only pass changed local offsets")

-- Native code may rebuild child anchors during combat, but OnAcquire only
-- reapplies the native scales BFI already retains. The compensated dimensions
-- must keep the rendered size stable while writes are blocked; the first safe
-- pass then repairs only holder ownership and exact offsets.
integrationItemA.points =
    {{"TOPLEFT", integrationViewer, "TOPLEFT", 0, 0}}
integrationItemB.points =
    {{"TOPLEFT", integrationViewer, "TOPLEFT", 42, 0}}
inCombat = true
integrationComplete, integrationChanged =
    ReconcileViewer(integrationState, integrationConfig)
check(not integrationComplete and not integrationChanged,
    "combat child rewrite was treated as safely repairable")
check(integrationItemA.scale == 1
    and integrationItemB.scale == 0.8
    and NearlyEqual(integrationItemA.width * integrationItemA.scale, 24)
    and NearlyEqual(integrationItemB.width * integrationItemB.scale, 24),
    "combat reacquire changed native scale or configured rendered size")
inCombat = false
integrationComplete, integrationChanged =
    ReconcileViewer(integrationState, integrationConfig)
check(integrationComplete and integrationChanged
    and integrationItemA.points[1][2] == integrationHolder
    and integrationItemB.points[1][2] == integrationHolder
    and NearlyEqual(integrationItemA.scale, 1)
    and NearlyEqual(integrationItemB.scale, 0.8),
    "post-combat pass did not safely repair holder geometry")

blizzardEditModeActive = true
integrationComplete, integrationChanged =
    ReconcileViewer(integrationState, integrationConfig)
check(integrationComplete and not integrationChanged,
    "edit-mode restoration did not complete")
check(table.concat(integrationRestoreOrder, ",") ==
    "child-1,child-2,root",
    "non-empty restoration did not restore children before the root")
check(integrationViewer.scale == 1
    and #integrationViewer.points == 2
    and integrationViewer.points[1][2] == integrationLatestContainer,
    "non-empty restoration lost native root geometry")
check(integrationItemA.scale == 1
    and integrationItemB.scale == 0.8,
    "non-empty restoration lost per-item native scale")

blizzardEditModeActive = false
ApplyStaticPresentation = originalApplyStaticPresentation
PresentationMethods.RestoreViewerGeometry =
    originalRestoreViewerGeometry

-- Form, aura-data, and target lifecycle edges are now dirty wakes only. They
-- must never write viewer alpha or arm a second observer transaction.
hotkeyRefreshEvents.UPDATE_SHAPESHIFT_FORM = true
hotkeyRefreshEvents.UPDATE_SHAPESHIFT_FORMS = true
presentationOnUpdate = nil
presentationUpdateSchedules = 0
presentationDirtyMarks = 0
viewerRoot.alphaWrites = 0
OnPresentationEvent(nil, "UPDATE_SHAPESHIFT_FORM")
OnPresentationEvent(nil, "UPDATE_SHAPESHIFT_FORMS")
PresentationMethods.OnCooldownDataChanged()
OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
check(viewerRoot.alphaWrites == 0 and viewerRoot.alpha == 0.7,
    "form or data lifecycle wake hid the native viewer")
check(presentationOnUpdate == ProcessPresentationUpdate
    and presentationUpdateSchedules >= 4,
    "form and data lifecycle edges did not schedule reconciliation")
check(presentationDirtyMarks == 2,
    "data and target lifecycle invalidation changed")

-- Ordinary aggregate reconciliation retains finite retries and returns to
-- dormancy after every viewer completes; there is no transition worker.
viewerStates = {
    {key = "first", complete = true},
    {key = "second", complete = true},
}
CM.config.viewers = {first = {}, second = {}}
presentationController.updateTimeLeft = 0
presentationController.retryPassesRemaining = 7
ProcessPresentationUpdate(nil, 0.15)
check(presentationOnUpdate == nil,
    "complete root reconciliation left the update worker installed")

print("Cooldown Manager presentation regression checks passed")
LUA
} > "$harness"

"$lua_interpreter" "$harness"
