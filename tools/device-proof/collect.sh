#!/bin/bash
set -euo pipefail
# shellcheck source=tools/device-proof/common.sh
source "$(dirname "$0")/common.sh"
load_signing
discover_device
rm -rf "$ARTIFACTS/collected"
mkdir -p "$ARTIFACTS/collected"
raw="$ARTIFACTS/collect.raw.log"
set +e
xcrun devicectl device copy from --device "$DEVICE_PROOF_DEVICE_ID" --timeout 30 --domain-type appDataContainer --domain-identifier "$DEVICE_PROOF_BUNDLE_ID" --source 'Library/Application Support/device-proof-events.jsonl' --destination "$ARTIFACTS/collected/device-proof-events.jsonl" >"$raw" 2>&1
status=$?
set -e
redact_log "$raw" "$ARTIFACTS/collect.log"; rm -f "$raw"
[[ $status -eq 0 ]] || { tail -80 "$ARTIFACTS/collect.log"; exit "$status"; }
python3 "$ROOT/tools/device-proof/summarize.py" "$ARTIFACTS/collected/device-proof-events.jsonl" "$ROOT/docs/evidence/phase-0/device/latest-results.json"
cp "$ARTIFACTS/collected/device-proof-events.jsonl" "$ROOT/docs/evidence/phase-0/device/device-events.jsonl"
echo "redacted device evidence collected"
