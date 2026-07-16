#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/deploy-app.sh" --launch
echo "Device smoke gate passed: signed app installed and launched. Live Jellyfin authentication requires an authorized server account."
