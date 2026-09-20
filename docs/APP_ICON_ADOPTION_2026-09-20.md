# HTDT app icon adoption — 2026-09-20

## Decision

The user-approved HTDT home-theater / digital-twin icon is the product icon for HTDT Capture.

## Implementation

- Canonical artwork source: `Branding/HTDT-AppIcon-source.jpg`.
- The source is an opaque square derivative of the approved artwork. iOS applies the platform icon mask; the source itself intentionally does not contain alpha.
- `App/Assets.xcassets/AppIcon.appiconset` is the Xcode app-icon authority.
- `tools/prepare-app-icon.sh` deterministically renders the required 1024 × 1024 PNG before asset compilation.
- `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` binds the application target to that asset catalog.
- The unsigned IPA workflow treats the asset catalog as part of the build and is triggered by branding changes.

The generated PNG is ignored by Git because the compressed canonical artwork is the maintained source. This keeps generated image bytes out of normal diffs while preserving reproducible builds.

## Validation

Repository-native validation is the existing unsigned IPA build on `macos-15`. It now also requires the archived application to contain `Assets.car`, so a broken asset-catalog integration fails the build.

No physical-device acceptance is claimed by this change.
