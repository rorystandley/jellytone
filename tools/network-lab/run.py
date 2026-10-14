#!/usr/bin/env python3
"""Run the Phase 0 host network lab and emit redacted evidence."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import ssl
import sys

from network_lab import run_proofs


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "docs" / "evidence" / "phase-0" / "network" / "host-network-results.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    arguments = parser.parse_args()
    report = run_proofs()
    tailscale_status = report["proofs"]["tailscaleEnvironment"]["liveProof"]
    report.update(
        {
            "proofId": "phase0-host-network-lab",
            "capturedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
            "command": "tools/network-lab/run.sh",
            "environment": {
                "runtime": platform.python_implementation() + " " + platform.python_version(),
                "tlsLibrary": ssl.OPENSSL_VERSION,
                "upstream": "digest-pinned-disposable-jellyfin-current",
            },
            "owner": {"phase": "Phase 0", "workstream": "network"},
            "status": "blocked" if tailscale_status == "BLOCKED" else "pass",
        }
    )
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("PASS: Phase 0 host network lab")
    try:
        displayed = arguments.output.relative_to(ROOT)
    except ValueError:
        displayed = arguments.output
    print("Evidence: {}".format(displayed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
