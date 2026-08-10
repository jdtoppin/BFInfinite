# 12.1 aura full-stack live QA

This is the release gate for BFInfinite's aura migration. The primary target
is Retail 12.1. The current audited pin is `12.1.0.69189`, with Blizzard UI
source at `a520b6c27bb897e6be2333b6cc2be36d52c7c11b`. Retail 12.1 is scheduled
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
install AF #37/r38 at
`a6b19d67f69ed82dbf80ae6e84bc69d0a6d1ce5a` with BFInfinite #142 at
`82783ce53821ff5149e3c6144f3b92fc529f8903`. A dependency warning is
expected because #142 requires AF #39/r39. Every BFI-owned unit-frame aura row,
including Party/Raid Debuffs and their native dispel highlights, must remain
hidden rather than using a legacy fallback. Begin with a reload in an active
Challenge Mode dungeon, then enter combat and exercise hostile, friendly,
cleared, and restored targets; Party/Raid roster changes; and config-mode
entry/exit. Blizzard-owned upper-right Buffs/Debuffs must remain available.
The error log must contain no `GetUnitAuraInstanceIDs`, `UNIT_AURA`, Lua, or
taint error. Then delete both addon folders before installing AF #39/r39.

1. AF #19 at `d6858f3997a1014a7ab9ce05ddaaf53efe4df9c6` with BFInfinite
   #90 at `d9c5a23246a01572e1fb75d470a250032f802b33`.
2. AF #19 at `d6858f3997a1014a7ab9ce05ddaaf53efe4df9c6` with BFInfinite
   #123 at `dcac8ca227734ee0132c3362ef7208f774e050c6`. Verify the
   Buff/Debuff control labels are plain, editable spell-list rows show the
   Edit/Delete mouse hints, and read-only rows do not advertise those actions.
   The Unit Frame Presets heading and semantic enabled/disabled colours remain
   unchanged.
3. AF #22 at `98db54e6734543265ed3a0eeaea12743e6d4e717` with BFInfinite
   #101 at `fb2c4fa7b1334d825347647dcc5b2943d1ef6308`.
4. AF #22 at `98db54e6734543265ed3a0eeaea12743e6d4e717` with BFInfinite
   #102 at `040b556bb7fbbcd6758f3e18a261e46a119824b2`.
5. AF #27 at `479084cd31f74a838ddf4b67785129148bb5d112` with BFInfinite
   #120 at `f80ac5b2863921fe90aa2796d857b72e82f6605f`.
6. AF #36 at `f3434d777bfcea2da8e1cc769e43ce06f5b456f6` with BFInfinite
   #136 at `4c9b5bbc5704159af321438d93b07f167fe723c9`. Run the complete
   native duration-threshold matrix below.
7. AF #36 at `f3434d777bfcea2da8e1cc769e43ce06f5b456f6` with BFInfinite
   #137 at `f72409c8a32f5210ace39b6e1b83eb361fd9485e`. Run the Blizzard
   healer-spell import matrix below.
8. AF #37 at `a6b19d67f69ed82dbf80ae6e84bc69d0a6d1ce5a` with BFInfinite
   #138 at `7622a7a59f1d286d9710151275b90a67f8dcb835`. Run the complete
   Party aura and native dispel-highlight matrix below. This supersedes closed
   PR #84.
9. AF #37 at `a6b19d67f69ed82dbf80ae6e84bc69d0a6d1ce5a` with BFInfinite
   #139 at `23b3e2176cbb2b2a2124fe864dc8bdec3a81e530`. Run the complete
   Raid matrix, then repeat the Party smoke test because #139 contains #138.
   This supersedes closed PR #87; no merge to `master` is needed for either
   isolated install.
10. AF #39 at `d2affb6d47914ada6b81f1dd81ecd3fb658dc6d6` with BFInfinite
    #142 at `82783ce53821ff5149e3c6144f3b92fc529f8903`. Run the complete
    native unit-frame Debuff-border matrix below, including Exhaustion on the
    standalone Player frame and Party's optional player child. Repeat the
    Party/Raid smoke tests because #142 contains #139 and #138.
11. AF #36 at `f3434d777bfcea2da8e1cc769e43ce06f5b456f6` with BFInfinite
   #134 at `762cbf687ae00456757a8747cf9216f12ee38faa`, then #110 at
   `8068aa4601f372e70200491ac839115ece29ccbc`. At #134, verify other
   allied players use class-coloured names, friendly NPCs retain reaction
   colours, and hostile-player custom-white defaults do not change. Reuse a
   nameplate token across public, restricted, and public identities; require
   a neutral restricted fallback, no stale class colour, and no Lua or taint
   error.
12. AF #36 at `f3434d777bfcea2da8e1cc769e43ce06f5b456f6` with BFInfinite
   #112 at `c7cda3c76e6264ed8d92a2b453481bd0f58d00d0`.
13. AF #20 at `5190acb56f85a52353d857b95510eca81348495e` with BFInfinite
   #103 at `ab6a3fd8e2d0c18416717a0c59e3c675fc203bac`. Verify the
   ordinary upper-right Debuffs use BFI's neutral square outline while
   Blizzard continues to own their data and layout.
14. Validation-only AF #25 at
   `0a04ecf055b888bb750b16df1cf623e4d927a162` with BFInfinite #110
   at `8068aa4601f372e70200491ac839115ece29ccbc`. This is the clean
   combined check for AF #26's square border and AF #36's required r37
   runtime. Verify Target Debuffs use a square border while Blizzard's native
   dispel type still controls its colour and visibility. Target Buffs must
   remain unchanged.
15. AF #36 at `f3434d777bfcea2da8e1cc769e43ce06f5b456f6` with BFInfinite
   #110 at `8068aa4601f372e70200491ac839115ece29ccbc`. On Target Buffs
   and Debuffs, test every cooldown choice after its required reload and
   require exactly one graphical timer.
16. AF #36 at `f3434d777bfcea2da8e1cc769e43ce06f5b456f6` with BFInfinite
    #112 at `c7cda3c76e6264ed8d92a2b453481bd0f58d00d0`. Repeat every
    cooldown choice on hostile nameplate Debuffs.
17. AF #27 at `479084cd31f74a838ddf4b67785129148bb5d112` with BFInfinite
    #121 at `d1a5fe741fc703458b5d0830e620cd6ac6f070b9`, then #103 at
    `ab6a3fd8e2d0c18416717a0c59e3c675fc203bac`. Verify the
    fixed-clock upper-right native Buff groups and temporary enchants have a
    circular swipe only, never a second vertical fill.
