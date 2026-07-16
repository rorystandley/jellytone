#!/usr/bin/env python3
"""Run Phase 0 connectivity policy and synthetic contract proofs."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys

from connectivity_policy import validate_contract_fixture


ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    suite = ROOT / "Tests" / "Phase0Connectivity"
    completed = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", str(suite), "-p", "test_*.py", "-v"],
        cwd=ROOT,
        check=False,
    )
    if completed.returncode:
        return completed.returncode
    fixture_paths = sorted((ROOT / "Tests" / "Fixtures" / "Jellyfin").glob("*/connectivity-contract.json"))
    reports = []
    for path in fixture_paths:
        fixture = validate_contract_fixture(path)
        reports.append({
            "fixture": str(path.relative_to(ROOT)),
            "serverVersion": fixture["declaredServerVersion"],
            "audioItems": len(fixture["audioItems"]),
            "result": "PASS",
        })
    if len(reports) != 2:
        raise SystemExit("expected exactly two supported-version contract fixtures")
    print(json.dumps({"contractFixtures": reports, "result": "PASS"}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
