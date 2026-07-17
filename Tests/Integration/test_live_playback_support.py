from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools" / "integration" / "run_live_playback.py"
SPEC = importlib.util.spec_from_file_location("live_playback", MODULE_PATH)
assert SPEC and SPEC.loader
live_playback = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(live_playback)


class LivePlaybackSupportTests(unittest.TestCase):
    def test_expected_lifecycle_accepts_pause_resume_seek(self) -> None:
        events = [
            {"event": "start", "positionTicks": 0, "statusClass": "2xx"},
            {"event": "progress", "paused": False, "positionTicks": 2_500_000, "statusClass": "2xx"},
            {"event": "progress", "paused": True, "positionTicks": 2_500_000, "statusClass": "2xx"},
            {"event": "progress", "paused": False, "positionTicks": 2_500_000, "statusClass": "2xx"},
            {"event": "progress", "paused": False, "positionTicks": 7_500_000, "statusClass": "2xx"},
            {"event": "stop", "positionTicks": 10_000_000, "statusClass": "2xx"},
        ]
        live_playback.validate_lifecycle(events)

    def test_lifecycle_rejects_missing_stop(self) -> None:
        with self.assertRaisesRegex(live_playback.IntegrationFailure, "ordered lifecycle"):
            live_playback.validate_lifecycle([
                {"event": "start", "statusClass": "2xx"},
                {"event": "progress", "paused": False, "positionTicks": 2_500_000, "statusClass": "2xx"},
            ])

    def test_redacted_result_has_no_private_field_names(self) -> None:
        live_playback.validate_redacted_result({
            "serverLabel": "current",
            "version": "10.11.11",
            "lifecycle": ["start", "progress", "stop"],
            "transcode": {"codec": "aac", "container": "mov,mp4,m4a,3gp,3g2,mj2"},
        })
        with self.assertRaisesRegex(live_playback.IntegrationFailure, "private field"):
            live_playback.validate_redacted_result({"token": "private"})

    def test_harness_failure_exposes_only_allowlisted_category(self) -> None:
        with self.assertRaisesRegex(
            live_playback.IntegrationFailure,
            "production gateway harness reported genreTrackMissing",
        ):
            live_playback.run(
                [sys.executable, "-c", 'print("genreTrackMissing private-runtime-detail") or exit(1)'],
                capture=True,
            )


if __name__ == "__main__":
    unittest.main()
