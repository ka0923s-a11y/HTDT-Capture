# Cross-Product Authority Ownership Contract (v1 draft)

Issue #405 — the single machine-distinguishable claim a Capture-
authored artifact makes, so the HTDT ecosystem never has to guess
what a record means.

Capture accumulates records that *look* alike — observations,
operator assertions, imported intent, derived diagnostics, field
reconciliation decisions — while representing very different claims.
Without an explicit class, downstream consumers (HTDT acquisition,
review tools, evaluation products) cannot tell an observation from a
project decision. This document is the shared contract; the type
`CaptureAuthorityClass` is its machine-readable form.

## 1. Authority classes

| Class | Claim | Examples | Owner after promotion |
|---|---|---|---|
| `observed` | Direct field observation | Label photo, visible cable endpoint, setting read-back, measured dimension, captured geometry | Capture field record |
| `operator_attested` | Human assertion based on field inspection | "This surface is gypsum drywall", "this is Front Left", operator type classification | Capture field record — evidence, not universal project truth |
| `imported_reference` | Intent supplied by HTDT or another document | Planned target, expected instance, catalog snapshot, task-plan item, Mission requirement | HTDT — never becomes observed merely because Capture displays it |
| `capture_derived_diagnostic` | Derived from acquisition evidence to help the operator | Coverage/blur/legibility warnings, frame-usability signal, evidence image quality assessment, registration residual, quality readiness | Capture diagnostic output — derived, not raw evidence, not a project decision |
| `field_reconciliation` | A bounded user decision local to the field workflow | Keep-both or merge confirmation, authority selection between two records | Capture field decision — retains both source records plus the explicit user confirmation |
| `project_authority` | Project/design/evaluation authority | Scene model, catalog definition, plan, evaluation result | HTDT — Capture does not create these |

Every Capture-authored artifact identifies exactly one of the first
five classes; the sixth exists in the vocabulary so cross-product
contracts can name the class Capture never authors. New cross-product
artifacts MUST pick a class from this vocabulary rather than growing
per-feature provenance spellings.

## 2. Ownership after promotion

- Imported intent remains `imported_reference` after Capture displays,
  annotates, or verifies against it; Capture may *confirm or deny* it
  but cannot turn it into an observation.
- Capture field records (`observed`, `operator_attested`,
  `field_reconciliation`) are authored in the field and reconciled
  downstream — HTDT owns their canonical interpretation once
  promoted, but the records themselves remain Capture-authored
  evidence.
- `capture_derived_diagnostic` artifacts are recomputed
  convenience/quality output: they never assert canonical geometry,
  evidence, or semantics, and a new algorithm version yields a *new*
  derived record — never a rewrite.
- `project_authority` records are read-only inputs to Capture
  (plans, catalogs, profiles); Capture never emits them.

## 3. Issue-specific bindings

**#403 — equipment identity bridge.** `same_physical_equipment` is an
`observed`/`operator_attested` claim asserted by the field app: one
spatial entity and one `inventory_item:` record describe the same
physical installed unit. Identity is equivalence, never inferred from
label/model/proximity equality. Conflicts surface through the review
surface (`PhysicalEquipmentReview`) as advisory findings for operator
resolution — never automatic merges.

**#407 — evidence image quality preflight.** The image-quality
assessment is `capture_derived_diagnostic`: bounded, on-device, per
exact image, recomputed per retake. It is deliberately distinct from
recognition confidence, catalog-match confidence, and operator
confirmation, and it never blocks finalization nor asserts semantic
verification.

**#333 — semantic relation authority.** Relation records carry their
own `provenance_class`, `verification_state`, and `evidence_refs` —
relation provenance is independent of the provenance of either
endpoint (an `imported_reference` plan may assert a relation between
two `user_annotation` entities). `member_of_rack` from an
`inventory_item:` subject is the canonical rack-membership claim;
`host_rack_entity_id` on the inventory record is its legacy
denormalized convenience read, validated to agree at commit when both
are present.
