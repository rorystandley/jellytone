import json
import hashlib
import pathlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
RESULTS = ROOT / "docs/evidence/phase-0/playback/results"
GENERATED_RESULTS = pathlib.Path(os.environ.get("PHASE0_PLAYBACK_EVIDENCE_DIR", RESULTS))
COMMON_FIELDS = {
    "schemaVersion", "proofId", "capturedAt", "command", "environment",
    "owner", "status", "limitations", "privacy",
}
APPLE_HOST = sys.platform == "darwin" and shutil.which("xcrun") is not None


class PlaybackProofTests(unittest.TestCase):
    def test_playback_records_use_common_envelope(self):
        for path in sorted(RESULTS.glob("*.json")):
            with self.subTest(path=path.name):
                record = json.loads(path.read_text())
                self.assertTrue(COMMON_FIELDS.issubset(record))
                self.assertEqual(record["schemaVersion"], 1)
                self.assertEqual(record["owner"], {"phase": "Phase 0", "workstream": "playback"})
                self.assertIn(record["status"], {"pass", "fail", "blocked", "not-run"})
                self.assertTrue(record["capturedAt"].endswith("Z"))
                self.assertIs(record["privacy"]["redacted"], True)
                self.assertIs(record["privacy"]["committedEvidenceContainsSecrets"], False)
                self.assertIs(record["privacy"]["privateServerDataPersisted"], False)

        source_policy = json.loads((RESULTS / "source-policy.json").read_text())
        self.assertEqual(source_policy["status"], "pass")
        self.assertEqual(source_policy["policyStatus"], "provisional-until-iOS-device-matrix")
        timestamps = {
            json.loads((RESULTS / name).read_text())["capturedAt"]
            for name in ("codec-matrix.json", "session-order.json", "source-policy.json", "transition-measurements.json")
        }
        self.assertEqual(len(timestamps), 1)

    @unittest.skipUnless(APPLE_HOST, "regenerates macOS-captured playback evidence")
    def test_transition_measurement_is_sample_bounded(self):
        subprocess.run([sys.executable, str(ROOT / "tools/playback/render_transitions.py")], check=True)
        report = json.loads((GENERATED_RESULTS / "transition-measurements.json").read_text())
        limits = report["acceptance"]
        for result in report["results"].values():
            self.assertLessEqual(result["durationErrorSamples"], limits["durationErrorSamplesMax"])
            self.assertLessEqual(result["longestDigitalSilenceSamples"], limits["longestDigitalSilenceSamplesMax"])

    def test_fixture_manifest_has_unique_reproducible_ids(self):
        with tempfile.TemporaryDirectory() as temp:
            output = pathlib.Path(temp)
            subprocess.run([
                sys.executable, str(ROOT / "tools/playback/generate_fixtures.py"),
                "--output", str(output),
            ], check=True)
            manifest = json.loads((output / "manifest.json").read_text())
            ids = [item["id"] for item in manifest["fixtures"]]
            self.assertEqual(len(ids), len(set(ids)))
            self.assertEqual({"mp3", "aac", "alac", "flac", "vorbis_ogg", "opus_ogg", "opus_mp4"}, set(ids) - {"pcm_a", "pcm_b"})

    def test_fixture_generation_is_byte_reproducible(self):
        generator = str(ROOT / "tools/playback/generate_fixtures.py")
        with tempfile.TemporaryDirectory() as temp:
            first_directory = pathlib.Path(temp) / "first-clean-run"
            second_directory = pathlib.Path(temp) / "second-clean-run"
            subprocess.run([sys.executable, generator, "--output", str(first_directory)], check=True)
            subprocess.run([sys.executable, generator, "--output", str(second_directory)], check=True)
            first = {path.name: path.read_bytes() for path in first_directory.iterdir()}
            second = {path.name: path.read_bytes() for path in second_directory.iterdir()}
            self.assertEqual(first, second)
            manifest = json.loads(first["manifest.json"])
            self.assertEqual(set(first), {"manifest.json", *(row["file"] for row in manifest["fixtures"])})
            for row in manifest["fixtures"]:
                self.assertEqual(row["sha256"], hashlib.sha256(first[row["file"]]).hexdigest())

    @unittest.skipUnless(APPLE_HOST, "requires macOS xcrun/AVFoundation")
    def test_full_sequence_leaves_codec_report_hashes_current(self):
        sequence = [ROOT / "tools/playback/run_codec_matrix.py", ROOT / "tools/playback/render_transitions.py",
                    ROOT / "tools/playback/validate_session_order.py"]
        for script in sequence:
            subprocess.run([sys.executable, str(script)], check=True)
        report = json.loads((GENERATED_RESULTS / "codec-matrix.json").read_text())
        fixture_dir = ROOT / "Tests/Fixtures/Audio"
        for row in report["results"]:
            self.assertEqual(row["sha256"], hashlib.sha256((fixture_dir / row["file"]).read_bytes()).hexdigest())
            transcode = row["aacTranscodeSurrogate"]
            self.assertEqual(transcode["sha256"], hashlib.sha256((fixture_dir / transcode["file"]).read_bytes()).hexdigest())
        evidence_paths = [GENERATED_RESULTS / "codec-matrix.json",
                          GENERATED_RESULTS / "transition-measurements.json",
                          GENERATED_RESULTS / "session-order.json"]
        first_evidence = {path.name: path.read_bytes() for path in evidence_paths}
        first_media = {path.name: path.read_bytes() for path in fixture_dir.iterdir() if path.is_file()}
        for script in sequence:
            subprocess.run([sys.executable, str(script)], check=True)
        self.assertEqual(first_evidence, {path.name: path.read_bytes() for path in evidence_paths})
        self.assertEqual(first_media, {path.name: path.read_bytes() for path in fixture_dir.iterdir() if path.is_file()})

    def test_replacement_closes_previous_session_before_start(self):
        subprocess.run([sys.executable, str(ROOT / "tools/playback/validate_session_order.py")], check=True)
        report = json.loads((GENERATED_RESULTS / "session-order.json").read_text())
        self.assertTrue(report["passed"])
        self.assertEqual(["start", "progress", "stop", "start", "progress", "stop", "start"],
                         [event["event"] for event in report["events"]])


if __name__ == "__main__":
    unittest.main()
