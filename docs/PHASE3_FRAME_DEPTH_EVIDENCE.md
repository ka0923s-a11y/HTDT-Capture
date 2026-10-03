# Phase 3 Frame + Depth Evidence Implementation Record

Status: In progress  
Issue: legacy bolph71656-ai/HTDT-Capture#4

## Implemented

- Typed evidence frame identity.
- Camera pose and 3x3 intrinsics metadata model.
- Explicit depth status:
  - not requested;
  - unavailable;
  - captured discrete scene depth;
  - captured smoothed scene depth.
- SHA-256 helper using CryptoKit.
- Canonical packed pixel-plane model.
- `HTDTPXL1` binary codec with:
  - source stride metadata;
  - packed row length;
  - per-plane dimensions;
  - explicit payload offsets/lengths;
  - contiguous payload requirement;
  - no allocator padding bytes.
- `HTDTDPT1` depth codec with float32 meters and optional explicit validity mask.
- `HTDTCNF1` confidence codec preserving ARKit confidence codes.
- iOS pixel-buffer adapter supporting only:
  - bi-planar 420 full-range;
  - bi-planar 420 video-range;
  - 32BGRA.
- iOS depth adapter supporting DepthFloat32 and OneComponent8 confidence maps.
- Non-finite depth values are normalized to 0 only together with an explicit validity-mask value of 0.
- iOS ARFrame artifact adapter that binds:
  - exact frame timestamp;
  - `T_world_from_camera`;
  - camera intrinsics;
  - packed RGB payload;
  - privacy-reviewed EXIF subset;
  - an explicitly selected discrete or smoothed depth authority.
- HEIC is not used as canonical camera evidence.

## EXIF policy

Only exposure/imaging parameters are retained by the current allowlist:

- exposure time;
- F-number;
- ISO speed ratings;
- focal length;
- 35mm-equivalent focal length;
- exposure bias;
- metering mode;
- white balance.

Date/time, GPS, device-identifying, and arbitrary metadata are not copied by default.

## Fail-closed behavior

Unknown RGB pixel formats are rejected instead of guessed.

Unexpected planar layout, inadequate row stride, unsupported depth/confidence pixel format, and depth/confidence dimension mismatch are errors.

## Remaining hardware-gated work

- prove the ARFrame adapter on the target LiDAR iPhone;
- confirm capturedImage pixel formats encountered in each capture mode;
- confirm exact sceneDepth availability during RoomPlan and after same-session RoomPlan stop;
- verify pose/intrinsics/depth correspond to the expected frame in captured fixtures;
- characterize depth accuracy by range/confidence under Issue bolph71656-ai/HTDT-Capture#9.

The optional derived HEIC preview is implemented as a best-effort
`capture_app_derived` artifact and never replaces canonical `HTDTPXL1`
evidence.

Issue bolph71656-ai/HTDT-Capture#4 remains open only for the physical-device observations above.


## Live working-set package

This slice adds a typed `FrameEvidencePackage` that binds one exact
`FrameEvidenceDescriptor` to:

- its packed `HTDTPXL1` camera payload;
- optional `HTDTDPT1` depth payload;
- optional `HTDTCNF1` confidence payload;
- a schema-owned per-frame JSON descriptor.

The package verifies byte counts and SHA-256 values before persistence and uses
deterministic paths derived from the exact `frame_id`.

The descriptor is written last after its referenced binary payloads. The
working-set store then emits exact manifest declarations and increments explicit
frame/depth evidence counts.

The next host integration in this same slice captures the frame and final mesh
from one exact `ARFrame` immediately before the RoomPlan scan boundary.


## Scan-end host integration

`SharedARSessionController.snapshotReviewEvidence()` now reads exactly one
current `ARFrame` and derives both:

- the final active ARMeshAnchor snapshots; and
- one `CapturedFrameArtifacts` camera/depth evidence snapshot.

The host calls this immediately before ending the RoomPlan scan. It then persists
both packages into the same working revision.

The default depth selection is discrete `sceneDepth`. Absence is represented
by `FrameDepthStatus.unavailable`; no depth payload is fabricated and no
capability-only assumption is promoted to evidence.


## Manual evidence-frame capture during scanning

The concrete host now exposes an explicit **Capture evidence frame** action while
the RoomPlan scan is active.

Each activation copies one exact current `ARFrame` through the existing
`ARFrameArtifactAdapter` and persists the resulting
`FrameEvidencePackage` into the same mutable working revision. The frame keeps
the exact capture-session ID, coordinate-space ID, AR timestamp, camera pose,
intrinsics, packed camera pixels, and discrete sceneDepth/confidence only when
the selected frame actually provides them.

The action is bounded to one in-flight persistence operation. Repeated taps do
not create overlapping writes. The existing actor-backed no-overwrite store
remains the persistence authority.

Scan-end evidence remains separate: the host still captures one final exact
ARFrame jointly with the final active mesh snapshot immediately before ending
RoomPlan. Manual evidence frames therefore add context without replacing the
scan-boundary evidence.

## Bounded automatic keyframes (policy `auto_keyframe_v1`)

During scanning the host also evaluates a bounded opportunistic selector on the
existing coverage samples (policy version `auto_keyframe_v1`, recorded on each
`automatic_keyframe` advisory note). A candidate may be retained only when
tracking is normal and it is spatially novel: at least
`minimumTranslationMeters` or `minimumRotationRadians` away from every retained
automatic frame, and at least `minimumIntervalSeconds` after the previous
retention. Retention is hard-capped at `maximumRetainedFrames` and
`maximumRetainedBytes` (estimated and persisted byte authorities both checked),
with a bounded `maximumNoDepthFrames` allowance for frames lacking scene depth.
Manual **Save evidence** is never classified as redundant and is always
persisted on demand. Candidates flagged `.unusable` by the
`frame_usability_v1` diagnostic are skipped when alternatives remain; a
manual save of a suspect/unusable frame is force-retained with an advisory
warning instead.


## Optional derived HEIC preview

The iOS ARFrame adapter now opportunistically creates a HEIC preview from the
same `capturedImage` used to build canonical `HTDTPXL1` evidence.

Preview generation is best-effort: encoder failure returns no preview and does
not fail the capture. When available, the preview is stored at:

`evidence/frames/<frame-id>.preview.heic`

with:

- `role=derived`;
- `provenance_class=capture_app_derived`;
- a manifest source reference to the exact canonical frame descriptor;
- an in-memory byte-count/SHA-256 authority that participates in working-set
  integrity preflight.

The preview never replaces the canonical packed pixel payload, is not used for
pose/intrinsics/depth authority, and carries no separately promoted EXIF
authority.
