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
case "$ARTIFACTS" in
  "$ROOT"/*)
    echo "device-proof generated artifacts must be outside the repository" >&2
    exit 2
    ;;
esac
rm -rf "$GENERATED_RESOURCES"
mkdir -p "$GENERATED_RESOURCES"
for fixture in tone-a.mp3 tone-a.m4a tone-a-alac.m4a tone-a.flac tone-a-vorbis.ogg tone-a-opus.ogg tone-a-opus.mp4; do
  cp "$ROOT/Tests/Fixtures/Audio/$fixture" "$GENERATED_RESOURCES/$fixture"
done
cp "$ROOT/Tests/Fixtures/Audio/manifest.json" "$GENERATED_RESOURCES/proof-media-manifest.json"
xattr -cr "$GENERATED_RESOURCES"
export DEVICE_PROOF_GENERATED_RESOURCES="$GENERATED_RESOURCES"
rm -rf "$PROJECT"
"$XCODEGEN_BIN" generate --spec "$HARNESS/project.yml" --project "$ARTIFACTS" --project-root "$HARNESS"
[[ "$(plutil -extract NSAppTransportSecurity.NSAllowsLocalNetworking raw -o - "$HARNESS/Config/Info.plist")" == "true" ]]
[[ "$(plutil -extract UIBackgroundModes.0 raw -o - "$HARNESS/Config/Info.plist")" == "audio" ]]
if plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads raw -o - "$HARNESS/Config/Info.plist" >/dev/null 2>&1; then
  echo "unsafe broad ATS setting generated" >&2
  exit 2
fi
resource_count=$(find "$GENERATED_RESOURCES" -maxdepth 1 -type f | wc -l | tr -d ' ')
[[ "$resource_count" == "8" ]] || {
  echo "expected exactly eight isolated DeviceProof resources, found $resource_count" >&2
  exit 2
}
echo "generated isolated DeviceProof project with XcodeGen $version outside the repository"
