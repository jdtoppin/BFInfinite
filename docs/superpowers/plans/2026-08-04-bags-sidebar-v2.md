# Bags Sidebar v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native (in-game) icons throughout the bag sidebar with a unifying tint, manual expand/collapse replacing hover auto-hide, chevrons in the collapsed rail, and a flush-to-edge rail.

**Architecture:** AF's `Widgets/TreeList.lua` gains a three-shape icon contract (`string` glyph / `{atlas}` / `{texture}`) with a `textureTint` treatment, loses all hover machinery in favor of a manual `SetCollapsed` API, and renders chevrons in compact mode. BFI remaps every sidebar category to native art (evidence-verified), migrates `sidebarAutoHide` → `sidebarCollapsed`, and anchors the rail flush. Orphaned Tabler assets are pruned from AF last.

**Tech Stack:** WoW addon Lua 5.1, AF widget framework, luacheck + luajit tests, Tabler icon generator (Node) for asset pruning only.

**Spec:** `docs/superpowers/specs/2026-08-04-bags-sidebar-v2-design.md` (committed on this branch). The spec governs; this plan implements it.

## Global Constraints

- Repos/branches: AF = `/Users/josiahtoppin/Documents/Claude BFI - AF/AbstractFramework` on `codex/bag-sidebar-foundation`; BFI = `/Users/josiahtoppin/Documents/Claude BFI - AF/BFInfinite` on `codex/bags-item-level`. Never switch branches; both are unreleased, so breaking renames need no aliases.
- Evidence policy (CONTRIBUTING.md, mandatory): every WoW API/enum/atlas claim verified against the pinned artifacts already cited in `Modules/Bags/Bags.lua`'s evidence comment — Gethe wow-ui-source commits `4383ced30106d51b27e3e86d1987f1552f0d259d` (Retail 12.0.7.68887) and `d3915c78aba77a7a9be76acbfa35c674bbb6abe9` (Retail 12.1.0.68914). Fetch files via `https://raw.githubusercontent.com/Gethe/wow-ui-source/<commit>/<path>`. Anything unverifiable stays on the existing fallback — no guesses. Extend the evidence comment with every member/API/atlas used.
- No Blizzard art is ever copied into either repo — runtime references only (`SetTexture`/`SetAtlas`).
- No `SetScript("OnUpdate")`, no `pcall`/`xpcall`, no `issecretvalue`, `Libs/` untouched.
- Lua 5.1 budgets: 200 locals per function/chunk (BFI `Bags.lua` main chunk is AT the ceiling — net-new top-level locals must nest on semantically-related existing locals, see `categoryOrderByClass.categoryIconBySubclass` precedent), 60 upvalues.
- Lint: `./scripts/lint.sh <files>`; BFI needs `LUA_COMPILER=$(command -v luac5.4 || echo /opt/homebrew/Cellar/lua@5.4/5.4.8/bin/luac5.4)` prefix (no luac5.1 in this env). Tests: `./scripts/run-tests.sh` (luajit). `rg` may be missing in subagent shells — `check-policy.sh` then silently no-ops; compensate with `git diff | grep -E 'issecretvalue|pcall'` before claiming policy-clean.
- Expansion-persistence contract is untouched: `expandedById` single authority; rail collapse never modifies it.
- Baseline-height layout, item-level display: out of scope, do not touch.
- BFI changelog: only via `Options/ChangelogData.lua` + `luajit scripts/generate-changelog.lua`; AF `CHANGELOG.md` is hand-edited.
- Commits: imperative subject, ending `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## File Structure

- AF `Widgets/TreeList.lua` — icon-shape dispatch + `textureTint` (Task 1); manual collapse API replacing hover (Task 2); compact chevrons (Task 3)
- AF `tests/tree_list_test.lua` — extended per task
- AF `.utils/generate_tabler_icons.cjs`, `Media/Icons/Bag_*` — pruned (Task 6)
- AF `tests/adaptive_icon_test.lua`, `CHANGELOG.md` — updated (Tasks 6, 8)
- BFI `Modules/Bags/Sidebar.lua` — renamed collapse API pass-through (Task 4)
- BFI `Modules/Bags/Bags.lua` — toggle wiring, icon mappings + evidence comment, flush layout (Tasks 4, 5, 7)
- BFI `Modules/Bags/Defaults.lua` — `sidebarCollapsed` migration (Task 4)
- BFI `Options/Bags.lua`, `Locales/enUS.lua`, `Locales/zhCN.lua` — relabel (Task 4)
- BFI `tests/bags_sidebar_controller_test.lua`, `tests/bags_view_modes_test.lua` — updated (Tasks 4, 5, 7)
- BFI `Options/ChangelogData.lua` (+ regenerated `CHANGELOG.md`/`RELEASE_NOTES.md`) — Task 8

---

### Task 1: AF TreeList icon-shape contract + textureTint

**Files:**
- Modify: `AbstractFramework/Widgets/TreeList.lua` (row icon application site — currently a single `AF.SetAdaptiveIcon(row.icon, node.icon or options.fallbackIcon)`-style call inside the row painter; read the file first and locate it)
- Test: `AbstractFramework/tests/tree_list_test.lua`

**Interfaces:**
- Consumes: existing node model (`node.icon`), existing list `options` table.
- Produces: node `icon` accepts `string` | `{atlas = name}` | `{texture = fileIDorPath}`; new list option `textureTint = {r, g, b}` (nil = no tint). Later tasks rely on exactly these key names: `atlas`, `texture`, `textureTint`.

- [ ] **Step 1: Write failing tests** — in the existing stub environment add a test block "icon shape dispatch": build a model with three rows, one per shape; assert the row icon texture object recorded `SetAtlas("X")` for `{atlas="X"}`, `SetTexture(123)` for `{texture=123}`, and the adaptive-icon path for `"Bag_Misc"`. With `textureTint = {0.8, 0.8, 0.8}` in options, assert `SetDesaturated(true)` + `SetVertexColor(0.8, 0.8, 0.8)` were called for the atlas and texture rows and NOT for the string row. The `CreateFrame` stub's texture objects must record these method calls (extend the stub's texture factory with `SetAtlas`/`SetTexture`/`SetDesaturated`/`SetVertexColor` recorders if absent).
- [ ] **Step 2: Run** `luajit tests/tree_list_test.lua` — expected: FAIL (methods not called / dispatch missing).
- [ ] **Step 3: Implement** a single local function near the row painter:

```lua
local function ApplyNodeIcon(list, iconRegion, icon)
    local tint = list.options.textureTint
    if type(icon) == "table" then
        if icon.atlas then
            iconRegion:SetAtlas(icon.atlas)
        else
            iconRegion:SetTexture(icon.texture)
        end
        if tint then
            iconRegion:SetDesaturated(true)
            iconRegion:SetVertexColor(tint[1], tint[2], tint[3])
        end
    else
        iconRegion:SetDesaturated(false)
        iconRegion:SetVertexColor(1, 1, 1)
        AF.SetAdaptiveIcon(iconRegion, icon)
    end
