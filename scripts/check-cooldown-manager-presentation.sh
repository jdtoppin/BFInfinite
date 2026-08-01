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
local FrameSetAlpha = function(region, alpha) region.alpha = alpha end
local FrameGetNumPoints = function(region) return #region.points end
local FrameGetPoint = function(region, index)
    return unpack(region.points[index])
end
local FrameGetSize = function(region) return region.width, region.height end
local FrameGetScale = function(region) return region.scale end
local FrameSetSize = function(region, width, height)
    region.width = width
    region.height = height
end
local FrameSetScale = function(region, scale) region.scale = scale end
local FrameClearAllPoints = function(region) region.points = {} end
local FrameSetPoint = function(region, ...)
    region.points = {{...}}
end
local FrameIsMouseMotionEnabled = function(region) return region.mouseMotion end
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
local CapturePoints = function(region) return region.points end

local presentationGeneration = 17
local CM = {
    config = {
        enabled = true,
        skin = true,
        assistedHighlight = false,
        viewers = {},
    },
}
local HighlightState = {proc = {Ensure = function() return true end}}
local EnsureAssistedHighlight = function() return true end
local iconSkins = setmetatable({}, {__mode = "k"})
local barSkins = setmetatable({}, {__mode = "k"})
local BFI = {media = {bar = "BFI bar"}}
local AF = {GetDefaultTexCoord = function() return 0, 1, 0, 1 end}
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
local StatusBarGetStatusBarTexture = function(bar) return bar.fill end
local TextureSetDrawLayer = function(region, layer, subLevel)
    region.drawLayer = layer
    region.subLevel = subLevel
end
local PresentationMethods = {
    PositionCooldownInside = function() return true end,
    GetCooldownCountdownText = function() return nil end,
    PositionText = function() end,
    UpdateNativeChildSkinPixels = function(skin) return skin.pixelReady end,
}
local CooldownSetSwipeTexture = function() end
local CooldownSetHideCountdownNumbers = function() end
local squareCooldownSwipeTexture = "square"
local nativeCooldownSwipeTexture = "native"
local ApplyFont = function() end
local GetCountText = function() return nil end
local ApplyBarContent = function() return true end
local UpdateItemAssistedHighlight = function() end
local ceil = math.ceil
local max = math.max
local min = math.min
local sort = table.sort
local itemStates = setmetatable({}, {__mode = "k"})
local fallbackOrder = 0
local GetActiveItems = function(viewer) return viewer.items end
local viewerStates = {}
local registeredEvents = {}
local presentationController = {
    RegisterUnitEvent = function(_, event, unit)
        registeredEvents[event] = unit
    end,
    UnregisterEvent = function(_, event)
        registeredEvents[event] = nil
    end,
    SetScript = function() end,
}
local presentationPollStarts = 0
local presentationDirtyMarks = 0
local presentationUpdateTimeLeft = 0
local InitializeViewers = function() end
local IsBlizzardEditModeActive = function() return false end
local inCombat = false
local InCombatLockdown = function() return inCombat end
local ReconcileViewer = function(state)
    return state.complete, state.geometryChanged
end
local RestoreViewer = function(state)
    return state.restored ~= false
end
local StartPresentationPolling = function()
    presentationPollStarts = presentationPollStarts + 1
end
local MarkPresentationDirty = function()
    presentationDirtyMarks = presentationDirtyMarks + 1
end
local hotkeyRefreshEvents = {}
local hotkeyGeneration = 1
LUA

    sed -n \
        '/^local function SkinIcon(/,/^ApplyFont =/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function CaptureNativeGeometry(/,/^local function CaptureShown(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function CapturePresentationDefaults(/,/^local function RecapturePresentationDefaults(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^function PresentationMethods.RestoreTrackedBarPip/,/^local function RestoreItemPresentation(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function ApplyStaticPresentation(/,/^local function GetPresentationAlpha(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function GetOrCreateItemState(/,/^local function CurrentGeometryMatches(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function CurrentGeometryMatches(/,/^local function RestoreMissingItems(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function GetLayoutBounds(/,/^local function GetHolderScaleRatio(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^function PresentationMethods.BeginTargetTransition/,/^function PresentationMethods.NoteTargetTransitionBarrier/p' \
        "$module" | sed '$d'
    sed -n \
        '/^function PresentationMethods.NoteTargetTransitionBarrier/,/^function PresentationMethods.AdvanceTargetTransition/p' \
        "$module" | sed '$d'
    sed -n \
        '/^function PresentationMethods.AdvanceTargetTransition/,/^local function PollPresentation(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function PollPresentation(/,/^local function StartPresentationPolling(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function OnPresentationEvent(/,/^for event in next, hotkeyRefreshEvents/p' \
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
local iconFrame = {shown = true, alpha = 1, Icon = {}}
local cooldown = {hideCountdownNumbers = false}
local item = {
    alpha = 1,
    mouseMotion = true,
    Cooldown = cooldown,
    Icon = iconFrame,
}
local state = {definition = {isBar = true}}
local config = {
    showTimer = true,
    cooldownText = {},
    countText = {},
    barText = {},
    durationText = {},
}
local itemState = {}

