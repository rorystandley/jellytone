#!/bin/bash
set -euo pipefail
# shellcheck source=tools/device-proof/common.sh
source "$(dirname "$0")/common.sh"
"$ROOT/tools/device-proof/generate.sh"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT/Tests/Phase0Device" -p 'test_*.py' -v
simulator="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for runtime, xs in d["devices"].items() if "iOS" in runtime for x in xs if x.get("isAvailable") and "iPhone" in x["name"]))')"
raw="$ARTIFACTS/test.raw.log"
set +e
xcodebuild -project "$PROJECT" -scheme DeviceProof -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$DERIVED-tests" CODE_SIGNING_ALLOWED=NO DEVICE_PROOF_TEAM_ID=LOCALONLY00 DEVICE_PROOF_BUNDLE_ID=org.example.phase0.deviceproof.tests test >"$raw" 2>&1
status=$?
set -e
redact_log "$raw" "$ARTIFACTS/test.log"
rm -f "$raw"
if [[ $status -ne 0 ]]; then tail -80 "$ARTIFACTS/test.log"; exit "$status"; fi
grep -E "Executed [0-9]+ tests|TEST SUCCEEDED" "$ARTIFACTS/test.log" | tail -4
