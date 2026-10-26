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
import urllib.error
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


def native_probe(binary: pathlib.Path, source: str, inputs: tuple[str, str]) -> dict:
    output = subprocess.check_output([str(binary), source, *inputs], text=True)
    return json.loads(output)


def wait_for_loopback_fixture(url: str) -> None:
    last_error: Exception | None = None
    for _ in range(30):
        try:
            request = urllib.request.Request(url, method="HEAD")
            with urllib.request.urlopen(request, timeout=2) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, TimeoutError) as error:
            last_error = error
        time.sleep(0.2)
    raise RuntimeError(f"loopback fixture server did not become ready: {last_error}")


def main() -> None:
    subprocess.run([sys.executable, str(ROOT / "tools/playback/generate_fixtures.py")], check=True)
    hard_filter = "[0:a][1:a]concat=n=2:v=0:a=1[out]"
    fade_filter = "[0:a][1:a]acrossfade=d=0.25:c1=tri:c2=tri[out]"
    local_inputs = (str(FIX / "tone-a.wav"), str(FIX / "tone-b.wav"))
    local_hard = run("transition-local-hard.wav", hard_filter, local_inputs)
    local_fade = run("transition-local-crossfade-250ms.wav", fade_filter, local_inputs)
    with tempfile.TemporaryDirectory() as temp:
        native_binary = pathlib.Path(temp) / "native-transition-probe"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-O", "-framework", "AVFoundation",
                        str(ROOT / "Prototypes/Playback/NativeTransitionProbe.swift"),
                        "-o", str(native_binary)], check=True)
        native_local_urls = tuple(pathlib.Path(path).as_uri() for path in local_inputs)
        native_local = native_probe(native_binary, "local-file", native_local_urls)
        server = subprocess.Popen([sys.executable, str(ROOT / "tools/playback/serve_fixtures.py"),
                                   "--directory", str(FIX), "--port", "18766"])
        try:
            remote_urls = ("http://127.0.0.1:18766/tone-a.wav",
                           "http://127.0.0.1:18766/tone-b.wav")
            wait_for_loopback_fixture(remote_urls[0])
            downloaded = []
            preload = []
            for name in ("tone-a.wav", "tone-b.wav"):
                data = urllib.request.urlopen(f"http://127.0.0.1:18766/{name}").read()
                path = pathlib.Path(temp) / name
                path.write_bytes(data)
                downloaded.append(str(path))
                preload.append({"file": name, "bytes": len(data)})
            native_remote_urls = tuple(pathlib.Path(path).as_uri() for path in downloaded)
            native_remote = native_probe(native_binary, "remote-loopback-preloaded", native_remote_urls)
            remote_inputs = (downloaded[0], downloaded[1])
            remote_hard = run("transition-remote-hard.wav", hard_filter, remote_inputs)
            remote_fade = run("transition-remote-crossfade-250ms.wav", fade_filter, remote_inputs)
        finally:
            server.terminate()
            server.wait()
    native_results = {
        "nativeLocalHardCut": {**native_local["hardCut"], "engine": native_local["engine"], "source": native_local["source"]},
        "nativeLocalLinearCrossfade250ms": {**native_local["linearCrossfade250ms"], "engine": native_local["engine"], "source": native_local["source"]},
        "nativeRemotePreloadedHardCut": {**native_remote["hardCut"], "engine": native_remote["engine"], "source": native_remote["source"]},
        "nativeRemotePreloadedLinearCrossfade250ms": {**native_remote["linearCrossfade250ms"], "engine": native_remote["engine"], "source": native_remote["source"]},
    }
    result = playback_envelope(
        proof_id="phase0-playback-transition-measurements",
        command="python3 tools/playback/render_transitions.py",
        environment={"sampleRate": RATE, "renderer": "FFmpeg reference plus AVAudioEngine offline manual rendering"},
        limitations=["Host offline rendering is not AVPlayer acoustic, background, route, or device transition evidence.",
                     "Remote inputs are fully preloaded over loopback before native rendering; streaming-buffer behavior remains unproven."],
        output=OUT,
        payload={"scope": "deterministic-render-algorithm-not-device-output",
                 "results": {"localPreparedHardCut": measure(local_hard, 4.0),
                             "localLinearCrossfade250ms": measure(local_fade, 3.75),
                             "remoteLoopbackPreparedHardCut": {**measure(remote_hard, 4.0), "preload": preload},
                             "remoteLoopbackLinearCrossfade250ms": {**measure(remote_fade, 3.75), "preload": preload},
                             **native_results},
                 "acceptance": {"durationErrorSamplesMax": 1, "longestDigitalSilenceSamplesMax": 4}},
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