check(not ApplyStaticPresentation(item, state, config, itemState),
    "incomplete startup capture unexpectedly succeeded")
check(itemState.presentationGeneration == nil,
    "incomplete startup capture was marked current")
check(itemState.presentationCaptured == nil,
    "incomplete startup capture was marked complete")
check(itemState.nativeAlpha == 1,
    "available startup defaults were not captured")

item.alpha = 0.25
item.Bar = {
    points = {{"LEFT"}},
    Name = {shown = true, alpha = 1},
    Duration = {shown = true, alpha = 1},
    fill = {},
}
check(not ApplyStaticPresentation(item, state, config, itemState),
    "missing icon regions unexpectedly marked presentation complete")
check(itemState.presentationGeneration == nil,
    "missing icon regions were not scheduled for retry")
check(itemState.nativeAlpha == 1,
    "retry overwrote an already-captured native default")

iconFrame.mask = {}
iconFrame.overlay = {}
check(not ApplyStaticPresentation(item, state, config, itemState),
    "missing bar background unexpectedly marked presentation complete")
check(itemState.presentationGeneration == nil,
    "missing bar background was not scheduled for retry")

item.Bar.BarBG = {}
check(not ApplyStaticPresentation(item, state, config, itemState),
    "missing tracked-bar pip unexpectedly marked presentation complete")
check(itemState.presentationGeneration == nil,
    "missing tracked-bar pip was not scheduled for retry")

item.Bar.Pip = {shown = true, alpha = 1}
local nativeTrackedBarFill = item.Bar.fill
item.Bar.fill.textureReady = false
check(not ApplyStaticPresentation(item, state, config, itemState),
    "failed tracked-bar fill swap unexpectedly marked presentation complete")
check(itemState.presentationGeneration == nil,
    "failed tracked-bar fill swap was not scheduled for retry")
check(item.Bar.BarBG.hidden ~= true,
    "failed tracked-bar fill swap hid the native background")

item.Bar.fill.textureReady = true
check(ApplyStaticPresentation(item, state, config, itemState),
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

-- Simulate event ordering directly: BFI has already applied its holder
-- anchor, PLAYER_TARGET_CHANGED wakes reconciliation, and Blizzard then
-- rewrites the item to its native container anchor before BFI's next pass.
-- The same reconciliation must recognize that drift and restore the holder
-- anchor without relying on a native mixin hook.
local holder = {}
local nativeContainer = {}
local desired = {
    x = -21,
    y = 0,
    width = 40,
    height = 40,
    scale = 0.8,
}
local geometryItem = {
    width = desired.width,
    height = desired.height,
    scale = desired.scale,
    points = {{"CENTER", holder, "CENTER", desired.x, desired.y}},
}
local geometryState = {
    applied = true,
    expected = desired,
}
local geometryEntry = {
    item = geometryItem,
    itemState = geometryState,
}
local geometryViewerState = {holder = holder}

geometryItem.points = {{"TOPLEFT", nativeContainer, "TOPLEFT", 8, -8}}
check(PrepareItemGeometry(
    geometryEntry,
    geometryViewerState,
    desired
), "native target-refresh anchor reset could not be reconciled")
check(geometryEntry.needsGeometry == true,
    "native target-refresh anchor reset was not detected")
check(geometryState.applied == nil and geometryState.expected == nil,
    "stale BFI geometry state survived the native anchor reset")
check(geometryState.nativePoints[1][2] == nativeContainer,
    "native anchor reset was not retained for reversible restore")

ApplyItemGeometry(geometryEntry, geometryViewerState)
check(CurrentGeometryMatches(geometryItem, holder, desired) == true,
    "BFI holder anchor was not restored in the reconciliation pass")
check(geometryState.applied == true and geometryState.expected == desired,
    "restored BFI geometry state was not recorded")

local stableEntry = {item = geometryItem, itemState = geometryState}
check(PrepareItemGeometry(stableEntry, geometryViewerState, desired),
    "stable holder geometry could not be verified")
check(stableEntry.needsGeometry == false,
    "stable holder geometry was needlessly reapplied")

-- If a geometry aspect becomes secret, the pass must stop without clearing
-- the last known BFI state or attempting a write.
geometryItem.points = {{"CENTER", holder, "CENTER", SECRET, desired.y}}
local guardedEntry = {item = geometryItem, itemState = geometryState}
check(not PrepareItemGeometry(guardedEntry, geometryViewerState, desired),
    "secret target-refresh geometry did not fail closed")
check(geometryState.applied == true and geometryState.expected == desired,
    "secret geometry invalidated the last known BFI state")

-- Model the render-order race seen on 12.1. BFI receives the target event and
-- reconciles once before Blizzard's later target-aura refresh rewrites native
-- anchors. The viewer curtain must be in place before that rewrite, an early
-- apparently stable pass must not uncover it, the correction pass must reset
-- stability, and only two subsequent stable passes may restore native alpha.
local transitionViewerA = {alpha = 0.7}
local transitionViewerB = {alpha = 1}
viewerStates = {
    {viewer = transitionViewerA},
    {viewer = transitionViewerB},
}

-- Entering a target transition in combat must fail open. Do not risk a
-- protected reconciliation leaving the Cooldown Manager invisible.
inCombat = true
OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "combat target event curtained viewers")
check(registeredEvents.UNIT_AURA == nil,
    "combat target event armed target aura observation")
