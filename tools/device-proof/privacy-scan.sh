#!/bin/bash
set -euo pipefail
# shellcheck source=tools/device-proof/common.sh
source "$(dirname "$0")/common.sh"
targets=("$ROOT/Prototypes/DeviceProof" "$ROOT/Tests/Phase0Device" "$ROOT/tools/device-proof" "$ROOT/docs/evidence/phase-0/device")
if rg -n --hidden --glob '!*.gitignore' --glob '!privacy-scan.sh' --glob '!.artifacts/**' '(Bearer[[:space:]]+[A-Za-z0-9._-]+|X-Emby-Token|api[_-]?key[=:][^<[:space:]]+|https?://(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})' "${targets[@]}"; then
  echo "privacy scan failed" >&2; exit 1
fi
if rg -n 'NSAllowsArbitraryLoads|NSExceptionAllowsInsecureHTTPLoads|allowsAnyHTTPSCertificate' "$ROOT/Prototypes/DeviceProof"; then
  echo "unsafe transport setting found" >&2; exit 1
fi
echo "privacy and transport-policy scan passed"
