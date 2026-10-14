#!/bin/bash
set -euo pipefail
# shellcheck source=tools/device-proof/common.sh
source "$(dirname "$0")/common.sh"
"$ROOT/tools/device-proof/test.sh"
"$ROOT/tools/device-proof/build.sh"
"$ROOT/tools/device-proof/install.sh"
state="$ARTIFACTS/server.json"
python3 "$ROOT/tools/device-proof/serve_fixture.py" --root "$ROOT/Tests/Fixtures/Audio" --state "$state" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$state"' EXIT
for _ in {1..50}; do [[ -s "$state" ]] && break; sleep 0.1; done
url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$state")"
"$ROOT/tools/device-proof/launch.sh" "$url"
sleep 15
"$ROOT/tools/device-proof/collect.sh"
"$ROOT/tools/device-proof/privacy-scan.sh"
