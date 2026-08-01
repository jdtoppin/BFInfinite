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
local targetRegisteredEvents = {}
local targetObserverOnEvent
local presentationOnUpdate
local presentationUpdateSchedules = 0
local presentationController = {
    buffVisibility = {
        Update = function() end,
    },
    targetObserver = {
        RegisterUnitEvent = function(_, event, ...)
            targetRegisteredEvents[event] = table.concat({...}, ",")
        end,
        UnregisterEvent = function(_, event)
            targetRegisteredEvents[event] = nil
        end,
        SetScript = function(_, script, handler)
            if script == "OnEvent" then
                targetObserverOnEvent = handler
            end
        end,
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
local IsBlizzardEditModeActive = function() return false end
local inCombat = false
local InCombatLockdown = function() return inCombat end
local ReconcileViewer = function(state)
    return state.complete, state.geometryChanged
end
local RestoreViewer = function(state)
    return state.restored ~= false
end
local RefreshAssistedHighlightState = function() end
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
        '/^function PresentationMethods.BeginTargetTransition/,/^presentationController.buffVisibility.weakKeys/p' \
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

    cat <<'LUA'
local function check(condition, message)
    if not condition then
        error(message, 2)
    end
end

local function DispatchTargetAura()
    check(targetObserverOnEvent ~= nil,
        "target aura observer callback was not installed")
    -- The observer deliberately binds no event payload. Passing a secret
    -- sentinel here proves the transaction wake does not inspect it.
    targetObserverOnEvent(
        presentationController.targetObserver,
        "UNIT_AURA",
        SECRET
    )
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

-- Model the two form-sensitive native layout paths from pinned Retail 12.1:
-- full player/target UNIT_AURA and a count-changing
-- CooldownViewerSettings.OnDataChanged. PLAYER_TARGET_CHANGED itself does not
-- run GridLayout, so it must arm observation without creating a blank flash.
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
    "combat target event changed viewer alpha")
check(targetRegisteredEvents.UNIT_AURA == nil,
    "combat target event armed target aura observation")
check(not presentationController.targetTransition
    or not presentationController.targetTransition.active,
    "combat target event activated a transition")
inCombat = false
presentationController.combatBlocked = true
presentationOnUpdate = nil
presentationUpdateSchedules = 0
presentationDirtyMarks = 0

OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "target event created a blank viewer flash")
check(targetRegisteredEvents.UNIT_AURA == "target",
    "target transition did not arm target aura observation")
check(presentationController.combatBlocked == nil,
    "safe target transition remained stranded behind a stale combat latch")
check(presentationOnUpdate == ProcessPresentationUpdate
    and presentationUpdateSchedules >= 2
    and presentationDirtyMarks == 1,
    "target transition did not wake and invalidate presentation")

local elapsedBeforeTargetAura =
    presentationController.targetTransition.elapsed
PresentationMethods.AdvanceTargetTransition(true, false, 1 / 60)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "untriggered target watch changed viewer alpha")
check(presentationController.targetTransition.active,
    "target watch ended before a possible late aura update")

DispatchTargetAura()
check(targetRegisteredEvents.UNIT_AURA == "target",
    "target aura update disarmed transition observation")
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "target aura barrier was not curtained before reconciliation")
check(presentationController.targetTransition.viewerAlphas[transitionViewerA]
    == 0.7,
    "target aura barrier did not capture the original viewer alpha")
check(presentationController.targetTransition.elapsed
    == elapsedBeforeTargetAura + 1 / 60,
    "target aura barrier reset the hard deadline")

PresentationMethods.AdvanceTargetTransition(false, false, 1 / 60)
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "incomplete target reconciliation uncovered viewers")

-- Native RefreshLayout is synchronous in the audited build. Once the first
-- complete BFI pass has corrected the reclaimed anchors, uncover immediately
-- instead of manufacturing two extra blank rendered frames. Keep the watch
-- alive so another late full update can re-curtain.
PresentationMethods.AdvanceTargetTransition(true, true, 1 / 60)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "complete correction did not immediately restore viewer alpha")
check(presentationController.targetTransition.active,
    "correction pass closed the late-aura watch")
check(targetRegisteredEvents.UNIT_AURA == "target",
    "correction pass disarmed target aura observation")

DispatchTargetAura()
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "late target aura did not re-curtain viewers")
check(presentationController.targetTransition.viewerAlphas[transitionViewerA]
    == 0.7,
    "late target aura recaptured the temporary zero alpha")
PresentationMethods.AdvanceTargetTransition(true, false, 1 / 60)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "late target aura did not restore exact viewer alpha")

-- A repeated precursor merges into the existing watch without hiding or
-- extending its absolute deadline.
local elapsedBeforeRepeatedTarget =
    presentationController.targetTransition.elapsed
OnPresentationEvent(nil, "PLAYER_TARGET_CHANGED")
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "repeated target event curtained viewers")
check(presentationController.targetTransition.elapsed
    == elapsedBeforeRepeatedTarget,
    "repeated target event extended the transition hard deadline")

-- If combat begins after a safe out-of-combat curtain was installed, the next
-- advance must fail open immediately and restore exact alphas.
DispatchTargetAura()
inCombat = true
PresentationMethods.AdvanceTargetTransition(true, false, 1 / 60)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "entering combat did not restore exact viewer alpha")
check(presentationController.targetTransition.active == false,
    "entering combat left the transition active")
check(targetRegisteredEvents.UNIT_AURA == nil,
    "entering combat kept target aura observation armed")
inCombat = false

-- Druid form changes arm both units without immediately hiding. The native
-- data callback is the actual late barrier and may refresh in place when the
-- category count is unchanged, so a complete pass restores even with no
-- geometry delta while the player/target observer window remains active.
OnPresentationEvent(nil, "UPDATE_SHAPESHIFT_FORM")
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "druid form precursor created a blank viewer flash")
check(targetRegisteredEvents.UNIT_AURA == "player,target",
    "druid form watch did not cover player and target auras")
