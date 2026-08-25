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

Only the combined BFInfinite archive is published. The two intermediate packages are build inputs, not user-facing release assets.

## Manual updates

Users should replace both addon folders together. BFInfinite also retains its runtime minimum-version check so a partial or manual downgrade produces a clear compatibility warning.