end
```

Route every place a row icon is set (initial paint AND pooled-row reuse) through it, defaulting `icon` to `options.fallbackIcon` when nil. The reset-to-white on the string path matters: pooled rows may switch shapes between models. Adapt names to the file's real structure (the row's icon region variable, options access pattern).
- [ ] **Step 4: Run** `luajit tests/tree_list_test.lua` then `./scripts/run-tests.sh` — expected: PASS.
- [ ] **Step 5: Lint + commit** — `./scripts/lint.sh Widgets/TreeList.lua`; commit `Support atlas and texture icons with unified tint in TreeList`.

### Task 2: AF rail manual collapse replaces auto-hide

**Files:**
- Modify: `AbstractFramework/Widgets/TreeList.lua` (the `AF.CreateSidebarRail` section)
- Test: `AbstractFramework/tests/tree_list_test.lua`

**Interfaces:**
- Consumes: `treeList:SetCompact(bool)`, existing rail options `expandedWidth`/`collapsedWidth`.
- Produces (exact names Task 4 consumes): `rail:SetCollapsed(collapsed, silent)` (returns true if state changed; instant `SetWidth` + `treeList:SetCompact(collapsed)`; fires `onCollapsedChanged(collapsed)` unless `silent`), `rail:GetCollapsed()`, `rail:ToggleCollapsed()` (returns new state, always fires), `rail:SetOnCollapsedChanged(fn)`. Removed (Task 4 must stop calling): `SetAutoHide`, `GetAutoHide`, `ToggleAutoHide`, `SetOnAutoHideChanged`, all hover expand/collapse. Kept unchanged: `SetShown`, `GetDesiredWidth()` (now returns the current mode's width), `GetContentInset(gap)`, `SetOnPresentationWidthChanged(fn)` (fires on every collapse state change with `width, reservedWidth` where both now always equal the current width).

- [ ] **Step 1: Write failing tests** — replace the hover-cycle test block with: (a) `SetCollapsed(true)` → width == collapsedWidth, treeList compact, callback fired once with `true`; (b) `SetCollapsed(true)` again → returns false, no second callback; (c) `SetCollapsed(false, true)` → expands silently (no callback), presentation-width callback still fires with `(expandedWidth, expandedWidth)`; (d) `ToggleCollapsed()` flips and fires; (e) THE PERSISTENCE CYCLE retargeted: expand a nest → `SetCollapsed(true)` → `expandedById` untouched, compact rows include expanded children → `SetCollapsed(false)` → children visible with labels; (f) source assertions: `assertNotContains` for `leaveGeneration`, `hoverExpand`, `PointerEnter`, `PointerLeave`, and `AnimatedResize` within the rail section is gone for width changes (the tree list's own content animation stays — scope the assertion to the removed function names, e.g. `ExpandRail`/`CollapseRail`).
- [ ] **Step 2: Run** — expected: FAIL.
- [ ] **Step 3: Implement** — delete the hover/debounce/width-animation machinery (`ExpandRail`, `CollapseRail`, pointer-enter/leave debouncing, and their `C_Timer.After` wiring); implement the four methods; update the rail's maintenance comment to describe manual collapse; keep `SetShown`/width/inset/presentation methods working off a single `collapsed` boolean.
- [ ] **Step 4: Run** focused test then `./scripts/run-tests.sh` — PASS.
- [ ] **Step 5: Lint + commit** — `Replace sidebar rail auto-hide with manual collapse API`.

### Task 3: AF compact-mode chevrons

**Files:**
- Modify: `AbstractFramework/Widgets/TreeList.lua` (row painter compact branch + chevron click region)
- Test: `AbstractFramework/tests/tree_list_test.lua`

**Interfaces:**
- Consumes: existing chevron glyphs (`ArrowDown1`/`ArrowRight1`), existing `ToggleExpanded`, `SetCompact`.
- Produces: in compact mode, parent rows (nodes with children) render the chevron beside the icon (icon left-of-center, chevron right, both within `collapsedWidth`); chevron click calls `ToggleExpanded(id)`; row-body click still selects. Child rows in compact mode stay icon-only. No new public API.

- [ ] **Step 1: Write failing tests** — compact mode: parent row's chevron region is shown and clicking it toggles expansion (assert `expandedById` flip + visible-entry change) without changing selection; leaf row's chevron hidden; expanded-mode behavior unchanged (existing assertions must keep passing).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** — the expanded-mode painter already positions icon + chevron + label; the compact branch currently hides label AND chevron. Change the compact branch to keep the chevron for `node.hasChildren`, repositioning: icon anchored left with ~4px inset, chevron anchored right with ~2px inset (exact offsets: keep the row's existing inset constants; the pair must fit `collapsedWidth = 40` with a 16px icon and the chevron's current size). Ensure the chevron's mouse region stays clickable in compact mode (it may currently be disabled/hidden there).
- [ ] **Step 4: Run** focused + full suite — PASS.
- [ ] **Step 5: Lint + commit** — `Show expand chevrons on compact tree rows`.

### Task 4: BFI collapse rename, migration, toggle, labels

**Files:**
- Modify: `BFInfinite/Modules/Bags/Sidebar.lua` (API pass-through), `BFInfinite/Modules/Bags/Bags.lua` (call sites + header toggle), `BFInfinite/Modules/Bags/Defaults.lua` (`NormalizeConfig`), `BFInfinite/Options/Bags.lua`, `BFInfinite/Locales/enUS.lua`, `BFInfinite/Locales/zhCN.lua`
- Test: `BFInfinite/tests/bags_sidebar_controller_test.lua`, `BFInfinite/tests/bags_view_modes_test.lua`

**Interfaces:**
- Consumes: Task 2's rail API exactly (`SetCollapsed(collapsed, silent)`, `GetCollapsed`, `ToggleCollapsed`, `SetOnCollapsedChanged`).
- Produces: `B.Sidebar.SetCollapsed(collapsed, silent)` / `GetCollapsed()` / `ToggleCollapsed()` / `SetOnCollapsedChanged(fn)` replacing the AutoHide quartet (same pre-Initialize buffering semantics as the old methods: boolean-returning safe no-ops that flush on Initialize); config key `config.sidebarCollapsed` (boolean, default false).

- [ ] **Step 1: Write failing tests** — in `bags_sidebar_controller_test.lua`: rename every AutoHide assertion to Collapsed (recording-stub calls, silent vs toggle callback semantics, pre-Initialize buffering + flush); add `assertNotContains(source, "AutoHide")` for `Modules/Bags/Sidebar.lua`. In `bags_view_modes_test.lua`: migration contract — `NormalizeConfig` source contains `sidebarCollapsed` handling AND consumes the legacy key (`config.sidebarAutoHide = nil` after mapping old `true` → `sidebarCollapsed = true`); `assertNotContains` for `sidebarAutoHide` anywhere in `Bags.lua`/`Sidebar.lua` (Defaults.lua keeps the one migration mention).
- [ ] **Step 2: Run both tests** — FAIL.
- [ ] **Step 3: Implement** — Sidebar.lua: rename the four pass-throughs + buffered state (`pendingCollapsed`). Defaults.lua `NormalizeConfig`:

```lua
if type(config.sidebarCollapsed) ~= "boolean" then
    config.sidebarCollapsed = config.sidebarAutoHide == true
