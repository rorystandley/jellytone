from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SUMMARIZER = ROOT / "tools" / "device-proof" / "summarize.py"
REQUIRED = ("mp3", "aac", "alac", "flac", "vorbis_ogg", "opus_ogg")
COMMON_FIELDS = {
    "schemaVersion", "proofId", "capturedAt", "command", "environment",
    "owner", "status", "limitations", "privacy",
}


def assert_common_envelope(test: unittest.TestCase, record: dict, workstream: str) -> None:
    test.assertTrue(COMMON_FIELDS.issubset(record))
    test.assertEqual(record["schemaVersion"], 1)
    test.assertEqual(record["owner"], {"phase": "Phase 0", "workstream": workstream})
    test.assertIn(record["status"], {"pass", "fail", "blocked", "not-run"})
    test.assertTrue(record["capturedAt"].endswith("Z"))
    test.assertIs(record["privacy"]["redacted"], True)
    test.assertIs(record["privacy"]["committedEvidenceContainsSecrets"], False)
    test.assertIs(record["privacy"]["privateServerDataPersisted"], False)


def event(sequence: int, category: str, action: str, result: str = "pass", **facts: str) -> dict:
    return {
        "schemaVersion": 1,
        "sequence": sequence,
        "monotonicMilliseconds": sequence,
        "category": category,
        "action": action,
        "result": result,
        "facts": facts,
    }


class DeviceSummaryTests(unittest.TestCase):
    def summarize(self, events: list[dict]) -> dict:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "events.jsonl"
            output = Path(directory) / "summary.json"
            source.write_text("".join(json.dumps(value) + "\n" for value in events), encoding="utf-8")
            subprocess.run(["python3", str(SUMMARIZER), str(source), str(output)], check=True)
            return json.loads(output.read_text(encoding="utf-8"))

    def complete_events(self) -> list[dict]:
        events = []
        sequence = 0
        for codec in REQUIRED:
            for source in ("local_synthetic", "remote_http_synthetic"):
                sequence += 1
                events.append(event(sequence, "codec", "prepare", codec=codec, source=source))
        sequence += 1
        events.append(event(sequence, "download", "scheduled"))
        sequence += 1
        events.append(event(sequence, "download", "session_restored"))
        for media_identity in ("aac", "mp3", "flac"):
            for action in ("completed_atomically", "final_file_probed"):
                sequence += 1
                events.append(event(sequence, "download", action, media_identity=media_identity))
        sequence += 1
        events.append(event(sequence, "download", "events_acknowledged"))
        return events

    def test_complete_codec_and_download_events_pass(self) -> None:
        summary = self.summarize(self.complete_events())
        assert_common_envelope(self, summary, "device")
        self.assertEqual(summary["result"], "pass")
        self.assertEqual(summary["status"], "pass")
        self.assertEqual(summary["proofs"]["background_download"]["delegate_acknowledgement_count"], 1)
        self.assertEqual(summary["proofs"]["background_download"]["session_restoration_count"], 1)

    def test_missing_session_restoration_fails(self) -> None:
        events = [value for value in self.complete_events() if value["action"] != "session_restored"]
        summary = self.summarize(events)
        self.assertEqual(summary["result"], "fail")
        self.assertEqual(summary["proofs"]["background_download"]["session_restoration_count"], 0)

    def test_contradictory_failure_event_cannot_be_hidden_by_passes(self) -> None:
        events = self.complete_events()
        events.append(event(100, "download", "completed_atomically", result="fail", reason="synthetic_failure"))
        summary = self.summarize(events)
        self.assertEqual(summary["result"], "fail")
        self.assertEqual(summary["status"], "fail")

    def test_duplicate_acknowledgement_or_missing_remote_codec_fails(self) -> None:
        events = self.complete_events()
        events.append(event(99, "download", "events_acknowledged"))
        events = [value for value in events if not (
            value["category"] == "codec"
            and value["facts"].get("codec") == "opus_ogg"
            and value["facts"].get("source") == "remote_http_synthetic"
        )]
        summary = self.summarize(events)
        self.assertEqual(summary["result"], "fail")
        self.assertEqual(summary["status"], "fail")
        self.assertEqual(summary["proofs"]["background_download"]["delegate_acknowledgement_count"], 2)

    def test_committed_device_and_external_status_use_common_envelope(self) -> None:
        records = (
            (ROOT / "docs/evidence/phase-0/device/execution-status.json", "device"),
            (ROOT / "docs/evidence/phase-0/platform/external-status.json", "platform"),
        )
        for path, workstream in records:
            with self.subTest(path=path):
                assert_common_envelope(self, json.loads(path.read_text(encoding="utf-8")), workstream)


if __name__ == "__main__":
    unittest.main()
