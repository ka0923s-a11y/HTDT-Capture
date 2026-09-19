# IPA Build

HTDT-Capture is primarily a Swift package. The repository therefore includes
a minimal iOS host application generated with XcodeGen for packaging and device
integration work.

The GitHub Actions workflow `Build unsigned IPA` archives the host app with
code signing disabled and uploads:

- `HTDT-Capture-unsigned.ipa`
- its SHA-256 sidecar

The unsigned IPA is a build artifact, not an installable App Store/Ad Hoc
package. Installation on a physical iPhone requires Apple signing credentials
and a provisioning profile appropriate to the target device/distribution
method.

The committed source of truth is `project.yml`; the generated
`HTDTCapture.xcodeproj` is intentionally not committed.
