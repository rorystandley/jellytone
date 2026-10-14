#!/bin/bash
set -euo pipefail
# shellcheck source=tools/device-proof/common.sh
source "$(dirname "$0")/common.sh"
load_signing
discover_device
app="$DERIVED/Build/Products/Debug-iphoneos/DeviceProof.app"
test -d "$app" || "$ROOT/tools/device-proof/build.sh"
raw="$ARTIFACTS/install.raw.log"
set +e
xcrun devicectl device install app --device "$DEVICE_PROOF_DEVICE_ID" --timeout 30 "$app" --json-output "$ARTIFACTS/install.json" >"$raw" 2>&1
status=$?
set -e
redact_log "$raw" "$ARTIFACTS/install.log"; redact_log "$ARTIFACTS/install.json" "$ARTIFACTS/install.redacted.json"
rm -f "$raw" "$ARTIFACTS/install.json"
[[ $status -eq 0 ]] || { tail -80 "$ARTIFACTS/install.log"; exit "$status"; }
echo "device install passed (device and signing identifiers redacted)"
