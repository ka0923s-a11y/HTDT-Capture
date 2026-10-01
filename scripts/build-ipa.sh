#!/bin/sh
# Build an HTDTCapture IPA locally — no CI required.
#
# Usage:
#   scripts/build-ipa.sh                     # unsigned IPA (CI parity)
#   scripts/build-ipa.sh --team <TEAMID>     # signed, device-installable IPA
#
# Signed mode uses Xcode automatic signing and your local Apple ID /
# development team; it needs network access to Apple the first time it
# creates the provisioning profile.
#
# Output: build/HTDT-Capture-<unsigned|signed>.ipa (+ .sha256, build-xcode.log)

set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

TEAM_ID=""
for arg in "$@"; do
  case "$arg" in
    --team)
      shift
      TEAM_ID="${1:-}"
      ;;
    --team=*)
      TEAM_ID="${arg#--team=}"
      ;;
    -h|--help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
  esac
done

command -v xcodebuild >/dev/null || {
  echo "xcodebuild not found — install Xcode." >&2
  exit 1
}
if ! command -v xcodegen >/dev/null; then
  echo "xcodegen not found — install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec project.yml

xcodebuild \
  -project HTDTCapture.xcodeproj \
  -scheme HTDTCapture \
  -resolvePackageDependencies

rm -rf "$ROOT/build/HTDTCapture.xcarchive"
mkdir -p "$ROOT/build"

ARCHIVE_ARGS=(
  -project HTDTCapture.xcodeproj
  -scheme HTDTCapture
  -configuration Release
  -destination generic/platform=iOS
  -archivePath "$ROOT/build/HTDTCapture.xcarchive"
)
SIGN_ARGS=(
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
)
if [ -n "$TEAM_ID" ]; then
  SIGN_ARGS=(
    DEVELOPMENT_TEAM="$TEAM_ID"
    -allowProvisioningUpdates
  )
fi

set -o pipefail
xcodebuild "${ARCHIVE_ARGS[@]}" "${SIGN_ARGS[@]}" archive \
  | tee "$ROOT/build-xcode.log"

APP="$ROOT/build/HTDTCapture.xcarchive/Products/Applications/HTDTCapture.app"
test -d "$APP"
test -f "$APP/Assets.car"

if [ -n "$TEAM_ID" ]; then
  EXPORT_PLIST="$ROOT/build/ExportOptions.plist"
  cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
</dict>
</plist>
EOF
  xcodebuild \
    -exportArchive \
    -archivePath "$ROOT/build/HTDTCapture.xcarchive" \
    -exportPath "$ROOT/build/ipa-export" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -allowProvisioningUpdates

  IPA="$(find "$ROOT/build/ipa-export" -maxdepth 1 -name '*.ipa' | head -1)"
  test -n "$IPA"
  OUT="$ROOT/build/HTDT-Capture-signed.ipa"
  mv "$IPA" "$OUT"
else
  rm -rf "$ROOT/build/Payload"
  mkdir -p "$ROOT/build/Payload"
  cp -R "$APP" "$ROOT/build/Payload/"
  OUT="$ROOT/build/HTDT-Capture-unsigned.ipa"
  (cd "$ROOT/build" && /usr/bin/zip -qry "$(basename "$OUT")" Payload)
fi

(cd "$ROOT/build" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256")
unzip -l "$OUT" | head -60

echo ""
echo "Done: $OUT"
if [ -z "$TEAM_ID" ]; then
  echo "Unsigned build — install on a device by signing with your team:"
  echo "  scripts/build-ipa.sh --team <TEAMID>"
fi
