#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Fixture contracts (no live server)"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT/Tests/Phase0Connectivity" -p 'test_*.py' -v
python3 "$ROOT/tools/connectivity/run_proofs.py"

echo "Production gateway against disposable Jellyfin"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT/Tests/Integration" -p 'test_*.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT/tools/integration/run_live_playback.py"
