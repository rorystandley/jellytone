#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS="$ROOT/Prototypes/DeviceProof"
ARTIFACTS="$ROOT/tools/device-proof/.artifacts"
DERIVED="$ARTIFACTS/Derived"
PROJECT="$ARTIFACTS/DeviceProof.xcodeproj"
export ROOT HARNESS ARTIFACTS DERIVED PROJECT
mkdir -p "$ARTIFACTS"

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
  DEVICE_PROOF_DEVICE_ID="$(python3 "$ROOT/tools/device-proof/select_device.py" "$inventory")"
  export DEVICE_PROOF_DEVICE_ID
}
