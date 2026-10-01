# Manual IPA build

HTDT-Capture has no continuous integration — nothing runs on push or pull
requests. The only GitHub Actions workflow is a manually dispatched unsigned
IPA build (`.github/workflows/build-ipa.yml`): Actions → "Build IPA" → Run
workflow produces the `HTDTCapture-unsigned-ipa` artifact (14-day retention).
The IPA can also be built locally on a Mac with the script below.

## Requirements

- macOS with Xcode installed and launched at least once (license accepted)
- [XcodeGen](https://github.com/yonsm/XcodeGen) 2.42.0+: `brew install xcodegen`
- For a device-installable (signed) IPA: an Apple ID joined to an Apple
  Developer team, added in Xcode → Settings → Accounts

## Unsigned IPA (verification / parity with the manual-dispatch workflow)

```sh
scripts/build-ipa.sh
```

Produces `build/HTDT-Capture-unsigned.ipa` plus a `.sha256` checksum. The
xcodebuild transcript lands in `build-xcode.log` at the repository root. An
unsigned bundle cannot be installed on a device directly;
it proves the app archives, embeds its asset catalog (`Assets.car`), and
packages cleanly.

## Signed, device-installable IPA

```sh
scripts/build-ipa.sh --team <TEAM_ID>
```

`<TEAM_ID>` is your 10-character Apple Developer team identifier (shown in
Xcode's account settings). The script archives with automatic signing and runs
`xcodebuild -exportArchive` (development distribution), producing
`build/HTDT-Capture-signed.ipa`. The first run may need network access for
provisioning-profile creation.

Install the signed IPA via Apple Configurator 2, the Devices & Simulators
window in Xcode, or `xcrun devicectl`.

## What the script does

1. `xcodegen generate --spec project.yml` — regenerates `HTDTCapture.xcodeproj`
2. `xcodebuild -resolvePackageDependencies` — fetches the local SwiftPM package
3. `xcodebuild archive -configuration Release -destination 'generic/platform=iOS'`
4. Unsigned mode: packs `Payload/HTDTCapture.app` into a `.ipa` zip and asserts
   `Assets.car` is present
5. Signed mode: `xcodebuild -exportArchive` with a generated development
   ExportOptions plist

IPA and checksum artifacts land in `build/`; `build-xcode.log` is written to
the repository root. The script is `sh`, fail-fast (`set -euo pipefail`), and
safe to re-run.
