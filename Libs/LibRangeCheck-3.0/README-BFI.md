# LibRangeCheck-3.0

Embedded from WeakAuras/LibRangeCheck-3.0 revision
`53628079a07872e492016108000a58e17f976f90` (minor version 35).

BFInfinite replaces the library's direct `issecretvalue` call with
AbstractFramework's canonical `F.isValueNonSecret` wrapper. This preserves the
upstream Midnight unit-token cache fallback without introducing a second
secret-value predicate.