check(not presentationController.targetTransition
    or not presentationController.targetTransition.active,
    "combat target event activated a transition")
inCombat = false
presentationPollStarts = 0
presentationDirtyMarks = 0

OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "target event did not curtain viewers before native refresh")
check(registeredEvents.UNIT_AURA == "target",
    "target transition did not arm target aura observation")
check(presentationPollStarts == 1 and presentationDirtyMarks == 1,
    "target transition did not wake and invalidate presentation")

PresentationMethods.AdvanceTargetTransition(true, false)
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "stable pre-barrier pass uncovered the target transition")

OnPresentationEvent(nil, "UNIT_AURA")
check(registeredEvents.UNIT_AURA == "target",
    "incremental target aura update disarmed transition observation")
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "incremental target aura update uncovered viewers before reconciliation")

PresentationMethods.AdvanceTargetTransition(true, false)
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "stable pass after incremental target aura update uncovered viewers")
check(presentationController.targetTransition.stablePasses == 0,
    "incremental target aura update was treated as the layout barrier")

-- The payload is opaque, so only the later geometry rewrite proves that the
-- native layout transition has happened. Keep observing target auras until
-- the entire transition completes.
OnPresentationEvent(nil, "UNIT_AURA")
check(registeredEvents.UNIT_AURA == "target",
    "target aura observation stopped before native geometry rewrite")

-- Blizzard rewrites anchors after the early BFI pass. The correction itself
-- does not count as a stable pass.
PresentationMethods.AdvanceTargetTransition(true, true)
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "geometry correction uncovered the target transition")
check(presentationController.targetTransition.stablePasses == 0,
    "geometry correction did not reset transition stability")

PresentationMethods.AdvanceTargetTransition(true, false)
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "first post-correction stable pass uncovered viewers")
check(presentationController.targetTransition.stablePasses == 1,
    "first post-correction stable pass was not recorded")

PresentationMethods.AdvanceTargetTransition(true, false)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "second post-correction stable pass did not restore viewer alpha")
check(presentationController.targetTransition.active == false,
    "completed target transition remained active")
check(registeredEvents.UNIT_AURA == nil,
    "completed target transition kept target aura observation armed")

-- If combat begins after a safe out-of-combat curtain was installed, the next
-- transition advance must fail open immediately and restore exact alphas.
OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "out-of-combat transition did not curtain before combat fixture")
inCombat = true
PresentationMethods.AdvanceTargetTransition(true, false, 1 / 60)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "entering combat did not restore exact viewer alpha")
check(presentationController.targetTransition.active == false,
    "entering combat left the transition active")
check(registeredEvents.UNIT_AURA == nil,
    "entering combat kept target aura observation armed")
inCombat = false

-- A native geometry rewrite is itself the authoritative transition proof. It
-- can be observed on the target-event pass before any target UNIT_AURA, so it
-- must reset stability and allow two following clean passes without waiting
-- for the timeout fallback.
OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
PresentationMethods.AdvanceTargetTransition(true, true)
check(presentationController.targetTransition.geometryCorrected == true,
    "pre-aura geometry correction was ignored")
check(presentationController.targetTransition.stablePasses == 0,
    "pre-aura geometry correction counted as a stable pass")
