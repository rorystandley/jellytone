#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/bootstrap.sh"
simulator="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for r,xs in d["devices"].items() if "iOS" in r for x in xs if x.get("isAvailable") and "iPhone" in x["name"]))')"
xcodebuild -project "$ROOT/JellyfinAudio.xcodeproj" -scheme JellyfinAudio \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "${TMPDIR:-/tmp}/jellyfin-audio-tests" \
  APP_TEAM_ID=LOCALONLY00 APP_BUNDLE_ID=org.example.jellyfinaudio.tests CODE_SIGNING_ALLOWED=NO test