18. Current AF `main` at `f31772e0733b3fdf22063c8bcda28dfe11236848`
   with BFInfinite #118 at
   `7e917de6bb31d345f5fa7177140a084b530ee013`. Test the native tooltip
   shell on Blizzard's TargetFrame with BFI Unit Frames disabled, then on any
   upper-right native AuraButtons available to the fixture.
19. Current AF `main` at `f31772e0733b3fdf22063c8bcda28dfe11236848`
   with BFInfinite #119 at
   `d555ad11c49cb8e598340e7d273778d33f285b39`. Reload before testing,
   then open the Character panel inside an active Challenge Mode both outside
   and during combat.
20. Current AF `main` at `f31772e0733b3fdf22063c8bcda28dfe11236848`
    with BFInfinite #122 at
    `7334f0ba2b6ec8434d94f79050642a99c8ef37a5`. Give Target Buffs and
    Debuffs visibly different settings, then switch between them slowly and
    rapidly outside combat and during ordinary combat. No value from the
    previous row may render on the selected row.
21. Current AF `main` at `f31772e0733b3fdf22063c8bcda28dfe11236848`
    with BFInfinite #124 at
    `5b01b20408e3044b18e8fc12a574f8c70befa6bf`. Start after a reload
    without opening Achievements, enter Challenge Mode combat, and open
    Achievements for the first time. Require no nil edit-box error, protected
    action, or taint.
22. Validation-only AF #25 at
    `0a04ecf055b888bb750b16df1cf623e4d927a162` with BFInfinite
    #127 at `625144a3aab87c95005de6b1930caf9d765a3e59`. Use the default
    Horizontal / Left / Down Blizzard Debuff Frame layout. Outside combat,
    move the restored **BFI Buff Frame** mover and verify custom Buffs and
    ordinary Debuffs travel together, remain right-edge aligned, and keep the
    five-pixel gap. Attempting to open BFI Edit Mode in combat must show the
    combat warning and perform no movement.
23. BFInfinite #143 at
    `d88d674e7f1e1401c57bdc6d2ad6c37da60e4818`, first with the
    validation-only pre-r39 AF #25 snapshot
    `53ea5bdb65d6f37e97ac7a40576350a78cc0521b` (AF r38, including AF
    #37 at `a6b19d67f69ed82dbf80ae6e84bc69d0a6d1ce5a` and AF #30 at
    `fa0a7b7e4be152da8f962bd74bc5b18238020976`), then as a clean
    reinstall with current AF #25/r39 at
    `0a04ecf055b888bb750b16df1cf623e4d927a162`. Under r38, the harmful
    custom pane must not register: Blizzard's ordinary Debuff container and
    all six private-aura anchors remain active, with the rounded native dispel
    atlas and without the four-pixel custom spacing guarantee. Under r39, run
    the complete terminal upper-right matrix below. Require the right-aligned
    native `HARMFUL` row, exact four-pixel horizontal spacing, the shared
    ordinary/private cap, native square dispel colours, and strict suppression
    of the ordinary container plus exactly six private anchors.
    `DeadlyDebuffFrame` remains separate and active in both runs.
24. Validation-only AF #25 at
    `0a04ecf055b888bb750b16df1cf623e4d927a162` with the exact
    checked-out head of `codex/unitframe-aura-full-stack-test` as the final #91
    validation SHA. Record that full branch-head SHA immediately before
    installation.

Delete and replace both addon folders between pairs. Descendants include their
ancestors, never sibling integrations; do not merge branches or overlay
folders to manufacture a test build. PR #91 is validation-only and must never
be merged. Closed PRs #84, #87, and #98 are superseded and are not install
inputs.

For the final stack, use validation-only AbstractFramework PR #25, branch
`codex/aura-full-stack-test`, exact head
`0a04ecf055b888bb750b16df1cf623e4d927a162`. It combines AF #23/r35,
AF #26, AF #27/r36, AF #28's legacy fail-closed boundary, AF #36/r37,
AF #37/r38, and AF #39/r39 with current AF `main` at
`f31772e0733b3fdf22063c8bcda28dfe11236848`, including #24's Retail
12.1 max-level fix, AF #29's saved-position shape fix, AF #30's
restricted-context mover guard, #35's package-artifact support, and #39's
native-coloured square Debuff-border contract. Never merge AF #25.

The aggregate must contain these exact BFInfinite terminal heads:

