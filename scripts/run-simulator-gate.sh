#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <gate-name> <scheme>" >&2
  exit 64
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_NAME="$1"
SCHEME="$2"
TMP_ROOT="${TMPDIR:-/tmp}"
umask 077

fail() {
  echo "${GATE_NAME} gate: $*" >&2
  exit 1
}

simulator_info="$(xcrun simctl list devices available -j | python3 -c '
import json
import sys

requested_udid = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    version = runtime.rsplit("iOS-", 1)[-1].replace("-", ".")
    version_key = tuple(int(part) for part in version.split(".") if part.isdigit())
    for device in entries:
        if not device.get("isAvailable") or "iPhone" not in device.get("name", ""):
            continue
        if requested_udid and device["udid"] != requested_udid:
            continue
        preferred_name = 0 if device["name"] == "iPhone 17 Pro" else 1
        candidates.append((version_key, preferred_name, device["name"], runtime, device["udid"]))

if requested_udid and not candidates:
    raise SystemExit(f"JELLYFIN_TEST_SIMULATOR_UDID is not an available iPhone simulator: {requested_udid}")
if not candidates:
    raise SystemExit("no available iPhone simulator found; install an iOS simulator runtime or set JELLYFIN_TEST_SIMULATOR_UDID")

# Prefer the declared current iPhone model, then choose consistently by newest
# installed runtime, device name, and UDID. The selected tuple is reported below.
chosen = sorted(candidates, key=lambda item: (item[1], tuple(-part for part in item[0]), item[2], item[4]))[0]
print("|".join((chosen[3], chosen[2], chosen[4])))
' "${JELLYFIN_TEST_SIMULATOR_UDID:-}" 2>&1)" || fail "$simulator_info"
IFS='|' read -r runtime device simulator <<< "$simulator_info"
[[ -n "$simulator" ]] || fail "simulator selection returned no UDID"

LOCK_ROOT="$TMP_ROOT/jellytone-simulator-gate-locks"
LOCK_DIR="$LOCK_ROOT/$simulator"
mkdir -p "$LOCK_ROOT"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  owner="unknown"
  [[ -f "$LOCK_DIR/owner" ]] && owner="$(tr '\n' ' ' < "$LOCK_DIR/owner")"
  owner_pid="$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$LOCK_DIR/owner" 2>/dev/null || true)"
  if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
    rm -f "$LOCK_DIR/owner"
    rmdir "$LOCK_DIR" 2>/dev/null || fail "stale simulator lock could not be released: $LOCK_DIR"
    mkdir "$LOCK_DIR" || fail "could not reserve simulator $device ($simulator)"
  else
    fail "simulator $device ($runtime, $simulator) is already reserved by $owner; wait for that gate to finish"
  fi
fi
printf 'pid=%s gate=%s scheme=%s started=%s\n' "$$" "$GATE_NAME" "$SCHEME" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCK_DIR/owner"

RUN_ROOT="$(mktemp -d "$TMP_ROOT/jellytone-${GATE_NAME}.XXXXXX")"
DERIVED_DATA="$RUN_ROOT/DerivedData"
RESULT_BUNDLE="$RUN_ROOT/${GATE_NAME}.xcresult"

cleanup() {
  rm -rf "$DERIVED_DATA"
  rm -f "$LOCK_DIR/owner"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

existing_runner="$(ps -axo pid=,command= | awk -v udid="$simulator" '$0 ~ /xcodebuild/ && index($0, "id=" udid) { print $1 }')"
if [[ -n "$existing_runner" ]]; then
  fail "simulator $device ($runtime, $simulator) already has xcodebuild process(es): $existing_runner; preserve its diagnostics and rerun after it exits"
fi

echo "${GATE_NAME} gate simulator: $device | runtime: $runtime | UDID: $simulator"
echo "${GATE_NAME} gate result bundle: $RESULT_BUNDLE"
echo "${GATE_NAME} gate DerivedData: $DERIVED_DATA (removed when the gate exits)"

xcrun simctl boot "$simulator" >/dev/null 2>&1 || true
if ! python3 - "$simulator" <<'PY'
import subprocess
import sys

try:
    subprocess.run(["xcrun", "simctl", "bootstatus", sys.argv[1], "-b"], check=True, timeout=120)
except subprocess.TimeoutExpired:
    raise SystemExit("simulator did not become ready within 120 seconds")
except subprocess.CalledProcessError as error:
    raise SystemExit(f"simulator readiness check failed with exit status {error.returncode}")
PY
then
  fail "simulator $device ($simulator) was not ready; inspect CoreSimulator and retry"
fi

set +e
build_arguments=(
  -project "$ROOT/Jellytone.xcodeproj"
  -scheme "$SCHEME"
  -destination "platform=iOS Simulator,id=$simulator"
  -derivedDataPath "$DERIVED_DATA"
  -resultBundlePath "$RESULT_BUNDLE"
  -parallel-testing-enabled NO
)
if [[ -n "${JELLYFIN_TEST_ONLY:-}" ]]; then
  IFS=',' read -r -a requested_tests <<< "$JELLYFIN_TEST_ONLY"
  for test_target in "${requested_tests[@]}"; do
    [[ "$test_target" =~ ^[A-Za-z0-9_./-]+$ ]] || fail "invalid JELLYFIN_TEST_ONLY target"
    build_arguments+=("-only-testing:$test_target")
  done
fi
xcodebuild "${build_arguments[@]}" \
  APP_TEAM_ID=LOCALONLY00 APP_BUNDLE_ID="org.example.jellytone.${GATE_NAME}" CODE_SIGNING_ALLOWED=NO test
result_code=$?
set -e

if [[ $result_code -ne 0 ]]; then
  echo "${GATE_NAME} gate failed with exit status $result_code; diagnostics retained at $RESULT_BUNDLE" >&2
  if [[ -d "$RESULT_BUNDLE" ]]; then
    xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" 2>&1 || true
  fi
  exit "$result_code"
fi

echo "${GATE_NAME} gate passed; result bundle retained at $RESULT_BUNDLE"
