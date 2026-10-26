#!/usr/bin/env python3
"""Prove disposable Jellyfin stop/unavailable/start recovery without credentials."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
from urllib.error import URLError

from network_lab import fetch, wait_for_public


ROOT = Path(__file__).resolve().parents[2]
COMPOSE = ROOT / "infra" / "jellyfin" / "compose.yml"
VERSIONS = ROOT / "infra" / "jellyfin" / "versions.env"
OUTPUT = ROOT / "docs" / "evidence" / "phase-0" / "network" / "server-restart-results.json"
UPSTREAM = "http://127.0.0.1:18096"


def compose(*arguments: str) -> None:
    subprocess.run(
        ["docker", "compose", "--env-file", str(VERSIONS), "-f", str(COMPOSE), *arguments],
        cwd=str(ROOT), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=OUTPUT)
    arguments = parser.parse_args()
    original_id = wait_for_public(UPSTREAM)
    unavailable = False
    recovered_id = None
    try:
        compose("stop", "current")
        try:
            status, _, _ = fetch(UPSTREAM + "/System/Info/Public", timeout=1)
            unavailable = status >= 500
        except (URLError, OSError):
            unavailable = True
    finally:
        compose("start", "current")
        recovered_id = wait_for_public(UPSTREAM)
    if not unavailable or recovered_id != original_id:
        raise AssertionError("disposable server did not prove unavailable then recover with stable identity")
    report = {
        "schemaVersion": 1,
        "proofId": "phase0-disposable-server-restart",
        "capturedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "command": "PHASE0_NETWORK_PROVE_RESTART=1 tools/network-lab/run.sh",
        "environment": {
            "runtime": "docker-compose-loopback",
            "upstream": "digest-pinned-disposable-jellyfin-current",
        },
        "owner": {"phase": "Phase 0", "workstream": "network"},
        "status": "pass",
        "limitations": [
            "This host-container proof does not replace iOS background playback recovery evidence."
        ],
        "privacy": {
            "redacted": True,
            "committedEvidenceContainsSecrets": False,
            "privateServerDataPersisted": False,
        },
        "evidenceDate": "2026-07-16",
        "result": "PASS",
        "disposableServerStopped": True,
        "unavailableClassifiedAsTransportFailure": True,
        "serverRestartedAndReady": True,
        "publicIdentityStableAfterRestart": True,
        "authenticatedRequestSent": False,
        "credentialsPersisted": False,
        "serverAddressPersisted": False,
        "serverIdentifierPersisted": False,
        "limitation": "This host-container proof does not replace iOS background playback recovery evidence.",
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("PASS: disposable Jellyfin stop/start recovery")
    try:
        displayed = arguments.output.relative_to(ROOT)
    except ValueError:
        displayed = arguments.output
    print("Evidence: {}".format(displayed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