| Coverage | Branch | Exact head |
|---|---|---|
| Current BFInfinite master compatibility | `master` | `482b386acf4f9028ff89c91e58ace88749ed2dca` |
| Achievement UI 12.1 search topology (#124) | `codex/achievement-ui-12-1-search-path` | `5b01b20408e3044b18e8fc12a574f8c70befa6bf` |
| Unit Frame pane-switch lifecycle (#122) | `codex/unitframe-aura-settings-switch` | `7334f0ba2b6ec8434d94f79050642a99c8ef37a5` |
| Aura settings presentation (#123) | `codex/unitframe-aura-plain-option-labels` | `dcac8ca227734ee0132c3362ef7208f774e050c6` |
| Global exact spell colors (#101) | `codex/unitframe-aura-spell-colors` | `fb2c4fa7b1334d825347647dcc5b2943d1ef6308` |
| Presentation hardening (#102) | `codex/unitframe-aura-presentation-hardening` | `040b556bb7fbbcd6758f3e18a261e46a119824b2` |
| Player | `codex/unitframe-aura-player` | `673838dc5dea739617155bf6806d4bb42fcaea97` |
| Boss | `codex/unitframe-aura-boss` | `9f01f432289b6b2457c5bb9cc6f023582ad85b5c` |
| Focus | `codex/unitframe-aura-focus` | `03b75af042fd84b93a3e3eaeb09ac68b1ff46440` |
| TargetTarget | `codex/unitframe-aura-targettarget` | `b463ff16fe91d17a081e248727190c8744fbe3c2` |
| FocusTarget | `codex/unitframe-aura-focustarget` | `58a60e011cb2dbd2d3b54d62cdb6ffc6b8df2df9` |
| PetTarget | `codex/unitframe-aura-pettarget` | `02a75fd22f8f04e21e7f139df214697e6350e567` |
| Pet | `codex/unitframe-aura-pet` | `8e91a8c7616b3000d5e607a2063bf528dd8c4f59` |
| Unit/nameplate AF r36 gate (#120) | `codex/native-aura-r36-unitframe-gate` | `f80ac5b2863921fe90aa2796d857b72e82f6605f` |
| Native duration thresholds (#136) | `codex/unitframe-aura-duration-text-colors` | `4c9b5bbc5704159af321438d93b07f167fe723c9` |
| Blizzard healer-spell import (#137) | `codex/unitframe-aura-import-healer-spells` | `f72409c8a32f5210ace39b6e1b83eb361fd9485e` |
| Friendly-player name class colours (#134) | `codex/nameplate-player-class-name-colors` | `762cbf687ae00456757a8747cf9216f12ee38faa` |
| Target partition (#110) | `codex/unitframe-aura-target-final` | `8068aa4601f372e70200491ac839115ece29ccbc` |
| Enemy nameplate Debuffs (#112) | `codex/nameplate-native-auras-12-1` | `c7cda3c76e6264ed8d92a2b453481bd0f58d00d0` |
| Party + native dispel highlight (#138; supersedes #84) | `codex/unitframe-party-dispel-highlights` | `7622a7a59f1d286d9710151275b90a67f8dcb835` |
| Raid + native dispel highlight (#139; includes #138; supersedes #87) | `codex/unitframe-raid-dispel-highlights` | `23b3e2176cbb2b2a2124fe864dc8bdec3a81e530` |
| Native unit-frame Debuff colours (#142; includes #139/#138) | `codex/unitframe-native-debuff-colors` | `82783ce53821ff5149e3c6144f3b92fc529f8903` |
| Upper-right AF r36 gate (#121) | `codex/native-aura-r36-upper-right-gate` | `d1a5fe741fc703458b5d0830e620cd6ac6f070b9` |
| Upper-right Debuff appearance (#103; includes #99 and #121) | `codex/buffs-debuffs-native-debuffs` | `ab6a3fd8e2d0c18416717a0c59e3c675fc203bac` |
| Upper-right shared BFI mover (#127; includes #103) | `codex/upper-aura-debuff-follower` | `625144a3aab87c95005de6b1930caf9d765a3e59` |
| Upper-right native Debuff container (#143; includes #127/#103) | `codex/upper-aura-native-debuff-container` | `d88d674e7f1e1401c57bdc6d2ad6c37da60e4818` |
| Tooltip/status safety (#85) | `codex/combat-secret-tooltip-fixes` | `b13a19842e7db7c19a447a97c009a4c968757d18` |
| Native AuraButton tooltip skin (#118) | `codex/native-aura-tooltip-skin` | `7e917de6bb31d345f5fa7177140a084b530ee013` |
| Secret identity (#100) | `codex/unitframe-secret-identity` | `b8e1671ed8a1c11657416357875f9c8277051654` |
| Unit Frame options preview safety (#114) | `codex/unitframe-options-preview-aura-safety` | `296667d9681c07ab1a7293ea8922561c44e9cb08` |
| Objective Tracker taint boundary (#115) | `codex/objective-tracker-taint-boundary` | `b829efaffd45939e268cfa6c0c1e167ce17312fe` |
| Secret pixel geometry (#116) | `codex/style-secret-pixel-geometry` | `3eb6642f82e81c1fb08a725727e80d0d2a1c566e` |
| Player Spells combat deferral (#117) | `codex/player-spells-combat-style-deferral` | `50b3c30a17a05c8d82279676d248f3bc48da5d2c` |
| Character unit-stat safety (#119) | `codex/character-frame-unit-stats-safety` | `d555ad11c49cb8e598340e7d273778d33f285b39` |

Test in this order:

1. Test AF #25 alone, including effective max-level compatibility, duration
   abbreviations, native duration-color curves, and secret identity.
2. Test #122 independently from current `master`. Give Buffs and Debuffs
   visibly different values and verify both slow and rapid selection changes
   bind the chosen pane immediately.
3. Test the policy, spec, lifecycle/controller, provider/counter, and #90
   supported-filter PRs in isolation. Test #123 next for plain aura labels and
   spell-list action hints, then test refreshed #101 spell colours and #102
   presentation hardening. Test AF #36 with #136 next, followed by #137's
   Blizzard healer-spell importer.
4. Test the eight unchanged unit-frame integration leaves independently. Then
   test AF #37 with #138 for Party, followed by AF #37 with #139 for Raid and
   a Party ancestry smoke test. Finally test AF #39 with #142 for native
   square Debuff colours on all unit-frame rows, including Party's player
   child. Do not install closed #84 or #87.
5. Test #134 after #137 and before #110. Verify allied-player class colours,
   non-player reaction colours, hostile-player custom-white defaults, and a
   public-to-restricted-to-public pooled-nameplate transition. Then test
   #112's enemy nameplate Debuffs migration independently after #110.
6. Test the upper-right foundation, controller, Buffs, options, and
   forbidden-button branches in their PR order.
7. Test #103's ordinary Debuff appearance controls with AF r33, including the
   neutral square outline and exact restoration of Blizzard's rounded border
   when styling is disabled. This is a historical leaf check, not the terminal
   #143 presentation.
8. Test AF #30's mover guard independently in Challenge Mode, then test #127
   with AF #25 after #103. Confirm the restored BFI Buff Frame mover owns one
   fixed seam, custom Buffs grow left/up, and ordinary `DebuffFrame` follows
   directly beneath it. Test combat refusal, Blizzard Edit Mode release and
   reattachment, native fallback, private-aura anchors, and
   `DeadlyDebuffFrame` independently.
9. Test #143 after #127 twice from clean folders: the pinned pre-r39 AF #25/r38
   snapshot first proves the rounded Blizzard Debuff fallback while retaining
   AF #30's mover guard; current AF #25/r39 then activates the terminal
   combined native `HARMFUL` row. Run its complete geometry, cap, suppression,
   colour, mover, Edit Mode, combat, hover, roleset, vehicle, private/deadly,
   and counter matrix. #143 enables Blizzard-owned native tooltips but does
   not contain #118; judge the BFI-skinned tooltip shell only on the final
   aggregate that carries #118.
10. Test AF #26's focused regression, then test its square border in the
   AF #25/BFI #110 combined pair because #110 now correctly requires AF r36.
   Test AF #39/BFI #142 for the supported native square-colour path, then
   repeat that exact Debuff-border matrix across every harmful unit-frame row
   on the final aggregate.
11. Test AF #36 with #136/#137/#134/#110 and #112 as two clean sibling paths.
    Test AF #37 with #138, then #139, and finally AF #39 with #142 as the
    group-frame path. Use AF #27 with #121/#103 for the historical
    upper-right styling path, then current AF #25/r39 with #143 for the
    terminal upper-right path. Run the
    single-graphical-timer and duration-threshold matrices below on unit-frame
    groups and the graphical-timer matrix on nameplate and upper-right groups,
    then repeat them on the final aggregate.
12. Test #85 and then #118 independently. For #118 alone, disable BFI Unit
   Frames and exercise Blizzard's native TargetFrame AuraButtons; the final
   aggregate carries #118 plus #143 for the upper-right Debuff tooltip-shell
   check.
13. Test #114, #115, #116, and #117 independently against their documented
   reproducers below.
14. Test #119 independently after a reload. In restricted content, require
    the custom Movement Speed row to be absent while Blizzard's supported
    tertiary Speed row and BFI's presentation styling remain.
15. Test #124 independently. The first Achievement UI load must occur during
    Challenge Mode combat; then exercise search, filter visibility, and
    comparison-mode layout as described below.
16. Install AF #25 at `0a04ecf055b888bb750b16df1cf623e4d927a162`
    and the current head of disposable BFI #91 as clean, complete folders.
17. Run the 12.1 gates below in order.

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
This is a hypothetical spell-colour expansion budget, not the shipped
Party/Raid base topology.

The fixed #138/#139 base contributions, unchanged by #142's presentation-only
border contract, are:

- Party: 15 containers (10 AF-created plus 5 secure-header seeded), 10 aura
  groups, 5 dispel slots, and 105 initial reservations.
- Raid: 120 containers (80 AF-created plus 40 secure-header seeded), 160 aura
  groups, 40 dispel slots, and 1,640 initial reservations.
- Together, with no other native owners: 135 containers, 170 groups, 45
  slots, and 1,745 reservations.

Scope, dispel-type, config-mode, provider, roster, and clean-unit retargeting
must not grow those contributions. Dispel appearance, alpha, blend mode, and
Health Bar frame level are construction-owned and require reload; quiescing a
stale presentation before reload must not allocate a replacement.

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

#### BFI movers with unavailable Challenge geometry

1. Install AF #30 at
   `fa0a7b7e4be152da8f962bd74bc5b18238020976`, or the exact AF #25
   aggregate head that contains it.
2. Reload in an active Challenge Mode dungeon while out of combat and open
   BFI mover mode. Repeat during combat; the movers must remain closed and a
   localized combat warning must be printed.
3. Require no `RoundToDecimal` nil arithmetic, secret-value arithmetic or
   comparison, Lua error, blocked action, or new taint.
4. When a mover's point, dimensions, edges, center, or scale are unavailable,
   its mover or position editor must fail closed without changing frame points
   or SavedVariables. Ordinary movers whose required values remain public must
   continue to work.
5. Open movers out of combat, begin dragging, and enter combat. The mover UI
   must close immediately, stop its update script, avoid saving or restoring
   protected owner points, and remain closed after combat until reopened.
6. Leave the restricted context and verify ordinary movers can still be
   shown, moved, saved, and undone.

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
3. On the final #91 aggregate, repeat on upper-right native Buffs and #143's
   combined ordinary/private Debuff row, plus any boss AuraButton Blizzard
   exposes. The shared shell may match BFI, but the private or boss button,
   anchor, contents, and update path must remain unchanged. On isolated #143,
   where #118 is absent, Blizzard's default shell is expected.
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
- With current AF #25/r39 and #143, confirm upper-right Buffs and the combined
  ordinary/private Debuffs row use native containers. The pinned AF r38
  fallback pair is the only intentional upper-right harmful legacy backend.
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
For #143's upper-right native Buffs and Debuffs, which intentionally use a
fixed Clock style, verify the ordinary Buff group, both temporary-weapon-
enchantment positions, and the combined `HARMFUL` group show only the circular
swipe. The isolated #103 historical leaf keeps Blizzard's legacy ordinary
Debuff duration presentation and remains outside this selector matrix.

Inspect the full duration: immediately after application, below one minute,
across the minute boundary, and near expiration. No native update may reveal
an AF-created second carrier that was hidden only at initialization.

Check every locale available to the tester. Long explanations must wrap and
remain readable; no help text may be clipped, including the native-category
and spell-ID restrictions. Duration text must abbreviate seconds, minutes,
hours, and days correctly, with permanent auras blank.

#### Native low-time duration colour

These controls change duration-text colour; they do not include or exclude an
aura. Mode, threshold, and colour are native-button construction settings, so
reload when BFI requests it before judging the result.

1. On a visible Target Buff or Debuff row, enable Duration Text, choose a
   conspicuous normal colour, and choose a different conspicuous low-time
   colour.
2. Select **Off**. Test both a short timed aura and a much longer timed aura.
   Both must retain the normal colour for their complete duration.
3. Select **Seconds** with a five-second threshold. Both fixtures must change
   at the same remaining time, regardless of their original duration.
4. Select **Percent** with a 50% threshold. Each fixture must change halfway
   through its own duration, so the absolute remaining seconds differ.
5. Record just above, exactly at, and just below each threshold. The threshold
   colour applies below the configured value; the normal colour owns the exact
   threshold. Record the build and video evidence if the client disagrees,
   because Blizzard documents Step curves without defining boundary ownership.
6. Import or edit a profile with both legacy Seconds and Percent flags enabled.
   Opening the pane must normalize visibly to Seconds, matching the historical
   seconds-first rule. The two rules must never appear active together.
7. Change mode, value, normal colour, and low-time colour outside combat and
   during Challenge Mode combat. The newest saved construction must apply at
   the legal reload boundary, with no Lua duration read, `OnUpdate` poll,
   forbidden-button access, or taint.
8. Repeat representative crossings in Mythic+, raid, arena, and battleground
   aura-secret contexts. Permanent auras remain blank and must not manufacture
   a threshold transition.

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

#### Blizzard healer-spell import

1. Enter a healing specialization, wait for Cooldown Viewer data to load, and
   open a native helpful Buffs row in **Show Only Listed Spells** mode. Confirm
   **Import Healer Spells** is enabled beside `+`.
2. In Blizzard's Cooldown Viewer Group Buffs page, use normal spell tooltips to
   record the current specialization's shown/default entries and its hidden
   entries. Include a desaturated unknown-talent entry when one is available.
3. Seed BFI's whitelist with a custom spell, an existing Blizzard entry, and a
   deliberate duplicate. Click **Import Healer Spells** once. The original
   table order and duplicate must remain; missing shown/default Blizzard IDs
   append in Blizzard order; hidden-by-default IDs must not be added. An
   unknown-talent entry is eligible and must not be discarded merely because
   the player has not learned it.
4. Click Import again. The whitelist, row allocation, reload state, and profile
   must not change. BFI must not call the legacy spell-existence lookup to
   decide whether an aura-only ID is valid.
5. Change Blizzard's Group Buff layout after importing. The saved BFI list must
   not change automatically; Import is a user-requested snapshot, not a live
   synchronization. Switch to another healing specialization and click Import
   to append that specialization's missing defaults.
6. Repeat in a damage/tank specialization, blacklist mode, a Debuffs row, and
   any non-native/read-only row. The importer must be hidden there. If the
   Blizzard catalog is unavailable or empty while an otherwise eligible pane
   is open, the discoverable button remains disabled and clicking it changes
   nothing.

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
classification must control the colour, including the `None`/red fallback;
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

#### Native unit-frame Debuff border colours

Run this section first on AF #39/BFI #142, then repeat it on AF #25/BFI #91.
This covers icon borders only; it is independent of the Party/Raid Health Bar
**Dispels** tint below.

1. For Player, Pet, Party, Raid, Target, Boss, Focus, TargetTarget,
   FocusTarget, and PetTarget Debuffs, enable **Border Color → Debuff Type**.
   Require BFI's complete square border with Blizzard's native Magic, Curse,
   Disease, Poison, and Bleed colours. Helpful Buff rows must not gain a
   Debuff-type border.
2. Apply Exhaustion, Well-Honed Instincts, or another known untyped/`None`
   harmful effect. Its icon must use Blizzard's ordinary red harmful colour,
   not a missing, neutral, black, or rounded border. BFInfinite must not
   identify the aura or read its type to produce that result.
3. Enable **Unit Frames → Party → General → Show Player**. Show the same
   player and harmful effect simultaneously on the standalone Player frame
   and Party's player child. The Party child must follow **Party → Debuffs →
   Border Color → Debuff Type**; it must not borrow the standalone **Player →
   Debuffs** value. Prove both directions by giving those settings opposite
   values, judging only after the requested reload, and then reversing them.
4. Disable **Debuff Type** for each representative owner and confirm its type
   border is absent without changing the aura filter, cooldown, duration,
   stack text, tooltip, or row placement. Re-enable it and confirm the native
   square colour returns after the required reload.
5. Treat the Debuff Type flag as construction-owned. A change must quiesce the
   applied row and produce one reload-required notice without allocating a
   replacement. Cancel leaves it quiesced; exact reversion before reload
   resumes the original container; confirmation/reload constructs the chosen
   mode exactly once.
6. With Party/Raid **Dispels** also enabled, an untyped red icon border must
   not by itself produce a typed Health Bar tint. Conversely, disabling icon
   **Debuff Type** must not disable an otherwise eligible Health Bar tint.
7. Repeat through dummy combat, Mythic+, raid, arena/BG, roster and target
   churn, secret-unit transitions, stationary hover, profile changes, and
   reload. Require no `AuraData`/UnitAura access, forbidden-object error,
   taint, duplicate border, rounded-atlas corner, or construction-counter
   growth beyond the one expected post-reload rebuild.

#### Party and Raid native dispel highlights

Run this section first on AF #37/BFI #138 for Party, then on AF #37/BFI #139
for Raid and a Party regression, and finally on AF #25/BFI #91. Disable Cell
or any other frame-colouring addon before judging ownership.

1. Open **Unit Frames → Party → Dispels** and **Unit Frames → Raid →
   Dispels**. The item must appear immediately after Buffs/Debuffs. A new
   profile defaults to enabled, **You Can Dispel**, all five types, **Bottom
   Gradient**, `0.5` alpha, and `ADD` blend mode.
2. Exercise every **Show When** scope with a known eligible harmful aura:
   **You Can Dispel** (`HARMFUL|RAID`), **Group Can Dispel**
   (`HARMFUL|RAID_PLAYER_DISPELLABLE`), and **Any Dispel Type**
   (`HARMFUL|DISPELLABLE`). The native filter, not addon Lua, decides whether
   a unit qualifies.
3. Toggle Magic, Curse, Disease, Poison, and Bleed one at a time, all together,
   overlapping in several combinations, and all off. A disabled type must not
   colour the frame. When several eligible auras overlap, do not assert which
   one wins; Blizzard's native `UnitFrameDebuff` ordering selects the tint.
4. Test **Bottom Gradient**, **Full Gradient**, and **Full Solid** with low,
   default, and high alpha and with `BLEND`, `ADD`, and `MOD`. The result must
   sit above the Health Bar but below text and icons, cover the expected area,
   and never capture targeting, clicks, or mouseover.
5. Enter BFI Config Mode before first construction and after live construction.
   The live native tint must turn off while exactly one synthetic,
   mouse-transparent tint represents the selected appearance. Leaving Config
   Mode restores the newest live unit without allocating another native
   container. Disabling the Health Bar hides both live and preview tints.
6. Treat enabled, scope, type selection, Health Bar enabled state, clean-unit
   retargeting, roster churn, and Config Mode cycles as live changes. Repeat
   each at least ten times without reload or construction growth.
7. Treat appearance, alpha, blend mode, and Health Bar frame level as
   construction-owned. After changing one, the applied tint must quiesce and
   exactly one reload-required notice must appear. Cancel leaves it quiesced;
   reverting to the exact applied construction resumes the original container;
   confirming reload rebuilds the requested construction once. Repeat through
   direct edits, Reset, profile paste/switch, and preset application.
8. Test migration for Party and Raid. An existing profile with no legacy
   feature stays disabled. Legacy player-dispellable stays enabled with the
   Player scope. The retired broad/unrestricted mode migrates disabled with
   the nearest Any scope. Legacy appearance becomes Full Solid; valid alpha
   and blend mode persist; the old nested Health Bar setting is removed.
9. Repeat scope/type/appearance checks through Party/Raid join, leave,
   conversion, subgroup and role changes; cross-faction, phased, offline,
   dead/resurrected, and duel units; dummy combat, Mythic+, raid, arena/BG;
   secret-unit transitions; reload; and stationary hover.
10. Keep the private-aura boundary explicit. The managed Debuffs row is the
    authorized general private-aura presence/icon path when Blizzard permits
    one. BFI creates no separate private anchor. The tint is not a general
    “private aura exists” signal: it may react only when Blizzard authorizes
    and classifies that aura through both the selected native scope and dispel
    type. A visible private icon without a tint can be correct, and no tint
    says nothing about presence. Never use `showDispelIcon`, geometry,
    visibility, logs, or counters to infer private state.

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
Blizzard authorizes through their inseparable source. The managed Debuffs row
is the general authorized presence/icon path. A Party/Raid dispel tint may
react only when Blizzard's selected scope and type filters classify that aura;
it is not a private-presence indicator. BFInfinite must never log or expose
private identity, spell, duration, count, source, or the absence of a tint as
state.

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

#### Terminal ownership and fallback

- With current AF #25/r39, which contains AF #39, #143 owns one native
  upper-right Debuff container as well as the existing supported Buff
  container. The Debuff container gives
  Blizzard one declarative `HARMFUL` group; BFI never receives or reads
  `AuraData`, aura identity, dispel type, privacy, duration, or visibility.
- The 12.1 public container source combines ordinary and private harmful
  auras. There is no supported public/private source filter or private
  reservation. Both sources therefore share the same native sort and the
  user-configured `icons per row * rows` cap. The default is `25 * 1 = 25`,
  which exceeds the pinned legacy capacity of 16 ordinary plus six private
  icons. It does not guarantee private priority when more than 25 candidates
  compete; a deliberately lower cap can exclude either source according to
  Blizzard's native ordering.
- The default Debuff group uses 26-by-26 buttons, exactly four pixels of
  horizontal spacing, six pixels between wrapped lines, right-to-left growth,
  downward wrapping, and a shared right edge with Buffs. AF r39 delegates the
  complete square Magic, Curse, Disease, Poison, Bleed, and untyped/`None` red
  border to Blizzard's native AuraButton presentation.
- Only after the custom group is fully constructed and enabled may #143 hide
  `DebuffFrame.AuraContainer` and the exact pinned set of six
  `DebuffFrame.PrivateAuraAnchors`. The frame root remains alive as the shared
  positioning seam. A missing, sparse, extra, reparented, or mismatched anchor
  identity fails native before suppression. `DeadlyDebuffFrame` remains a
  separate Blizzard-owned warning, with independent position, icon/text,
  sound, visibility, and lifetime.
- Under the pinned pre-r39 AF #25/r38 snapshot, the harmful custom pane does
  not register. That snapshot includes AF #30's mover guard, so the fallback
  isolates the r39 capability gate rather than an unrelated mover dependency.
  It keeps Blizzard's ordinary container and all six private anchors active,
  and retains Blizzard's rounded, native-coloured border atlas on the fixed
  16 ordinary buttons. Four-pixel spacing, the combined cap, and square native
  borders are r39-only assertions. A suppression or construction failure on
  r39 must fail back to the same complete Blizzard presentation.
- #143 enables Blizzard-owned native tooltips but does not contain #118. Test
  native tooltip ownership on #143 alone; judge BFI's static tooltip outer
  shell only on the final aggregate, where #118 is present. Tooltip content,
  anchor, shown state, and lifetime remain Blizzard-owned in both cases.

#### Shared position and lifecycle

- The restored **BFI Buff Frame** mover remains the only BFI position owner.
  Custom Buffs anchor at its bottom-right and grow left/up. Outside combat,
  #127 anchors `DebuffFrame.TOPRIGHT` to the mover holder's `BOTTOMRIGHT` at
  `(0, -5)`; #143 anchors its own plain holder to `DebuffFrame.TOPRIGHT` and
  grows left/down. The two rows therefore travel together and share a right
  edge without reparenting either native container or any AuraButton. If Buffs
  are disabled, custom Debuffs follow Blizzard's saved `DebuffFrame` position
  and expose no independent mover.
- The mover saver must canonicalize a legacy
  `{ point, relativePoint, x, y }` value to `{ point, x, y }` and clear index
  4. Both panes offer **Open BFI Edit Mode** while the shared controller is
  active. Movement and protected follower attachment occur only outside
  combat, after the pinned access and saved-anchor preflight succeeds.
- On `EditMode.Enter`, #143 hides its custom Debuff holder, releases the
  ordinary Blizzard container for Edit Mode examples, and keeps all six
  private anchors hidden to match Blizzard's preview. #127 simultaneously
  restores Blizzard's saved root anchor. On the next tick after
  `EditMode.Exit`, the newest pending settings and player/vehicle unit apply,
  then the ordinary container and six anchors are suppressed again and the
  same custom container resumes. No Edit Mode cycle may allocate another
  container, group, enchantment, or initial reservation.
- Both custom holders use the Blizzard `buffs` roleset. A client scene,
  minigame, pet battle, spectator/commentator mode, or other Blizzard mode
  that filters this roleset must hide the rows authoritatively. BFI must not
  fight the roleset, read back visibility, or rebuild when the role returns.

#### Live matrix

1. Run the pinned pre-r39 AF #25/r38 fallback with #143 before installing the
   current aggregate. Confirm the ordinary container, fixed 16 ordinary
   buttons, and six independent private anchors remain available; the rounded
   native border remains; no custom harmful controller/state, suppression,
   four-pixel promise, duplicate, Lua error, or taint appears.
2. Clean-install current AF #25/r39 with #143. At default settings, measure
   adjacent 26-by-26 Debuff icons from edge to edge and require exactly four
   pixels between them. Compare the final right edge against Buffs with one
   and several rows, with main-hand and off-hand temporary enchants present.
   Debuffs wrap down; Buffs continue to wrap up.
3. Open **BFInfinite → Buffs & Debuffs → Debuffs**. Confirm the enabled size,
   sorting, horizontal/vertical spacing, icons-per-row, row-count, stack text,
   and duration-text controls bind only to Debuffs. The cap tooltip/status must
   say in plain language that ordinary and private Debuffs share one native
   icon limit. `Separate Own` remains unsupported and must restore Blizzard
   Debuffs rather than widen the native filter.
4. Test Magic, Curse, Disease, Poison, Bleed, and a known untyped effect such
   as Exhaustion or Well-Honed Instincts. Require one complete square native
   border in the correct Blizzard colour, including red for `None`; never a
   neutral substitute, rounded corner underneath, duplicate border, or Lua
   classification.
5. Move **BFI Buff Frame** through several screen positions outside combat,
   close mover mode, and reload. Buffs and Debuffs must remain directly
   stacked, right-aligned, and saved. Disable Buffs and confirm Debuffs follow
   Blizzard's saved position without an independent BFI mover; re-enable Buffs
   and confirm the shared seam returns.
6. Begin a mover drag and enter combat. The overlay must close without saving
   or mutating protected points and must not reopen automatically. Attempting
   to open movers in combat prints the localized warning, changes no
   SavedVariables, and leaves the options panel usable.
7. Enter Blizzard Edit Mode before first custom construction and again after
   both rows are live. Confirm the custom Debuff row is absent, Blizzard's
   ordinary examples are visible, and all six private anchors stay hidden.
   Change Debuff tuning, disable/re-enable it, change player/vehicle state, and
   make one construction-owned edit while Edit Mode remains open. Exit and
   require latest-request-wins behavior, one next-tick resume or one reload
   notice as appropriate, strict re-suppression, and no new allocation.
8. Repeat settings edits before combat, during combat, and while combat begins
   or ends around the queued operation. Same-construction spacing, sort, cap,
   enabled-state, and unit changes apply at the legal boundary. Button-style
   construction changes quiesce the old row and request one reload without
   allocating a replacement; exact reversion before reload resumes it.
9. Park the pointer over a visible native Debuff button and do not move it.
   Exercise enable/disable, spacing, sorting, cap changes, profile switches,
   Edit Mode entry/exit, combat transitions, roleset filtering, and
   player/vehicle retargeting. Recovery must not depend on pointer leave,
   tooltip dismissal, visibility reads, or a retry loop.
10. Exercise `player` to `vehicle` and back through
    `UNIT_ENTERED_VEHICLE`/`UNIT_EXITED_VEHICLE`, including a transition
    deferred by combat or Edit Mode. The same completed container must retarget
    to the newest unit, never briefly restore a stale unit, and never rebuild.
11. Exercise pet battle, minigame/client scene, spectating, commentator, and
    any available mode that filters the `buffs` roleset. Both custom holders
    follow Blizzard's filter together; returning to the ordinary role reuses
    them without using visibility as state.
12. At the default cap, generate as many simultaneous ordinary and authorized
    private harmful fixtures as the environment permits. Then set a visibly
    low cap such as three and create more than three competing candidates.
    Require one combined native row with no duplicates or blank reserved
    private slots. Do not require a private aura to outrank an ordinary aura,
    infer private absence from the visible subset, or increase the configured
    cap silently. Restore `25 * 1` afterward.
13. Generate ordinary, private, and deadly harmful effects together in
    Mythic+, raid, and PvP fixtures. Authorized private icons may participate
    in the combined row, subject to the same cap and sort; the six legacy
    private anchors must not duplicate them. `DeadlyDebuffFrame` must remain
    independently positioned and functional. BFI must not expose the private
    or deadly spell, source, count, duration, or absence as addon state.
14. With #118 present on the aggregate, hover ordinary and authorized private
    native Debuff buttons outside combat and in each restricted context. The
    static BFI tooltip shell should match other native AuraButtons while
    Blizzard retains content and lifecycle. Repeat without #118 on the clean
    #143 leaf and expect Blizzard's default shell, not a #143 failure.
15. Reload in a city and an active Challenge Mode dungeon, outside combat and
    during combat. Repeat mover alignment, Edit Mode, stationary hover,
    roleset, vehicle, crowded-cap, private/deadly, and settings mutations in
    Mythic+, raid, arena/BG, duel, cross-faction, and phased contexts. Require
    no `UnitAura` access, secret arithmetic, forbidden-object call, protected
    action, Lua error, duplicate, missing fallback, or taint.

### 10. Counters, leaks, errors, and taint

Capture these before and after the full run:

```text
/dump BFInfinite.modules.UnitFrames.GetNativeAuraRuntimeStats()
/dump BFInfinite.modules.UnitFrames.GetNativeAuraConstructionStats()
/dump AbstractFramework.GetCustomAuraContainerConstructionTotals()
/dump BFI_Target.indicators.buffs:GetNativeAuraState()
/dump BFI_Target.indicators.debuffs:GetNativeAuraState()
/dump BFI_Party.header[1].indicators.dispels:GetNativeDispelState()
/dump BFI_Raid.header[1].indicators.dispels:GetNativeDispelState()
/dump BFInfinite.modules.BuffsDebuffs.GetCustomAuraContainerState("buffs")
/dump BFInfinite.modules.BuffsDebuffs.GetCustomAuraContainerState("debuffs")
/dump BFInfinite.modules.BuffsDebuffs.AreNativePublicAurasSuppressed("debuffs")
/dump BFInfinite.modules.BuffsDebuffs.GetCustomAuraContainerConstructionStats()
/dump BFInfinite.modules.BuffsDebuffs.GetBlizzardDebuffStyleState()
```

These expose only tracked BFI/AF state; they do not inspect a native child or
aura.
The final runtime snapshot must satisfy
`runtimesCreated - runtimesDestroyed == liveRuntimes`. Require no incomplete
build, no stranded shell or reservation, no unexpected allocation after
no-op/live-tuning/provider/unit changes, `providerMode == "live"`, and
`reloadRequired == false`. Verify the Target state `metrics` against the
explicit partition fixtures above. Measure AF's global, cumulative ledger as
a before/after delta. The isolated Party contribution must be exactly
`15 containers / 10 groups / 5 slots / 105 reservations`; Raid must be
`120 / 160 / 40 / 1,640`; and both together, with no other native owner, must
be `135 / 170 / 45 / 1,745`. On the full aggregate, subtract the baseline
because Target, nameplate, and upper-right owners also contribute. Build
attempts must equal completions, `incompleteBuilds` and stranded shells or
reservations must be zero, and the expected group/slot/reservation totals must
match AF's added totals. Target totals must include all prebuilt relation
variants while only one relation is active. Nameplate totals may grow only
when Blizzard creates a new cached plate root; token retarget, reaction
changes, settings tuning, and provider transitions must reuse that root's
completed carrier.

After the initial Party/Raid build, perform at least ten scope changes, type
map changes, Config Mode cycles, roster transitions, and secret-unit retargets.
Neither BFI nor AF construction totals may grow. A construction-owned dispel
change must set `reloadRequired`, quiesce the old tint, and allocate nothing;
exact reversion before reload must resume the original container. After one
reload, counters restart and rebuild the fixed topology exactly once.

Measure #143 first with Buffs disabled so its Debuff contribution is isolated.
The first successful r39 build must add exactly `1` build attempt, `1` build
completion, `1` AF container, `1` group, `0` item enchantments, and `10`
initial frame reservations. `incompleteBuilds`, `strandedNativeShells`, and
`strandedInitialReservations` must remain zero. With Buffs and Debuffs both
built from clean counters, the combined upper-right totals are exactly `2`
attempts/completions, `2` AF containers, `2` groups, `2` item enchantments,
and `22` initial reservations. On the aggregate, record and subtract the
pre-existing unit-frame/nameplate baseline before comparing these deltas.

Outside Edit Mode, the r39 Debuff state must be complete and active on the
current `player` or `vehicle` unit, with `editModeSuspended == false`,
`reloadRequired == false`, and the tracked suppression ledger true. During
Edit Mode it must be inactive with `editModeSuspended == true` and suppression
false; exit must restore the active state and suppression without changing any
construction total. Repeat at least ten combat queues, stationary-hover
changes, spacing/sort/cap tuning cycles, enable/disable cycles, profile
changes, roleset filter cycles, player/vehicle retargets, and Edit Mode
entries/exits. None may add a container, group, enchantment, reservation, or
build attempt. A construction-owned edit may request reload but may not
allocate before that reload.

On the clean pre-r39 AF #25/r38 fallback,
`GetCustomAuraContainerState("debuffs")` must be nil and the suppression ledger
false. With fallback styling enabled, `GetBlizzardDebuffStyleState()` must
report `active == true`, `styledButtonCount == 16`, and
`snapshotsCreated == 16`; repeated live settings and combat deferral must not
grow snapshots. On the r39 custom path, that legacy style state must be
inactive with zero styled buttons. Disabling or failing the custom path must
restore the ordinary container and all six private anchors, never leave a
partially suppressed hybrid.

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
- friendly nameplate Debuffs, nameplate Buffs, or nameplate Crowd Controls
  appearing in #112; Global Colors affecting a nameplate row; a second build
  on nameplate pool reuse; or a settings change constructing an untouched row;
- Party/Raid external seeded content visible behind a hidden plain holder;
- a Party/Raid dispel tint capturing clicks, drawing above text/icons, staying
  live behind Config Mode's synthetic preview, or remaining visible when its
  Health Bar is disabled;
- scope/type tuning, Config Mode, roster churn, or clean-unit retargeting
  growing Party/Raid containers, groups, slots, or reservations;
- appearance, alpha, blend mode, or Health Bar frame level applying as a live
  structural mutation; failure to quiesce pending-reload tint; more than one
  reload notice; or exact construction-key reversion failing to resume it;
- a dispel tint, `showDispelIcon`, visibility, geometry, or counter being used
  as a general private-aura-presence signal; a dedicated BFI private anchor;
  or duplication of the managed Debuffs presence/icon presentation;
- an untyped/`None` unit-frame Debuff such as Exhaustion missing Blizzard's
  red square border while **Debuff Type** is enabled; any typed category using
  the wrong native colour; a rounded or duplicate unit-frame Debuff border;
  or a helpful Buff receiving a Debuff-type border;
- Party's optional player child borrowing the standalone Player Debuff Type
  setting instead of Party's setting; changing icon Debuff Type changing the
  independent Health Bar Dispels eligibility (or the reverse); or a
  construction-owned border change applying live, allocating before reload,
  or growing counters after the one expected reload rebuild;
- missing category, duplicate aura, partial color fallback, inferred spell
  family, or a listed ID using the wrong exact RGBA;
- more than one graphical duration display on a native AuraButton, including
  a circular swipe beneath Vertical/Block Vertical or a vertical fill beneath
  any Clock style;
- a low-time duration mode that does not change text colour, Seconds and
  Percent active together, a Seconds rule behaving as a percentage (or the
  reverse), the exact threshold taking the low-time colour, or any Lua read or
  poll of opaque remaining duration;
- the healer importer deleting, reordering, or deduplicating existing entries;
  importing a Blizzard hidden-by-default entry; omitting an eligible unknown
  talent solely because it is unlearned; mutating on a second click; syncing
  without a click; or appearing for a non-healer, blacklist, Debuffs, or
  non-native row;
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
- #143 activating its custom harmful pane below AF r39, failing to activate it
  when the complete r39 capability and an enabled/supported Debuff config are
  present, or suppressing any Blizzard harmful presentation before the
  replacement group is complete and enabled;
- suppression of anything other than `DebuffFrame.AuraContainer` plus the
  exact pinned six private anchors; accepting a missing, sparse, extra,
  reparented, or identity-mismatched anchor topology; leaving any of those
  seven legacy visuals visible behind the active combined row; failing to
  restore all seven on disable/fallback; or touching `DeadlyDebuffFrame`;
- hooking a Blizzard harmful/private/deadly script or update method; reading
  an ordinary or private button's aura, identity, privacy, active state,
  visibility, geometry, or tooltip state; creating a private-only group,
  reservation, slot, or inference path; or claiming that a finite cap gives
  private auras priority;
- a missing/non-saving BFI Buff Frame mover, a saved four-field position that
  is not canonicalized, Buffs and Debuffs losing their shared right edge and
  five-pixel inter-row seam, or adjacent default Debuff icons using anything
  other than exact four-pixel horizontal spacing;
- a default combined Debuff cap below 22, a low user cap being silently
  widened, ordinary/private candidates rendering in duplicate or in reserved
  blank slots, or any addon assertion about which source must win the shared
  native sort/cap;
- any `DebuffFrame` anchor mutation in combat, failure to release its anchor
  to Blizzard Edit Mode, failure to reattach after exit, failure to restore
  Blizzard's saved anchors/native Buff and Debuff fallbacks, private anchors
  becoming visible in Blizzard Edit Mode, repeated native allocation, or
  calls into Blizzard aura/Edit Mode update methods;
- any read of `DebuffFrame` geometry, visibility, hover, protection, button,
  or aura state; any addon-side private-aura classification or dedicated
  private styling/positioning; or any `DeadlyDebuffFrame` styling/positioning;
- fighting the `buffs` roleset, rebuilding on roleset hide/show, stale
  `player`/`vehicle` assignment after a deferred transition, or construction
  growth from hover, combat, Edit Mode, tuning, profile, or unit changes;
- a mover `RoundToDecimal` nil error, secret-geometry arithmetic, mutation of
  a mover owner whose required geometry is unavailable, a mover remaining
  interactive in combat, or an absent combat warning when opening is blocked;
- failure to restore the complete ordinary-plus-six-private Blizzard Debuff
  presentation when custom Debuffs are disabled or fail native;
- `Separate Own`, arbitrary Lua filtering, or an upper-right Buff Arrangement
  control being enabled; enabled Debuff layout controls failing to update only
  their own custom row; or missing plain-language shared-cap copy;
- BFI reading or mutating `PAPERDOLL_STATCATEGORIES`, adding the dormant
  `MOVESPEED` row, formatting or deriving a restricted unit-stat value, or
  branching on a stat row's visibility;
- clipped or unwrapped settings explanations;
- any r39-capable 12.1 native frame silently using the legacy backend; the
  documented #143 AF r38 harmful fallback is intentional and must remain
  complete.
