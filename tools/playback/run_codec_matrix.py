#!/usr/bin/env python3
"""Generate machine-readable ffprobe + AVFoundation local/HTTP evidence."""
from __future__ import annotations

import json
import hashlib
import os
import pathlib
import platform
import subprocess
import sys
import tempfile
import time

from evidence_envelope import playback_envelope

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "Tests/Fixtures/Audio"
RESULTS = pathlib.Path(os.environ.get(
    "PHASE0_PLAYBACK_EVIDENCE_DIR",
    ROOT / "docs/evidence/phase-0/playback/results",
))
OUT = RESULTS / "codec-matrix.json"


def capture(command: list[str]) -> str:
    return subprocess.run(command, check=True, text=True, capture_output=True).stdout


def main() -> None:
    subprocess.run([sys.executable, str(ROOT / "tools/playback/generate_fixtures.py")], check=True)
    manifest = json.loads((FIXTURES / "manifest.json").read_text())
    source_rows = [row for row in manifest["fixtures"] if row["id"] != "pcm_b"]
    media = [FIXTURES / row["file"] for row in source_rows]
    transcoded = {}
    with tempfile.TemporaryDirectory() as transcode_directory:
        for row in source_rows:
            path = FIXTURES / f"transcoded-from-{row['id']}.m4a"
            generated = pathlib.Path(transcode_directory) / path.name
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i",
                            str(FIXTURES / row["file"]), "-c:a", "aac", "-b:a", "160k",
                            "-ac", "2", "-ar", "48000", "-map_metadata", "-1", str(generated)], check=True)
            data = generated.read_bytes()
            if not path.exists() or path.read_bytes() != data:
                path.write_bytes(data)
            transcoded[row["id"]] = path
    ff = {}
    for path in [*media, *transcoded.values()]:
        ff[path.name] = json.loads(capture(["ffprobe", "-v", "error", "-show_entries",
            "format=format_name,duration:stream=codec_name,codec_type,sample_rate,channels", "-of", "json", str(path)]))
    with tempfile.TemporaryDirectory() as temp:
        binary = pathlib.Path(temp) / "capability-probe"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                        str(ROOT / "Prototypes/Playback/CapabilityProbe.swift"), "-o", str(binary)], check=True)
        server = subprocess.Popen([sys.executable, str(ROOT / "tools/playback/serve_fixtures.py"),
                                   "--directory", str(FIXTURES), "--port", "18765"])
        try:
            time.sleep(0.3)
            all_media = [*media, *transcoded.values()]
            urls = [path.as_uri() for path in all_media] + [f"http://127.0.0.1:18765/{path.name}" for path in all_media]
            av = json.loads(capture([str(binary), *urls]))
        finally:
            server.terminate()
            server.wait()
    lookup = {(r["url"], r["transport"]): r for r in av}
    rows = []
    for item in source_rows:
        name = item["file"]
        transcode = transcoded[item["id"]]
        rows.append({"fixtureId": item["id"], "file": name, "sha256": item["sha256"],
                     "ffprobe": ff[name], "avFoundation": {
                         "local": lookup[(name, "local")],
                         "remoteLoopback": lookup[(name, "remote-loopback")]},
                     "aacTranscodeSurrogate": {"file": transcode.name,
                         "sha256": hashlib.sha256(transcode.read_bytes()).hexdigest(),
                         "ffprobe": ff[transcode.name],
                         "local": lookup[(transcode.name, "local")],
                         "remoteLoopback": lookup[(transcode.name, "remote-loopback")]}})
    host = {"platform": platform.platform(), "swift": capture(["xcrun", "swift", "--version"]).splitlines()[0],
            "ffprobe": capture(["ffprobe", "-version"]).splitlines()[0]}
    result = playback_envelope(
        proof_id="phase0-playback-codec-matrix",
        command="python3 tools/playback/run_codec_matrix.py",
        environment={"host": host, "fixtureSource": "deterministic-synthetic-audio"},
        limitations=["Host macOS AVFoundation preparation is not iOS/iPadOS device decode or audibility evidence."],
        output=OUT,
        payload={"scope": "macOS-host-probe-not-iOS-advertising-proof", "host": host, "results": rows},
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
