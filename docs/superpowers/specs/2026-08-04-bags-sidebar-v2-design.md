# Bags Sidebar v2 — native icons, manual collapse, flush layout

Date: 2026-08-04
Repos: BFInfinite (`codex/bags-item-level`, PR #126) + AbstractFramework (`codex/bag-sidebar-foundation`, PR #34)
Status: approved by owner (this conversation), pending implementation

## Context

In-game QA of the sidebar (built on the shared `AF.CreateSidebarRail`/`AF.CreateTreeList` widget) surfaced four owner decisions:

1. The Tabler equipment-slot glyphs don't fit the game's look (motorcycle-style helmet; unreadable legs icon), and tradeskill/recipe subtype dropdowns never got icons at all.
2. The hover auto-hide behavior should be removed entirely — the sidebar is manually toggled.
3. The collapsed icon rail must show expand/collapse chevrons next to parent categories.
4. The sidebar should sit flush against the window edge instead of inset.

## 1. Native icons with a unifying tint

### Widget (AF `Widgets/TreeList.lua`)

The tree-list node `icon` field accepts three shapes:

- `string` — adaptive icon name (existing behavior, `AF.SetAdaptiveIcon`)
- `{ atlas = <atlasName> }` — rendered via `SetAtlas`
- `{ texture = <fileID or path> }` — rendered via `SetTexture`

New list option `textureTint = {r, g, b}`: every `{atlas}`/`{texture}` icon renders `SetDesaturated(true)` + `SetVertexColor(r, g, b)`. Adaptive-glyph icons are untouched (they already follow the widget tone). No per-node opt-out until a real need appears.

### BFI mappings (`Modules/Bags/Bags.lua`)

- **Equipment slots (22)**: `categoryIconByEquipLoc` values become `{ texture = ... }` using the paper-doll empty-slot textures resolved at load via `GetInventorySlotInfo("<SlotName>")` (the same icons the character pane shows). Requires an `INVTYPE_* → slot name` table (aliased slots resolve post-alias, e.g. `INVTYPE_ROBE` → ChestSlot). The API contract (name, return values, Retail 12.x availability) must be verified against the pinned client artifacts per CONTRIBUTING.md before use, and recorded in the evidence comment.
- **Trade Goods / Recipe subtypes**: new `categoryIconBySubclass` entries for `ITEM_CLASS.Tradegoods` and `ITEM_CLASS.Recipe` mapping subclasses to `{ atlas = ... }` profession icons (Blacksmithing, Tailoring, Alchemy, …). Every atlas name must be verified against the pinned artifacts; any subtype without a verified, sensible native fit stays unmapped and inherits the parent icon (existing fallback chain — no guesses).
- **Consumable subtypes**: replace the five Tabler icons with `{ texture = ... }` representative native item icons (potion, flask/phial, food, bandage, elixir). Icon art choices are eyeballed in-game (art selection is not an API claim); the file references are runtime-only — no Blizzard art is ever copied into either repo.
- **Parent categories go native too** (owner decision: the rail is one column — mixing icon styles there is jarring). Every parent row with a verifiable native equivalent switches to `{atlas}`/`{texture}` art: Equipment, Consumables, Trade Goods, Recipes, Quest, Housing, Reagent, Backpack. Each mapping follows the same evidence rule as the subtypes: verified against the pinned artifacts or left on its current glyph — no guesses.
- **Abstract rows keep Tabler glyphs** — All, Individual Bags, Empty, Misc, and the Categories heading have no native equivalent. They render in the same tone the `textureTint` targets, so the column stays cohesive.
- BFI passes `textureTint` matched to the tone its Tabler glyphs render at in the rail.
- **AF asset removal**: after the mappings land, every `Bag_*` Tabler asset no longer referenced by BFI is removed from the generator `ICONS` table and `Media/Icons/` (SVG+TGA), with test assertions updated. That definitely covers the 22 `Bag_Slot_*` and 5 consumable icons added earlier on this unreleased branch, plus whichever parent glyphs the native swap orphans. `Bag_Misc` (fallback) and the abstract-row glyphs stay.

### QA gate

"Can you tell potion from flask from food, and head from legs, at 16px in the collapsed rail." If a specific icon reads badly in-game, swap that one icon — not the approach.

## 2. Manual collapse replaces auto-hide

### Widget (AF)

Remove all hover machinery from `AF.CreateSidebarRail`: pointer enter/leave debouncing, hover expand/collapse, and the rail width animation. Replacement API:

- `SetCollapsed(collapsed, silent)` — instant width swap (expandedWidth ↔ collapsedWidth) + `treeList:SetCompact()`
- `GetCollapsed()`, `ToggleCollapsed()`, `SetOnCollapsedChanged(fn)`
- `SetShown`, `GetDesiredWidth`, `GetContentInset`, `SetOnPresentationWidthChanged` remain; presentation width now always equals the current mode's width (reserved == presented).

The nested-row expand/collapse animation inside the tree list is kept. The expansion-persistence contract is untouched: `expandedById` survives collapse/expand of the rail.

### BFI

- Config key `sidebarAutoHide` migrates to `sidebarCollapsed` in `Modules/Bags/Defaults.lua` `NormalizeConfig` (old `true` → `true`: an auto-hide user lands collapsed).
- The existing bag-header toggle button drives `ToggleCollapsed`; glyphs/tooltip update to expand/collapse wording. `Options/Bags.lua` checkbox re-labels accordingly (enUS + zhCN locale keys).
- `B.Sidebar.*` renames: `SetAutoHide/GetAutoHide/ToggleAutoHide/SetOnAutoHideChanged` → `SetCollapsed/GetCollapsed/ToggleCollapsed/SetOnCollapsedChanged`. All Bags.lua call sites update; no aliases kept (both branches are unreleased).

## 3. Chevrons in the collapsed rail

Compact parent rows render a small chevron (existing `ArrowDown1`/`ArrowRight1` glyphs) beside the 16px icon within the 40px rail. Chevron click toggles the nest; icon/row click selects — the same split as the expanded view. Child rows in compact mode remain icon-only (indented or slightly smaller per current compact styling).

## 4. Flush layout

The rail anchors flush to the styled shell's left/top/bottom inner border at full height (edge inset removed). The 8px gap between rail and item grid stays. Change lives in BFI (`Bags.lua` layout/`GetContentInset` usage and shell sizing) — the widget needs no change beyond what its options already express.

## Testing

- AF `tests/tree_list_test.lua`: drop hover-cycle tests; add manual `SetCollapsed` cycle (persistence assertions retained), compact-chevron toggle behavior, and icon-shape dispatch (string vs atlas vs texture, tint applied to non-glyph only).
- BFI `tests/bags_sidebar_controller_test.lua`: renamed API surface, migration pass-through.
- BFI `tests/bags_view_modes_test.lua`: `sidebarCollapsed` migration contract (`sidebarAutoHide` consumed, not left behind), icon-table shape contracts, evidence-comment presence for `GetInventorySlotInfo` and atlas names.
- Both repos: full `./scripts/verify.sh` green.

## Out of scope

- Recolor/redesign of the remaining abstract-row Tabler glyphs.
- Any change to baseline-height layout, item-level display, or the expansion-persistence contract.
- Backfilling BFI changelog entries for r3/r4-alpha.

## In-game QA checklist (post-implementation)

1. Toggle collapses/expands instantly via header button; state persists per profile and across `/reload`.
2. Collapsed rail: chevrons visible and clickable on parents; expansion persists across collapse/expand.
3. Icon legibility pass at 16px (the QA gate above), including the desaturated-tint treatment cohesion.
4. Flush rail alignment vs the styled shell border at multiple UI scales (pixel-perfect check).
5. 12.0.x client or enum-less environment: fallback chain still sane.
