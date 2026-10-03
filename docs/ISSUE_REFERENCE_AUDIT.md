# Legacy Issue-Reference Disambiguation (issue #276)

## Collision classes found

| Class | Example | Resolution |
|-------|---------|------------|
| `issue #N` / `Issue #N` / `PR #N` provenance in `//`/`///` comments | `SharedARSessionController.swift` `issue #271` (orientation authority), `#268` (mesh-anchor diagnostics) | `issue bolph71656-ai/HTDT-Capture#N` |
| Bare `(#N)` parenthesized refs in comments | `(#364 §5)`, `(#297)` | `(legacy bolph71656-ai/HTDT-Capture#N)` |
| Doc-header and prose refs in `docs/*.md`, `README.md` | `Issue: #2`, `Related issues: #2, #3` | same qualified form |
| Python comment/docstring refs in `tools/` | `"""Issue #141: ..."""` | same qualified form |

## Why every bare `#N` is ambiguous

The recovered repository's issue numbering does not preserve legacy numbering:
migrated skeleton issues were numbered by creation order, so e.g. current
`ka0923s-a11y/HTDT-Capture#8` is the skeleton of legacy `bolph71656-ai/HTDT-Capture#56`,
and the new iOS-27 program occupies #266–#277. Every bare reference copied from
legacy history therefore resolves to an unrelated current issue.

## Normalization convention

- `#N` after `issue`/`Issue`/`issues`/`PR` → `bolph71656-ai/HTDT-Capture#N`.
- Any other comment `#N` → `legacy bolph71656-ai/HTDT-Capture#N`.
- Scope: `//`/`///` comment text in `Sources/`, `App/`, `Tests/`; all of
  `docs/**/*.md`, `README.md`; comments and docstrings in `tools/**/*.py`.

## Deliberately untouched

- String literals and emitted payloads (e.g. `supportMatrixJSON` descriptions
  inside `CaptureBundleSchemaRegistry.swift`, diagnostic message strings):
  these are shipped content whose bytes are digest-governed; rewriting them
  would change the emitted wire format, not just provenance.
- Localizable `.strings` values (user-facing content).
- `#\d+` occurrences that are hex colors, format specifiers, or numbers > 500
  (no legacy issue exists above ~#473).
- `Tests/**/ZZ*.swift` untracked test scaffolds.
