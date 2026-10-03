# Vision Iterative Segmentation + Depth Fusion Record

Status: In progress  
Issue: legacy bolph71656-ai/HTDT-Capture#269 (parent legacy bolph71656-ai/HTDT-Capture#266)

## Implemented

- Operator-seeded iterative object segmentation on iOS 27 Vision
  `GenerateIterativeSegmentationRequest`, adapted in
  `Sources/HTDTCapturePlatform/ObjectSegmentationSupport.swift`:
  - point, box, and scribble seeds — a lasso-style UI drag is
    translated into the request's supported scribble representation
    (`CVPixelBuffer` mask at source-image resolution), never a fake
    "lasso API";
  - bounded included/excluded-point refinement
    (`addIncludedPoint`/`addExcludedPoint`) inside
    `SegmentationRunPolicy.maximumRefinementCount`;
  - explicit `qualityLevel` (accurate | balanced | fast), default
    `balanced` for operator work;
  - the mask returned by the request's `PixelBufferObservation` is
    thresholded into a bit-packed `SegmentationMaskGrid` — no
    semantic confidence is fabricated.
- Downloadable-asset honesty
  (`ObjectSegmentationAssetController`):
  - `assetStatus` is read-only and probed only;
  - `downloadAssets()` runs exclusively on explicit operator request
    ("Prepare" before a scan, or the Prepare button during a pass) —
    a single-flight task, cancellable between sessions;
  - `SegmentationAssetReadiness.admitsSegmentation` is true only for
    `.ready`, so no mid-scan network work can ever start;
  - ordinary capture/finalization is fully functional without the
    asset — the controls hide and capture proceeds.
- Explicit display-orientation authority for the
  view→image→Vision coordinate chain:
  - iOS 27 `ARSession.viewRotationAngle` drives
    `ARFrame.displayTransform(viewRotationAngle:viewportSize:)` when
    the SDK-qualified path is available and the value is finite;
  - legacy `ARFrame.displayTransform(for:viewportSize:)` +
    `UIInterfaceOrientation` remains the fallback, recorded as the
    authority in every observation record;
  - SwiftUI orientation values are never used as camera extrinsics —
    `UIWindowScene.interfaceOrientation` is only the input token to
    the documented ARKit fallback API;
  - `SegmentationViewToImageMapping` inverts the recorded display
    transform; taps outside the covered image are rejected
    (`seed_outside_image`), and a y-flip converts image-normalized
    (top-left) to Vision normalized (bottom-left) space;
  - the gesture overlay is sized to exactly the preview image bounds
    and reports its own viewport size, so the recorded transform's
    viewport matches the gesture surface at all orientations.
- Same-frame spatial authority for depth fusion:
  - the Vision input image is the retained `capturedImage` of a
    pose-linked `CapturedFrameSnapshot`;
  - `SharedARSessionController.maskedTargetedShapeObservation` reads
    that same snapshot's `ARDepthData` (sceneDepth) — never a
    different frame — with real `ARConfidenceLevel` filtering
    (`arkit_confidence_map_nonzero`; `confidence_map_absent` recorded
    honestly when the map is missing);
  - world points are unprojected through the frame's own intrinsics
    and `T_world_from_camera`; depth is never upsampled;
  - a LiDAR-less device falls back to mesh-ray support gated by the
    mask (`SegmentationDepthGate.maskContains`), also from the same
    snapshot's captured anchors;
  - a mask with insufficient spatial support stays a 2D derived
    observation (`unsupported_mask_2d_only`) — it is never extruded
    into fabricated geometry.
- Bounded temporal behavior: segmentation runs once per explicit
  operator request (seed gesture, refinement point, Use / New
  selection); there is no frame-rate or timer re-run.
  `SegmentationRunPolicy.viewChangeIsMaterial` gates a re-seed after
  a completed attempt; Vision work runs in a detached task off the
  AR delegate path and cancels under the legacy bolph71656-ai/HTDT-Capture#273 memory-pressure flag.
- Persistence — masks exist only as derived evidence:
  - `ObjectSegmentationObservation` records the issue's field list
    verbatim (seed kind + coordinates, refinement points/count,
    quality level, mask dims/encoding/payload, display-authority
    revision, Vision/OS/app context, downstream spatial refs);
  - `derived/segmentation-observations.json` is bound in the bundle
    manifest as `.derived` with `path:` source refs to the persisted
    `segmentation_source` evidence frame;
  - the doc is empty-omitted at finalize when no segmentation ran.
- UI: seed mode (tap | box | lasso→scribble), gesture surface on the
  live preview, refinement (Include/Exclude point buttons when a
  mask is ready), Use / Refine / Cancel controls, inline
  Prepare/download state — all inside the existing target-scan
  section of `CaptureScanningView`.

## Verified (this environment)

- `swift build` clean; `swift test` all green including the new
  `ObjectSegmentationTests` (mapping in all four orientations,
  bit-pack/base64 round-trip, policy bounds, record validation, the
  package document validating against the published schema, and the
  depth-gate projection math).
- `xcodebuild` iOS build against the Xcode 27 RC SDK.

## Device-gated (documented, not faked)

- End-to-end Vision request behavior (mask quality, `qualityLevel`
  trade-offs, scribble fidelity, refinement semantics) requires
  iPhone-class hardware with the downloadable model asset — the
  simulator cannot run ARKit/Vision segmentation.
- `ARSession.viewRotationAngle` runtime values and the
  `displayTransform(viewRotationAngle:)` vs legacy-path pixel
  comparison in portrait/landscape require a physical iOS 27 device.
- `DownloadableAssetsRequest` `assetStatus`/`downloadAssets()`
  progress/failure states need a device that can reach Apple's asset
  service.
- The issue's benchmark suite (seed reprojection error, IoU,
  supported-depth fraction, 3D extent error, contamination,
  unresolved rate, latency/thermal) is physical-device work on
  iPhone 17 Pro / iOS 27 and remains scheduled for the device bench.