PresentationMethods.AdvanceTargetTransition(true, false)
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "first stable pass after pre-aura correction uncovered viewers")
PresentationMethods.AdvanceTargetTransition(true, false)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "pre-aura geometry correction did not complete after two stable passes")

-- A failed pass is not stable and must leave the curtain closed.
OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
PresentationMethods.NoteTargetTransitionBarrier()
PresentationMethods.AdvanceTargetTransition(true, false)
PresentationMethods.AdvanceTargetTransition(false, false)
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "failed reconciliation uncovered the target transition")
check(presentationController.targetTransition.stablePasses == 0,
    "failed reconciliation did not reset transition stability")

-- A second target change while the curtain is already closed must not capture
-- zero as the new native alpha. If reconciliation never succeeds (combat or a
-- target with no relevant full aura update), the bounded fail-safe must still
-- restore the original alpha and disarm observation.
local elapsedBeforeRepeatedTarget =
    presentationController.targetTransition.elapsed
OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "repeated target event unexpectedly opened the curtain")
check(presentationController.targetTransition.elapsed
    == elapsedBeforeRepeatedTarget,
    "repeated target event extended the transition hard deadline")
local timeoutPasses = 0
while presentationController.targetTransition.active and timeoutPasses < 120 do
    timeoutPasses = timeoutPasses + 1
    PresentationMethods.AdvanceTargetTransition(false, false)
end
check(timeoutPasses < 120,
    "target transition fail-safe did not complete within its bound")
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "target transition fail-safe lost the original viewer alpha")
check(registeredEvents.UNIT_AURA == nil,
    "target transition fail-safe kept target aura observation armed")

-- Incremental target aura churn may continuously reset stability, but it must
-- not reset the elapsed fail-safe and leave the Cooldown Manager invisible.
OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
local auraChurnPasses = 0
while presentationController.targetTransition.active
    and auraChurnPasses < 120
do
    auraChurnPasses = auraChurnPasses + 1
    OnPresentationEvent(nil, "UNIT_AURA")
    PresentationMethods.AdvanceTargetTransition(false, false, 1 / 60)
end
check(auraChurnPasses < 120,
    "incremental target aura churn defeated the transition fail-safe")
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "aura-churn fail-safe did not restore original viewer alpha")
check(registeredEvents.UNIT_AURA == nil,
    "aura-churn fail-safe kept target aura observation armed")

-- Poll aggregation is global across all initialized viewers: one viewer's
-- geometry rewrite must reset the shared transition, and every viewer must be
-- complete on each of the two following stable passes. A clean viewer cannot
-- mask another viewer's correction or failure.
local aggregateViewerA = {alpha = 0.6}
local aggregateViewerB = {alpha = 0.9}
viewerStates = {
    {
        key = "first",
        viewer = aggregateViewerA,
        complete = true,
        geometryChanged = false,
    },
    {
        key = "second",
        viewer = aggregateViewerB,
        complete = true,
        geometryChanged = true,
    },
}
CM.config.viewers = {first = {}, second = {}}
OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
PresentationMethods.NoteTargetTransitionBarrier()
PollPresentation(nil, 1 / 60)
check(presentationController.targetTransition.geometryCorrected == true,
    "one viewer's geometry correction was lost during aggregation")
check(presentationController.targetTransition.stablePasses == 0,
    "aggregated correction pass counted as stable")
check(aggregateViewerA.alpha == 0 and aggregateViewerB.alpha == 0,
    "aggregated correction uncovered a viewer")

viewerStates[2].geometryChanged = false
PollPresentation(nil, 1 / 60)
check(presentationController.targetTransition.stablePasses == 1,
    "first aggregated stable pass was not recorded")
viewerStates[1].complete = false
PollPresentation(nil, 1 / 60)
check(presentationController.targetTransition.stablePasses == 0,
    "one incomplete viewer was masked by a complete viewer")
check(aggregateViewerA.alpha == 0 and aggregateViewerB.alpha == 0,
    "incomplete aggregated pass uncovered viewers")

viewerStates[1].complete = true
PollPresentation(nil, 1 / 60)
check(presentationController.targetTransition.stablePasses == 1,
    "aggregated stability did not restart after failure")
PollPresentation(nil, 1 / 60)
check(aggregateViewerA.alpha == 0.6 and aggregateViewerB.alpha == 0.9,
    "two aggregated stable passes did not restore all viewers")
check(presentationController.targetTransition.active == false,
    "aggregated transition remained active after completion")

print("Cooldown Manager presentation regression checks passed")
LUA
} > "$harness"

"$lua_interpreter" "$harness"
