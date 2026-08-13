# Bags Sidebar v3 — plated full-color icons, complete coverage

Date: 2026-08-05
Repos: BFInfinite (`codex/bags-item-level`, PR #126) + AbstractFramework (`codex/bag-sidebar-foundation`, PR #34)
Status: approved by owner (in-game QA feedback round on v2)

## Context

In-game QA of sidebar v2 found: the desaturate+tint treatment renders icons too dark to read; the circular parent-category atlases are too small at 1440p; Trade Goods subtypes all share one icon and Recipe subtypes are all books; icon backgrounds are visually inconsistent (circles, rounded stock-icon corners) with BFI's squared AF design. Owner decisions:

1. Full-color icons on squared AF plates (bag-item look), tint treatment deleted.
2. 20px icon plates, 28px rows (up from 16px/26px) — legible at 1440p.
3. Policy exemption granted: undocumented subclass keys (Trade Goods, Housing children) may be keyed by runtime-observed numeric subclass IDs with an explicit exemption maintenance comment. Recipes get proper per-profession icons on their verified enum keys.
4. Plates use AF's lightweight one-fill/four-edge border path (like the bag icons), never NineSlice/BackdropTemplate — better performance.

## 1. Plated icon presentation (AF `Widgets/TreeList.lua`)

- Every row icon renders inside a squared plate: one fill + four one-pixel edges via the existing lightweight backdrop primitives (`AF.ApplyLightweightBackdropWithColors` family). No NineSlice, no `BackdropTemplate`.
- `{texture=...}` icons get the standard WoW icon crop (reuse AF's existing crop helper if one exists; otherwise texcoords 0.08–0.92) so stock rounded corners vanish into the square. `{atlas=...}` icons are never texcoord-cropped (atlas UVs own the region). Adaptive glyph icons render on plates too, uncropped, keeping their tintable-glyph look.
- The `textureTint` option and its desaturate/vertex-color treatment are deleted (unreleased branch; no compat shim). Pooled-row reuse must still reset texcoords when leaving an atlas shape.
- Defaults change: `iconSize` 16 → 20 (plate size; icon fills the plate inside its 1px edges), `rowHeight` 26 → 28. Headings unchanged.
- Compact (40px) rail geometry: 4px left inset + 20px plate + right-aligned chevron shrunk to fit (target ~14px with a 2px right inset; exact arithmetic must total ≤ 40). Expanded-mode chevron unchanged.
- Plate colors come from widget options with AF-default border/fill values consistent with AF's lightweight backdrop defaults; BFI passes nothing unless it needs an override.

## 2. BFI icon remap (`Modules/Bags/Bags.lua`)

- Parent categories drop the `bags-icon-*` circular atlases; every parent (Equipment, Consumables, Trade Goods, Reagents, Quest, Recipes, Housing) gets a full-color `{texture}` item icon (art choice, in-game QA gated).
- Equipment children keep their paper-doll slot textures (already square-friendly, game's own slot art).
- **Trade Goods subtypes — policy exemption**: keyed by runtime-observed numeric subclass IDs. The mapping table carries a maintenance comment stating: the exemption, what was observed (subclassID → localized name pairs), on which live build, and that both pinned artifacts document no Trade Goods subclass enum (verified twice in v2). Icons: cloth bolt, leather, ore/ingot, herb, elemental, enchanting, gem, ink/pigment, parts/cog, cooking, reagent pouch (art choices).
- **Recipe subtypes**: per-profession item icons on the already-verified `Enum.ItemRecipeSubclass` keys (replace the all-books set).
- **Housing children**: if the sidebar renders housing subcategories with undocumented keys, same exemption treatment; otherwise parent icon suffices.
- `Sidebar.lua` stops passing `textureTint`.
- Unmappable rows still fall back through `child.icon or group.icon` → widget `fallbackIcon`.

## 3. Testing

- AF `tests/tree_list_test.lua`: plate construction (fill + 4 edges recorded, no NineSlice/Backdrop API calls), crop applied to texture icons and never to atlas icons, glyph rows plated, tint option gone (source assertion), 20/28 defaults, compact 40px geometry arithmetic, pooled-reuse texcoord reset still correct.
- BFI `tests/bags_view_modes_test.lua`: updated mapping-table contracts, exemption-comment presence for Trade Goods, no `textureTint` in Sidebar.lua, no `bags-icon-` atlas references remain in the sidebar model.
- Full `./scripts/verify.sh` green in both repos.

## Out of scope

- Any change to collapse behavior, chevron click semantics, expansion persistence, flush layout, baseline layout, item-level display.
- Redesign of the 4 abstract Tabler glyphs themselves (they just gain plates).

## In-game QA checklist (post-implementation)

1. Legibility at 1440p: parents and children readable, full color, no black mud; plate edges crisp at pixel-perfect scales.
2. One visual system: plates identical across glyph/texture rows; no circles, no rounded corners, no NineSlice artifacts.
3. Trade Goods / Recipe / Housing rows all distinct and sensible.
4. Compact rail: 20px plates + smaller chevron fit cleanly in 40px; hit targets still comfortable.
5. Row height 28 doesn't clip labels or crowd headings; scrollbar behavior unchanged.
