# 12.1 aura full-stack live QA

This is the release gate for BFInfinite's aura migration. The primary target
is Retail 12.1. The current audited pin is `12.1.0.68914`, with Blizzard UI
source at `d3915c78aba77a7a9be76acbfa35c674bbb6abe9`. Retail 12.1 is scheduled
for August 11, 2026; repeat this entire gate against the final release build
and replace both pins before release.

The disposable aggregate branch is
`codex/unitframe-aura-full-stack-test`. It exists to prove coexistence. Never
merge PR #91 or use its aggregate commit as a substitute for the separately
reviewed production PRs.

## Exact inputs and test order

Merging a PR into `master` is not required for in-game testing. Install the
exact branch head as a complete addon folder. Do not overlay files from one
branch onto another. Each integration leaf contains its own required
ancestors, but it does not contain sibling frame integrations; use the
aggregate only after the isolated leaves pass.

Use this clean isolated-install sequence:

Before the supported pairs, run one deliberate dependency-mismatch preflight:
install AF #23/r35 at
`43f79cf2e9e91c47c9142c3546c900baf8fe092f` with the exact checked-out
head of BFInfinite #91. A dependency warning is acceptable. Every BFI-owned
unit-frame and nameplate aura row must remain hidden, and the error log must
contain no `GetUnitAuraInstanceIDs`, `UNIT_AURA`, Lua, or taint error. Then
delete both addon folders before installing the supported AF #25/r36 pair.

1. AF #19 at `d6858f3997a1014a7ab9ce05ddaaf53efe4df9c6` with BFInfinite
   #90 at `d9c5a23246a01572e1fb75d470a250032f802b33`.
2. AF #19 at `d6858f3997a1014a7ab9ce05ddaaf53efe4df9c6` with BFInfinite
   #123 at `6840357a27c4473672227b8d4d9b25a73cc53596`. Verify the
   Buff/Debuff control labels are plain while the Unit Frame Presets heading
   and semantic enabled/disabled colours remain unchanged.
3. AF #22 at `98db54e6734543265ed3a0eeaea12743e6d4e717` with BFInfinite
   #101 at `32ea029e6b605559f67314829e9359679aee4d8c`.
4. AF #22 at `98db54e6734543265ed3a0eeaea12743e6d4e717` with BFInfinite
   #102 at `9fedb173cc7da9a4152ca3bd077fd2c3bf203df7`.
5. AF #27 at `479084cd31f74a838ddf4b67785129148bb5d112` with BFInfinite
   #120 at `e205ec51605b3ceee2687d1339b428057d921277`, then #110 at
   `b10ffbf7b5e1a4f8970a448c8fad0d0a9aa64742`.
6. AF #27 at `479084cd31f74a838ddf4b67785129148bb5d112` with BFInfinite
   #112 at `ab05284aae32d9478ac7181ea9db92b8c2c7f947`.
7. AF #20 at `5190acb56f85a52353d857b95510eca81348495e` with BFInfinite
   #103 at `dc0546639fec885ced82bdf1399d998f2c2f03bd`. Verify the
   ordinary upper-right Debuffs use BFI's neutral square outline while
   Blizzard continues to own their data and layout.
8. Validation-only AF #25 at
   `d5a0984f5dc7f14b0b75314a0cae6d190bf61b88` with BFInfinite #110
   at `b10ffbf7b5e1a4f8970a448c8fad0d0a9aa64742`. This is the clean
   combined check for AF #26's square border and AF #27's required r36
   runtime. Verify Target Debuffs use a square border while Blizzard's native
   dispel type still controls its colour and visibility. Target Buffs must
   remain unchanged.
9. AF #27 at `479084cd31f74a838ddf4b67785129148bb5d112` with BFInfinite
   #110 at `b10ffbf7b5e1a4f8970a448c8fad0d0a9aa64742`. On Target Buffs
   and Debuffs, test every cooldown choice after its required reload and
   require exactly one graphical timer.
10. AF #27 at `479084cd31f74a838ddf4b67785129148bb5d112` with BFInfinite
    #112 at `ab05284aae32d9478ac7181ea9db92b8c2c7f947`. Repeat every
    cooldown choice on hostile nameplate Debuffs.
11. AF #27 at `479084cd31f74a838ddf4b67785129148bb5d112` with BFInfinite
    #121 at `d1a5fe741fc703458b5d0830e620cd6ac6f070b9`, then #103 at
    `dc0546639fec885ced82bdf1399d998f2c2f03bd`. Verify the
    fixed-clock upper-right native Buff groups and temporary enchants have a
    circular swipe only, never a second vertical fill.
12. Current AF `main` at `d95ae87f4538d6d3f40be8534ec220eace42f265`
   with BFInfinite #118 at
   `24c26df850ee0730982a1263e0770d5a5e7296c4`. Test the native tooltip
   shell on Blizzard's TargetFrame with BFI Unit Frames disabled, then on any
   upper-right native AuraButtons available to the fixture.
13. Current AF `main` at `d95ae87f4538d6d3f40be8534ec220eace42f265`
   with BFInfinite #119 at
   `d555ad11c49cb8e598340e7d273778d33f285b39`. Reload before testing,
   then open the Character panel inside an active Challenge Mode both outside
   and during combat.
14. Current AF `main` at `d95ae87f4538d6d3f40be8534ec220eace42f265`
    with BFInfinite #122 at
    `7334f0ba2b6ec8434d94f79050642a99c8ef37a5`. Give Target Buffs and
    Debuffs visibly different settings, then switch between them slowly and
    rapidly outside combat and during ordinary combat. No value from the
    previous row may render on the selected row.
