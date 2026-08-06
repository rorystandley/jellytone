#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEGEN="$ROOT/tools/phase0/.cache/xcodegen-2.46.0/unpacked/xcodegen/bin/xcodegen"
if [[ ! -x "$XCODEGEN" ]]; then "$ROOT/tools/phase0/fetch-xcodegen.sh" >/dev/null; fi
[[ "$($XCODEGEN --version | awk '{print $NF}')" == "2.46.0" ]]
# Generate the project. Bundle ID + team resolve from Config/*.xcconfig
# (and optional Config/Local.xcconfig). CLI env overrides are applied by
# xcodebuild callers, not baked into the generated project.
"$XCODEGEN" generate --spec "$ROOT/project.yml" --project "$ROOT"
echo "Generated Jellytone.xcodeproj with pinned XcodeGen 2.46.0"
if [[ ! -f "$ROOT/Config/Local.xcconfig" ]]; then
  echo "Note: no Config/Local.xcconfig — Xcode device signing uses defaults."
  echo "      cp Config/Local.xcconfig.example Config/Local.xcconfig  # then set APP_TEAM_ID"
fi
