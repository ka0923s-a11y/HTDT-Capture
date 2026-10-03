# lane-d — iterative segmentation + spatial fusion (#269)

Protocol revision: **v2** (fixtures/metrics/decision sections filled; v1 was the initial scaffold)

iOS 27 `GenerateIterativeSegmentationRequest` as operator-seeded mask evidence for targeted-object geometry. A confirmed mask lands as a persisted observation in `derived/segmentation-observations.json` — always `.derived`, never canonical, and never overwriting sceneDepth/mesh evidence. The physical-benchmark numbers in this lane are **device-gated**: they need iPhone-class hardware on iOS 27 (target: iPhone 17 Pro). Software-side behavior (seed reprojection, bounded refinement, confidence filtering, persistence, orientation authority) is verified by `Tests/HTDTCaptureCoreTests/ObjectSegmentationTests.swift` on macOS.

Implementation landed in PR #285 (`Sources/HTDTCaptureCore/ObjectSegmentation*.swift`, `SharedARSessionController.swift` wiring, `docs/PHASE7_VISION_SEGMENTATION_FUSION.md`).

## Fixtures

- `obj-targeted-*` — the existing targeted-object fixture set (small/medium objects on support planes) reused so lane-d compares directly against the targeted-pass baseline.
- `seed-mode-matrix` — each fixture presented under all three seed modes (point / box / scribble) plus bounded included+excluded refinement rounds; refinement count and per-round wall time recorded.
- `orientation-pair` — identical seed performed in portrait AND landscape so the `viewRotationAngle` display-transform route is exercised against the legacy `displayTransform(for:viewportSize:)` fallback; reprojection error measured in both.
- `depth-coverage-map` — for each confirmed mask, the fraction of mask pixels with usable ARDepthData (supported-depth fraction) is recorded per depth-confidence tier; masks whose support comes only from mask-gated mesh are tagged as the non-LiDAR arm.
- `contamination-neg` — seeds deliberately placed on background/support plane: expected to yield either no mask or a mask that fails spatial support, never silent background geometry.
- `private_fixture: true` for in-situ runs — commit case manifest, protocol, and aggregates only.

## Metrics

### Numeric (device)

- `seed_reprojection_error_px` — seed point/box projected through the resolved display transform vs intended target, portrait and landscape arms.
- `mask_iou` / `boundary_f1` — mask vs hand-labeled ground truth per fixture and seed mode.
- `refinement_rounds` / `refinement_time_s` — count and wall time to operator-confirmed mask; `qualityLevel` trade-off measured across levels.
- `supported_depth_fraction` — usable-depth pixel fraction inside the mask, split by ARDepthData confidence tier (real `.low/.medium/.high` values, never assumed).
- `centroid_error_m` / `extent_error_m` / `footprint_error_m` — fused 3D geometry vs measured object dimensions, separated into sceneDepth arm and mesh-fallback arm.
- `contamination_rate` — fraction of contamination-neg seeds producing geometry on background/support plane (target: 0 accepted).
- `unresolved_rate` — seeds yielding no usable mask/depth after the refinement bound.
- `frame_interval_ms` / `thermal_timeline` — cadence and thermal cost of a segmentation-assisted pass vs baseline-0.

### Rate/count (software-verifiable now, macOS `swift test`)

- Seed→mask request construction: bounded included/excluded refinement sets, explicit qualityLevel, iteration caps enforced.
- Orientation authority: `viewRotationAngle` used only when SDK-qualified; legacy transform fallback recorded; the display-transform revision is stamped on every observation; SwiftUI orientation never consumed as extrinsics.
- Depth fusion honesty: real `ARDepthData.confidence` filtering (no fabricated confidence); mesh support mask-gated and tagged as fallback arm.
- Persistence: `derived/segmentation-observations.json` schema-validated, `.derived` role with source_refs to the persisted `segmentation_source` evidence frame; no mask ever lands canonical.

### Failure categories (hard)

- `authority_violation` — a mask mutating canonical evidence, entity identity, or geometry authority without an operator confirm. Any occurrence fails the run.
- `orientation_fraud` — seed applied under a display transform that does not match the captured frame orientation (the classic portrait/landscape seed-offset bug).
- `phantom_geometry` — 3D output emitted where mask pixels had neither depth-confidence support nor mesh support.

## Decision scope

Adopt iterative segmentation as a **supplemental derived mask-evidence lane** for targeted objects if, on the device gate: reprojection error stays sub-threshold in both orientations, IoU/boundary quality beats the unassisted targeted pass at comparable operator time, supported-depth fraction is high enough that the sceneDepth arm — not the mesh fallback — carries most masks, and contamination stays at zero. Roll back or narrow (box seeds only, LiDAR-only, tighter refinement bounds) on: orientation-fraud class failures, phantom geometry, non-trivial contamination, or frame/thermal cost that degrades the baseline capture. `experimental` remains the correct status until the first real-device campaign completes — no aggregate is claimed before then.
