#!/usr/bin/env python3
"""Exercise the required close-before-open replacement-session invariant."""
from __future__ import annotations

import json
import pathlib

from evidence_envelope import playback_envelope

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/evidence/phase-0/playback/results/session-order.json"


class SessionProbe:
    def __init__(self):
        self.active = None
        self.events = []

    def start(self, session):
        assert self.active is None
        self.events.append({"event": "start", "session": session})
        self.active = session

    def replace(self, session, reason):
        if self.active:
            self.events.append({"event": "progress", "session": self.active, "reason": reason})
            self.events.append({"event": "stop", "session": self.active, "reason": reason})
            self.active = None
        self.start(session)


def main() -> None:
    probe = SessionProbe()
    probe.start("synthetic-session-a")
    probe.replace("synthetic-session-b", "endpoint-failover")
    probe.replace("synthetic-session-c", "queue-replacement")
    starts = [i for i, e in enumerate(probe.events) if e["event"] == "start"]
    stops = [i for i, e in enumerate(probe.events) if e["event"] == "stop"]
    passed = stops == [starts[1] - 1, starts[2] - 1]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    report = playback_envelope(
        proof_id="phase0-playback-session-order",
        command="python3 tools/playback/validate_session_order.py",
        environment={"runtime": "Python standard library", "clock": "event-order-only"},
        limitations=["Prototype ordering invariant only; no Jellyfin server or AVFoundation player was contacted."],
        output=OUT,
        payload={"passed": passed, "events": probe.events,
                 "scope": "prototype ordering invariant; no Jellyfin server contacted"},
        status="pass" if passed else "fail",
    )
    OUT.write_text(json.dumps(report,
                              indent=2, sort_keys=True) + "\n")
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
