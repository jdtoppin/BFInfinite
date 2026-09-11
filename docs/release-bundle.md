# BFInfinite release bundle

BFInfinite and AbstractFramework remain independent World of Warcraft addons. A BFInfinite release combines their already-validated packages into one installable archive with exactly two sibling roots:

```text
AbstractFramework/
BFInfinite/
```

This preserves each addon's own TOC, namespace, lifecycle, and SavedVariables behavior. `BFInfinite.toc` keeps a hard `Dependencies: AbstractFramework` declaration so the game loads the framework first.

## Dependency lock

`.github/abstract-framework.lock` is the single source of truth for the bundled framework repository, full commit SHA, and declared release version. CI checks out that exact commit; a branch or tag is never used as a floating package input.

To update the bundled framework:

1. Choose a reviewed AbstractFramework commit from its default branch.
2. Update all three lock fields together.
3. Confirm the framework TOC version satisfies BFInfinite's runtime requirement.
4. Let both source verifiers and the composite-package tests pass before releasing.

## Package pipeline

The release workflow verifies BFInfinite, verifies the locked AbstractFramework checkout, and builds each addon with its own packaging metadata. It smoke-tests both source archives before combining them. The final verifier then requires:

- exactly the `AbstractFramework` and `BFInfinite` top-level folders;
- the required TOC in each folder;
- byte-for-byte preservation of every file from both source archives;
- no duplicate, case-colliding, unsafe, symbolic-link, or developer-only entries;
- provenance matching the locked AbstractFramework repository, commit, and TOC version.

Only the combined BFInfinite archive is published in BFInfinite releases. The two intermediate packages are build inputs, not user-facing release assets.

## Optional international fonts

The large `Noto_AP`, `Noto_Dolphin`, and `Unifont` binaries live in the separate
`AbstractFramework_Media` addon maintained in AbstractFramework's repository.
The regular bundle includes `Noto_AP_Latin`, a slim subset generated from the
existing Noto_AP font, and keeps every locale table and the small Latin fonts,
including plain `Dolphin` and `Accidental Presidency`. `Dolphin` is a Latin
face; `Noto_Dolphin` combines it with Noto Sans CJK. `Noto_AP` combines Noto
Sans CJK with Accidental Presidency. Unifont supplies broader Unicode coverage.

The English letters in the full Noto_AP have adjusted sizing/spacing compared
with plain Accidental Presidency. The subset retains their outlines, advances,
and vertical metrics, plus Latin accents and common punctuation, while removing
CJK coverage. New English-client configurations use this included base font.
Generation and glyph/metric checks run in CI with a pinned FontTools version;
the generation tools are not shipped to players.

The PR workflow builds the optional pack from the same locked AF commit and
links a separate download with its own checksum and source provenance. It is
excluded from the main bundle, so downloading routine core updates does not
download the font binaries again. For tagged releases, the optional pack is
distributed with the matching AbstractFramework release. These downloads are
manual installation assets; a separate media project in addon managers is a
future distribution step.

Install the optional folder alongside the other addons:

```text
Interface/AddOns/AbstractFramework/
Interface/AddOns/BFInfinite/
Interface/AddOns/AbstractFramework_Media/   (optional)
```

BFInfinite's optional dependency loads the media pack after AbstractFramework
and before BFInfinite. The pack registers the existing shared-media font
names. Without the pack, saved `Noto_AP` selections on English clients use
`Noto_AP_Latin`; other missing selections use the game's native font. The
saved choice is retained and resumes after installing/enabling the pack and
reloading. The font menu explains when the selected font is unavailable.
No language files move into the pack, and English remains the fallback locale.

## Manual updates

Users should replace both addon folders together. BFInfinite also retains its runtime minimum-version check so a partial or manual downgrade produces a clear compatibility warning.

When upgrading from the old full archive, replace the existing
`AbstractFramework` folder instead of extracting over it: otherwise the old
font binaries remain on disk. Keep `WTF`/SavedVariables intact. Enabling,
disabling, installing, or removing the optional pack requires a UI reload
(restart the client if it has not discovered the new addon folder).

## Font API evidence and manual checks

The fallback uses the existing `GameFontNormal:GetFont()` path and AF's shared
font setter. Reviewed Retail source: 12.1.0.68914 at
`jdtoppin/wow-ui-source` commit `d3915c78aba77a7a9be76acbfa35c674bbb6abe9`,
`Blizzard_APIDocumentationGenerated/SimpleFontAPIDocumentation.lua` (`GetFont`
returns a non-nil filename; `SetFont` requires a valid font asset) and
`Blizzard_Fonts_Shared/Mainline/Fonts.xml` (native alphabet-specific fonts).
This source check does not replace live rendering checks.

English-client selection uses Blizzard's `LOCALE_enUS` symbol, declared in the
same source revision's `Blizzard_LoadLocale/LoadLocale.lua`. Latin defaults are
not inferred merely from a client being non-CJK; other languages retain their
native fallback to avoid missing glyphs.

Before release, test clean settings and existing Noto selections on enUS and
zhCN with the pack absent, enabled, and disabled again. Check BFInfinite
labels, settings, chat, combat text, and player names after reload; confirm
the saved font selection survives and there are no missing-font errors.
