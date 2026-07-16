#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT/Tests/Phase0Connectivity" -p 'test_*.py' -v
python3 "$ROOT/tools/connectivity/run_proofs.py"
