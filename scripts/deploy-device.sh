#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launch=0
probe_url=""

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy-device.sh [--launch] [--probe-url URL]

Builds, development-signs, and installs the isolated Phase 0 DeviceProof app on
the first paired, unlocked physical iPhone or iPad with Developer Mode enabled.

  --launch         Launch the installed proof app with its synthetic autorun.
  --probe-url URL  Launch and exercise the supplied synthetic HTTP fixture URL.
  -h, --help       Show this help.

This is a direct development-signed device deployment. It does not export an
Ad Hoc distribution IPA or modify Apple Developer portal state.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --launch)
      launch=1
      shift
      ;;
    --probe-url)
      [[ $# -ge 2 ]] || { echo "--probe-url requires a URL" >&2; exit 2; }
      probe_url="$2"
      launch=1
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

"$ROOT/tools/device-proof/test.sh"
"$ROOT/tools/device-proof/build.sh"
"$ROOT/tools/device-proof/install.sh"

if [[ $launch -eq 1 ]]; then
  "$ROOT/tools/device-proof/launch.sh" "$probe_url"
fi

echo "DeviceProof deployment passed. Generated projects, signing identifiers, and logs remain outside the repository."
