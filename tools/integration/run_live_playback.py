#!/usr/bin/env python3
"""Exercise the production Jellyfin gateway against both disposable servers.

All credentials, endpoints and Jellyfin identities remain process-local. Output
and the returned summary contain only fixed labels, versions, status classes and
codec/container facts from synthetic media.
"""

from __future__ import annotations

from contextlib import contextmanager
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from typing import Any, Iterator
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[2]
VERSIONS_FILE = ROOT / "infra" / "jellyfin" / "versions.env"
STATE_ROOT = ROOT / "infra" / "jellyfin" / ".state"
FIXTURE_MARKER = "Phase Two Unsupported Source"
GENRE_MARKER = "Phase Three Fixture Genre"
GENRE_TRACK_MARKER = "Phase Three Genre Track"
PRIVATE_KEYS = {
    "accesstoken", "password", "pw", "token", "secret", "code", "url",
    "address", "serverid", "userid", "itemid", "mediasourceid", "playsessionid",
    "username", "name", "title", "album", "artist",
}


class IntegrationFailure(RuntimeError):
    pass


def versions() -> list[tuple[str, str, str]]:
    values: dict[str, str] = {}
    for line in VERSIONS_FILE.read_text(encoding="utf-8").splitlines():
        key, value = line.split("=", 1)
        values[key] = value
    return [
        ("current", values["JELLYFIN_CURRENT_VERSION"], "http://127.0.0.1:18096"),
        ("previous", values["JELLYFIN_PREVIOUS_VERSION"], "http://127.0.0.1:18097"),
    ]


