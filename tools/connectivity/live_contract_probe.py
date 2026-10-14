#!/usr/bin/env python3
"""Run redacted authenticated contracts against disposable loopback servers.

Passwords are read from mode-0600 files. Passwords, access tokens, user/item/server
identifiers, Quick Connect codes, and secrets remain process-local and are never
included in the report.
"""

from __future__ import annotations

import argparse
from contextlib import suppress
from datetime import datetime, timezone
from enum import Enum
import json
from pathlib import Path
import platform
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener
import uuid

from connectivity_policy import normalize_endpoint, same_server_identity


EVIDENCE_COMMAND = (
    "PYTHONDONTWRITEBYTECODE=1 python3 tools/connectivity/live_contract_probe.py "
    "> docs/evidence/phase-0/connectivity/live-contract-results.json"
)


class ContractFailure(RuntimeError):
    pass


class QuickConnectPollOutcome(str, Enum):
    PENDING = "pending"
    AUTHORIZED = "authorized"
    DENIED = "denied"
    EXPIRED = "expired"
    TIMED_OUT = "timed_out"
    CANCELLED = "cancelled"


def classify_quick_connect_poll(
    status: int,
    payload: Any,
    *,
    now: float,
    deadline: float,
    cancelled: bool,
) -> QuickConnectPollOutcome:
    """Map observable API/client state without inventing a server reason."""
    if cancelled:
        return QuickConnectPollOutcome.CANCELLED
    if now >= deadline:
        return QuickConnectPollOutcome.TIMED_OUT
    if status in {401, 403}:
        return QuickConnectPollOutcome.DENIED
    if status in {404, 410}:
        return QuickConnectPollOutcome.EXPIRED
    if status == 200 and isinstance(payload, dict):
        if payload.get("Authenticated") is True:
            return QuickConnectPollOutcome.AUTHORIZED
        if payload.get("Authenticated") is False:
            return QuickConnectPollOutcome.PENDING
    raise ContractFailure("Quick Connect poll returned an unclassified redacted response")


def classify_token_rejection(*, locally_revoked: bool) -> str:
    """401 has no expiry reason; only prior local revocation makes it specific."""
    return "known-logout-revocation" if locally_revoked else "expired-or-invalid-reauthentication"


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        return None


class Client:
    def __init__(self, endpoint: str, device_id: str = "phase0-connectivity-primary") -> None:
        self.endpoint = normalize_endpoint(endpoint)
        self.opener = build_opener(NoRedirect)
        self.authorization = (
            'MediaBrowser Client="Phase0Connectivity", Device="Agent", '
            f'DeviceId="{device_id}", Version="0"'
        )

    def request(
        self,
        method: str,
        path: str,
        *,
        token: str | None = None,
        body: dict[str, Any] | None = None,
        expected: set[int] = {200, 204},
    ) -> tuple[int, Any]:
        data = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"Accept": "application/json", "X-Emby-Authorization": self.authorization}
        if body is not None:
            headers["Content-Type"] = "application/json"
        if token is not None:
            headers["X-Emby-Token"] = token
        request = Request(self.endpoint.api_url(path), data=data, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=15) as response:
                status = response.status
                raw = response.read()
        except HTTPError as error:
            status = error.code
            raw = b""  # Error bodies may contain private server details.
        if status not in expected:
            raise ContractFailure(f"{method} redacted-path returned unexpected HTTP {status}")
        if not raw:
            return status, None
        try:
            return status, json.loads(raw)
        except json.JSONDecodeError:
            return status, raw.decode("utf-8")

    def request_audio_bytes(
        self,
        path: str,
        *,
        token: str,
        request_range: bool,
        expected_codec: str,
        maximum_bytes: int = 16 * 1024 * 1024,
    ) -> dict[str, Any]:
        headers = {
            "Accept": "audio/*",
            "X-Emby-Authorization": self.authorization,
            "X-Emby-Token": token,
        }
        if request_range:
            headers["Range"] = f"bytes=0-{maximum_bytes - 1}"
        request = Request(self.endpoint.api_url(path), headers=headers, method="GET")
        try:
            with self.opener.open(request, timeout=30) as response:
                status = response.status
                content_type = response.headers.get_content_type().lower()
                payload = response.read(maximum_bytes + 1)
        except HTTPError as error:
            raise ContractFailure(f"GET redacted-audio-path returned unexpected HTTP {error.code}") from None
        if status not in {200, 206}:
            raise ContractFailure(f"GET redacted-audio-path returned unexpected HTTP {status}")
        if not payload:
            raise ContractFailure("redacted audio response was empty")
        if len(payload) > maximum_bytes:
            raise ContractFailure("redacted audio response exceeded bounded validation size")
        structure = inspect_audio(payload, expected_codec=expected_codec)
        return {
            "result": "PASS",
            "statusClass": f"{status // 100}xx",
            "contentType": content_type,
            "bytesPresent": True,
            "boundedBytesInspected": len(payload),
            "audioValidation": "ffprobe-audio-structure",
            **structure,
        }


