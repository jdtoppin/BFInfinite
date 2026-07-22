# Contribution rules

These rules apply to first-party code. Code under `Libs/` is vendored and must
not be edited merely to make it conform.

## Secret-safe combat code

- The combat-capable secret-safe path is the only implementation path. Do not
  divide behavior into secret and non-secret branches.
- Never use `pcall` or `xpcall` in first-party code. An API failure is not a
  secret-value test and must not be used as control flow.
- Pass secret values only to Blizzard C-level APIs whose exact Retail contract
  explicitly accepts secret values. Never pass them to Lua operations or APIs
  without that contract.
- Never inspect, compare, concatenate, index, serialize, log, format, or replace
  a secret value with placeholder text.
- Never call or alias bare `issecretvalue`. First-party code calls only
  `F.isValueNonSecret(value)`, delegating to the one canonical implementation in
  AbstractFramework. Do not reinvent it per file.
- Prefer facts derived from non-secret inputs. For example, derive `isHarmful`
  from the caller's filter string when that is authoritative, rather than from
  a possibly secret aura field.

Existing violations listed in `.lint/policy-baseline.txt` are migration debt,
not approved examples. The policy check permits removals and rejects additions.

## Shared widgets

When a feature uses a widget, extend the appropriate shared AbstractFramework
widget or mixin. Do not copy or fork widget behavior inside BFInfinite.

## API evidence

Do not make API compatibility or secret-safety claims from memory or a summary
alone. Verify each claim against an exact Retail client artifact, such as
generated API documentation or FrameXML/UI source at a recorded build, tag, or
commit. The Gethe `wow-ui-source` mirror may be used when pinned to that exact
artifact. Warcraft Wiki API-change pages are useful indexes, but are not the
sole evidence for a code decision.

Record the build and source location in the relevant issue, PR, commit message,
or nearby maintenance comment when the reason would otherwise be unclear.

## Validation

Install `luacheck` locally and run `./scripts/lint.sh`. The script always checks
all Lua for parse errors and policy regressions. When Lua paths are supplied, it
also applies the warning configuration to those changed files. Pull requests
run the same checks.
