# BFInfinite working agreement

Read `CONTRIBUTING.md` before changing first-party Lua. Its secret-value,
shared-widget, evidence, and validation rules are mandatory.

BFInfinite consumes AbstractFramework. Reusable widgets and the canonical
secret-value helper belong in AbstractFramework; do not fork them here.

Before handing off a change, run:

```sh
./scripts/lint.sh [changed Lua files...]
```