def inspect_audio(payload: bytes, *, expected_codec: str) -> dict[str, Any]:
    """Inspect complete, bounded synthetic audio bytes without retaining a URL."""
    with tempfile.NamedTemporaryFile(prefix="phase0-redacted-audio-", suffix=".bin") as temporary:
        temporary.write(payload)
        temporary.flush()
        completed = subprocess.run(
            [
                "ffprobe", "-v", "error", "-show_entries",
                "format=format_name:stream=codec_type,codec_name", "-of", "json", temporary.name,
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    if completed.returncode:
        raise ContractFailure("ffprobe rejected redacted audio response")
    try:
        probe = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise ContractFailure("ffprobe returned malformed redacted output") from error
    streams = probe.get("streams") if isinstance(probe, dict) else None
    if not isinstance(streams, list):
        raise ContractFailure("ffprobe omitted stream structure")
    audio = [row for row in streams if row.get("codec_type") == "audio"]
    video = [row for row in streams if row.get("codec_type") == "video"]
    codecs = sorted({str(row.get("codec_name")) for row in audio if row.get("codec_name")})
    if codecs != [expected_codec] or video:
        raise ContractFailure("ffprobe audio codec/structure differed from requested contract")
    format_value = probe.get("format", {}).get("format_name")
    if not isinstance(format_value, str) or not format_value:
        raise ContractFailure("ffprobe omitted container format")
    return {
        "detectedCodec": expected_codec,
        "detectedContainer": format_value,
        "audioStreamCount": len(audio),
        "videoStreamCount": len(video),
    }


def read_password(path: Path) -> str:
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode != 0o600:
        raise ContractFailure("fixture password file must have mode 0600")
    value = path.read_text(encoding="utf-8")
    if not value:
        raise ContractFailure("fixture password is empty")
    return value


def logout_and_prove_rejection(client: Client, token: str) -> None:
    client.request("POST", "/Sessions/Logout", token=token)
    client.request("GET", "/Users/Me", token=token, expected={401})


def exercise_quick_connect(
    client: Client, primary_token: str, sensitive_values: set[str]
) -> dict[str, Any]:
    quick_client = Client(client.endpoint.url, device_id="phase0-connectivity-quick")
    _, config = client.request("GET", "/System/Configuration", token=primary_token)
    if not isinstance(config, dict) or "QuickConnectAvailable" not in config:
        raise ContractFailure("server configuration lacks QuickConnectAvailable")
    original = bool(config["QuickConnectAvailable"])
    disabled_status: int | None = None
    quick_token: str | None = None
    restored_original = False
    pending_result = QuickConnectPollOutcome.PENDING
    denied_status: int | None = None
    expired_status: int | None = None
    try:
        disabled = dict(config)
        disabled["QuickConnectAvailable"] = False
        client.request("POST", "/System/Configuration", token=primary_token, body=disabled)
        _, enabled_value = client.request("GET", "/QuickConnect/Enabled")
        if enabled_value is not False:
            raise ContractFailure("Quick Connect did not report disabled after configuration update")
        disabled_status, _ = client.request("POST", "/QuickConnect/Initiate", expected={401, 403, 404})

        enabled = dict(config)
        enabled["QuickConnectAvailable"] = True
        client.request("POST", "/System/Configuration", token=primary_token, body=enabled)
        _, enabled_value = client.request("GET", "/QuickConnect/Enabled")
        if enabled_value is not True:
            raise ContractFailure("Quick Connect did not report enabled after configuration update")
        _, initiated = quick_client.request("POST", "/QuickConnect/Initiate")
        if not isinstance(initiated, dict) or not initiated.get("Code") or not initiated.get("Secret"):
            raise ContractFailure("Quick Connect initiation omitted code or secret")
        code = str(initiated["Code"])
        secret = str(initiated["Secret"])
        sensitive_values.update({code, secret})
        pending_status, pending = quick_client.request(
            "GET", "/QuickConnect/Connect?" + urlencode({"secret": secret})
        )
        pending_result = classify_quick_connect_poll(
            pending_status, pending, now=1, deadline=2, cancelled=False
        )
        if pending_result is not QuickConnectPollOutcome.PENDING:
            raise ContractFailure("Quick Connect did not expose a pending poll state")
        if classify_quick_connect_poll(
            pending_status, pending, now=2, deadline=2, cancelled=False
        ) is not QuickConnectPollOutcome.TIMED_OUT:
            raise ContractFailure("Quick Connect deadline did not terminate polling")
        if classify_quick_connect_poll(
            pending_status, pending, now=1, deadline=2, cancelled=True
        ) is not QuickConnectPollOutcome.CANCELLED:
            raise ContractFailure("Quick Connect cancellation did not terminate polling")

        denied = dict(config)
        denied["QuickConnectAvailable"] = False
        client.request("POST", "/System/Configuration", token=primary_token, body=denied)
        denied_status, denied_payload = quick_client.request(
            "GET", "/QuickConnect/Connect?" + urlencode({"secret": secret}),
            expected={401, 403},
        )
        if classify_quick_connect_poll(
            denied_status, denied_payload, now=1, deadline=2, cancelled=False
        ) is not QuickConnectPollOutcome.DENIED:
            raise ContractFailure("Quick Connect server-disabled request was not denied")

        client.request("POST", "/System/Configuration", token=primary_token, body=enabled)
        expired_status, expired_payload = quick_client.request(
            "GET", "/QuickConnect/Connect?"
            + urlencode({"secret": "00000000-0000-0000-0000-000000000000"}),
            expected={404, 410},
        )
        if classify_quick_connect_poll(
            expired_status, expired_payload, now=1, deadline=2, cancelled=False
        ) is not QuickConnectPollOutcome.EXPIRED:
            raise ContractFailure("Quick Connect expired/unknown secret was not rejected")

        client.request(
            "POST", "/QuickConnect/Authorize?" + urlencode({"code": code}), token=primary_token
        )
        _, connected = quick_client.request("GET", "/QuickConnect/Connect?" + urlencode({"secret": secret}))
        if not isinstance(connected, dict) or connected.get("Authenticated") is not True:
            raise ContractFailure("Quick Connect did not become authorized")
        _, quick_auth = quick_client.request(
            "POST", "/Users/AuthenticateWithQuickConnect", body={"Secret": secret}
        )
        if not isinstance(quick_auth, dict) or not quick_auth.get("AccessToken"):
            raise ContractFailure("Quick Connect exchange omitted access token")
        quick_token = str(quick_auth["AccessToken"])
        sensitive_values.add(quick_token)
        logout_and_prove_rejection(quick_client, quick_token)
        quick_token = None
    finally:
        restored = dict(config)
        restored["QuickConnectAvailable"] = original
        try:
            client.request("POST", "/System/Configuration", token=primary_token, body=restored)
            _, restored_value = client.request("GET", "/QuickConnect/Enabled")
            restored_original = restored_value is original
        except Exception:
            restored_original = False
        if quick_token is not None:
            with suppress(Exception):
                quick_client.request("POST", "/Sessions/Logout", token=quick_token)
    if not restored_original:
        raise ContractFailure("Quick Connect original configuration was not restored")
    return {
        "initialStateRecorded": True,
        "disabledState": "PASS",
        "disabledInitiateStatusClass": f"{disabled_status // 100}xx" if disabled_status else "unknown",
        "pendingPoll": pending_result.value,
        "serverDisabledDenialStatusClass": f"{denied_status // 100}xx" if denied_status else "unknown",
        "expiredOrUnknownSecretStatusClass": (
            f"{expired_status // 100}xx" if expired_status else "unknown"
        ),
        "boundedTimeout": QuickConnectPollOutcome.TIMED_OUT.value,
        "clientCancellation": QuickConnectPollOutcome.CANCELLED.value,
        "enabledFullExchange": "PASS",
        "restoredOriginalState": restored_original,
    }


FORMAT_MATRIX = {
    1: ("mp3", "mp3"),
    2: ("aac", "aac"),
    3: ("alac", "alac"),
    4: ("flac", "flac"),
    5: ("vorbis", "vorbis"),
    6: ("opus", "opus"),
}


def run_server(
    label: str, endpoint: str, password_file: Path, expected_version: str
) -> tuple[dict[str, Any], set[str]]:
    client = Client(endpoint)
    password = read_password(password_file)
    sensitive_values = {password, endpoint, "root"}
    token: str | None = None
    _, public = client.request("GET", "/System/Info/Public")
    if not isinstance(public, dict) or public.get("Version") != expected_version or not public.get("Id"):
        raise ContractFailure(f"{label}: public identity/version mismatch")
    sensitive_values.add(str(public["Id"]))
    try:
        _, authentication = client.request(
            "POST", "/Users/AuthenticateByName", body={"Username": "root", "Pw": password}
        )
        password = ""  # Discard the only in-process password reference immediately.
        if not isinstance(authentication, dict):
            raise ContractFailure(f"{label}: malformed authentication response")
        token = authentication.get("AccessToken")
        user = authentication.get("User")
        if not isinstance(token, str) or not token or not isinstance(user, dict) or not user.get("Id"):
            raise ContractFailure(f"{label}: authentication omitted token or user")
        if not same_server_identity(public.get("Id"), authentication.get("ServerId")):
            raise ContractFailure(f"{label}: authenticated server identity mismatch")
        user_id = str(user["Id"])
        sensitive_values.update({str(token), user_id, str(authentication.get("ServerId"))})

        client.request("GET", "/Users/Me", token="synthetic-invalid-token", expected={401})
        query = urlencode({
            "userId": user_id,
            "Recursive": "true",
            "IncludeItemTypes": "Audio",
            "Fields": "MediaSources",
        })
        client.request("POST", "/Library/Refresh", token=token)
        items: Any = None
        matrix_items: dict[int, dict[str, Any]] = {}
        for _ in range(30):
            _, items_result = client.request("GET", "/Items?" + query, token=token)
            items = items_result.get("Items") if isinstance(items_result, dict) else None
            if isinstance(items, list):
                matrix_items = {
                    int(item["IndexNumber"]): item
                    for item in items
                    if isinstance(item, dict)
                    and item.get("Album") == "Format Matrix"
                    and isinstance(item.get("IndexNumber"), int)
                    and item["IndexNumber"] in FORMAT_MATRIX
                }
            if len(matrix_items) == len(FORMAT_MATRIX):
                break
            time.sleep(1)
        if len(matrix_items) != len(FORMAT_MATRIX):
            raise ContractFailure(f"{label}: synthetic format matrix was incomplete")

        delivery_matrix = []
        reporting_state: dict[str, Any] | None = None
        for index in sorted(FORMAT_MATRIX):
            fixture_id, expected_codec = FORMAT_MATRIX[index]
            item = matrix_items[index]
            item_id = item.get("Id")
            if not item_id:
                raise ContractFailure(f"{label}: format-matrix item omitted ID")
            sensitive_values.add(str(item_id))
            _, playback = client.request(
                "GET", "/Items/" + str(item_id) + "/PlaybackInfo?"
                + urlencode({"userId": user_id}), token=token
            )
            media_sources = playback.get("MediaSources") if isinstance(playback, dict) else None
            if not isinstance(media_sources, list) or not media_sources or not media_sources[0].get("Id"):
                raise ContractFailure(f"{label}: playback info omitted media source")
            media_source_id = str(media_sources[0]["Id"])
            play_session_id = str(playback.get("PlaySessionId") or uuid.uuid4())
            sensitive_values.update({media_source_id, play_session_id})
            original_query = urlencode({
                "static": "true",
                "mediaSourceId": media_source_id,
                "playSessionId": play_session_id,
            })
            original_delivery = client.request_audio_bytes(
                "/Audio/" + str(item_id) + "/stream?" + original_query,
                token=token,
                request_range=True,
                expected_codec=expected_codec,
            )
            transcode_query = urlencode({
                "container": "mp4",
                "mediaSourceId": media_source_id,
                "deviceId": "phase0-connectivity-primary",
                "userId": user_id,
                "audioCodec": "aac",
                "maxAudioChannels": "2",
                "transcodingAudioChannels": "2",
                "maxStreamingBitrate": "128000",
                "audioBitRate": "128000",
                "transcodingContainer": "mp4",
                "transcodingProtocol": "http",
                "enableDirectPlay": "false",
                "enableDirectStream": "false",
                "enableTranscoding": "true",
                "enableRedirection": "false",
            })
            transcode_delivery = client.request_audio_bytes(
                "/Audio/" + str(item_id) + "/universal?" + transcode_query,
                token=token,
                request_range=False,
                expected_codec="aac",
            )
            delivery_matrix.append({
                "fixture": fixture_id,
                "sourceCodec": expected_codec,
                "originalDelivery": {
                    **original_delivery,
                    "requestDecision": "original-static-source",
                    "deviceDecodeClaimed": False,
                },
                "requestedServerTranscode": {
                    **transcode_delivery,
                    "requestedCodec": "aac",
                    "requestedContainer": "mp4",
                    "requestDecision": "direct-play-and-direct-stream-disabled",
                    "deviceDecodeClaimed": False,
                },
            })
            if reporting_state is None:
                reporting_state = {
                    "ItemId": str(item_id), "MediaSourceId": media_source_id,
                    "PlaySessionId": play_session_id, "PlayMethod": "DirectPlay",
                    "CanSeek": True, "IsPaused": False, "PositionTicks": 0,
                }
        if reporting_state is None:
            raise ContractFailure("playback reporting lacked a synthetic matrix item")
        state = {
            **reporting_state,
        }
        client.request("POST", "/Sessions/Playing", token=token, body=state)
        progress = dict(state)
        progress["PositionTicks"] = 10_000_000
        client.request("POST", "/Sessions/Playing/Progress", token=token, body=progress)
        client.request(
            "POST", "/Sessions/Playing/Stopped", token=token,
            body={
                "ItemId": state["ItemId"], "MediaSourceId": state["MediaSourceId"],
                "PlaySessionId": state["PlaySessionId"], "PositionTicks": 10_000_000,
            },
        )
        quick_connect = exercise_quick_connect(client, token, sensitive_values)
        logout_and_prove_rejection(client, token)
        token = None
        return ({
            "label": label,
            "expectedVersion": expected_version,
            "publicIdentity": "PASS",
            "passwordAuthentication": "PASS",
            "authenticatedIdentityMatch": "PASS",
            "credentialRejection": {
                "expiredOrUnrecognized": classify_token_rejection(locally_revoked=False),
                "logoutRevocation": classify_token_rejection(locally_revoked=True),
            },
            "musicLibrary": {"result": "PASS", "audioItemsPresent": True},
            "playbackInfo": {"result": "PASS", "mediaSourcePresent": True},
            "serverDeliveryMatrix": delivery_matrix,
            "playbackReporting": {"start": "PASS", "progress": "PASS", "stop": "PASS"},
            "quickConnect": quick_connect,
            "logoutCredentialRejected": "PASS",
        }, sensitive_values)
    finally:
        password = ""
        if token is not None:
            with suppress(Exception):
                client.request("POST", "/Sessions/Logout", token=token)


FORBIDDEN_REPORT_KEYS = {
    "AccessToken", "Password", "Pw", "Secret", "Code", "Url", "Address",
    "ServerId", "UserId", "ItemId", "MediaSourceId", "PlaySessionId",
}


def prove_report_contains_no_sensitive_values(
    report: dict[str, Any], sensitive_values: set[str]
) -> None:
    """Scan the only durable/output sink: the final JSON report."""
    serialized = json.dumps(report, sort_keys=True)
    lowered_keys: set[str] = set()

    def collect_keys(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                lowered_keys.add(str(key).lower())
                collect_keys(child)
        elif isinstance(value, list):
            for child in value:
                collect_keys(child)

    collect_keys(report)
    forbidden = {key.lower() for key in FORBIDDEN_REPORT_KEYS}
    if lowered_keys & forbidden:
        raise ContractFailure("report contains a forbidden private field")
    for value in sensitive_values:
        if value and len(value) >= 4 and value in serialized:
            raise ContractFailure("report contains a process-local sensitive value")


def evidence_environment() -> dict[str, str]:
    completed = subprocess.run(
        ["ffprobe", "-version"], check=False, capture_output=True, text=True, timeout=5
    )
    first_line = completed.stdout.splitlines()[0] if completed.returncode == 0 else "unavailable"
    return {
        "hostOS": platform.mac_ver()[0] or platform.system(),
        "architecture": platform.machine(),
        "python": platform.python_version(),
        "ffprobe": first_line,
        "serverRuntime": "loopback-only disposable Docker containers",
    }


def common_evidence_envelope(*, status: str, limitations: list[str]) -> dict[str, Any]:
    return {
        "schemaVersion": 2,
        "proofId": "phase0-connectivity-live-contracts",
        "capturedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "command": EVIDENCE_COMMAND,
        "environment": evidence_environment(),
        "owner": {"phase": "Phase 0", "workstream": "connectivity"},
        "status": status,
        "limitations": limitations,
        "privacy": {
            "redacted": True,
            "committedEvidenceContainsSecrets": False,
            "privateServerDataPersisted": False,
            "omitted": [
                "server endpoints and identities",
                "user, item, media-source, and play-session identities",
                "passwords and access credentials",
                "Quick Connect codes and secrets",
                "authenticated media request URLs",
            ],
            "notes": [
                "The complete final JSON sink is scanned against process-local sensitive values and forbidden private field names before output.",
                "This record does not claim memory inspection, Keychain integration, device decode, audibility, or Apple-device playback.",
            ],
        },
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-root", type=Path, default=root / "infra" / "jellyfin" / ".state")
    args = parser.parse_args()
    specifications = (
        ("current", "http://127.0.0.1:18096", "10.11.11"),
        ("previous", "http://127.0.0.1:18097", "10.10.7"),
    )
    try:
        executions = [
            run_server(label, endpoint, args.state_root / label / "fixture-password", version)
            for label, endpoint, version in specifications
        ]
        results = [execution[0] for execution in executions]
        sensitive_values = set().union(*(execution[1] for execution in executions))
        report = {
            **common_evidence_envelope(
                status="pass",
                limitations=[
                    "Loopback server delivery does not prove iOS decode, audibility, timing, route behavior, or device playback.",
                    "Jellyfin exposes expired and unknown Quick Connect secrets through the same rejection class.",
                    "A server 401 does not distinguish token expiry from another invalid credential unless local logout revocation is already known.",
                    "The report-sink privacy scan does not inspect process memory or prove Phase 1 Keychain storage.",
                ],
            ),
            "result": "PASS",
            "summary": {
                "status": "pass",
                "serverVersions": ["10.11.11", "10.10.7"],
                "originalDeliveries": 12,
                "requestedServerTranscodes": 12,
                "quickConnectEdgeContracts": "pass",
            },
            "reportPrivacy": {
                "reportContainsSecrets": False,
                "scannedSink": "final-json-report",
                "result": "PASS",
            },
            "servers": results,
        }
        prove_report_contains_no_sensitive_values(report, sensitive_values)
    except (ContractFailure, OSError):
        # The committed/pass record retains detailed redacted evidence. Failure
        # output deliberately omits exception text because an OS error can contain
        # a local path or endpoint that was unavailable to the completed sink scan.
        failure = {
            **common_evidence_envelope(
                status="fail",
                limitations=["Live contract execution failed before complete redacted evidence was available."],
            ),
            "result": "FAIL",
            "summary": {"status": "fail"},
            "reason": "redacted live contract failure",
        }
        prove_report_contains_no_sensitive_values(failure, set())
        print(json.dumps(failure, indent=2, sort_keys=True))
        return 1
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
