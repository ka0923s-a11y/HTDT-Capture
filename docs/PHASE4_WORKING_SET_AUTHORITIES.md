# Phase 4 Working-Set Annotation and Measurement Slice

Date: 2026-09-20  
Issue: legacy bolph71656-ai/HTDT-Capture#5

## Purpose

The typed Phase 4 authorities now have a deterministic persistence boundary into
the same mutable Capture Bundle working revision used by RoomPlan, ARMesh and
frame evidence.

## Deterministic packages

`AnnotationEvidencePackageBuilder` sorts entities by stable entity UUID and
writes:

`annotations/entities.json`

`MeasurementEvidencePackageBuilder` sorts measurements by stable measurement
UUID and writes:

`annotations/measurements.json`

Both builders encode with sorted JSON object keys and immediately decode the
bytes back into the typed authority before the package can be persisted.

## Coordinate authority

Every spatial annotation in one persisted collection must share one
`coordinate_space_id`. That authority must match the working revision's
RoomPlan/mesh/frame coordinate authority when one is already established.

Measurements with an explicit spatial coordinate authority are subject to the
same rule. Non-spatial scalar measurements remain valid without inventing a
coordinate identity.

A mismatch fails closed; annotation/measurement evidence is not silently
reprojected.

## Quality completeness

Persisted entities contribute stable quality keys:

- speakers: `speaker:<CHANNEL_ROLE>`;
- other entities: `<entity_type>:<label>`.

Persisted measurements contribute their exact `quantity_type` tokens.

These sets now feed the existing `CaptureQualityRequirements`
annotation/measurement completeness gates.

The manifest-level provenance class identifies the authority file category.
Annotation collections must stay homogeneous (a mixed collection fails
closed). Measurement collections may mix per-record provenance so derived
and user-attested records coexist for conflict review (issue bolph71656-ai/HTDT-Capture#286): a
homogeneous measurement collection declares its exact class while a mixed
one declares `capture_app_derived` container authority — the manifest never
overclaims. Per-record provenance remains authoritative in every case.

## Integrity

The Phase 5 working-set preflight reopens and decodes both collection files and
requires exact equality with the typed collections held by the active working
revision. Post-write tamper therefore changes quality integrity to `fail`.

## Remaining Phase 4 work

This slice does not fabricate placement UI or physical evidence. Remaining work
includes:

- interactive raycast/mesh-hit-test placement;
- orientation-capture UX;
- equipment authority selection UX;
- user measurement entry/edit UX;
- real-device repeatability and spatial-accuracy evidence.
