#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/bootstrap.sh"
"$ROOT/scripts/run-simulator-gate.sh" unit Jellytone
