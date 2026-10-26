#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)

"$ROOT/tools/phase0/jellyfin.sh" up >/dev/null
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT/tools/network-lab/run.py"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT/Tests/Phase0Network" -p 'test_*.py' -v

# Deliberately separate because this briefly stops one disposable server.
if [ "${PHASE0_NETWORK_PROVE_RESTART:-0}" = "1" ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT/tools/network-lab/prove_server_restart.py"
fi
