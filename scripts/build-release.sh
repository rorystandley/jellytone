#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/bootstrap.sh"
xcodebuild -project "$ROOT/Jellytone.xcodeproj" -scheme Jellytone -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "${TMPDIR:-/tmp}/jellytone-release" \
  APP_TEAM_ID=LOCALONLY00 APP_BUNDLE_ID=org.example.jellytone.release CODE_SIGNING_ALLOWED=NO build
