#!/bin/bash
set -euo pipefail
# shellcheck source=tools/device-proof/common.sh
source "$(dirname "$0")/common.sh"
load_signing
discover_device
url="${1:-}"
args=(--reset-evidence --autorun)
if [[ -n "$url" ]]; then args+=(--probe-url "$url"); fi
raw="$ARTIFACTS/launch.raw.log"
set +e
xcrun devicectl device process launch --device "$DEVICE_PROOF_DEVICE_ID" --timeout 30 --terminate-existing "$DEVICE_PROOF_BUNDLE_ID" "${args[@]}" --json-output "$ARTIFACTS/launch.json" >"$raw" 2>&1
status=$?
set -e
redact_log "$raw" "$ARTIFACTS/launch.log"; redact_log "$ARTIFACTS/launch.json" "$ARTIFACTS/launch.redacted.json"
rm -f "$raw" "$ARTIFACTS/launch.json"
[[ $status -eq 0 ]] || { tail -80 "$ARTIFACTS/launch.log"; exit "$status"; }
echo "device launch passed (runtime endpoint and identifiers redacted)"
