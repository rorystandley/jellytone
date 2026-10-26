from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SELECTOR = ROOT / "tools" / "device-proof" / "select_device.py"


def device(
    identifier: str,
    kind: str,
    model: str,
    paired: bool = True,
    developer: bool = True,
    connected: bool = True,
) -> dict:
    return {
        "identifier": identifier,
        "connectionProperties": {
            "pairingState": "paired" if paired else "unpaired",
            "tunnelState": "connected" if connected else "unavailable",
        },
        "deviceProperties": {
            "developerModeStatus": "enabled" if developer else "disabled",
            "osVersionNumber": "26.5.2",
        },
        "hardwareProperties": {
            "reality": "physical",
            "deviceType": kind,
            "marketingName": model,
            "platform": "iOS",
        },
    }


class SelectDeviceTests(unittest.TestCase):
    def run_selector(
        self,
        devices: list[dict],
        *,
        allow_disconnected: bool = False,
    ) -> tuple[subprocess.CompletedProcess[str], dict | None]:
        with tempfile.TemporaryDirectory() as directory:
            inventory = Path(directory) / "inventory.json"
            metadata = Path(directory) / "metadata.json"
            inventory.write_text(json.dumps({"result": {"devices": devices}}), encoding="utf-8")
            command = ["python3", str(SELECTOR), str(inventory), "--metadata-output", str(metadata)]
            if allow_disconnected:
                command.append("--allow-disconnected")
            result = subprocess.run(
                command,
                text=True,
                capture_output=True,
                check=False,
            )
            return result, json.loads(metadata.read_text(encoding="utf-8")) if metadata.exists() else None

    def test_selects_eligible_physical_phone_without_persisting_identifier(self) -> None:
        result, metadata = self.run_selector([
            device("ipad-id", "iPad", "iPad Pro"),
            device("phone-id", "iPhone", "Synthetic iPhone"),
        ])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "phone-id")
        self.assertEqual(metadata, {
            "deviceType": "iPhone",
            "model": "Synthetic iPhone",
            "os": "26.5.2",
            "platform": "iOS",
        })
        self.assertNotIn("phone-id", json.dumps(metadata))

    def test_rejects_unpaired_or_developer_mode_disabled_devices(self) -> None:
        result, metadata = self.run_selector([
            device("unpaired", "iPhone", "Phone", paired=False),
            device("disabled", "iPad", "Tablet", developer=False),
        ])
        self.assertEqual(result.returncode, 1)
        self.assertIsNone(metadata)

    def test_rejects_disconnected_device(self) -> None:
        result, metadata = self.run_selector([
            device("disconnected", "iPhone", "Phone", connected=False),
        ])
        self.assertEqual(result.returncode, 1)
        self.assertIsNone(metadata)

    def test_allows_device_operation_to_create_tunnel(self) -> None:
        result, metadata = self.run_selector(
            [device("disconnected", "iPhone", "Phone", connected=False)],
            allow_disconnected=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "disconnected")
        self.assertIsNotNone(metadata)


if __name__ == "__main__":
    unittest.main()
