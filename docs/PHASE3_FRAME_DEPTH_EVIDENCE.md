# Phase 3 Frame + Depth Evidence Implementation Record

Status: In progress  
Issue: #4

## Implemented in this slice

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
- characterize depth accuracy by range/confidence under Issue #9;
- add optional derived HEIC preview only after canonical capture is proven.

Issue #4 remains open until these are demonstrated.
