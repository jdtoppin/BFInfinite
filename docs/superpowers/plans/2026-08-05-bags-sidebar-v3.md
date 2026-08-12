# Bags Sidebar v3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full-color icons on squared AF 4-edge plates at 20px/28px sizing, with complete Trade Goods/Recipe/Housing icon coverage via an owner-granted policy exemption.

**Architecture:** AF's TreeList replaces the tint treatment with a plated-icon presentation (lightweight one-fill/four-edge backdrop, icon crop for textures) and grows its default sizes; BFI remaps parents and exempted subtypes to full-color item icons and drops the tint option.

**Tech Stack:** WoW addon Lua 5.1, AF widget framework, luacheck + luajit tests.

**Spec:** `docs/superpowers/specs/2026-08-05-bags-sidebar-v3-design.md` (governs).

## Global Constraints

- Repos/branches: AF = `/Users/josiahtoppin/Documents/Claude BFI - AF/AbstractFramework` on `codex/bag-sidebar-foundation`; BFI = `/Users/josiahtoppin/Documents/Claude BFI - AF/BFInfinite` on `codex/bags-item-level`. Never switch branches; both unreleased (breaking changes fine, no compat shims).
- Plates: lightweight one-fill/four-edge only (`AF.ApplyLightweightBackdropWithColors` family in `Widgets/Base.lua`). Never NineSlice, never `BackdropTemplate` — and the tests must assert their absence.
- Policy exemption (owner-granted, spec §2): Trade Goods (and Housing, if needed) subtype keys may be runtime-observed numeric subclass IDs, with an explicit exemption maintenance comment (what observed, which live build, why artifacts can't verify — both pinned commits document no such enum, verified twice in v2). All OTHER API/enum claims remain under the standard evidence policy (pinned commits `4383ced30106d51b27e3e86d1987f1552f0d259d` / `d3915c78aba77a7a9be76acbfa35c674bbb6abe9`).
- Icon art paths are art choices (in-game QA gated), recorded in maintenance comments; no Blizzard art copied into either repo.
- No `SetScript("OnUpdate")`, no `pcall`/`xpcall`, no `issecretvalue`, `Libs/` untouched; Lua 5.1 budgets (BFI `Bags.lua` main chunk at the 200-top-level-local ceiling — nest on existing host locals).
- Lint: `./scripts/lint.sh <files>`; BFI needs `LUA_COMPILER=$(command -v luac5.4 || echo /opt/homebrew/Cellar/lua@5.4/5.4.8/bin/luac5.4)`. Tests: `./scripts/run-tests.sh` (luajit). `rg` may be absent in subagent shells — compensate with `git diff | grep -E 'issecretvalue|pcall'` before claiming policy-clean.
- Untouched invariants: collapse API + semantics, chevron click semantics, expansion persistence (`expandedById`), flush layout anchors, baseline layout, item-level display.
- BFI changelog only via `Options/ChangelogData.lua` + generator; AF `CHANGELOG.md` hand-edited.
- Commits: imperative subject + trailing `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## File Structure

- AF `Widgets/TreeList.lua` — plate presentation + crop + tint removal (Task 1); size/geometry defaults (Task 2)
- AF `tests/tree_list_test.lua` — per task
- BFI `Modules/Bags/Bags.lua` + `Modules/Bags/Sidebar.lua` — icon remap + exemption + tint drop (Task 3)
- BFI `tests/bags_view_modes_test.lua` — Task 3
- Changelogs both repos (Task 4)

---

### Task 1: AF plated icons, crop, tint removal

**Files:**
- Modify: `AbstractFramework/Widgets/TreeList.lua` (row construction + `ApplyNodeIcon`)
- Test: `AbstractFramework/tests/tree_list_test.lua`

**Interfaces:**
- Consumes: `AF.ApplyLightweightBackdropWithColors` (read `Widgets/Base.lua` for the real signature and default colors first); existing `ApplyNodeIcon` three-shape dispatch.
- Produces: each row's icon region sits inside a plate frame (`row.iconPlate`) carrying the lightweight backdrop; `ApplyNodeIcon` crops texture-shape icons (never atlas, never glyph) and no longer supports `textureTint` (option deleted). New list option `iconPlateColors = { border = {r,g,b,a}, fill = {r,g,b,a} }` defaulting to AF's lightweight-backdrop defaults. Task 3 relies on: option name `iconPlateColors`, tint removal, crop-on-texture behavior.

- [ ] **Step 1: Read** `Widgets/Base.lua`'s lightweight backdrop functions (signature, what regions they create, default colors) and check for an existing AF icon-crop helper (`grep -rn "TexCoord" Media/ Widgets/ | grep -i crop` — reuse if found, else use 0.08–0.92).
- [ ] **Step 2: Write failing tests** — extend the CreateFrame stub as needed so plate creation is observable (record backdrop calls; assert the plate exists per row, one per pooled row, reused not recreated). Assert: (a) texture-shape rows get `SetTexCoord(0.08, 0.92, 0.08, 0.92)` (or the helper's values); (b) atlas rows get `SetAtlas` and NO crop texcoords; (c) glyph rows get the adaptive-icon path, plated, uncropped, with the reset-to-full texcoords on pooled reuse after an atlas/texture row preserved; (d) source assertions: `textureTint` absent, `SetDesaturated` absent, `NineSlice` and `BackdropTemplate` absent from TreeList.lua.
- [ ] **Step 3: Run** `luajit tests/tree_list_test.lua` — FAIL.
- [ ] **Step 4: Implement** — create the plate once per pooled row in the row factory (frame or textures parented under the row, sized to `iconSize`, backdrop applied with `iconPlateColors`); parent the icon region inside it with 1px insets; rewrite `ApplyNodeIcon`: delete the tint branch entirely, texture branch = `SetTexture` + crop texcoords, atlas branch = `SetAtlas` only, glyph branch = adaptive icon + full texcoords (pooled-reuse reset). Delete the `textureTint` option plumbing.
- [ ] **Step 5: Run** focused + `./scripts/run-tests.sh` — PASS. Note: this may break assertions in the existing icon-dispatch test blocks that asserted tint behavior — rewrite those blocks to the new contract (that rewrite belongs in Step 2).
- [ ] **Step 6: Lint + commit** — `./scripts/lint.sh Widgets/TreeList.lua`; commit `Render tree list icons on lightweight square plates`.

### Task 2: AF sizing and compact geometry

**Files:**
- Modify: `AbstractFramework/Widgets/TreeList.lua` (default constants + compact branch)
- Test: `AbstractFramework/tests/tree_list_test.lua`

**Interfaces:**
- Consumes: Task 1's plate.
- Produces: defaults `iconSize = 20`, `rowHeight = 28` (headings unchanged); compact-mode chevron rendered at a reduced size (target 14px) so `leftInset(4) + plate(20) + gap + chevron + rightInset(2) ≤ collapsedWidth(40)` — pick the exact gap so the total is exactly 40 and state the arithmetic in a comment. Expanded-mode chevron size unchanged. BFI passes no size overrides (Task 3 removes none — its options already omit sizes? read `Modules/Bags/Sidebar.lua` OPTIONS: it currently passes rowHeight/iconSize explicitly — Task 3 must update those values to 20/28 or drop them to inherit defaults; coordinate via this Produces block: **Task 3 drops explicit `iconSize`/`rowHeight` from BFI's options so AF defaults govern**).

- [ ] **Step 1: Write failing tests** — defaults assertions (20/28); compact geometry: parent row in compact mode has plate at left inset 4 spanning 20px, chevron sized 14 anchored right with the computed offsets, total ≤ 40 (assert the recorded sizes/anchors); expanded chevron unchanged (existing assertions keep passing).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** — change `DEFAULT_*` constants; add a compact chevron size constant + apply in the compact branch (both anchor and size), restore full size in expanded branch on the same pooled row.
- [ ] **Step 4: Run** focused + full suite — PASS.
- [ ] **Step 5: Lint + commit** — `Grow tree list icons to plated 20px in 28px rows`.

### Task 3: BFI icon remap, exemption, tint drop

**Files:**
- Modify: `BFInfinite/Modules/Bags/Bags.lua` (parent + subtype icon tables, exemption comment), `BFInfinite/Modules/Bags/Sidebar.lua` (OPTIONS: remove `textureTint`, drop explicit `iconSize`/`rowHeight` per Task 2)
- Test: `BFInfinite/tests/bags_view_modes_test.lua`

**Interfaces:**
- Consumes: Task 1's tint removal + crop-on-texture; Task 2's defaults.
- Produces: final icon tables; the Trade Goods exemption comment pattern (Task 4's changelog references it).

- [ ] **Step 1: Choose art + build tables** (all `{texture = "Interface\\Icons\\..."}` art choices, recorded in maintenance comments):
  - Parents (replace the `bags-icon-*` atlas entries): Equipment → an armor/chest icon; Consumables → potion satchel/bottle; Trade Goods → tradegoods bundle; Reagents → reagent pouch; Quest → exclamation/quest scroll; Recipes → recipe book; Housing → house/hearthstone (keep `INV_Misc_GarrisonHearthstone` if it reads well). Pick well-known long-stable `Interface\Icons\` paths.
  - Trade Goods subtypes — **exemption table** keyed by numeric subclass IDs, nested on the existing host (`categoryOrderByClass.categoryIconBySubclass[ITEM_CLASS.Tradegoods]`). The maintenance comment MUST state: owner-granted exemption to the artifact-evidence policy; both pinned commits document no Trade Goods subclass enum (verified in v2, see existing evidence comment); IDs observed at runtime on Retail 12.1.x via `C_Item.GetItemInfoInstant`/`GetItemSubClassInfo`; each ID listed with its observed enUS name. Map: Parts(1)→cog, Jewelcrafting(4)→gem, Cloth(5)→cloth bolt, Leather(6)→leather, Metal & Stone(7)→ore, Cooking(8)→meat/spice, Herb(9)→herb, Elemental(10)→mote, Other(11)→bundle, Enchanting(12)→dust, Inscription(16)→pigment/ink — VERIFY these numeric IDs are the ones the existing sidebar actually produces (read how `GetCategory` derives subclassID and cross-check the ID constants against any numeric usage already in the file or in the live child keys; adjust the table to the code's reality, and note in the comment that unlisted IDs fall back to the parent icon by design).
  - Recipe subtypes: replace the all-books values on the verified `Enum.ItemRecipeSubclass` keys with per-profession icons (Alchemy flask, Blacksmithing anvil/hammer, Enchanting rod, Engineering wrench, Cooking pot/meat, Tailoring thread/bolt, Leatherworking knife, Jewelcrafting gem, Inscription scroll, Fishing pole, Book→generic only for the generic "Book" member).
  - Housing children: read `BuildSidebarModel` — if housing child rows exist with undocumented keys, apply the same exemption pattern; if none exist, note that in the report and skip.
- [ ] **Step 2: Write failing tests** — contracts: no `bags-icon-` string remains in Bags.lua; no `textureTint` in Sidebar.lua; Trade Goods exemption table present with the exemption comment marker text; Recipe table no longer maps two professions to the same book path (assert a couple of distinct values); Sidebar OPTIONS no longer contain `iconSize`/`rowHeight`.
- [ ] **Step 3: Run** — FAIL.
- [ ] **Step 4: Implement** per Step 1. Watch the 200-local ceiling (tables nest on existing hosts).
- [ ] **Step 5: Run** focused + full `./scripts/run-tests.sh` — PASS. Lint both files (LUA_COMPILER prefix).
- [ ] **Step 6: Commit** — `Give every sidebar category a full-color plated icon`.

### Task 4: Changelogs + verification

**Files:** `BFInfinite/Options/ChangelogData.lua` (+ regenerate; update `tests/changelog_test.lua` counts), `AbstractFramework/CHANGELOG.md`

- [ ] **Step 1:** BFI r5-alpha entry: update the icon-related notes to final truth (full-color plated icons; complete Trade Goods/Recipe/Housing coverage) rather than stacking near-duplicate bullets; keep enUS/zhCN parity and 侧栏 terminology. Regenerate via `luajit scripts/generate-changelog.lua`; fix `tests/changelog_test.lua` counts.
- [ ] **Step 2:** AF r30 section: plated icon presentation, size defaults, tint option removed.
- [ ] **Step 3:** Full `./scripts/verify.sh` both repos (BFI with LUA_COMPILER prefix) — both exit 0; policy compensation grep per Global Constraints; `git status` clean both repos.
- [ ] **Step 4:** Commit per repo.

## Self-Review

- Spec coverage: §1 → Tasks 1-2; §2 → Task 3; §3 → embedded + Task 4. No gaps.
- Placeholders: none; art paths are explicitly art-choice inputs with named candidates and an in-game QA gate; Trade Goods IDs are explicitly verify-against-code inputs.
- Type consistency: `iconPlateColors` (Tasks 1/3 n/a — BFI passes none), `iconSize`/`rowHeight` removal coordinated between Tasks 2 and 3; crop-never-on-atlas consistent between Tasks 1 and 3's atlas-free BFI mapping.
