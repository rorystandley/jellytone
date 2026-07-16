#!/bin/bash
set -euo pipefail
# shellcheck source=tools/device-proof/common.sh
source "$(dirname "$0")/common.sh"
"$ROOT/tools/device-proof/generate.sh"
load_signing
rm -rf "$DERIVED"
raw="$ARTIFACTS/build.raw.log"
set +e
xcodebuild -project "$PROJECT" -scheme DeviceProof -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" DEVICE_PROOF_TEAM_ID="$DEVICE_PROOF_TEAM_ID" DEVICE_PROOF_BUNDLE_ID="$DEVICE_PROOF_BUNDLE_ID" build >"$raw" 2>&1
status=$?
set -e
redact_log "$raw" "$ARTIFACTS/build.log"
rm -f "$raw"
if [[ $status -ne 0 ]]; then
  echo "signed device build blocked or failed; redacted tail follows" >&2
  tail -100 "$ARTIFACTS/build.log" >&2
  exit "$status"
fi
test -d "$DERIVED/Build/Products/Debug-iphoneos/DeviceProof.app"
echo "signed device build passed (identifiers redacted)"
