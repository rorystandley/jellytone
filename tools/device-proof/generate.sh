#!/bin/bash
set -euo pipefail
# shellcheck source=tools/device-proof/common.sh
source "$(dirname "$0")/common.sh"
export DEVICE_PROOF_TEAM_ID="LOCALONLY00"
export DEVICE_PROOF_BUNDLE_ID="org.example.phase0.deviceproof.generated"
XCODEGEN_BIN=${XCODEGEN_BIN:-"$ROOT/tools/phase0/.cache/xcodegen-2.46.0/unpacked/xcodegen/bin/xcodegen"}
if [[ ! -x "$XCODEGEN_BIN" ]]; then
  "$ROOT/tools/phase0/fetch-xcodegen.sh" >/dev/null
fi
version=$($XCODEGEN_BIN --version | awk '{print $NF}')
[[ "$version" == "2.46.0" ]] || {
  echo "XcodeGen 2.46.0 required, found $version" >&2
  exit 2
}
conflict_copy=$(find "$HARNESS" -maxdepth 2 \
  \( -name 'DeviceProof [0-9]*.xcodeproj' -o -name 'Info [0-9]*.plist' \) \
  -print -quit)
if [[ -n "$conflict_copy" ]]; then
  echo "unexpected generated conflict copy: $conflict_copy" >&2
  echo "remove it before regenerating the isolated DeviceProof project" >&2
  exit 2
fi
resources="$HARNESS/GeneratedResources"
rm -rf "$resources"
mkdir -p "$resources"
for fixture in tone-a.mp3 tone-a.m4a tone-a-alac.m4a tone-a.flac tone-a-vorbis.ogg tone-a-opus.ogg tone-a-opus.mp4; do
  cp "$ROOT/Tests/Fixtures/Audio/$fixture" "$resources/$fixture"
done
cp "$ROOT/Tests/Fixtures/Audio/manifest.json" "$resources/proof-media-manifest.json"
xattr -cr "$resources"
rm -rf "$PROJECT"
"$XCODEGEN_BIN" generate --spec "$HARNESS/project.yml" --project "$ARTIFACTS" --project-root "$HARNESS"
[[ "$(plutil -extract NSAppTransportSecurity.NSAllowsLocalNetworking raw -o - "$HARNESS/Config/Info.plist")" == "true" ]]
[[ "$(plutil -extract UIBackgroundModes.0 raw -o - "$HARNESS/Config/Info.plist")" == "audio" ]]
if plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads raw -o - "$HARNESS/Config/Info.plist" >/dev/null 2>&1; then
  echo "unsafe broad ATS setting generated" >&2
  exit 2
fi
conflict_copy=$(find "$HARNESS" -maxdepth 2 \
  \( -name 'DeviceProof [0-9]*.xcodeproj' -o -name 'Info [0-9]*.plist' \) \
  -print -quit)
if [[ -n "$conflict_copy" ]]; then
  echo "generation created unexpected conflict copy: $conflict_copy" >&2
  exit 2
fi
echo "generated isolated DeviceProof project with XcodeGen $version"
