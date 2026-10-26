#!/usr/bin/env python3
"""Generate deterministic, synthetic two-track audio fixtures."""
from __future__ import annotations

import hashlib
import argparse
import json
import math
import pathlib
import shutil
import struct
import subprocess
import tempfile
import wave

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Tests/Fixtures/Audio"
RATE = 48_000
SECONDS = 2


def wav(path: pathlib.Path, frequency: float, phase: float) -> None:
    with wave.open(str(path), "wb") as output:
        output.setparams((2, 2, RATE, RATE * SECONDS, "NONE", "not compressed"))
        frames = bytearray()
        for index in range(RATE * SECONDS):
            envelope = min(1.0, index / 480.0, (RATE * SECONDS - 1 - index) / 480.0)
            sample = int(0.55 * envelope * 32767 * math.sin(2 * math.pi * frequency * index / RATE + phase))
            frames.extend(struct.pack("<hh", sample, sample))
        output.writeframes(frames)


def run(command: list[str]) -> None:
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def ogg_crc(page: bytes) -> int:
    crc = 0
    for value in page:
        crc ^= value << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if crc & 0x80000000 else (crc << 1) & 0xFFFFFFFF
    return crc


def normalize_ogg(path: pathlib.Path, serial: int) -> None:
    """Replace FFmpeg's random Ogg stream serial and recompute page CRCs."""
    data = bytearray(path.read_bytes())
    offset = 0
    while offset < len(data):
        if data[offset:offset + 4] != b"OggS":
            raise ValueError(f"invalid Ogg capture pattern at byte {offset}")
        segment_count = data[offset + 26]
        header_size = 27 + segment_count
        page_size = header_size + sum(data[offset + 27:offset + header_size])
        end = offset + page_size
        data[offset + 14:offset + 18] = serial.to_bytes(4, "little")
        data[offset + 22:offset + 26] = b"\0\0\0\0"
        data[offset + 22:offset + 26] = ogg_crc(data[offset:end]).to_bytes(4, "little")
        offset = end
    path.write_bytes(data)


def install_if_changed(source: pathlib.Path, destination: pathlib.Path) -> None:
    data = source.read_bytes()
    if not destination.exists() or destination.read_bytes() != data:
        destination.write_bytes(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, default=OUT)
    args = parser.parse_args()
    output_directory = args.output
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is required")
    output_directory.mkdir(parents=True, exist_ok=True)
    encodings = {
        "mp3": ("tone-a.mp3", ["-c:a", "libmp3lame", "-b:a", "192k"]),
        "aac": ("tone-a.m4a", ["-c:a", "aac", "-b:a", "192k"]),
        "alac": ("tone-a-alac.m4a", ["-c:a", "alac"]),
        "flac": ("tone-a.flac", ["-c:a", "flac"]),
        "vorbis_ogg": ("tone-a-vorbis.ogg", ["-c:a", "vorbis", "-q:a", "5", "-strict", "experimental"]),
        "opus_ogg": ("tone-a-opus.ogg", ["-c:a", "libopus", "-b:a", "160k"]),
        "opus_mp4": ("tone-a-opus.mp4", ["-c:a", "libopus", "-b:a", "160k", "-strict", "experimental"]),
    }
    fixtures = []
    with tempfile.TemporaryDirectory() as directory:
        temp = pathlib.Path(directory)
        a, b = temp / "tone-a.wav", temp / "tone-b.wav"
        wav(a, 440.0, 0.0)
        wav(b, 660.0, math.pi / 2)
        for key, (name, options) in encodings.items():
            path = temp / name
            run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(a), *options,
                 "-map_metadata", "-1", str(path)])
            if key == "vorbis_ogg":
                normalize_ogg(path, 0x4A464956)
            elif key == "opus_ogg":
                normalize_ogg(path, 0x4A46494F)
            install_if_changed(path, output_directory / name)
            fixtures.append({"id": key, "file": name})
        install_if_changed(a, output_directory / a.name)
        install_if_changed(b, output_directory / b.name)
        fixtures.extend([{"id": "pcm_a", "file": a.name}, {"id": "pcm_b", "file": b.name}])
    for item in fixtures:
        data = (output_directory / item["file"]).read_bytes()
        item["sha256"] = hashlib.sha256(data).hexdigest()
        item["bytes"] = len(data)
    manifest = {"schemaVersion": 1, "sampleRate": RATE, "durationSeconds": SECONDS,
                "source": "synthetic sine waves; no private media", "fixtures": fixtures}
    manifest_data = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    manifest_path = output_directory / "manifest.json"
    if not manifest_path.exists() or manifest_path.read_bytes() != manifest_data:
        manifest_path.write_bytes(manifest_data)


if __name__ == "__main__":
    main()