def require_prerequisites() -> None:
    missing = [name for name in ("docker", "ffmpeg", "ffprobe", "jq", "swift") if not shutil.which(name)]
    if missing:
        raise IntegrationFailure("external prerequisite unavailable: " + ", ".join(missing))
    probe = subprocess.run(
        ["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False
    )
    if probe.returncode:
        raise IntegrationFailure("external prerequisite unavailable: Docker daemon is not running")


def run(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command, cwd=ROOT, check=False, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )
    if completed.returncode:
        if capture:
            output = completed.stdout or ""
            for failure in (
                "versionMismatch", "fixtureMissing", "genreListEmpty", "genreMarkerMissing",
                "genreAlbumMissing", "genreTrackMissing",
                "homeRecentlyAddedMissing", "homeRecentlyPlayedMissing",
                "wrongPlaybackMethod", "deliveryFailed", "reportingFailed",
            ):
                if failure in output:
                    raise IntegrationFailure(f"production gateway harness reported {failure}")
        raise subprocess.CalledProcessError(completed.returncode, command)
    return completed


def build_harness(output: Path) -> None:
    run([
        "swiftc", "-parse-as-library", "-o", str(output),
        str(ROOT / "Domain" / "Models.swift"),
        str(ROOT / "JellyfinGateway" / "JellyfinAPI.swift"),
        str(ROOT / "tools" / "integration" / "ProductionGatewayHarness.swift"),
    ])


def provision_servers() -> None:
    command = [str(ROOT / "tools" / "phase0" / "jellyfin.sh")]
    reset = subprocess.run(
        command + ["reset"], cwd=ROOT, check=False, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    if reset.returncode == 0:
        return
    # A freshly created container can briefly answer Public Info before all
    # startup endpoints accept writes. The repository's idempotent `up` path
    # waits again and completes only the same disposable state.
    retry = subprocess.run(
        command + ["up"], cwd=ROOT, check=False, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    if retry.returncode:
        raise IntegrationFailure("disposable Jellyfin provisioning failed after the bounded reset/up retry")


def add_unsupported_fixture() -> None:
    destination = STATE_ROOT / "media" / "Phase Two Integration" / "01 Unsupported.wma"
    destination.parent.mkdir(parents=True, exist_ok=True)
    run([
        "ffmpeg", "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", "sine=frequency=915:sample_rate=48000:duration=1",
        "-map_metadata", "-1", "-ac", "2", "-c:a", "wmav2", "-b:a", "128k",
        "-metadata", f"title={FIXTURE_MARKER}",
        "-metadata", "album=Phase Two Integration",
        "-metadata", "artist=Fixture Artist",
        "-metadata", "album_artist=Fixture Artist",
        "-metadata", f"genre={GENRE_MARKER}",
        "-metadata", "disc=1", "-metadata", "track=1", str(destination),
    ])
    genre_destination = destination.with_name("02 Genre.mp3")
    run([
        "ffmpeg", "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", "sine=frequency=1015:sample_rate=48000:duration=1",
        "-map_metadata", "-1", "-ac", "2", "-c:a", "libmp3lame", "-b:a", "128k",
        "-metadata", f"title={GENRE_TRACK_MARKER}",
        "-metadata", "album=Phase Three Genre Album",
        "-metadata", "artist=Fixture Artist",
        "-metadata", "album_artist=Fixture Artist",
        "-metadata", f"genre={GENRE_MARKER}",
        "-metadata", "disc=1", "-metadata", "track=2", str(genre_destination),
    ])


def refresh_libraries() -> None:
    for label, _version, endpoint in versions():
        parsed = urlsplit(endpoint)
        password = (STATE_ROOT / label / "fixture-password").read_text(encoding="utf-8")
        connection = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=15)
        authorization = 'MediaBrowser Client="Phase2Integration", Device="Agent", DeviceId="phase2-live-integration", Version="1"'
        try:
            body = json.dumps({"Username": "root", "Pw": password}).encode("utf-8")
            connection.request(
                "POST", "/Users/AuthenticateByName", body=body,
                headers={"Content-Type": "application/json", "X-Emby-Authorization": authorization},
            )
            response = connection.getresponse()
            payload = response.read()
            if response.status // 100 != 2:
                raise IntegrationFailure("disposable server rejected fixture-library refresh authentication")
            token = json.loads(payload).get("AccessToken")
            if not isinstance(token, str) or not token:
                raise IntegrationFailure("disposable server omitted the fixture-library refresh credential")
            connection.close()
            connection = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=15)
            connection.request("POST", "/Library/Refresh", headers={"X-Emby-Token": token})
            response = connection.getresponse()
            response.read()
            if response.status // 100 != 2:
                raise IntegrationFailure("disposable server rejected fixture-library refresh")
        finally:
            password = ""
            connection.close()


class CaptureProxy(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, upstream: str):
        self.upstream = urlsplit(upstream)
        self.events: list[dict[str, Any]] = []
        self.transcode_requested = False
        super().__init__(("127.0.0.1", 0), CaptureHandler)


class CaptureHandler(BaseHTTPRequestHandler):
    server: CaptureProxy

    def do_GET(self) -> None:  # noqa: N802
        self._forward()

    def do_POST(self) -> None:  # noqa: N802
        self._forward()

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def _forward(self) -> None:
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        upstream = self.server.upstream
        connection = http.client.HTTPConnection(upstream.hostname, upstream.port, timeout=45)
        headers = {
            key: value for key, value in self.headers.items()
            if key.lower() not in {"host", "content-length", "connection", "accept-encoding"}
        }
        headers["Host"] = upstream.netloc
        try:
            connection.request(self.command, self.path, body=body or None, headers=headers)
            response = connection.getresponse()
            payload = response.read()
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in {"connection", "transfer-encoding", "content-length", "content-encoding"}:
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            self._capture(response.status, body)
        finally:
            connection.close()

    def _capture(self, status: int, body: bytes) -> None:
        path = urlsplit(self.path).path
        if path.startswith("/Audio/") and path.endswith("/universal"):
            self.server.transcode_requested = True
        event = None
        if path == "/Sessions/Playing":
            event = "start"
        elif path == "/Sessions/Playing/Progress":
            event = "progress"
        elif path == "/Sessions/Playing/Stopped":
            event = "stop"
        if event is None:
            return
        parsed = json.loads(body) if body else {}
        record: dict[str, Any] = {"event": event, "statusClass": f"{status // 100}xx"}
        if event == "progress":
            record["paused"] = parsed.get("IsPaused") is True
        record["positionTicks"] = parsed.get("PositionTicks")
        self.server.events.append(record)


@contextmanager
def capture_proxy(upstream: str) -> Iterator[CaptureProxy]:
    server = CaptureProxy(upstream)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def validate_lifecycle(events: list[dict[str, Any]]) -> None:
    expected = ["start", "progress", "progress", "progress", "progress", "stop"]
    if [event.get("event") for event in events] != expected:
        raise IntegrationFailure("controlled capture did not observe the ordered lifecycle")
    if any(event.get("statusClass") != "2xx" for event in events):
        raise IntegrationFailure("controlled capture observed a non-success reporting response")
    if [event.get("paused") for event in events[1:5]] != [False, True, False, False]:
        raise IntegrationFailure("controlled capture did not observe progress, pause, resume and seek")
    positions = [event.get("positionTicks") for event in events]
    if positions != [0, 2_500_000, 2_500_000, 2_500_000, 7_500_000, 10_000_000]:
        raise IntegrationFailure("controlled capture observed incorrect deterministic positions")


def validate_redacted_result(result: dict[str, Any]) -> None:
    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if str(key).lower() in PRIVATE_KEYS:
                    raise IntegrationFailure("redacted result contains a private field")
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
    walk(result)


def inspect_transcode(path: Path) -> dict[str, str]:
    completed = run([
        "ffprobe", "-v", "error", "-show_entries", "format=format_name:stream=codec_name,codec_type",
        "-of", "json", str(path),
    ], capture=True)
    payload = json.loads(completed.stdout)
    streams = payload.get("streams", [])
    if len(streams) != 1 or streams[0].get("codec_type") != "audio" or streams[0].get("codec_name") != "aac":
        raise IntegrationFailure("forced production transcode was not single-stream AAC audio")
    format_name = str(payload.get("format", {}).get("format_name", ""))
    if "mp4" not in format_name and "mov" not in format_name:
        raise IntegrationFailure("forced production transcode was not delivered in an MP4-family container")
    return {"codec": "aac", "container": "mp4-family"}


def main() -> int:
    stage = "prerequisite check"
    provisioned = False
    try:
        require_prerequisites()
        stage = "disposable server provisioning"
        provision_servers()
        provisioned = True
        stage = "unsupported synthetic fixture generation"
        add_unsupported_fixture()
        stage = "disposable library refresh"
        refresh_libraries()
        with tempfile.TemporaryDirectory(prefix="phase2-live-integration.") as temporary:
            temporary_path = Path(temporary)
            harness = temporary_path / "production-gateway-harness"
            stage = "production gateway harness compilation"
            build_harness(harness)
            results = []
            for label, version, upstream in versions():
                stage = f"{label} production gateway execution"
                output = temporary_path / f"{label}.m4a"
                password_file = STATE_ROOT / label / "fixture-password"
                with capture_proxy(upstream) as proxy:
                    endpoint = f"http://127.0.0.1:{proxy.server_port}"
                    completed = run([
                        str(harness), endpoint, version, str(password_file), str(output), FIXTURE_MARKER,
                    ], capture=True)
                    if "LIVE_GATEWAY_RESULT version=pass tracks=complete genre=complete home=complete transcode=aac-mp4 lifecycle=complete" not in completed.stdout:
                        raise IntegrationFailure("production gateway harness omitted its fixed success marker")
                    validate_lifecycle(proxy.events)
                    if not proxy.transcode_requested:
                        raise IntegrationFailure("controlled capture did not observe the universal transcode endpoint")
                results.append({
                    "serverLabel": label,
                    "version": version,
                    "genreBrowsing": "complete",
                    "homeShelves": "complete",
                    "lifecycle": [event["event"] for event in proxy.events],
                    "transcode": inspect_transcode(output),
                })
        result = {
            "status": "PASS",
            "scope": "production JellyfinAPI source against digest-pinned disposable servers",
            "fixtureContractsSeparated": True,
            "servers": results,
            "privacy": "credentials endpoints identities and library content omitted",
            "limitations": [
                "Host Swift URLSession and server delivery do not prove AVPlayer decode or physical-device playback.",
                "The controlled capture proves production gateway request ordering and server success responses, not Jellyfin database persistence internals.",
            ],
        }
        validate_redacted_result(result)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (IntegrationFailure, subprocess.CalledProcessError, OSError, json.JSONDecodeError) as error:
        if isinstance(error, IntegrationFailure):
            reason = str(error)
        elif isinstance(error, subprocess.CalledProcessError):
            reason = f"external command failed during {stage}; private runtime output was suppressed"
        else:
            reason = "live integration failed before redacted evidence was complete"
        print(f"BLOCKED/FAIL: {reason}", file=sys.stderr)
        return 1
    finally:
        # This lane owns the disposable compose project it reset. Keep teardown
        # bounded to that explicit compose file and suppress runtime details.
        if provisioned and shutil.which("docker"):
            subprocess.run(
                [str(ROOT / "tools" / "phase0" / "jellyfin.sh"), "down"],
                cwd=ROOT, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )


if __name__ == "__main__":
    sys.exit(main())
