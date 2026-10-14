#!/usr/bin/env python3
import argparse, datetime, json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("destination", type=Path)
parser.add_argument("--require-pass", action="store_true")
parser.add_argument("--device-metadata", type=Path)
arguments = parser.parse_args()
source = arguments.source
destination = arguments.destination
device = {"model": "not-captured", "os": "not-captured", "platform": "not-captured", "identifier": "redacted"}
if arguments.device_metadata:
    captured_device = json.loads(arguments.device_metadata.read_text(encoding="utf-8"))
    device.update({key: captured_device.get(key, "unknown") for key in ("model", "os", "platform")})
events = [json.loads(line) for line in source.read_text().splitlines() if line.strip()]
for event in events:
    serialized = json.dumps(event)
    if any(term in serialized.lower() for term in ["http://", "https://", "authorization", "bearer "]):
        raise SystemExit("privacy failure: unredacted network data in device events")
categories = {}
for event in events:
    categories.setdefault(event["category"], {"pass": 0, "fail": 0, "blocked": 0, "observed": 0})
    result = event["result"]
    categories[event["category"]][result] = categories[event["category"]].get(result, 0) + 1
required_codecs = {"mp3", "aac", "alac", "flac", "vorbis_ogg", "opus_ogg"}
run_identifiers = {event.get("runIdentifier") for event in events}
sequences = [event.get("sequence") for event in events]
integrity_pass = (
    bool(events)
    and len(run_identifiers) == 1
    and None not in run_identifiers
    and all(event.get("schemaVersion") == 1 for event in events)
    and sequences == list(range(1, len(events) + 1))
)
codec_passes = {
    (event.get("facts", {}).get("codec"), event.get("facts", {}).get("source"))
    for event in events
    if event.get("category") == "codec" and event.get("action") == "prepare" and event.get("result") == "pass"
}
local_codecs = sorted(codec for codec in required_codecs if (codec, "local_synthetic") in codec_passes)
remote_codecs = sorted(codec for codec in required_codecs if (codec, "remote_http_synthetic") in codec_passes)

def passing_actions(category):
    return [event.get("action") for event in events if event.get("category") == category and event.get("result") == "pass"]

def exercised_actions(category):
    return [
        event.get("action") for event in events
        if event.get("category") == category and event.get("result") in {"pass", "observed"}
    ]

download_actions = passing_actions("download")
acknowledgements = download_actions.count("events_acknowledged")
duplicate_acknowledgements = download_actions.count("duplicate_acknowledgement_rejected")
restorations = download_actions.count("session_restored")
installed_media = {
    event.get("facts", {}).get("media_identity")
    for event in events
    if event.get("category") == "download" and event.get("action") == "completed_atomically" and event.get("result") == "pass"
}
probed_media = {
    event.get("facts", {}).get("media_identity")
    for event in events
    if event.get("category") == "download" and event.get("action") == "final_file_probed" and event.get("result") == "pass"
}
required_download_media = {"aac", "mp3", "flac"}
network_transports = {
    event.get("facts", {}).get("transport")
    for event in events
    if event.get("category") == "network"
    and event.get("action") == "ats_lan_probe"
    and event.get("result") == "pass"
}
playback_actions = set(passing_actions("playback"))
remote_actions = set(passing_actions("remote"))
route_actions = set(exercised_actions("route"))
interruption_actions = set(exercised_actions("interruption"))
required_remote_actions = {"registered", "play", "pause", "seek", "previous", "next"}
platform_pass = (
    network_transports >= {"https", "local_http"}
    and playback_actions >= {"background_audio_started", "background_continuity_observed"}
    and remote_actions >= required_remote_actions
    and route_actions >= {"baseline", "changed"}
    and interruption_actions >= {"began", "ended"}
)
has_disqualifying_event = any(
    event.get("result") == "fail"
    for event in events
)
download_pass = (
    "scheduled" in download_actions
    and installed_media == required_download_media
    and probed_media == required_download_media
    and restorations == 1
    and acknowledgements == 1
    and duplicate_acknowledgements == 0
    and not has_disqualifying_event
)
codec_pass = (
    set(local_codecs) == required_codecs
    and set(remote_codecs) == required_codecs
    and not has_disqualifying_event
)
overall_pass = integrity_pass and codec_pass and download_pass and platform_pass
result = {
    "schemaVersion": 1,
    "proofId": "phase0-device-runtime-results",
    "capturedAt": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "command": "./tools/device-proof/collect.sh",
    "environment": {
        "platform": "physical iOS device",
        "harnessType": "isolated non-production proof",
    },
    "owner": {"phase": "Phase 0", "workstream": "device"},
    "status": "pass" if overall_pass else "fail",
    "harness": "isolated-phase0-device-proof",
    "device": device,
    "syntheticDataOnly": True,
    "eventCount": len(events),
    "eventIntegrity": {
        "singleRun": len(run_identifiers) == 1 and None not in run_identifiers,
        "strictSequence": sequences == list(range(1, len(events) + 1)),
        "result": "pass" if integrity_pass else "fail",
    },
    "categories": categories,
    "proofs": {
        "codec_preparation": {
            "required": sorted(required_codecs),
            "local_passed": local_codecs,
            "remote_http_passed": remote_codecs,
            "result": "pass" if codec_pass else "fail",
        },
        "background_download": {
            "scheduled": "scheduled" in download_actions,
            "session_restoration_count": restorations,
            "required_media": sorted(required_download_media),
            "manifest_validated_and_atomically_installed": sorted(value for value in installed_media if value),
            "final_file_reopened_and_probed": sorted(value for value in probed_media if value),
            "delegate_acknowledgement_count": acknowledgements,
            "duplicate_acknowledgement_count": duplicate_acknowledgements,
            "result": "pass" if download_pass else "fail",
        },
        "platform_runtime": {
            "network_transports_passed": sorted(value for value in network_transports if value),
            "playback_actions_passed": sorted(playback_actions),
            "remote_actions_passed": sorted(remote_actions),
            "required_remote_actions": sorted(required_remote_actions),
            "route_actions_exercised": sorted(route_actions),
            "interruption_actions_exercised": sorted(interruption_actions),
            "result": "pass" if platform_pass else "fail",
        },
    },
    "result": "pass" if overall_pass else "fail",
    "limitations": [
        "Launch proof does not establish locked-screen duration or process suspension.",
        "Physical route changes require an attached route and separate agent-operated execution.",
        "CarPlay is excluded because no entitlement was requested by this harness."
    ],
    "privacy": {
        "redacted": True,
        "committedEvidenceContainsSecrets": False,
        "privateServerDataPersisted": False,
        "notes": ["Synthetic media and ephemeral loopback or LAN transports only."],
    },
}
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
if arguments.require_pass and result["status"] != "pass":
    raise SystemExit("device proof summary did not pass")