end
config.sidebarAutoHide = nil
```

Bags.lua: header toggle button calls `B.Sidebar.ToggleCollapsed()`; its glyph/tooltip logic keys off `GetCollapsed()` (collapsed → expand arrow + "Expand Sidebar" tooltip; expanded → collapse arrow + "Collapse Sidebar"); startup applies `B.Sidebar.SetCollapsed(config.sidebarCollapsed, true)`; the `SetOnCollapsedChanged` handler persists to `config.sidebarCollapsed` and refreshes layout (mirror how the auto-hide handler did both). Options/Bags.lua: checkbox binds `sidebarCollapsed`, label key `L["Collapse Sidebar"]`; add enUS `"Collapse Sidebar"` = `"Collapse Sidebar"` (+ tooltip text if the old auto-hide entry had one) and zhCN translations consistent with the file's existing 侧栏 terminology; remove the now-unused auto-hide locale keys from both locale files.
- [ ] **Step 4: Run** both focused tests + full `./scripts/run-tests.sh` — PASS.
- [ ] **Step 5: Lint + commit** — `LUA_COMPILER=... ./scripts/lint.sh Modules/Bags/Sidebar.lua Modules/Bags/Bags.lua Modules/Bags/Defaults.lua Options/Bags.lua`; commit `Replace sidebar auto-hide with manual collapse toggle`.

### Task 5: BFI native icon mappings + evidence

**Files:**
- Modify: `BFInfinite/Modules/Bags/Bags.lua` (icon tables ~L44-135, `BuildSidebarModel` parent/view icon literals, evidence comment ~L180-266), `BFInfinite/Modules/Bags/Sidebar.lua` (pass `textureTint` in rail options)
- Test: `BFInfinite/tests/bags_view_modes_test.lua`

**Interfaces:**
- Consumes: Task 1's icon shapes (`{atlas=...}`/`{texture=...}`) and `textureTint` option key.
- Produces: final icon usage list (which `Bag_*` glyph names remain referenced anywhere in BFI) — Task 6's prune depends on it; report it explicitly.

- [ ] **Step 1: Verify APIs against pinned artifacts (evidence policy — do this before writing any mapping).** Fetch from both pinned commits and record path+commit in the evidence comment:
  1. `GetInventorySlotInfo(slotName)` — confirm existence and return contract (`slotId, textureName[, checkRelic]`) in FrameXML (search `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua` and `Blizzard_Deprecated` at both commits; the invTypeToSlot mapping used by `PaperDollFrame` is also the authority for INVTYPE → slot-name pairs).
  2. Candidate slot-name table to verify (post-alias INVTYPEs; drop/adjust any pair the artifact contradicts): HEAD→HeadSlot, NECK→NeckSlot, SHOULDER→ShoulderSlot, CLOAK→BackSlot, CHEST→ChestSlot, BODY→ShirtSlot, TABARD→TabardSlot, WRIST→WristSlot, HAND→HandsSlot, WAIST→WaistSlot, LEGS→LegsSlot, FEET→FeetSlot, FINGER→Finger0Slot, TRINKET→Trinket0Slot, WEAPON→MainHandSlot, 2HWEAPON→MainHandSlot, WEAPONMAINHAND→MainHandSlot, WEAPONOFFHAND→SecondaryHandSlot, RANGED→MainHandSlot (verify: retail removed the ranged slot — confirm what `PaperDollFrame` maps RANGED/RANGEDRIGHT to), plus the ProfessionGear and any remaining slots BFI's `equipmentSlotOrder` contains — enumerate from the code, verify each.
  3. Profession/tradeskill atlas names: search the artifacts' `Blizzard_Professions` code and `AtlasInfo`/`UIAtlasInfo` sources for per-profession atlas members (the professions UI's spec/tab icons). Only names literally present in the artifact are usable. Map Trade Goods subclasses (from `Enum.ItemReagentSubclass`/tradegoods members verified the same way) and Recipe subclasses (per-profession) to those atlases; any subclass without a verified sensible atlas stays unmapped (parent-icon fallback).
  4. Parent-category native art: Equipment→a verified paper-doll or transmog atlas (or `GetInventorySlotInfo("ChestSlot")` texture as last resort), Consumables/Quest/Reagent/Backpack/Housing/TradeGoods/Recipes→verified atlases (e.g. quest-log, reagent-bag, backpack, housing UI atlas members found in the artifacts). Same rule: verified or keep the current glyph.
  5. Consumable subtype textures: pick five stable `Interface\Icons\` paths (art choice, not an API claim — record chosen paths in a maintenance comment; final look is an in-game QA gate).
- [ ] **Step 2: Write failing tests** — `bags_view_modes_test.lua` source contracts: `categoryIconByEquipLoc` values are `{ texture = ... }` tables built from `GetInventorySlotInfo`; consumable/tradegoods/recipe subclass tables use `{ atlas/texture }` shapes; parent icon literals in `BuildSidebarModel` updated; evidence comment names `GetInventorySlotInfo` and at least one verified atlas; `Sidebar.lua` passes `textureTint`; `assertNotContains` for `"Bag_Slot_"` anywhere in `Bags.lua`.
- [ ] **Step 3: Run** — FAIL.
- [ ] **Step 4: Implement** — resolve slot textures once at load into the nested table (keep the 200-local nesting pattern):

```lua
-- Values resolved from the client's own paper-doll slot art so the sidebar
-- matches the character pane. See the evidence comment for the verified
-- INVTYPE -> slot-name contract.
local slotTextures = equipmentSlotOrder.categoryIconByEquipLoc -- reuse host table, now storing {texture=...}
for invType, slotName in next, INV_TYPE_TO_SLOT do
    local _, textureName = GetInventorySlotInfo(slotName)
    slotTextures[invType] = textureName and { texture = textureName } or nil
