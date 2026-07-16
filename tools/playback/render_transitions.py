#!/usr/bin/env python3
"""Render and objectively measure deterministic hard-cut/crossfade transitions."""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import time
import tempfile
import urllib.request
import wave

from evidence_envelope import playback_envelope

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIX = ROOT / "Tests/Fixtures/Audio"
RESULTS = pathlib.Path(os.environ.get(
    "PHASE0_PLAYBACK_EVIDENCE_DIR",
    ROOT / "docs/evidence/phase-0/playback/results",
))
OUT = RESULTS / "transition-measurements.json"
RATE = 48_000


def run(name: str, filter_graph: str, inputs: tuple[str, str]) -> pathlib.Path:
    path = FIX / name
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", inputs[0],
                    "-i", inputs[1], "-filter_complex", filter_graph,
                    "-map", "[out]", "-c:a", "pcm_s16le", str(path)], check=True)
    return path


def measure(path: pathlib.Path, expected_seconds: float) -> dict:
    with wave.open(str(path), "rb") as source:
        frames = source.readframes(source.getnframes())
        samples = [int.from_bytes(frames[i:i+2], "little", signed=True) for i in range(0, len(frames), 4)]
        longest = current = 0
        for sample in samples:
            current = current + 1 if abs(sample) <= 2 else 0
            longest = max(longest, current)
        duration = len(samples) / source.getframerate()
    return {"file": path.name, "durationSeconds": duration, "expectedDurationSeconds": expected_seconds,
            "durationErrorSamples": round(abs(duration - expected_seconds) * RATE),
            "longestDigitalSilenceSamples": longest, "sampleRate": RATE}


def main() -> None:
    subprocess.run([sys.executable, str(ROOT / "tools/playback/generate_fixtures.py")], check=True)
    hard_filter = "[0:a][1:a]concat=n=2:v=0:a=1[out]"
    fade_filter = "[0:a][1:a]acrossfade=d=0.25:c1=tri:c2=tri[out]"
    local_inputs = (str(FIX / "tone-a.wav"), str(FIX / "tone-b.wav"))
    local_hard = run("transition-local-hard.wav", hard_filter, local_inputs)
    local_fade = run("transition-local-crossfade-250ms.wav", fade_filter, local_inputs)
    server = subprocess.Popen([sys.executable, str(ROOT / "tools/playback/serve_fixtures.py"),
                               "--directory", str(FIX), "--port", "18766"])
    try:
        time.sleep(0.3)
        with tempfile.TemporaryDirectory() as temp:
            downloaded = []
            preload = []
            for name in ("tone-a.wav", "tone-b.wav"):
                data = urllib.request.urlopen(f"http://127.0.0.1:18766/{name}").read()
                path = pathlib.Path(temp) / name
                path.write_bytes(data)
                downloaded.append(str(path))
                preload.append({"file": name, "bytes": len(data)})
            remote_inputs = (downloaded[0], downloaded[1])
            remote_hard = run("transition-remote-hard.wav", hard_filter, remote_inputs)
            remote_fade = run("transition-remote-crossfade-250ms.wav", fade_filter, remote_inputs)
    finally:
        server.terminate()
        server.wait()
    result = playback_envelope(
        proof_id="phase0-playback-transition-measurements",
        command="python3 tools/playback/render_transitions.py",
        environment={"sampleRate": RATE, "renderer": "FFmpeg deterministic PCM render"},
        limitations=["Sample-domain fixture rendering is not AVPlayer acoustic, background, route, or device transition evidence."],
        output=OUT,
        payload={"scope": "deterministic-render-algorithm-not-device-output",
                 "results": {"localPreparedHardCut": measure(local_hard, 4.0),
                             "localLinearCrossfade250ms": measure(local_fade, 3.75),
                             "remoteLoopbackPreparedHardCut": {**measure(remote_hard, 4.0), "preload": preload},
                             "remoteLoopbackLinearCrossfade250ms": {**measure(remote_fade, 3.75), "preload": preload}},
                 "acceptance": {"durationErrorSamplesMax": 1, "longestDigitalSilenceSamplesMax": 4}},
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
