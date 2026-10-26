#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
export PYTHONDONTWRITEBYTECODE=1

fixture_output=
fixture_repeat=
live_report=
network_report=
restart_report=
playback_output=
containers_started=0

cleanup() {
  exit_status=$?
  if [ "$containers_started" -eq 1 ]; then
    if [ "$exit_status" -ne 0 ]; then
      docker compose --env-file infra/jellyfin/versions.env \
        -f infra/jellyfin/compose.yml logs --tail 100 >&2 || true
    fi
    tools/phase0/jellyfin.sh down >/dev/null 2>&1 || true
  fi
  for directory in "$fixture_output" "$fixture_repeat" "$playback_output"; do
    if [ -n "$directory" ] && [ -d "$directory" ]; then
      find "$directory" -mindepth 1 -delete
      rmdir "$directory"
    fi
  done
  for report in "$live_report" "$network_report" "$restart_report"; do
    if [ -n "$report" ] && [ -f "$report" ]; then
      rm -f "$report"
    fi
  done
}
trap cleanup EXIT HUP INT TERM

require_commands() {
  for command in "$@"; do
    command -v "$command" >/dev/null 2>&1 || {
      echo "required command not found: $command" >&2
      exit 2
    }
  done
}

fixture_hash() {
  python3 - "$1" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

root = Path(sys.argv[1])
digest = sha256()
for path in sorted(item for item in root.rglob("*") if item.is_file()):
    digest.update(path.relative_to(root).as_posix().encode("utf-8"))
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")
print(digest.hexdigest())
PY
}

run_common_core() {
  require_commands jq ffmpeg ffprobe python3 shellcheck

  find tools/phase0 tools/fixtures -path '*/.cache' -prune -o \
    -type f -name '*.sh' -exec sh -n {} \;
  find tools/device-proof -type f -name '*.sh' -exec bash -n {} \;
  find tools/network-lab -type f -name '*.sh' -exec sh -n {} \;
  find tools/phase0 tools/fixtures tools/device-proof tools/network-lab \
    \( -path '*/.cache' -o -path '*/.artifacts' \) -prune -o \
    -type f -name '*.sh' -exec shellcheck {} +

  jq -e . tools/fixtures/library-manifest.json >/dev/null
  jq -e . docs/evidence/phase-0/automation/evidence-schema.json >/dev/null
  python3 -m unittest discover -s Tests/Phase0Evidence -p 'test_*.py' -v

  fixture_output=$(mktemp -d "${TMPDIR:-/tmp}/phase0-library.XXXXXX")
  fixture_repeat=$(mktemp -d "${TMPDIR:-/tmp}/phase0-library.XXXXXX")
  tools/fixtures/generate-library.sh "$fixture_output"
  tools/fixtures/generate-library.sh "$fixture_repeat" >/dev/null

  first_fixture_hash=$(fixture_hash "$fixture_output")
  second_fixture_hash=$(fixture_hash "$fixture_repeat")
  test "$first_fixture_hash" = "$second_fixture_hash" || {
    echo "synthetic fixture bytes differ across identical generation runs" >&2
    exit 1
  }
  echo "deterministic fixture bytes verified: $first_fixture_hash"

  python3 tools/connectivity/run_proofs.py
  python3 -m unittest discover -s Tests/Phase0Playback -p 'test_*.py' -v
}

run_apple_gate() {
  require_commands xcrun xcodebuild

  tools/connectivity/verify_sdk_pin.sh

  xcodegen_binary="$ROOT/tools/phase0/.cache/xcodegen-2.46.0/unpacked/xcodegen/bin/xcodegen"
  if [ ! -x "$xcodegen_binary" ]; then
    tools/phase0/fetch-xcodegen.sh >/dev/null
  fi
  XCODEGEN_BIN="$xcodegen_binary" tools/phase0/prove-project-generation.sh

  python3 tools/playback/run_codec_matrix.py
  python3 tools/playback/render_transitions.py
  python3 tools/playback/validate_session_order.py
  tools/device-proof/test.sh
}

run_linux_container_gate() {
  require_commands curl docker uuidgen
  docker info >/dev/null
  docker compose version >/dev/null
  docker compose --env-file infra/jellyfin/versions.env \
    -f infra/jellyfin/compose.yml config --quiet

  containers_started=1
  tools/phase0/jellyfin.sh reset
  live_report=$(mktemp "${TMPDIR:-/tmp}/phase0-live-contract.XXXXXX.json")
  python3 tools/connectivity/live_contract_probe.py | tee "$live_report"
  python3 - "$live_report" <<'PY'
import json
from pathlib import Path
import sys

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["result"] == "PASS"
assert [server["expectedVersion"] for server in report["servers"]] == ["10.11.11", "10.10.7"]
PY
  network_report=$(mktemp "${TMPDIR:-/tmp}/phase0-network.XXXXXX.json")
  restart_report=$(mktemp "${TMPDIR:-/tmp}/phase0-restart.XXXXXX.json")
  PYTHONDONTWRITEBYTECODE=1 python3 tools/network-lab/run.py --output "$network_report"
  PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
    -s Tests/Phase0Network -p 'test_*.py' -v
  PYTHONDONTWRITEBYTECODE=1 python3 tools/network-lab/prove_server_restart.py \
    --output "$restart_report"
}

run_evidence_gate() {
  python3 tools/phase0/validate_evidence.py
}

case "${1:-all}" in
  common)
    playback_output=$(mktemp -d "${TMPDIR:-/tmp}/phase0-playback.XXXXXX")
    export PHASE0_PLAYBACK_EVIDENCE_DIR="$playback_output"
    run_common_core
    run_evidence_gate
    ;;
  apple)
    playback_output=$(mktemp -d "${TMPDIR:-/tmp}/phase0-playback.XXXXXX")
    export PHASE0_PLAYBACK_EVIDENCE_DIR="$playback_output"
    run_common_core
    run_apple_gate
    run_evidence_gate
    ;;
  linux)
    playback_output=$(mktemp -d "${TMPDIR:-/tmp}/phase0-playback.XXXXXX")
    export PHASE0_PLAYBACK_EVIDENCE_DIR="$playback_output"
    run_common_core
    run_linux_container_gate
    run_evidence_gate
    ;;
  evidence)
    require_commands python3
    python3 -m unittest discover -s Tests/Phase0Evidence -p 'test_*.py' -v
    run_evidence_gate
    ;;
  all)
    playback_output=$(mktemp -d "${TMPDIR:-/tmp}/phase0-playback.XXXXXX")
    export PHASE0_PLAYBACK_EVIDENCE_DIR="$playback_output"
    run_common_core
    run_apple_gate
    run_linux_container_gate
    run_evidence_gate
    ;;
  *)
    echo "usage: $0 {all|common|apple|linux|evidence}" >&2
    exit 2
    ;;
esac

echo "Phase 0 ${1:-all} validation passed"
