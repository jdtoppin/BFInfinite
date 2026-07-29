#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module="$repo_root/Modules/CooldownManager/CooldownManager.lua"
code="$(mktemp)"
matches="$(mktemp)"
trap 'rm -f "$code" "$matches"' EXIT

# Maintenance comments intentionally name the APIs that caused the original
# taint. Check executable text only so those comments remain useful evidence.
sed -E 's/--.*$//' "$module" > "$code"

patterns=(
    '\bhooksecurefunc[[:space:]]*\('
    '\bBackdropTemplate\b'
    '\b(BackdropTemplateMixin|NineSlice)\b'
    '\bAF[.](ApplyDefaultBackdrop|ApplyDefaultBackdropWithColors|ApplyDefaultBackdrop_NoBackground|ApplyDefaultBackdrop_NoBorder|SetBackdrop)[[:space:]]*\('
    ':SetBackdrop[[:space:]]*\('
    '\bRegion(GetAlpha|IsShown|SetAlpha|Hide|Show)\b'
    '\b(viewer|item|itemFrame|cooldownItem|state[.]viewer):[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\('
    '\b(GetActionInfo|ActionButtonUtil[.]GetActionButtonBySpellID)[[:space:]]*\('
    '\bActionButtonSpellAlertManager[.:]'
    '\b(ActionBarButtonAssistedCombatHighlightTemplate|RotationHelper_Ants_Flipbook_2x)\b'
    ':(RefreshLayout|RefreshData|RefreshOverlayGlow|Layout|UpdateShownState|SetIsEditing|SetHideWhenInactive|SetTimerShown|SetTooltipsShown|SetBarContent|SetBarWidthScale|SetCooldownID|ClearCooldownID|SetEditModeData|ClearEditModeData|GetSpellID|GetBaseSpellID|GetCooldownInfo|GetAuraData|RefreshAuraInstance|RefreshTotemData|BreakFromFrameManager|ApplySystemAnchor|ClearFrameSnap|HighlightSystem|ClearHighlight|UpdateSystem|UpdateSystemSetting)[[:space:]]*\('
    '\b(viewer|item|itemFrame|cooldownItem|state[.]viewer|bar|icon|cooldown|name|duration)[.][A-Za-z_][A-Za-z0-9_]*[[:space:]]*='
    '\bS[.](CreateBackdrop|StyleSquareIcon)[[:space:]]*\('
    '[.](BFIBackdrop|_BFI[A-Za-z0-9_]*)[[:space:]]*='
    'itemFramePool:(Acquire|Release|ReleaseAll)[[:space:]]*\('
)

failed=false
for pattern in "${patterns[@]}"; do
    if rg -n "$pattern" "$code" > "$matches"; then
        if [[ "$failed" == false ]]; then
            echo "Cooldown Manager native-state boundary violations were found:" >&2
        fi
        cat "$matches" >&2
        failed=true
    fi
done

if [[ "$failed" == true ]]; then
    echo "Use guarded C widget presentation and BFI-owned side tables instead." >&2
    exit 1
fi
