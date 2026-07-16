#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key="$(printf '%s' "$ROOT" | shasum -a 256 | awk '{print substr($1,1,12)}')"
ARTIFACTS="${TMPDIR:-/tmp}/jellyfin-audio-app-$key"
mkdir -p "$ARTIFACTS"
python3 "$ROOT/tools/device-proof/signing.py" "$ARTIFACTS/signing.env" >/dev/null
# shellcheck source=/dev/null
source "$ARTIFACTS/signing.env"
APP_TEAM_ID="$DEVICE_PROOF_TEAM_ID"
APP_BUNDLE_ID="org.example.jellyfinaudio.${DEVICE_PROOF_BUNDLE_ID##*.}"
export APP_TEAM_ID APP_BUNDLE_ID
"$ROOT/scripts/bootstrap.sh"
set +e
xcodebuild -project "$ROOT/JellyfinAudio.xcodeproj" -scheme JellyfinAudio -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath "$ARTIFACTS/Derived" \
  APP_TEAM_ID="$APP_TEAM_ID" APP_BUNDLE_ID="$APP_BUNDLE_ID" build >"$ARTIFACTS/build.raw.log" 2>&1
build_status=$?
set -e
python3 "$ROOT/tools/device-proof/redact.py" "$ARTIFACTS/build.raw.log" "$ARTIFACTS/build.log"
rm -f "$ARTIFACTS/build.raw.log"
if [[ $build_status -ne 0 ]]; then
  tail -80 "$ARTIFACTS/build.log" >&2
  exit "$build_status"
fi
xcrun devicectl list devices --json-output "$ARTIFACTS/devices.json" >/dev/null
device="$(python3 "$ROOT/tools/device-proof/select_device.py" "$ARTIFACTS/devices.json")"
app="$ARTIFACTS/Derived/Build/Products/Debug-iphoneos/JellyfinAudio.app"
set +e
xcrun devicectl device install app --device "$device" --timeout 30 "$app" >"$ARTIFACTS/install.raw.log" 2>&1
install_status=$?
set -e
python3 "$ROOT/tools/device-proof/redact.py" "$ARTIFACTS/install.raw.log" "$ARTIFACTS/install.log"
rm -f "$ARTIFACTS/install.raw.log"
if [[ $install_status -ne 0 ]]; then
  tail -40 "$ARTIFACTS/install.log" >&2
  exit "$install_status"
fi
if [[ "${1:-}" == "--launch" ]]; then
  xcrun devicectl device process launch --device "$device" --timeout 30 --terminate-existing "$APP_BUNDLE_ID" >/dev/null
fi
echo "Jellyfin Audio installed on the paired device (identifiers redacted)."