PresentationMethods.OnCooldownDataChanged()
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "form-driven data rebuild was not curtained")
PresentationMethods.AdvanceTargetTransition(true, false, 1 / 60)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "equal-count form rebuild did not uncover after a complete pass")
check(presentationController.targetTransition.active
    and targetRegisteredEvents.UNIT_AURA == "player,target",
    "form rebuild closed its late-aura watch")

DispatchTargetAura()
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "late form aura did not re-curtain viewers")
PresentationMethods.AdvanceTargetTransition(true, true, 1 / 60)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "late form aura correction did not restore exact alpha")

local elapsedBeforePluralForm =
    presentationController.targetTransition.elapsed
OnPresentationEvent(nil, "UPDATE_SHAPESHIFT_FORMS")
check(presentationController.targetTransition.elapsed
    == elapsedBeforePluralForm,
    "plural form event extended the hard deadline")
check(targetRegisteredEvents.UNIT_AURA == "player,target",
    "plural form event narrowed aura observation")

local timeoutPasses = 0
while presentationController.targetTransition.active and timeoutPasses < 120 do
    timeoutPasses = timeoutPasses + 1
    PresentationMethods.AdvanceTargetTransition(true, false, 1 / 60)
end
check(timeoutPasses < 120,
    "form watch fail-safe did not complete within its bound")
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "form watch fail-safe lost the original viewer alpha")
check(targetRegisteredEvents.UNIT_AURA == nil,
    "form watch fail-safe kept aura observation armed")

-- A data rebuild outside a target/form watch is still a possible synchronous
-- native relayout, but it can close completely after one successful pass.
PresentationMethods.OnCooldownDataChanged()
check(transitionViewerA.alpha == 0 and transitionViewerB.alpha == 0,
    "standalone data rebuild was not curtained")
check(targetRegisteredEvents.UNIT_AURA == nil,
    "standalone data rebuild armed an unrelated aura observer")
PresentationMethods.AdvanceTargetTransition(true, false, 1 / 60)
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "standalone data rebuild did not restore exact alpha")
check(not presentationController.targetTransition.active,
    "standalone data rebuild left a transaction active")

-- Repeated opaque aura barriers cannot reset the fixed hard deadline or leave
-- the viewer invisible indefinitely when native construction never completes.
OnPresentationEvent(nil, "UPDATE_SHAPESHIFT_FORM")
local auraChurnPasses = 0
while presentationController.targetTransition.active
    and auraChurnPasses < 120
do
    auraChurnPasses = auraChurnPasses + 1
    DispatchTargetAura()
    PresentationMethods.AdvanceTargetTransition(false, false, 1 / 60)
end
check(auraChurnPasses < 120,
    "form aura churn defeated the transition fail-safe")
check(transitionViewerA.alpha == 0.7 and transitionViewerB.alpha == 1,
    "form aura churn did not restore original viewer alpha")
check(targetRegisteredEvents.UNIT_AURA == nil,
    "form aura churn kept observation armed")

-- Update aggregation is global across all initialized viewers: one viewer's
-- incomplete construction must keep every viewer curtained. The first fully
-- complete aggregate pass restores all exact alphas together.
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
-- A target transaction is urgent: even an existing ordinary debounce and a
-- nearly exhausted construction retry budget must not delay or consume its
-- curtained reconciliation window.
presentationController.updateTimeLeft = 99
presentationController.retryPassesRemaining = 1
ProcessPresentationUpdate(nil, 1 / 60)
check(aggregateViewerA.alpha == 0.6 and aggregateViewerB.alpha == 0.9,
    "complete aggregate correction did not restore all viewers")
check(presentationController.targetTransition.active,
    "aggregate correction closed the target watch")
check(presentationController.updateTimeLeft == 0,
    "layout watch was delayed by the ordinary debounce")
check(presentationController.retryPassesRemaining == 1,
    "layout watch consumed the ordinary construction retry budget")
check(presentationOnUpdate == ProcessPresentationUpdate,
    "layout watch stopped its update worker before its deadline")

viewerStates[2].geometryChanged = false
viewerStates[1].complete = false
DispatchTargetAura()
ProcessPresentationUpdate(nil, 1 / 60)
check(aggregateViewerA.alpha == 0 and aggregateViewerB.alpha == 0,
    "incomplete aggregated pass uncovered viewers")

viewerStates[1].complete = true
ProcessPresentationUpdate(nil, 1 / 60)
check(aggregateViewerA.alpha == 0.6 and aggregateViewerB.alpha == 0.9,
    "complete aggregate retry did not restore all viewers")

-- Let the remaining watch expire through the real worker. Completion must
-- remove OnUpdate and preserve normal post-transition dormancy.
local workerPasses = 0
while presentationController.targetTransition.active and workerPasses < 120 do
    workerPasses = workerPasses + 1
    ProcessPresentationUpdate(nil, 1 / 60)
end
check(workerPasses < 120,
    "aggregate watch did not reach its bounded deadline")
check(presentationOnUpdate == nil,
    "completed aggregate watch left the update worker installed")

presentationController.updateTimeLeft = 0
presentationController.retryPassesRemaining = nil
OnPresentationEvent(nil, "UPDATE_BINDINGS")
check(not presentationController.targetTransition.active,
    "ordinary binding update started a layout watch")
ProcessPresentationUpdate(nil, 0.15)
check(presentationOnUpdate == nil,
    "ordinary complete update failed to return to dormancy")

print("Cooldown Manager presentation regression checks passed")
LUA
} > "$harness"

"$lua_interpreter" "$harness"
