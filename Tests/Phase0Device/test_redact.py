from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
REDACT = ROOT / "tools" / "device-proof" / "redact.py"


class RedactTests(unittest.TestCase):
    def test_hyphenated_device_names_are_removed_and_model_names_stay(self) -> None:
        source = "\n".join([
            "Alexs-iPhone",
            "Alex's-iPhone",
            "alexs-iphone",
            "Sam-iPhone",
            "iPhone 13",
            "http://192.168.1.4:8080/file",
        ]) + "\n"
        with tempfile.TemporaryDirectory() as directory:
            raw = Path(directory) / "raw.log"
            redacted = Path(directory) / "redacted.log"
            raw.write_text(source, encoding="utf-8")
            subprocess.run(["python3", str(REDACT), str(raw), str(redacted)], check=True)
            text = redacted.read_text(encoding="utf-8")
        self.assertNotIn("Alex", text)
        self.assertNotIn("alex", text)
        self.assertNotIn("Sam", text)
        self.assertEqual(text.lower().count("<redacted-device-name>"), 4)
        self.assertIn("iPhone 13", text)
        self.assertIn("<redacted-url>", text)
        self.assertNotIn("192.168.1.4", text)
