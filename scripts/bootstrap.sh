#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEGEN="$ROOT/tools/phase0/.cache/xcodegen-2.46.0/unpacked/xcodegen/bin/xcodegen"
LOCKFILE="$ROOT/Config/Package.resolved"
if [[ ! -f "$LOCKFILE" ]]; then
  echo "Missing Config/Package.resolved" >&2
  exit 1
fi
if [[ ! -x "$XCODEGEN" ]]; then "$ROOT/tools/phase0/fetch-xcodegen.sh" >/dev/null; fi
[[ "$($XCODEGEN --version | awk '{print $NF}')" == "2.46.0" ]]
# Generate the project. Bundle ID + team resolve from Config/*.xcconfig
# (and optional Config/Local.xcconfig). CLI env overrides are applied by
# xcodebuild callers, not baked into the generated project.
"$XCODEGEN" generate --spec "$ROOT/project.yml" --project "$ROOT"
# Xcode reads this lockfile inside the generated project. The committed copy
# stays outside Jellytone.xcodeproj so a fresh clone has no half-written project.
dest="$ROOT/Jellytone.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$dest"
cp "$LOCKFILE" "$dest/Package.resolved"
echo "Generated Jellytone.xcodeproj with pinned XcodeGen 2.46.0"
if [[ ! -f "$ROOT/Config/Local.xcconfig" ]]; then
  echo "Note: no Config/Local.xcconfig. Xcode device signing uses defaults."
  echo "      cp Config/Local.xcconfig.example Config/Local.xcconfig  # then set APP_TEAM_ID"
fi
