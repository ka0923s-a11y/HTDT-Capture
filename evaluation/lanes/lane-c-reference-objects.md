# lane-c — reference objects (#268)

Protocol revision: **v2** (fixtures/metrics/decision sections filled; v1 was the initial scaffold)

iOS 27 `.referenceobject` recognition as equipment/fixture pose evidence. A match lands as a persisted `ReferenceObjectPoseObservation` in the capture bundle — never as equipment identity, and never overwriting raycast/orientation/geometry evidence. The physical-benchmark numbers in this lane are **device-gated**: they need iPhone-class hardware on iOS 27 (target: iPhone 17 Pro). Software-side behavior (selection policy, observation document, advisory provenance, evidence-link acceptance) is verified by `Tests/HTDTCaptureCoreTests/ReferenceObjectCaptureTests.swift` on macOS.

## Fixtures

Physical ground truth comes from staged objects, not house scans:

- `fixture-panel-01` — mounted flat panel (detection role): the canonical stationary fixture. USDZ scanned from the panel itself; measured dimensions on file in `tools/reference_object_training/training-manifest.json`.
- `fixture-cabinet-01` — freestanding cabinet (detection role): larger stationary object, tests scale sensitivity and view-angle coverage.
- `prop-handheld-01` — movable box (tracking role): handheld object moved during a capture to exercise `trackingObjects` and the `isTracked` loss/resume lifecycle.
- `prop-lookalike-01` — visually similar negative example: present in the same scenes, declared in `objects_to_avoid`, expected to produce zero matches.
- `private_fixture: true` for any in-situ theater/equipment runs — commit the case manifest, protocol, and aggregates only.

Asset provenance for every case: the training manifest/digests (`xcrun createml objecttracker` args, source USDZ digest/revision, toolchain, negative examples, `REFERENCEOBJECT_STRIP_USDZ` decision, training mode standard|extended, viewing-angle config) — see `tools/reference_object_training/` — so every reference-object revision is explainable.

## Metrics

### Numeric (device)

- `pose_translation_error_m` — anchor translation vs surveyed object position, p50/p95.
- `pose_orientation_error_deg` — anchor rotation vs surveyed orientation, p50/p95.
- `pose_repeatability_m` / `pose_repeatability_deg` — variance of `T_world_from_reference_object` across re-detections of the same static object within and across sessions.
- `recognition_latency_s` — session start to first `ARObjectAnchor` add, per fixture.
- `recognition_rate` — fraction of staged presentations producing an anchor (trials ≥ 20 per fixture/condition).
- `tracked_loss_incidence` / `tracked_resume_rate` — `isTracked` flips per minute under occlusion/motion, and recovery fraction.
- `coordinate_drift_m` — pose deviation after an ARKit relocalization while the anchor persists.
- `frame_interval_ms` — AR frame cadence with detection vs tracking configured, vs baseline-0 (the power/processing cost of `trackingObjects` must be measured, not assumed).
- `thermal_timeline` — thermal state over a sustained tracking session vs baseline-0.
- `false_match_rate` — `prop-lookalike-01` match count per trial (target: 0; nonzero is a hard failure category, not a regression to average away).

### Rate/count (software-verifiable now, macOS `swift test`)

- Selection policy: dedupe/unknown-role/cap (>10 combined) rejection coverage — unit tests.
- Observation document: schema validation of `evidence/reference-object-observations.json`, lifecycle-event modeling (added/updated/tracking_lost/tracking_resumed/removed), `is_currently_tracked` never fabricated, no confidence scalar.
- Bounded persistence: record-cap truncation counted honestly (`truncated_observation_count`), restore-from-document for reopened drafts.
- Acceptance path: observation refs land alongside — never replacing — placement/orientation evidence in entity `evidence_refs`.

### Failure categories (hard)

- `authority_violation` — a match silently mutating equipment identity, or overwriting existing placement evidence. Any occurrence fails the run regardless of aggregate.
- `coordinate_integrity` — an observation persisted under the wrong coordinate-space authority after a reconfiguration reset, or a new space not minted when required.
- `identity_conflation` — asset-level match treated as entity-level identity without an operator accept.

## Decision scope

Adopt detection-mode fixture anchors as a **supplemental pose-evidence lane** if, on the device gate: recognition is reliable on the two fixture cases (≥ ~80% at reasonable presentation), pose repeatability is inside a few centimeters / a few degrees, `trackingObjects` is only adopted for genuinely movable objects, and the `isTracked`-loss lifecycle behaves as modeled (loss ≠ removal). Roll back or narrow (detection only, tighter viewing angles, extended training mode) on: false positives vs lookalikes, recognition too fragile for operator ergonomics, or power/thermal cost that measurably degrades the baseline capture. `experimental` is the correct status until the first real-device campaign completes — no aggregate is claimed before then.
