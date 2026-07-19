#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEGEN="$ROOT/tools/phase0/.cache/xcodegen-2.46.0/unpacked/xcodegen/bin/xcodegen"
if [[ ! -x "$XCODEGEN" ]]; then "$ROOT/tools/phase0/fetch-xcodegen.sh" >/dev/null; fi
[[ "$($XCODEGEN --version | awk '{print $NF}')" == "2.46.0" ]]
APP_TEAM_ID="${APP_TEAM_ID:-LOCALONLY00}" APP_BUNDLE_ID="${APP_BUNDLE_ID:-org.example.jellytone.local}" \
  "$XCODEGEN" generate --spec "$ROOT/project.yml" --project "$ROOT"
echo "Generated Jellytone.xcodeproj with pinned XcodeGen 2.46.0"
