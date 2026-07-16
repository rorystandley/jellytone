#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("inventory", type=Path)
parser.add_argument("--metadata-output", type=Path)
arguments = parser.parse_args()

inventory = json.loads(arguments.inventory.read_text(encoding="utf-8"))
devices = inventory.get("result", {}).get("devices", [])
eligible = []
for device in devices:
    connection = device.get("connectionProperties", {})
    properties = device.get("deviceProperties", {})
    hardware = device.get("hardwareProperties", {})
    identifier = device.get("identifier")
    if not isinstance(identifier, str):
        continue
    if connection.get("pairingState") != "paired":
        continue
    if connection.get("tunnelState") != "connected":
        continue
    if properties.get("developerModeStatus") != "enabled":
        continue
    if hardware.get("reality") != "physical" or hardware.get("deviceType") not in {"iPhone", "iPad"}:
        continue
    eligible.append(device)

if not eligible:
    raise SystemExit("blocked: no paired physical iPhone or iPad with Developer Mode enabled")

selected = sorted(
    eligible,
    key=lambda item: (
        item.get("hardwareProperties", {}).get("deviceType") != "iPhone",
        item.get("hardwareProperties", {}).get("marketingName", ""),
        item["identifier"],
    ),
)[0]
if arguments.metadata_output:
    hardware = selected.get("hardwareProperties", {})
    properties = selected.get("deviceProperties", {})
    metadata = {
        "model": hardware.get("marketingName", "unknown"),
        "os": properties.get("osVersionNumber", "unknown"),
        "platform": hardware.get("platform", "unknown"),
        "deviceType": hardware.get("deviceType", "unknown"),
    }
    arguments.metadata_output.parent.mkdir(parents=True, exist_ok=True)
    arguments.metadata_output.write_text(json.dumps(metadata, sort_keys=True) + "\n", encoding="utf-8")

print(selected["identifier"])