15. Current AF `main` at `d95ae87f4538d6d3f40be8534ec220eace42f265`
    with BFInfinite #124 at
    `5b01b20408e3044b18e8fc12a574f8c70befa6bf`. Start after a reload
    without opening Achievements, enter Challenge Mode combat, and open
    Achievements for the first time. Require no nil edit-box error, protected
    action, or taint.
16. Validation-only AF #25 at
    `d5a0984f5dc7f14b0b75314a0cae6d190bf61b88` with the exact
    checked-out head of `codex/unitframe-aura-full-stack-test` as the final #91
    validation SHA. Record that full branch-head SHA immediately before
    installation.

Delete and replace both addon folders between pairs. Descendants include their
ancestors, never sibling integrations; do not merge branches or overlay
folders to manufacture a test build. PR #91 is validation-only and must never
be merged. Closed PR #98 is superseded and is not an install input.

For the final stack, use validation-only AbstractFramework PR #25, branch
`codex/aura-full-stack-test`, exact head
`d5a0984f5dc7f14b0b75314a0cae6d190bf61b88`. It combines AF #23/r35,
AF #26, AF #27/r36, and AF #28's legacy fail-closed boundary with current AF
`main` at `d95ae87f4538d6d3f40be8534ec220eace42f265`, including #24's Retail
12.1 max-level fix. Never merge AF #25.

The aggregate must contain these exact BFInfinite terminal heads:

| Coverage | Branch | Exact head |
|---|---|---|
| Current BFInfinite master compatibility | `master` | `56c5a66c9156c29c9dd732e4f5571686a06dd305` |
| Achievement UI 12.1 search topology (#124) | `codex/achievement-ui-12-1-search-path` | `5b01b20408e3044b18e8fc12a574f8c70befa6bf` |
| Unit Frame pane-switch lifecycle (#122) | `codex/unitframe-aura-settings-switch` | `7334f0ba2b6ec8434d94f79050642a99c8ef37a5` |
| Plain aura control labels (#123) | `codex/unitframe-aura-plain-option-labels` | `6840357a27c4473672227b8d4d9b25a73cc53596` |
| Global exact spell colors (#101) | `codex/unitframe-aura-spell-colors` | `32ea029e6b605559f67314829e9359679aee4d8c` |
| Presentation hardening (#102) | `codex/unitframe-aura-presentation-hardening` | `9fedb173cc7da9a4152ca3bd077fd2c3bf203df7` |
| Player | `codex/unitframe-aura-player` | `673838dc5dea739617155bf6806d4bb42fcaea97` |
| Boss | `codex/unitframe-aura-boss` | `9f01f432289b6b2457c5bb9cc6f023582ad85b5c` |
| Focus | `codex/unitframe-aura-focus` | `03b75af042fd84b93a3e3eaeb09ac68b1ff46440` |
| TargetTarget | `codex/unitframe-aura-targettarget` | `b463ff16fe91d17a081e248727190c8744fbe3c2` |
| FocusTarget | `codex/unitframe-aura-focustarget` | `58a60e011cb2dbd2d3b54d62cdb6ffc6b8df2df9` |
| PetTarget | `codex/unitframe-aura-pettarget` | `02a75fd22f8f04e21e7f139df214697e6350e567` |
| Pet | `codex/unitframe-aura-pet` | `8e91a8c7616b3000d5e607a2063bf528dd8c4f59` |
| Unit/nameplate AF r36 gate (#120) | `codex/native-aura-r36-unitframe-gate` | `e205ec51605b3ceee2687d1339b428057d921277` |
| Target partition (#110) | `codex/unitframe-aura-target-final` | `b10ffbf7b5e1a4f8970a448c8fad0d0a9aa64742` |
| Enemy nameplate Debuffs (#112) | `codex/nameplate-native-auras-12-1` | `ab05284aae32d9478ac7181ea9db92b8c2c7f947` |
| Party | `codex/unitframe-aura-party` | `2cfcbca80d0b2b45b9a9abb657907511152ae6b9` |
| Raid | `codex/unitframe-aura-raid` | `0afa46686c1984b357200d1807929e26b99a8cb9` |
| Upper-right AF r36 gate (#121) | `codex/native-aura-r36-upper-right-gate` | `d1a5fe741fc703458b5d0830e620cd6ac6f070b9` |
| Upper-right Debuff appearance (#103; includes #99 and #121) | `codex/buffs-debuffs-native-debuffs` | `dc0546639fec885ced82bdf1399d998f2c2f03bd` |
| Tooltip/status safety (#85) | `codex/combat-secret-tooltip-fixes` | `b13a19842e7db7c19a447a97c009a4c968757d18` |
| Native AuraButton tooltip skin (#118) | `codex/native-aura-tooltip-skin` | `24c26df850ee0730982a1263e0770d5a5e7296c4` |
| Secret identity (#100) | `codex/unitframe-secret-identity` | `b8e1671ed8a1c11657416357875f9c8277051654` |
| Unit Frame options preview safety (#114) | `codex/unitframe-options-preview-aura-safety` | `296667d9681c07ab1a7293ea8922561c44e9cb08` |
| Objective Tracker taint boundary (#115) | `codex/objective-tracker-taint-boundary` | `b829efaffd45939e268cfa6c0c1e167ce17312fe` |
| Secret pixel geometry (#116) | `codex/style-secret-pixel-geometry` | `3eb6642f82e81c1fb08a725727e80d0d2a1c566e` |
| Player Spells combat deferral (#117) | `codex/player-spells-combat-style-deferral` | `50b3c30a17a05c8d82279676d248f3bc48da5d2c` |
| Character unit-stat safety (#119) | `codex/character-frame-unit-stats-safety` | `d555ad11c49cb8e598340e7d273778d33f285b39` |

Test in this order:

1. Test AF #25 alone, including effective max-level compatibility, duration
   abbreviations, and secret identity.
2. Test #122 independently from current `master`. Give Buffs and Debuffs
   visibly different values and verify both slow and rapid selection changes
   bind the chosen pane immediately.
3. Test the policy, spec, lifecycle/controller, provider/counter, and #90
   supported-filter PRs in isolation. Test #123 next for plain aura labels,
   then test refreshed #101 spell colours and #102 presentation hardening.
4. Test each of the ten unit-frame integration leaves independently.
5. Test #112's enemy nameplate Debuffs migration independently after #110.
6. Test the upper-right foundation, controller, Buffs, options, and
   forbidden-button branches in their PR order.
7. Test #103's ordinary Debuff appearance controls with AF r33, including the
   neutral square outline and exact restoration of Blizzard's rounded border
   when styling is disabled.
8. Test AF #26's focused regression, then test its square border in the
   AF #25/BFI #110 combined pair because #110 now correctly requires AF r36.
   Repeat the square, native-dispel-colour check across every harmful
   unit-frame row on the final aggregate.
9. Test AF #27 with #120/#110, #112, and #121/#103 as three clean paths. Run the
   single-graphical-timer matrix below on unit-frame groups, nameplate groups,
   and upper-right Buff groups/temporary enchants, then repeat it on the final
   aggregate.
10. Test #85 and then #118 independently. For #118 alone, disable BFI Unit
   Frames and exercise Blizzard's native TargetFrame AuraButtons; the final
   aggregate carries both PRs for their combined restricted-context gate.
11. Test #114, #115, #116, and #117 independently against their documented
   reproducers below.
12. Test #119 independently after a reload. In restricted content, require
    the custom Movement Speed row to be absent while Blizzard's supported
    tertiary Speed row and BFI's presentation styling remain.
13. Test #124 independently. The first Achievement UI load must occur during
    Challenge Mode combat; then exercise search, filter visibility, and
    comparison-mode layout as described below.
14. Install AF #25 and the disposable BFI aggregate as clean, complete folders.
15. Run the 12.1 gates below in order.

Record the full local SHA for every installed folder. A short SHA in this
document is a review aid, not permission to test a different head.

## Exact spell-color contract

Global aura colors are an explicit saved map from numeric spell ID to exact
RGBA. BFInfinite gives that static map to Blizzard before constructing the
native row.

- BFInfinite never reads the spell ID, duration, source, secrecy, or other
  state of an active aura.
- There is no name, rank, family, healer, dispel, class, or visual inference.
- IDs with byte-for-byte identical RGBA values share one color family.
- Every listed ID in one family receives that exact RGBA.
- Unlisted IDs use the baseline gray group.
- Whitelist and blacklist candidate maps remain explicit and disjoint from
  color-family maps.
- Color families are compiled as compact, disjoint native groups plus one
  gray complement. They are not implemented with `AuraSlots`.
- Color applies only to supported Block cooldown styles. Blizzard's opaque
  duration continues to drive the swipe and duration text.
- If the reaction required for exact ID matching is false, indeterminate, or
  secret, the entire presentation fails closed. BFInfinite does not substitute
  a relation, inspect a native child, or refresh the curtained row.

Changing membership inside an existing exact-RGBA family is live tuning.
Adding, removing, or changing an RGBA family changes native construction and
requires reload after the row has been built.

Before runtime color checks, open **Auras → Global Colors** and verify:

- the introduction is the short four-sentence explanation;
- Search, `+`, and Reset share one toolbar above the bordered list;
- the list uses three columns and never consumes a cell for `+`;
- long spell names end in an ellipsis, while hovering the row shows the full
  spell tooltip; and
- clicking `+` opens a usable spell-ID field across the Search area.

### Color expansion budget and counters

The ceiling of eight applies only to the requested color-expanded active
presentation. A baseline gray policy may already exceed eight after an
any-scope category is duplicated across hostile main and complement variants.
That baseline is never truncated, reordered, or partially colored.

For an ordinary row with `P` baseline policy groups and `K` exact-RGBA color
families:

```text
G = P * (K + 1)
initial reservations = 10 * G
fresh ceiling = G * ceil(numTotal / 10) * 10
```

Color expansion is accepted only when `G <= 8`. Otherwise the whole row keeps
its exact baseline gray policy.

For Target's mutually exclusive relation partition:

```text
Gf = Pf * (K + 1)
Gm = Pm * (K + 1)
Gc = Pc * (K + 1)
maximum active groups = max(Gf, Gm + Gc)
prebuilt groups = Gf + Gm + Gc
initial reservations = 10 * prebuilt groups
fresh ceiling = sum(Gv * ceil(numTotal / 10) * 10) for each prebuilt variant
```

Budget color expansion against `maximum active groups`, not the sum of hidden
prebuilt variants. If it exceeds eight, all variants retain their full
baseline gray groups. Never drop a category and never color only part of a
row.

Example: `Pf=2`, `Pm=1`, `Pc=1`, `K=2`, and `numTotal=4` produces six active
groups in either relation, twelve prebuilt groups, 120 initial reservations,
and a fresh ceiling of 120. Only one relation presentation may be visible.

Target regression fixtures for #102 are mandatory:

- a single `player` category with `K=7` must report eight maximum active
  groups, sixteen prebuilt groups, and 160 initial reservations;
- repeat with a single `notPlayer` category and require the same
  `8 / 16 / 160` result; and
- `all` with `K=7` must reject color expansion and keep the gray partition at
  two maximum active groups, three prebuilt groups, and 30 initial
  reservations.

Raid example: `P=1`, `K=3`, and `numTotal=8` gives `G=4`, 40 initial
reservations per indicator, and a fresh ceiling of 40. Forty Raid frames with
two rows each therefore prebuild 320 groups and 3,200 initial reservations.

## Clean setup and evidence

For every 12.1 run:

1. Back up `WTF` and `Interface/AddOns`.
2. Delete the installed AbstractFramework and BFInfinite folders, then copy
   clean folders at the recorded heads.
3. Disable all other addons except an error collector. Disable Cell while
   testing BFI Raid ownership.
4. Create one clean profile and one copy of a pre-migration profile.
5. Clear `Logs/taint.log`, then run:

   ```text
   /console scriptErrors 1
   /console taintLog 2
   /reload
   ```

6. Record `/dump GetBuildInfo()`, locale, character/class/spec, profile, exact
   addon SHAs, AF/BFI versions, and other enabled addons.
7. Capture a short video for combat, hover, reaction, roster, provider, and
   visibility transitions. Capture before/after counters and the final taint
   log.

Do not dump a unit API, aura value, native child, or private-aura identity
while it may be secret.

## 12.1 live gates

### Restricted-context regression preflight

Run these seven checks on the clean aggregate before the longer aura gates.
Clear and inspect the taint log after each check so one failure cannot
contaminate later evidence.

#### Unit Frame options during challenge combat

1. Reload inside an active Mythic+ run without opening Unit Frame options.
2. Enter combat, then open **BFInfinite → Unit Frames** for the first time.
3. Switch repeatedly among General, Unit, Target, and Group; close and reopen
   the panel while combat continues.
4. Open Target, give Buffs and Debuffs visibly different values, then alternate
   between their sidebar rows at least 20 times, including rapid clicks. Every
   visible field must belong to the selected row immediately; the previous
   row's values must never flash for one frame.
5. Confirm there is no `GetUnitAuraInstanceIDs` error,
   `BFI_ShowOptionsPanel` failure, nil `frameOptionsPane`, or nil callback.
6. Confirm preset cards look unchanged. Their already-hidden Buff and Debuff
   rows are intentionally not constructed, while live unit-frame aura rows
   continue to render.

#### Objective Tracker restricted-aura path

1. Enable the Objective Tracker and set its position and height through
   Blizzard Edit Mode.
2. Reload in an active challenge run or scenario, enter combat, and force
   several objective/scenario updates.
3. Change only BFI's Objective Tracker font setting while the restricted
   context remains active.
4. Confirm there is no Maw Buffs `GetAuraDataByIndex` error or new taint.
5. Confirm Blizzard still owns tracker position, height, managed-frame
   membership, and layout. BFI visual and font styling remains, with no
   duplicate tracker or BFI mover.

#### Challenge reload with secret geometry

1. Reload inside an active challenge dungeon while out of combat, then repeat
   during combat.
2. Open and close several BFI-styled Blizzard windows and, when permitted,
   change and restore UI scale to trigger another pixel refresh.
3. Confirm there is no Backdrop arithmetic error involving a secret width,
   height, or scale and no corresponding taint entry.
4. Leave the challenge context, trigger another pixel refresh, and confirm
   ordinary public-geometry borders still update and remain aligned.

#### First Spellbook load during ordinary combat

1. Start from a fresh reload without opening the Spellbook.
2. Enter ordinary combat on a training dummy and open the Spellbook for the
   first time.
3. Confirm there is no `ADDON_ACTION_BLOCKED` for `Frame:ClearAllPoints()` or
   `Frame:SetPoint()`.
4. The assisted-combat rotation block may temporarily retain Blizzard's
   appearance and position; the rest of the Spellbook styling should load.
5. Leave combat and confirm that block receives BFI styling and positioning
   automatically.
6. Open and close the Spellbook again in and out of combat and confirm no
   further blocked action or duplicate deferred update.

#### First Achievement UI load during challenge combat

1. Start from a fresh reload without opening Achievements.
2. Enter Challenge Mode combat and open Achievements for the first time so
   `Blizzard_AchievementUI` loads through its Bootstrap path.
3. Require no `StyleEditBox: box is nil`, other Lua error, protected action,
   or new taint.
4. Exercise search text, category changes, filter visibility, and repeated
   close/reopen while the restricted context remains active. Blizzard must
   continue to own the search and filter layout.
5. Leave combat, then enter and leave achievement comparison mode. The search
   box, filter dropdown, comparison header, and search preview must remain
   aligned without a stale anchor or duplicate style hook.
6. Repeat the first-load check outside combat and flush the taint log.

#### Native AuraButton tooltip shell and hover

1. After a clean login, target fixtures with visible helpful and harmful
   auras. Hover both BFI Target rows and compare their tooltip shell with an
   ordinary BFI-skinned `GameTooltip`.
2. Require the same flat background, black one-pixel border, and one-pixel
   inset. Blizzard must still own the native tooltip text, aura content,
   anchor, visibility, and lifetime.
3. Repeat on upper-right native Buffs and on any private or boss AuraButton
   that Blizzard exposes. The shared shell may match BFI, but the private or
   boss button, anchor, contents, and update path must remain unchanged.
4. Park the pointer, then enter and leave combat, swap and clear targets, and
   reload in an active Challenge Mode both outside and during combat. Require
   no forbidden access, Lua error, taint, tooltip-driven visibility recovery,
   or delayed aura transition that depends on moving the pointer.
5. Confirm nameplate aura tooltips remain disabled where their row contract
   disables them. Disable BFI and reload once during the isolated #118 run to
   confirm Blizzard's default native tooltip shell returns.

#### Character panel with restricted unit stats

1. Reload inside an active Challenge Mode while out of combat. This reload is
   mandatory because an older BFI build may already have mutated Blizzard's
   stat-category table for the current session.
2. Open, close, and reopen the Character panel. Change gear, specialization,
   and target, then begin moving to force stat and speed updates.
3. Confirm BFI's former extra **Movement Speed** row is absent. Blizzard's
   separate tertiary **Speed** stat, the supported stat list, row backgrounds,
   and BFI fonts must remain intact.
4. Repeat while in combat, then leave combat and repeat once more without
   reloading.
5. Require no `MovementSpeed_OnUpdate` secret arithmetic, Versatility
   arithmetic, `Background:IsShown()` secret-boolean test, Lua error, blocked
   action, or new taint.
6. Leave the Challenge Mode restriction and reopen the panel. The retired
   Movement Speed row must not return; ordinary Blizzard stats must continue
   to update and retain BFI's presentation styling.

### 0. Current-master compatibility preflight

- Enable BFInfinite's Objective Tracker, then cover login, reload, and Edit
  Mode. Confirm Blizzard Edit Mode remains the sole owner of its position,
  height, managed-frame membership, and layout. BFI retains visual and font
  styling only; no BFI tracker mover or height control should remain.
- Exercise the Experience Bar while ordinary XP is available, while XP is
  disabled, and at effective max level. Confirm there is no
  `AF.IsMaxLevel` callback error, no screen-wide Stripe texture, and the
  disabled overlay remains bounded to the inner bar and hidden when it should
  not be shown.
- Stop the aura certification if either baseline regression produces a Lua
  error or contaminates the taint log; those failures can mask later aura
  evidence.

### 1. Backend, load, and ownership

- Login and reload with every unit-frame Buffs and Debuffs indicator enabled.
- Confirm the `BFI_UpdateModule` callback produces no interface-version
  `tonumber` error when upper-right Buffs & Debuffs initializes.
- Confirm Player, Pet, Party, Raid, Target, Boss, Focus, TargetTarget,
  FocusTarget, and PetTarget use native containers.
- Confirm hostile NPC/player nameplate Debuffs use a native container and
  unsupported friendly Debuffs remain absent.
- Confirm no unit-frame row silently falls back to the legacy backend.
- Confirm no nameplate row calls the legacy aura iterator or suppresses
  Blizzard nameplates when the complete native backend is unavailable.
- Confirm Party and Raid reuse their secure-header seeded containers.
- Confirm BFI never creates a `SecureAuraHeaderTemplate` on 12.1.
- Enter and leave BFI Config Mode and Blizzard Edit Mode repeatedly. There
  must be no duplicate row, stale preview identity, or controller growth.

### 2. Settings, profiles, migration, and text

Mutate every supported setting for both Buffs and Debuffs:

- enabled, placement/anchor, orientation, size, spacing, per-line and total
  limits, frame level, cooldown style, tooltip, duration text, stack text,
  supported categories, explicit whitelist/blacklist IDs, and global colors;
- Copy, Paste, Reset, profile switch, import, export, and reload;
- same-value changes, multiple changes before commit, changes in combat, and
  changes while hovered.

Before the broad mutation pass, configure one Target Buff value and the
matching Target Debuff value differently for size, cooldown style, Stack Text,
and Duration Text. Alternate between Buffs and Debuffs slowly, then rapidly.
Repeat outside combat, during training-dummy combat, and during Challenge Mode
combat. The selected pane must show its own values before it is rendered; no
stale check, slider, dropdown, text, or tooltip state may flash from the other
row, and an older deferred refresh must not change the current selection.

Inspect the aura controls in every available locale. **Stack Text**,
**Duration Text**, **Border Color**, **Aura Arrangement**, and the Target
Debuff partition label must use ordinary plain text without a per-character
gradient. The Unit Frame Presets page heading, cast-bar labels, Party/Raid/Boss
layout labels, and semantic enabled/disabled colours must remain unchanged.

Exercise Global Colors as a complete CRUD surface: add, inspect, search,
change, and delete exact IDs; cancel without mutation; confirm exactly one
mutation; reset and restore defaults; import/export valid maps; and reject or
normalize malformed IDs, RGBA values, and imported structures according to
the documented policy. Repeat search, empty-state, validation, confirm/cancel,
reset, and import in every available locale. Long rows and explanations must
wrap without clipping. Confirm the old #98 per-indicator Block Fill Color
picker is absent; color ownership lives only in Global Colors.

Verify that live-tunable values update without allocation and that
construction-owned values produce one reload-required state. Reverting to the
exact applied construction clears the prompt. The newest saved mutation wins.

#### Single graphical cooldown display

Cooldown style is construction-owned on native rows. After selecting each
style below, reload before judging the result. Keep Duration Text enabled for
one pass and disabled for another; numeric text is independent and is not a
second graphical timer.

- **None:** no circular swipe and no vertical fill.
- **Vertical** and **Block Vertical:** one vertical fill and no circular
  swipe, including behind the block colour.
- **Clock**, **Clock (With Leading Edge)**, **Block Clock**, and **Block Clock
  (With Leading Edge):** one circular swipe and no vertical fill.

Run the complete selector matrix on visible Target Buffs and Debuffs, then on
hostile nameplate Debuffs. Repeat representative helpful and harmful rows on
Player, Pet, Party, Raid, Boss, Focus, TargetTarget, FocusTarget, and PetTarget.
For upper-right native Buffs, which intentionally use a fixed Clock style,
verify ordinary Buff groups and both temporary-weapon-enchantment positions
show only the circular swipe. Upper-right ordinary Debuffs remain on
Blizzard's legacy duration presentation and are outside this selector matrix.

Inspect the full duration: immediately after application, below one minute,
across the minute boundary, and near expiration. No native update may reveal
an AF-created second carrier that was hidden only at initialization.

Check every locale available to the tester. Long explanations must wrap and
remain readable; no help text may be clipped, including the native-category
and spell-ID restrictions. Duration text must abbreviate seconds, minutes,
hours, and days correctly, with permanent auras blank.

### 3. Filters, overlap, and exact colors

- Temporarily enable Blizzard's nonpersistent tooltip spell-ID display. Run
  the first command before choosing fixtures and the second after the gate:

  ```text
  /run BFIQAOldSpellIDs=GetCVar("tooltipShowAuraSpellIDs");SetCVar("tooltipShowAuraSpellIDs",1)
  /run SetCVar("tooltipShowAuraSpellIDs",BFIQAOldSpellIDs);BFIQAOldSpellIDs=nil
  ```

  From visible tooltips, record fixtures outside addon code: A1 and A2 use
  exactly the same green `{0, 1, 0, 1}`, A3 uses pink
  `{1, 0.25, 0.6, 1}`, a related but unentered spell remains gray, and
  unrelated U1 remains gray. Add optional hostile D1 when a permitted harmful
  fixture is available. Never add addon logging or aura inspection to discover
  or verify an identity.
- Test each supported native category alone and in overlapping combinations.
- Confirm OR-unions are compiled as disjoint groups and do not duplicate an
  aura.
- Test whitelist and blacklist overlap, unknown IDs, empty lists, duplicate
  IDs, and profile-imported IDs.
- Test two explicit IDs with the same RGBA, two families with different RGBA,
  and an unlisted gray spell.
- Change IDs inside one family and confirm live tuning. Add a new family and
  confirm the reload boundary.
- Add and remove families repeatedly. Native groups must remain compact and
  contiguous, with no `AuraSlots` or blank-slot gaps. Confirm each group's cap
  and sort are independent; combined row capacity and cross-family ordering
  must not be mistaken for one global cap or sort.
- Test exactly eight color-expanded active groups and an over-budget case.
  The latter must preserve the complete baseline gray policy with no reaction
  gate added by the unused colors.
- Test a baseline partition whose any-scope split already exceeds eight, both
  without colors and with requested colors. The no-color baseline must remain
  exact, and the colored request must fall back to that same baseline.
- Do not choose a healing spell because it is assumed public. The pass
  condition depends only on Blizzard accepting the explicit ID map.

### 4. Reaction, stationary pointer, visibility, and identity

First reproduce the exact Target partition boundary:

1. Enable Target Debuffs and **Separate Auras Not from Player, Pet, or
   Vehicle**, then reload. This creates the hostile-complement holder named
   `BFI_Target_Debuffs_HostileComplement`.
2. In combat or another aura-secret context, target a hostile unit with a
   harmful aura from another player. Park the pointer over a visible
   complement aura and do not move it for the rest of this sequence.
3. Clear the target or select a friendly, cross-faction, duel, phased,
   offline, secret, or indeterminate unit, then retarget the hostile unit.
4. Repeat hostile-to-friendly, friendly-to-hostile, and no-target transitions.
   Also disable and re-enable the row, then repeat without relation
   partitioning.

The pointer is never a transition signal. Outside combat, the newest permitted
presentation must apply immediately even while the pointer remains stationary.
In combat, any physical visibility, initialization, retirement, or structural
swap that is not already applied remains at alpha zero until
`PLAYER_REGEN_ENABLED`; moving the pointer must not release it. A request that
reverses to the already-applied relation or shown state may remove the curtain
immediately using only BFInfinite's write ledgers.

At no point may the stale row, both relation variants, or a partial new row be
visible. Repeat the same stationary-pointer sequence on a non-partitioned row
and on Party/Raid secure-header seeded containers, including roster retarget,
disable, destroy, and reload quiesce. `GameTooltip` or Blizzard's native
AuraButton tooltip may remain visible; BFInfinite must neither inspect nor
dismiss either one. Its only native-tooltip operation is the one-time global
static shell configuration through Blizzard's inbound styling API.

The implementation must not call `IsShown`, `IsVisible`, `IsMouseOver`, or
`GetAlpha` on holders or native aura objects; probe protected writes with
`pcall`; call `Show`, `Hide`, or `SetShown` in combat; toggle an already-built
native container merely because a pooled nameplate is temporarily hidden;
schedule a hover retry; inspect children, buttons, aura data, or tooltip
ownership; or make pointer movement necessary for recovery. The one nameplate
first-build exception may submit the complete container's final enabled state
after all groups, layout, unit, and refresh work, using the supported inbound
12.1 method while the holder remains alpha-curtained.

### 5. Unit and roster churn

Before starting churn, place a visible harmful aura on each supported frame
type and inspect every cooldown style. Debuff borders must use the complete
square asset with no rounded atlas corners or cropped edge. Blizzard's native
dispel classification must still control the border colour and visibility;
helpful Buff rows must remain visually unchanged. Repeat this check on Player,
Pet, Party, Raid, Target, Boss, Focus, TargetTarget, FocusTarget, and PetTarget.

Exercise:

- target/focus changes and rapid target swaps;
- pet summon/dismiss, vehicle transitions, PetTarget and owner changes;
- Party and Raid join/leave, role changes, subgroup changes, disconnects,
  cross-faction members, phased units, and roster conversion;
- TargetTarget and FocusTarget changes during combat;
- repeated enable/disable and profile changes during the same churn.

No secret identity may be cached or compared. A temporarily unavailable unit
must wait, remain curtained, and recover to the newest clean token without
retargeting a native container to a preview identity.

### 6. Enemy nameplate Debuffs

Test #112 first as the clean AF #27/BFI #112 pair, then repeat this entire
section on the aggregate. This leaf owns only enemy NPC/player Debuffs.
Friendly dispellable Debuffs, nameplate Buffs, and nameplate Crowd Controls
are expected to remain absent.

1. Enable **Nameplates → Auras → Debuffs** and verify the notice says the row
   is enemy-only and that Global Colors do not affect it. Confirm the shared
   toggle changes hostile NPC/player profiles only.
2. Apply several player-cast harmful auras to hostile NPC and player fixtures.
   Confirm the compact native row uses the configured size, spacing,
   orientation, capacity, placement, cooldown style, duration text, stack
   text, frame level, and supported Debuff border treatment. Do not infer an
   exact active-aura count from the fixed maximum footprint.
3. Add conspicuous Global Colors entries for the same spell IDs. The nameplate
   row must remain on its ordinary appearance; it must not create color
   families, fixed slots, blank gaps, or a gray-complement partition.
4. Enter combat before a previously unseen hostile plate is created. The
   complete row may be created in combat, but it must remain alpha-curtained
   until its group, layout, unit, refresh, and final enabled state are all
   submitted. Require no native `Show`, `Hide`, or `SetShown` call and no
   regen queue for that complete first build.
5. Force repeated pool reuse: hostile-to-hostile token changes, then
   hostile-to-friendly-to-hostile before regen. The friendly assignment must
   show no BFI Debuffs row. The returning hostile assignment must reuse and
   retarget the completed native carrier without a second build or an
   enable/disable cycle.
6. Repeat with duel, cross-faction, phased, and `UNIT_FACTION` reaction
   changes. A combat reaction change must curtain the row immediately; the
   protected plate rebuild completes after `PLAYER_REGEN_ENABLED`.
7. Park the pointer over the aura area and do not move it while plates appear,
   disappear, phase, recycle, and change reaction. No tooltip, pointer-leave,
   visibility read, or hover retry may control recovery. Native nameplate aura
   tooltips are expected to remain disabled.
8. Change every supported nameplate Debuffs setting outside combat, then in
   combat, while the pooled row is hostile, friendly/hidden, and removed.
   Same-topology tuning must apply at the legal boundary. Construction-owned
   changes must raise the reload-required notice. The next hostile assignment
   must use the newest prepared snapshot; an untouched cached row must not be
   constructed merely because settings changed.
9. Disable Debuffs and confirm the native carrier is disabled rather than
   only made transparent. Re-enable it out of combat, reload, and repeat the
   combat pool sequence.
10. Repeat the section in an ordinary dungeon, Mythic+, raid, arena/BG, and
    Edit Mode/test-provider transitions. Confirm unsupported friendly Buffs,
    Debuffs, and Crowd Controls do not appear opportunistically in any mode.

Record UnitFrames runtime/construction counters before and after first build,
50 hostile plate churn cycles, settings changes, and provider transitions.
One completed controller/container per cached nameplate root is expected;
same-combat retargets and no-op/tuning changes must not add builds, groups,
buttons, stranded shells, or reservations.

### 7. Restricted content

Repeat representative gates in:

- an ordinary dungeon and Mythic+ pull;
- a raid encounter;
- battleground or arena/PvP restrictions;
- a duel and cross-faction group;
- combat lockdown while hovered.

Use real boss, important, dispellable, private, and deadly auras where
available. Unit-frame native groups may render only the private content
Blizzard authorizes through its inseparable source. BFInfinite must never log
or expose private identity, spell, duration, count, or source.

### 8. Blizzard Edit Mode provider

- Enter Edit Mode before first construction and after rows are already built.
- Cover all ten frame types, with special evidence for Boss, Party, Raid, and
  Target partition.
- Verify provider entry/exit does not construct a duplicate container,
  retarget to a test identity, apply reaction gates to Blizzard test data, or
  mutate settings.
- On one already-built live-to-test-to-live cycle, require exactly two added
  provider-switch events, one test-provider activation, one live-provider
  restoration, and no container, group, or button allocation.
- Exit Edit Mode and confirm the newest live unit, relation, and roster appear.
- Cover private and boss-aura fixtures supplied by Blizzard without reading
  their protected data.
- BFI Config Mode is not a spell-identity provider: its preview remains gray
  and must not consume or infer a Global Colors entry.

### 9. Upper-right Buffs and Debuffs

- On 12.1, BFInfinite may own only the supported helpful Buffs native
  container when its complete backend and settings allow it.
- Blizzard continues to own all harmful-aura data, filtering, ordering,
  layout, updates, tooltips, and visibility. BFInfinite only applies static
  appearance settings to the fixed pool of 16 ordinary Blizzard Debuff
  buttons.
- Private-aura anchors are separate Blizzard-owned objects, but Blizzard lays
  them out in the same `DebuffFrame` flow as ordinary Debuffs. BFInfinite must
  not style, hide, inspect, or move them, and must not reanchor the containing
  `DebuffFrame`. `DeadlyDebuffFrame` is separate and must also remain
  unchanged. If Blizzard routes one of their tooltips through the shared
  native AuraButton tooltip, only its global outer shell may use BFI's static
  background and border; the anchor, button, contents, visibility, and
  lifetime remain Blizzard-owned.
- Toggle Buffs, Separate Own, supported appearance options, profiles, Edit
  Mode, combat, hover, reload, and temporary enchants.
- For ordinary Debuffs, verify the main enable toggle, icon width and height
  from 10 through 30, icon crop, neutral square outline fit, and all supported
  stack-count font, position, color, shadow, and visibility controls. The
  rounded Blizzard atlas must be fully hidden while BFI styling is enabled;
  the square outline must not depend on reading the active dispel type.
- Confirm the ordinary Debuff duration control only shows or hides Blizzard's
  text. Blizzard must continue to supply and abbreviate the value in seconds,
  minutes, hours, and days.
- Confirm the Debuff arrangement, sorting, spacing, per-line limit, total cap,
  Separate Own, and duration font, position, and color controls are disabled.
  Their plain-language explanations must wrap without clipping.
- This aggregate does not claim exact right-edge parity between BFI's native
  Buff container and Blizzard's legacy Debuff row. Confirm no attempted fix
  reanchors `DebuffFrame`, changes Blizzard Edit Mode state, or moves a private
  anchor. Record the visible right-edge difference for the pending product
  decision rather than treating private-anchor movement as a pass.
- Generate ordinary, private, and deadly debuffs together. Confirm ordinary
  Debuffs receive the selected appearance with no duplicates, while private
  auras and deadly debuffs retain their original Blizzard presentation apart
  from the permitted shared native-tooltip outer shell.
- Disable ordinary Debuff styling and confirm the icon, rounded native border,
  stack count, and duration visibility return exactly to their original
  Blizzard values. Re-enable it and confirm the same fixed 16 buttons and the
  same BFI-owned square outlines are reused.
- Change every supported ordinary Debuff setting in combat. Confirm the old
  presentation remains stable until combat ends, the options report a pending
  update, and the new presentation applies afterward without a reload.
- Keep the pointer stationary over an ordinary Debuff while changing each
  supported setting outside combat. The appearance must update immediately;
  no pointer-leave retry or tooltip manipulation is permitted. Repeat in
  combat and confirm that combat alone, not hover, controls the pending state.
- Repeat the ordinary/private/deadly checks across Edit Mode, reload, hover,
  Mythic+, raid, and PvP restrictions.
- Confirm no restricted AuraButton inspection, reparenting, duplicate aura,
  script or event hooking, Blizzard update-method driving, active-state or
  visibility reads, or hidden Blizzard-owned harmful/private presentation.

### 10. Counters, leaks, errors, and taint

Capture these before and after the full run:

```text
/dump BFInfinite.modules.UnitFrames.GetNativeAuraRuntimeStats()
/dump BFInfinite.modules.UnitFrames.GetNativeAuraConstructionStats()
/dump BFI_Target.indicators.buffs:GetNativeAuraState()
/dump BFI_Target.indicators.debuffs:GetNativeAuraState()
/dump BFInfinite.modules.BuffsDebuffs.GetCustomAuraContainerState("buffs")
/dump BFInfinite.modules.BuffsDebuffs.GetCustomAuraContainerConstructionStats()
/dump BFInfinite.modules.BuffsDebuffs.GetBlizzardDebuffStyleState()
```

These are tracked BFI state only; they do not inspect a native child or aura.
The final runtime snapshot must satisfy
`runtimesCreated - runtimesDestroyed == liveRuntimes`. Require no incomplete
build, no stranded shell or reservation, no unexpected allocation after
no-op/live-tuning/provider/unit changes, `providerMode == "live"`, and
`reloadRequired == false`. Verify the Target state `metrics` against the
explicit partition fixtures above. Party/Raid totals must match the fixed
child count; Target totals must include all prebuilt relation variants while
only one relation is active. Nameplate totals may grow only when Blizzard
creates a new cached plate root; token retarget, reaction changes, settings
tuning, and provider transitions must reuse that root's completed carrier.

With ordinary Debuff styling enabled, require `active == true`,
`styledButtonCount == 16`, and `snapshotsCreated == 16`. Repeated settings,
combat deferral, Edit Mode, and reload-free enable/disable cycles must not
increase `snapshotsCreated`. With styling disabled, require `active == false`
and `styledButtonCount == 0`; retaining the 16 restoration snapshots is
expected.

Reload once, log out cleanly, and inspect the error collector and flushed
`taint.log`.

## Hard blockers

Stop and file a failure with evidence for any of the following:

- Lua error, blocked action, forbidden-access error, or new taint;
- secret value comparison, logging, caching, or branching;
- any holder/native visibility, hover, or alpha read-back; a protected-call
  write probe; or an unsupported/protected visibility or enabled write in
  combat outside #112's complete first-build final enabled submission;
- restricted intrinsic AuraButton or aura-state inspection, or
  tooltip-driving logic;
- direct lookup, hook, inspection, or mutation of the hidden native AuraButton
  tooltip; failure of its outer shell to match BFI while #118 is enabled; or
  the global shell setter enabling a tooltip that the row disabled;
- any transition delayed, completed, or retried because the pointer moved;
- stale wrong-relation content visible during hover or visibility deferral;
- refresh while presentation is disallowed or still curtained;
- both Target relation variants visible together;
- friendly nameplate Debuffs, nameplate Buffs, or nameplate Crowd Controls
  appearing in #112; Global Colors affecting a nameplate row; a second build
  on nameplate pool reuse; or a settings change constructing an untouched row;
- Party/Raid external seeded content visible behind a hidden plain holder;
- missing category, duplicate aura, partial color fallback, inferred spell
  family, or a listed ID using the wrong exact RGBA;
- more than one graphical duration display on a native AuraButton, including
  a circular swipe beneath Vertical/Block Vertical or a vertical fill beneath
  any Clock style;
- more than eight color-expanded active groups, except an unchanged baseline
  gray policy that already exceeds eight;
- reload prompt for same-family ID tuning, or no reload for a new family;
- duplicate/stranded restricted buttons, unbounded counter growth, or
  construction during provider-only changes;
- Buffs showing Debuff settings, Debuffs showing Buff settings, any one-frame
  stale-value flash while switching, or an obsolete deferred refresh changing
  the current pane;
- a per-character gradient on an ordinary aura control label, or loss of the
  intended presets heading and enabled/disabled state colours;
- BFI replacing or hiding Blizzard's harmful container, touching private
  anchors or `DeadlyDebuffFrame`, hooking their scripts or update methods, or
  reading an ordinary Debuff button's aura, active, or visibility state;
- failure to restore the original ordinary Debuff appearance when its BFI
  styling is disabled;
- any unsupported ordinary Debuff control being enabled;
- BFI reading or mutating `PAPERDOLL_STATCATEGORIES`, adding the dormant
  `MOVESPEED` row, formatting or deriving a restricted unit-stat value, or
  branching on a stat row's visibility;
- clipped or unwrapped settings explanations;
- any 12.1 native frame silently using the legacy backend.