end
```

(Adapt to the real host-table layout; `INV_TYPE_TO_SLOT` nests on the same host. A nil texture falls back to the parent icon automatically.) Update subclass tables and `BuildSidebarModel` parent/view literals per Step 1's verified results; pass `textureTint = {r, g, b}` from `Sidebar.lua`'s options (measure the tone: use the same RGB AF's adaptive glyphs render at in the rail — read the widget's glyph color constant and reuse it). Extend the evidence comment.
- [ ] **Step 5: Run** focused + full suite — PASS. `LUA_COMPILER=... ./scripts/lint.sh Modules/Bags/Bags.lua Modules/Bags/Sidebar.lua`.
- [ ] **Step 6: Report + commit** — list every `Bag_*` name still referenced in BFI (grep `Bag_` across `Modules/ Options/`) in the task report for Task 6; commit `Use native client art for sidebar category icons`.

### Task 6: AF asset prune

**Files:**
- Modify: `AbstractFramework/.utils/generate_tabler_icons.cjs` (ICONS table), delete orphaned `AbstractFramework/Media/Icons/Bag_*.svg|.tga`
- Test: `AbstractFramework/tests/adaptive_icon_test.lua`, `AbstractFramework/tests/tree_list_test.lua`

**Interfaces:**
- Consumes: Task 5's still-referenced list (from its report/commit).
- Produces: ICONS table contains only referenced + abstract-row glyphs.

- [ ] **Step 1:** Compute the orphan set: all `Bag_*` entries in ICONS minus Task 5's still-referenced list (expected survivors: `Bag_All`, `Bag_IndividualBags`, `Bag_Categories`, `Bag_Empty`, `Bag_Misc`, plus any parent that kept its glyph as fallback in Task 5; expected orphans: all 22 `Bag_Slot_*`, the 5 consumable glyphs, and parent glyphs the native swap replaced). Cross-check by grepping BFI for each candidate orphan before deleting.
- [ ] **Step 2:** Remove orphan entries from ICONS; `git rm` their SVG+TGA pairs; update `tests/adaptive_icon_test.lua` (drop removed-icon assertions; keep a surviving `Bag_*` assertion in both stub environments); ensure `tests/tree_list_test.lua` fixtures don't reference removed names.
- [ ] **Step 3: Verify** — `node .utils/generate_tabler_icons.cjs --check` (must pass: validates every ICONS entry has assets and no stray assets exist — if stray-asset detection isn't part of --check, verify manually that `ls Media/Icons/Bag_*` matches ICONS exactly); `./scripts/run-tests.sh`; `./scripts/lint.sh`.
- [ ] **Step 4: Commit** — `Prune Tabler bag icons replaced by native art`.

### Task 7: BFI flush rail layout

**Files:**
- Modify: `BFInfinite/Modules/Bags/Bags.lua` (rail anchoring in the sidebar wiring/`LayoutItemsInternal` region — locate where the rail frame is positioned relative to the styled shell and where `GetContentInset` feeds the grid origin)
- Test: `BFInfinite/tests/bags_view_modes_test.lua`

**Interfaces:**
- Consumes: `B.Sidebar.GetContentInset(gap)` (unchanged), rail frame anchor points.
- Produces: rail anchored `TOPLEFT`/`BOTTOMLEFT` to the shell's inner border (0 edge inset, full height); item-grid origin keeps `railWidth + 8` inset.

- [ ] **Step 1: Read** the current anchoring: find the `AF.SetPoint`/`SetPoint` calls positioning the rail and the constants producing the edge inset (likely the same inset other BFI panels use). Identify the inner-border offset the styled shell expects (border thickness, typically 1px pixel-perfect units via `AF.GetOnePixelForRegion` or similar — reuse whatever the shell's own children use to sit flush).
- [ ] **Step 2: Write failing test** — source contract in `bags_view_modes_test.lua`: the rail anchor call uses the flush offsets (assert the new exact `SetPoint` argument snippet after you've decided it in Step 1 — write the assertion to match the real line, e.g. `assertContains(bags, 'AF.SetPoint(railFrame, "TOPLEFT", shell, "TOPLEFT", 1, -1)')` adjusted to actual names).
- [ ] **Step 3: Implement** — change the anchors; verify `GetContentInset` math still yields grid origin = rail width + 8 (adjust the gap constant only if the removed edge inset was previously included in it).
- [ ] **Step 4: Run** focused + full suite; `LUA_COMPILER=... ./scripts/lint.sh Modules/Bags/Bags.lua` — PASS.
- [ ] **Step 5: Commit** — `Anchor sidebar rail flush to the bag frame edge`.

### Task 8: Changelogs + full verification

**Files:**
- Modify: `BFInfinite/Options/ChangelogData.lua` (+ regenerate `CHANGELOG.md`/`RELEASE_NOTES.md`), `BFInfinite/tests/changelog_test.lua` (note counts), `AbstractFramework/CHANGELOG.md`

**Interfaces:** none produced; consumes everything.

- [ ] **Step 1:** BFI: append to the existing `r5-alpha` entry (enUS+zhCN, matching established terminology): native in-game icons for sidebar categories; sidebar toggle now collapses/expands instantly (auto-hide removed); chevrons in the collapsed rail; rail sits flush with the window edge. Regenerate via `luajit scripts/generate-changelog.lua` (read its `--help`/usage first); update `tests/changelog_test.lua` note counts.
- [ ] **Step 2:** AF: extend the r30 `CHANGELOG.md` section (newest-first position): TreeList atlas/texture icon support with tint, manual rail collapse API, compact chevrons, pruned bag glyph set.
- [ ] **Step 3:** Full verify both repos: AF `./scripts/verify.sh`; BFI `LUA_COMPILER=... bash scripts/verify.sh`. Both must exit 0. Manual policy grep per Global Constraints if `rg` absent.
- [ ] **Step 4:** `git status` clean both repos; commit changelog changes per repo.

## Self-Review

- Spec coverage: §1 icons → Tasks 1, 5, 6; §2 collapse → Tasks 2, 4; §3 chevrons → Task 3; §4 flush → Task 7; testing → embedded per task + Task 8 verify; QA checklist → post-merge, in-game (unchanged from spec). No gaps.
- Placeholders: none — candidate tables are explicitly verification inputs with a drop-to-fallback rule, per the repo's own evidence policy; Task 7's assertion is written after Step 1 by design (source-contract must match real code).
- Type consistency: `SetCollapsed(collapsed, silent)`/`GetCollapsed`/`ToggleCollapsed`/`SetOnCollapsedChanged` identical across Tasks 2 and 4; icon shape keys `atlas`/`texture`/`textureTint` identical across Tasks 1 and 5; `sidebarCollapsed` key identical across Task 4's files.
