#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS="$ROOT/Prototypes/DeviceProof"
artifact_key=$(printf '%s' "$ROOT" | shasum -a 256 | awk '{print substr($1, 1, 12)}')
ARTIFACTS="${DEVICE_PROOF_ARTIFACTS:-${TMPDIR:-/tmp}/jellyfin-ios-audio-device-proof-$artifact_key}"
mkdir -p "$ARTIFACTS"
ARTIFACTS="$(cd "$ARTIFACTS" && pwd -P)"
DERIVED="$ARTIFACTS/Derived"
PROJECT="$ARTIFACTS/DeviceProof.xcodeproj"
GENERATED_RESOURCES="$ARTIFACTS/GeneratedResources"
export ROOT HARNESS ARTIFACTS DERIVED PROJECT GENERATED_RESOURCES

redact_log() {
  local input="$1" output="$2"
  python3 "$ROOT/tools/device-proof/redact.py" "$input" "$output"
}

load_signing() {
  if [[ ! -f "$ARTIFACTS/signing.env" ]] || ! grep -q '^DEVICE_PROOF_BUNDLE_ID=org\.example\.phase0\.deviceproof\.' "$ARTIFACTS/signing.env"; then
    python3 "$ROOT/tools/device-proof/signing.py" "$ARTIFACTS/signing.env"
  fi
  # Runtime-only file is ignored and permissions are restricted by signing.py.
  # shellcheck source=/dev/null
  source "$ARTIFACTS/signing.env"
  export DEVICE_PROOF_TEAM_ID DEVICE_PROOF_BUNDLE_ID
}

discover_device() {
  local inventory="$ARTIFACTS/device-inventory.json"
  xcrun devicectl list devices --json-output "$inventory" >/dev/null
  DEVICE_PROOF_DEVICE_ID="$(python3 "$ROOT/tools/device-proof/select_device.py" \
    "$inventory" --metadata-output "$ARTIFACTS/device-metadata.json")"
  export DEVICE_PROOF_DEVICE_ID
}
