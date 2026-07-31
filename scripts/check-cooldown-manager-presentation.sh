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
local FrameIsMouseMotionEnabled = function(region) return region.mouseMotion end
local FrameIsShown = function(region) return region.shown end
local FontStringIsShown = FrameIsShown
local FontStringGetAlpha = FrameGetAlpha
local CooldownGetHideCountdownNumbers = function(cooldown)
    return cooldown.hideCountdownNumbers
end
local CapturePoints = function(region) return region.points end

local presentationGeneration = 17
local CM = {config = {skin = true, assistedHighlight = false}}
local HighlightState = {proc = {Ensure = function() return true end}}
local EnsureAssistedHighlight = function() return true end
local iconSkins = setmetatable({}, {__mode = "k"})
local barSkins = setmetatable({}, {__mode = "k"})
local BFI = {media = {bar = "BFI bar"}}
local AF = {GetDefaultTexCoord = function() return 0, 1, 0, 1 end}
local GetIconMaskAndOverlay = function(iconParent)
    return iconParent.mask, iconParent.overlay
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
local FrameShow = function(region) region.shown = true end
local StatusBarGetStatusBarTexture = function(bar) return bar.fill end
local StatusBarSetStatusBarTexture = function() end
local TextureSetDrawLayer = function() end
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
LUA

    sed -n \
        '/^local function SkinIcon(/,/^ApplyFont =/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function CapturePresentationDefaults(/,/^local function RecapturePresentationDefaults(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function ApplyStaticPresentation(/,/^local function GetPresentationAlpha(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function GetOrCreateItemState(/,/^local function CurrentGeometryMatches(/p' \
        "$module" | sed '$d'
    sed -n \
        '/^local function GetLayoutBounds(/,/^local function GetHolderScaleRatio(/p' \
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
check(ApplyStaticPresentation(item, state, config, itemState),
    "completed startup presentation did not succeed on retry")
check(itemState.presentationGeneration == presentationGeneration,
    "successful retry was not marked current")
check(itemState.presentationCaptured == true,
    "successful retry did not complete native-default capture")

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

print("Cooldown Manager presentation regression checks passed")
LUA
} > "$harness"

"$lua_interpreter" "$harness"
