"""Common evidence envelope for deterministic Phase 0 playback proofs."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
from typing import Any


def retained_capture_timestamp(output: Path) -> str:
    """Retain the real snapshot time unless an intentional refresh overrides it."""
    override = os.environ.get("PHASE0_PLAYBACK_CAPTURED_AT")
    if override:
        datetime.fromisoformat(override.replace("Z", "+00:00"))
        return override
    if output.exists():
        try:
            captured_at = json.loads(output.read_text(encoding="utf-8"))["capturedAt"]
            datetime.fromisoformat(captured_at.replace("Z", "+00:00"))
            return captured_at
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            pass
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def playback_envelope(
    *,
    proof_id: str,
    command: str,
    environment: dict[str, Any],
    limitations: list[str],
    payload: dict[str, Any],
    output: Path,
    status: str = "pass",
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "proofId": proof_id,
        "capturedAt": retained_capture_timestamp(output),
        "command": command,
        "environment": environment,
        "owner": {"phase": "Phase 0", "workstream": "playback"},
        "status": status,
        "limitations": limitations,
        "privacy": {
            "redacted": True,
            "committedEvidenceContainsSecrets": False,
            "privateServerDataPersisted": False,
            "notes": ["Synthetic media and loopback transports only."],
        },
        **payload,
    }
