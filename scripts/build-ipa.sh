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

# The app targets iOS 27 APIs — it cannot compile against an older
# iPhoneOS SDK (e.g. `DownloadableAssetsRequestStatus` is iOS-27-only).
# Unless the caller pinned a toolchain with DEVELOPER_DIR, pick the
# newest installed Xcode that ships an iOS 27+ SDK so a machine with
# several Xcodes side by side doesn't silently use an old one.
# Invoke that app's own xcodebuild by absolute path: a bare
# `xcodebuild` on PATH (or one from another Xcode's bin dir) may keep
# using its own SDKs even when DEVELOPER_DIR points elsewhere.
if [ -n "${DEVELOPER_DIR:-}" ]; then
  XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
  [ -x "$XCODEBUILD" ] || XCODEBUILD="$(command -v xcodebuild)"
else
  BEST_APP=""
  BEST_MAJOR=0
  for app in /Applications/Xcode*.app; do
    for sdk in \
      "$app"/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS[0-9]*.sdk
    do
      [ -d "$sdk" ] || continue
      ver="$(basename "$sdk" .sdk)"
      major="${ver#iPhoneOS}"
      major="${major%%.*}"
      [ "$major" -ge 27 ] 2>/dev/null || continue
      if [ "$major" -gt "$BEST_MAJOR" ]; then
        BEST_MAJOR="$major"
        BEST_APP="$app"
      fi
    done
  done
  if [ -n "$BEST_APP" ]; then
    DEVELOPER_DIR="$BEST_APP/Contents/Developer"
    export DEVELOPER_DIR
    XCODEBUILD="$BEST_APP/Contents/Developer/usr/bin/xcodebuild"
    echo "Using Xcode at $BEST_APP (iPhoneOS ${BEST_MAJOR} SDK)"
  else
    CURRENT_SDK="$(xcodebuild -showsdks 2>/dev/null \
      | sed -n 's/.*iPhoneOS \([0-9][0-9]*\)\..*/\1/p' | sort -n | tail -1)"
    if [ -z "${CURRENT_SDK:-}" ] || [ "$CURRENT_SDK" -lt 27 ]; then
      echo "No Xcode with an iOS 27+ SDK found under /Applications/Xcode*.app." >&2
      echo "This app uses iOS 27 APIs — install Xcode 27 or set DEVELOPER_DIR to it." >&2
      exit 1
    fi
    XCODEBUILD="$(command -v xcodebuild)"
  fi
fi
"$XCODEBUILD" -version

xcodegen generate --spec project.yml

"$XCODEBUILD" \
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
"$XCODEBUILD" "${ARCHIVE_ARGS[@]}" "${SIGN_ARGS[@]}" archive \
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
  "$XCODEBUILD" \
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
