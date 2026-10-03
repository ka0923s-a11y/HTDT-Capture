# ADR-0005: iOS 27 / iPhone-only platform baseline

Status: Accepted  
Date: 2026-10-02  
Supersedes: the deployment-target and device-family decisions of ADR-0001 (its capability-probe and same-session requirements remain in force)

## Context

The product deployment target is now explicitly **iPhone 17 Pro running iOS 27** (program issue #266/#267). ADR-0001 chose iOS 17 + iPhone/iPad under the prior assumption of a broader LiDAR device test matrix; that assumption no longer holds.

Raising the deployment target does not itself improve capture accuracy. The value is removing irrelevant compatibility burden (iPad UX surface, iOS <27 availability branches, a Mac "Designed for iPhone/iPad" destination outside the product contract) and letting the app use and qualify the chosen iOS 27 capability set without pretending older systems remain product targets.

## Decision

- `IPHONEOS_DEPLOYMENT_TARGET = 27.0` (project.yml base + app target; Swift package iOS floor `"27.0"`).
- `TARGETED_DEVICE_FAMILY = 1` — iPhone device family only. This removes iPad as a product UX target; it is **not** a hardware-model whitelist and does not enforce "iPhone 17 Pro only".
- `SUPPORTS_MACCATALYST = NO` (unchanged) and `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO` — as a LiDAR/RoomPlan capture utility the app does not offer a Mac destination, so Xcode must not advertise one.
- The Swift package keeps its macOS floor so `swift build`/`swift test` keep running on macOS for CI-free verification; the iOS app target is the product.

## Runtime capability truth (unchanged)

Build settings are a product contract, not capability evidence. The app continues to derive support exclusively from framework probes — `RoomCaptureSession.isSupported`, world tracking, scene reconstruction, sceneDepth/smoothed depth, high-resolution capture support, the actual active combined AR configuration, and iOS 27 feature/model readiness — via `PlatformCapabilityProbe` and the AR session authorities. No `if model == "iPhone17Pro"` logic may replace a probe.

## Consequences

- Availability checks below iOS 27 become unnecessary; iOS <27-only code paths may be removed as they are encountered rather than in one sweep.
- Features the program qualifies on iPhone 17 Pro (reference objects, iterative segmentation, Foundation Models, Core AI, high-quality visual capture) are adopted as **runtime-gated** capabilities, never as build-time assumptions.
- A future expansion back to iPad or Mac requires a new ADR; the device-family setting is deliberately narrower than the hardware envelope.

## Validation

- `xcodegen` regenerates `HTDTCapture.xcodeproj` with the new settings (committed together).
- `swift build`, `swift test`, and `xcodebuild -destination 'generic/platform=iOS'` must remain clean.
- The device/simulator matrix is unchanged in behavior: unsupported/degraded modes still come from runtime probes, not from the deployment target.
