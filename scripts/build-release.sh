#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/bootstrap.sh"
xcodebuild -project "$ROOT/JellyfinAudio.xcodeproj" -scheme JellyfinAudio -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "${TMPDIR:-/tmp}/jellyfin-audio-release" \
  APP_TEAM_ID=LOCALONLY00 APP_BUNDLE_ID=org.example.jellyfinaudio.release CODE_SIGNING_ALLOWED=NO build
