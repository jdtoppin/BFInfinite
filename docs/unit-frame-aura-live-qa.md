# 12.1 aura full-stack live QA

This is the release gate for BFInfinite's aura migration. The primary target
is Retail 12.1. The current audited pin is `12.1.0.68914`, with Blizzard UI
source at `d3915c78aba77a7a9be76acbfa35c674bbb6abe9`. Retail 12.1 is scheduled
for August 11, 2026; repeat this entire gate against the final release build
and replace both pins before release.

Retail 12.0.7 is not a second full validation target. Use it only for the
cross-version saved-map and legacy-gray preservation smoke described below.

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

1. AF #19 at `d6858f3997a1014a7ab9ce05ddaaf53efe4df9c6` with BFInfinite
   #90 at `adad69628fff7419aef513276322d377bed2b3b0`.
2. AF #22 at `98db54e6734543265ed3a0eeaea12743e6d4e717` with BFInfinite
   #101 at `3a0d80a38247f6487dbbff2371f681672a61adc8`.
3. AF #22 at `98db54e6734543265ed3a0eeaea12743e6d4e717` with BFInfinite
   #102 at `5bbd4948ec55353ab31418f30a39b4c592ae7457`.
4. AF #20 at `5190acb56f85a52353d857b95510eca81348495e` with BFInfinite
   #103 at `8025cd837d40ea476c5086d64d3384f826428b1e`.
5. AF #23 at `43f79cf2e9e91c47c9142c3546c900baf8fe092f` with the exact
   checked-out head of `codex/unitframe-aura-full-stack-test` as the final #91
   validation SHA. Record that full branch-head SHA immediately before
   installation.

Delete and replace both addon folders between pairs. Descendants include their
ancestors, never sibling integrations; do not merge branches or overlay
folders to manufacture a test build. PR #91 is validation-only and must never
be merged. Closed PR #98 is superseded and is not an install input.

For the final stack, use AbstractFramework PR #23, branch
`codex/secret-unit-identity`, exact head
`43f79cf2e9e91c47c9142c3546c900baf8fe092f` (r35).

The aggregate must contain these exact BFInfinite terminal heads:

| Coverage | Branch | Exact head |
|---|---|---|
| Global exact spell colors (#101) | `codex/unitframe-aura-spell-colors` | `3a0d80a38247f6487dbbff2371f681672a61adc8` |
| Presentation hardening (#102) | `codex/unitframe-aura-presentation-hardening` | `5bbd4948ec55353ab31418f30a39b4c592ae7457` |
| Player | `codex/unitframe-aura-player` | `3f0fd66` |
| Boss | `codex/unitframe-aura-boss` | `241640a` |
| Focus | `codex/unitframe-aura-focus` | `2217919` |
| TargetTarget | `codex/unitframe-aura-targettarget` | `7f58d6c` |
| FocusTarget | `codex/unitframe-aura-focustarget` | `ed903c8` |
| PetTarget | `codex/unitframe-aura-pettarget` | `387cab3` |
| Pet | `codex/unitframe-aura-pet` | `86b0bd4` |
| Target partition | `codex/unitframe-aura-target` | `edcb992` |
| Party | `codex/unitframe-aura-party` | `a354756` |
| Raid | `codex/unitframe-aura-raid` | `4f370f7` |
| Upper-right Debuff appearance (#103; includes #99) | `codex/buffs-debuffs-native-debuffs` | `8025cd837d40ea476c5086d64d3384f826428b1e` |
| Secret identity (#100) | `codex/unitframe-secret-identity` | `b8e1671ed8a1c11657416357875f9c8277051654` |

Test in this order:

1. Test AF r35 alone, including duration abbreviations and secret identity.
2. Test the policy, spec, lifecycle/controller, provider/counter, supported
   filter-control, spell-color, and presentation-hardening PRs in isolation.
3. Test each of the ten unit-frame integration leaves independently.
4. Test the upper-right foundation, controller, Buffs, options, and
   forbidden-button branches in their PR order.
5. Test #103's ordinary Debuff appearance controls with AF r33.
6. Install AF r35 and the disposable aggregate as clean, complete folders.
7. Run the 12.1 gates below in order.
8. Run the narrow 12.0.7 preservation smoke.

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

### 1. Backend, load, and ownership

- Login and reload with every unit-frame Buffs and Debuffs indicator enabled.
- Confirm Player, Pet, Party, Raid, Target, Boss, Focus, TargetTarget,
  FocusTarget, and PetTarget use native containers.
- Confirm no unit-frame row silently falls back to the legacy backend.
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

### 4. Reaction, hover, visibility, and identity

With a Target partition and an active spell-list/color gate:

1. Show a hostile presentation and hover a native aura.
2. Change to friendly, cross-faction, duel, phased, offline, or a secret or
   indeterminate reaction.
3. The addon-owned holder and any external seeded container must curtain to
   alpha zero immediately. The stale relation must not remain visible, no new
   variant may be driven while display is disallowed, and explicit refresh
   must be skipped.
4. Reverse the desired state while still hovered. If the already-applied
   presentation is again correct, alpha must return to one without exposing
   both variants.
5. End hover or restore a public permitted reaction. The correct variant must
   apply first, then alpha returns to one.

Repeat the hide/recovery sequence on a non-partitioned row and on Party/Raid
seeded containers. Include a failed/deferred holder write, reload quiesce, and
destroy while hovered. The implementation may read only BFInfinite's plain
holder state and its own tracked configuration. It must not read native
visibility, children, buttons, aura data, or tooltip ownership, and must not
drive a tooltip to force hover to end. `GameTooltip` may remain visible while
the alpha curtain applies; BFInfinite must neither inspect nor dismiss it, and
the transition must produce no error or taint.

### 5. Unit and roster churn

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

### 6. Restricted content

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

### 7. Blizzard Edit Mode provider

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

### 8. Upper-right Buffs and Debuffs

- On 12.1, BFInfinite may own only the supported helpful Buffs native
  container when its complete backend and settings allow it.
- Blizzard continues to own all harmful-aura data, filtering, ordering,
  layout, updates, tooltips, and visibility. BFInfinite only applies static
  appearance settings to the fixed pool of 16 ordinary Blizzard Debuff
  buttons.
- Private-aura anchors are independent siblings of that ordinary pool.
  BFInfinite must not style, hide, inspect, move, or otherwise operate on
  them. `DeadlyDebuffFrame` is separate and must also remain unchanged.
- Toggle Buffs, Separate Own, supported appearance options, profiles, Edit
  Mode, combat, hover, reload, and temporary enchants.
- For ordinary Debuffs, verify the main enable toggle, icon width and height
  from 10 through 30, icon crop, native Debuff border fit, and all supported
  stack-count font, position, color, shadow, and visibility controls.
- Confirm the ordinary Debuff duration control only shows or hides Blizzard's
  text. Blizzard must continue to supply and abbreviate the value in seconds,
  minutes, hours, and days.
- Confirm the Debuff arrangement, sorting, spacing, per-line limit, total cap,
  Separate Own, and duration font, position, and color controls are disabled.
  Their plain-language explanations must wrap without clipping.
- Generate ordinary, private, and deadly debuffs together. Confirm ordinary
  Debuffs receive the selected appearance with no duplicates, while private
  auras and deadly debuffs retain their original Blizzard presentation.
- Disable ordinary Debuff styling and confirm the icon, native border, stack
  count, and duration visibility return exactly to their original Blizzard
  values. Re-enable it and confirm the same fixed 16 buttons are reused.
- Change every supported ordinary Debuff setting in combat. Confirm the old
  presentation remains stable until combat ends, the options report a pending
  update, and the new presentation applies afterward without a reload.
- Repeat the ordinary/private/deadly checks across Edit Mode, reload, hover,
  Mythic+, raid, and PvP restrictions.
- Confirm no restricted AuraButton inspection, reparenting, duplicate aura,
  script or event hooking, Blizzard update-method driving, active-state or
  visibility reads, or hidden Blizzard-owned harmful/private presentation.

### 9. Counters, leaks, errors, and taint

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
only one relation is active.

With ordinary Debuff styling enabled, require `active == true`,
`styledButtonCount == 16`, and `snapshotsCreated == 16`. Repeated settings,
combat deferral, Edit Mode, and reload-free enable/disable cycles must not
increase `snapshotsCreated`. With styling disabled, require `active == false`
and `styledButtonCount == 0`; retaining the 16 restoration snapshots is
expected.

Reload once, log out cleanly, and inspect the error collector and flushed
`taint.log`.

## Narrow 12.0.7 preservation smoke

Do not rerun the 12.1 native matrix on 12.0.7.

1. Export a 12.1 profile containing several explicit spell-color families,
   an unknown ID, and an over-budget configuration.
2. Import it on 12.0.7.
3. Confirm the saved spell-ID/RGBA map survives exactly through profile
   switch, export, reload, and re-import.
4. Confirm legacy unit-frame Block rows remain gray. The saved 12.1 map must
   not be applied, inferred, normalized into fewer colors, or discarded.
   The old raw `auraData.spellId` lookup must not be restored on 12.0.7; that
   active-aura read is secret-unsafe even though the static saved map is
   preserved.
5. Confirm legacy upper-right Buffs/Debuffs still load without a
   12.1-only `CreateFrame` path or error.
6. Return the exported profile to 12.1 and confirm the exact families and IDs
   are restored.

## Hard blockers

Stop and file a failure with evidence for any of the following:

- Lua error, blocked action, forbidden-access error, or new taint;
- secret value comparison, logging, caching, or branching;
- native child/button/aura inspection or tooltip-driving logic;
- stale wrong-relation content visible during hover or visibility deferral;
- refresh while presentation is disallowed or still curtained;
- both Target relation variants visible together;
- Party/Raid external seeded content visible behind a hidden plain holder;
- missing category, duplicate aura, partial color fallback, inferred spell
  family, or a listed ID using the wrong exact RGBA;
- more than eight color-expanded active groups, except an unchanged baseline
  gray policy that already exceeds eight;
- reload prompt for same-family ID tuning, or no reload for a new family;
- duplicate/stranded restricted buttons, unbounded counter growth, or
  construction during provider-only changes;
- BFI replacing or hiding Blizzard's harmful container, touching private
  anchors or `DeadlyDebuffFrame`, hooking their scripts or update methods, or
  reading an ordinary Debuff button's aura, active, or visibility state;
- failure to restore the original ordinary Debuff appearance when its BFI
  styling is disabled;
- any unsupported ordinary Debuff control being enabled;
- clipped or unwrapped settings explanations;
- any 12.1 native frame silently using the legacy backend.
