#!/usr/bin/env python3
"""Validate Phase 0 evidence envelopes, privacy, and record semantics.

The validator intentionally uses only the Python standard library so the same
gate runs in a clean macOS checkout, Linux CI, and the local combined gate.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
import ipaddress
import json
from pathlib import Path
import re
import sys
from typing import Any, Callable, Iterable, Mapping, Sequence
from urllib.parse import parse_qsl, urlsplit


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_ROOT = ROOT / "docs" / "evidence" / "phase-0"
SCHEMA_PATH = EVIDENCE_ROOT / "automation" / "evidence-schema.json"

STATUSES = {"pass", "fail", "blocked", "not-run"}
WORKSTREAMS = {"automation", "connectivity", "device", "network", "platform", "playback"}
FORBIDDEN_PRIVATE_KEYS = {
    "accesstoken",
    "authorization",
    "password",
    "quickconnectcode",
    "quickconnectsecret",
    "token",
    "username",
}


@dataclass(frozen=True, order=True)
class ValidationIssue:
    path: str
    pointer: str
    message: str

    def as_dict(self) -> dict[str, str]:
        return {"path": self.path, "pointer": self.pointer, "message": self.message}


class RecordValidator:
    def __init__(self, path: Path, record: Any) -> None:
        try:
            self.path = path.resolve().relative_to(ROOT.resolve()).as_posix()
        except ValueError:
            self.path = path.as_posix()
        self.record = record
        self.issues: list[ValidationIssue] = []

    def issue(self, pointer: str, message: str) -> None:
        self.issues.append(ValidationIssue(self.path, pointer, message))

    def require(self, value: bool, pointer: str, message: str) -> None:
        if not value:
            self.issue(pointer, message)

    def validate_common(self) -> None:
        if not isinstance(self.record, dict):
            self.issue("/", "record must be a JSON object")
            return
        required = (
            "schemaVersion",
            "proofId",
            "capturedAt",
            "command",
            "environment",
            "owner",
            "status",
            "limitations",
            "privacy",
        )
        for key in required:
            if key not in self.record:
                self.issue(f"/{key}", "required common evidence field is missing")

        if "schemaVersion" in self.record:
            version = self.record.get("schemaVersion")
            self.require(isinstance(version, int) and not isinstance(version, bool) and version >= 1, "/schemaVersion", "must be a positive integer")
        if "proofId" in self.record:
            self._nonempty_string("proofId")
        if "command" in self.record:
            self._nonempty_string("command")
        if "capturedAt" in self.record:
            self._validate_timestamp()
        if "environment" in self.record:
            self.require(isinstance(self.record.get("environment"), dict), "/environment", "must be an object")
        if "owner" in self.record:
            self._validate_owner()
        status = self.record.get("status")
        if "status" in self.record:
            self.require(status in STATUSES, "/status", f"must be one of {sorted(STATUSES)}")
        limitations: list[str] = []
        if "limitations" in self.record:
            limitations = self._string_list("limitations")
            if status in {"blocked", "not-run"} and not limitations:
                self.issue("/limitations", f"{status} evidence must state at least one limitation")
        if "privacy" in self.record:
            self._validate_privacy()
        self._validate_checks()
        self._scan_private_keys(self.record)
        self._scan_private_values(self.record)

    def _nonempty_string(self, key: str) -> None:
        value = self.record.get(key)
        self.require(isinstance(value, str) and bool(value.strip()), f"/{key}", "must be a non-empty string")

    def _validate_timestamp(self) -> None:
        value = self.record.get("capturedAt")
        if not isinstance(value, str) or not value:
            self.issue("/capturedAt", "must be a non-empty RFC 3339 date-time")
            return
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            self.issue("/capturedAt", "must be an RFC 3339 date-time")
            return
        if parsed.tzinfo is None:
            self.issue("/capturedAt", "must include a UTC offset or Z suffix")

    def _validate_owner(self) -> None:
        owner = self.record.get("owner")
        if not isinstance(owner, dict):
            self.issue("/owner", "must be an object with phase and workstream")
            return
        self.require(owner.get("phase") == "Phase 0", "/owner/phase", 'must equal "Phase 0"')
        self.require(owner.get("workstream") in WORKSTREAMS, "/owner/workstream", f"must be one of {sorted(WORKSTREAMS)}")
        unexpected = sorted(set(owner) - {"phase", "workstream"})
        if unexpected:
            self.issue("/owner", f"contains unsupported fields: {', '.join(unexpected)}")

    def _string_list(self, key: str) -> list[str]:
        value = self.record.get(key)
        if not isinstance(value, list):
            self.issue(f"/{key}", "must be an array of non-empty strings")
            return []
        result: list[str] = []
        for index, item in enumerate(value):
            if not isinstance(item, str) or not item.strip():
                self.issue(f"/{key}/{index}", "must be a non-empty string")
            else:
                result.append(item)
        return result

    def _validate_privacy(self) -> None:
        privacy = self.record.get("privacy")
        if not isinstance(privacy, dict):
            self.issue("/privacy", "must be an object")
            return
        required_values = {
            "redacted": True,
            "committedEvidenceContainsSecrets": False,
            "privateServerDataPersisted": False,
        }
        for key, expected in required_values.items():
            if privacy.get(key) is not expected:
                self.issue(f"/privacy/{key}", f"must be the boolean {str(expected).lower()}")
        for key in ("omitted", "notes"):
            if key in privacy:
                value = privacy[key]
                if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
                    self.issue(f"/privacy/{key}", "must be an array of non-empty strings")

    def _validate_checks(self) -> None:
        checks = self.record.get("checks")
        if checks is None:
            return
        if not isinstance(checks, list) or not checks:
            self.issue("/checks", "must be a non-empty array when present")
            return
        seen: set[str] = set()
        observed_statuses: list[str] = []
        for index, check in enumerate(checks):
            pointer = f"/checks/{index}"
            if not isinstance(check, dict):
                self.issue(pointer, "must be an object")
                continue
            expected = {"id", "status", "facts", "limitations"}
            missing = sorted(expected - set(check))
            unexpected = sorted(set(check) - expected)
            if missing:
                self.issue(pointer, f"missing required fields: {', '.join(missing)}")
            if unexpected:
                self.issue(pointer, f"contains unsupported fields: {', '.join(unexpected)}")
            check_id = check.get("id")
            if not isinstance(check_id, str) or not check_id.strip():
                self.issue(pointer + "/id", "must be a non-empty string")
            elif check_id in seen:
                self.issue(pointer + "/id", "must be unique within the record")
            else:
                seen.add(check_id)
            check_status = check.get("status")
            if check_status not in STATUSES:
                self.issue(pointer + "/status", f"must be one of {sorted(STATUSES)}")
            else:
                observed_statuses.append(check_status)
            if not isinstance(check.get("facts"), dict):
                self.issue(pointer + "/facts", "must be an object")
            check_limitations = check.get("limitations")
            if not isinstance(check_limitations, list) or any(
                not isinstance(item, str) or not item.strip() for item in check_limitations
            ):
                self.issue(pointer + "/limitations", "must be an array of non-empty strings")
            elif check_status in {"blocked", "not-run"} and not check_limitations:
                self.issue(pointer + "/limitations", f"{check_status} check must state a limitation")
        expected_summary = "pass"
        for candidate in ("fail", "blocked", "not-run"):
            if candidate in observed_statuses:
                expected_summary = candidate
                break
        if observed_statuses and "status" in self.record and self.record.get("status") != expected_summary:
            self.issue("/status", f"must summarize check statuses as {expected_summary}")

    def _scan_private_keys(self, value: Any, pointer: str = "") -> None:
        if isinstance(value, dict):
            for key, nested in value.items():
                normalized = re.sub(r"[^a-z0-9]", "", str(key).lower())
                child = f"{pointer}/{key}"
                if normalized in FORBIDDEN_PRIVATE_KEYS:
                    self.issue(child, "private credential or identity key is forbidden in committed evidence")
                self._scan_private_keys(nested, child)
        elif isinstance(value, list):
            for index, nested in enumerate(value):
                self._scan_private_keys(nested, f"{pointer}/{index}")

    def _scan_private_values(self, value: Any, pointer: str = "") -> None:
        if isinstance(value, dict):
            for key, nested in value.items():
                self._scan_private_values(nested, f"{pointer}/{key}")
            return
        if isinstance(value, list):
            for index, nested in enumerate(value):
                self._scan_private_values(nested, f"{pointer}/{index}")
            return
        if not isinstance(value, str):
            return

        if re.search(r"(?i)\bauthorization\s*[:=]|\bbearer\s+[a-z0-9._~+/-]+", value):
            self.issue(pointer, "credential-bearing text is forbidden in committed evidence")

        for candidate in re.findall(r"https?://[^\s\]\[<>{}\"']+", value):
            parsed = urlsplit(candidate.rstrip(".,;:)"))
            if parsed.username is not None or parsed.password is not None:
                self.issue(pointer, "URL user information is forbidden in committed evidence")
            for key, _ in parse_qsl(parsed.query, keep_blank_values=True):
                if re.sub(r"[^a-z0-9]", "", key.lower()) in FORBIDDEN_PRIVATE_KEYS | {"apikey", "api_key"}:
                    self.issue(pointer, "credential query parameter is forbidden in committed evidence")
            self._reject_private_host(parsed.hostname, pointer)

        for candidate in re.findall(r"(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])", value):
            self._reject_private_host(candidate, pointer)

    def _reject_private_host(self, host: str | None, pointer: str) -> None:
        if not host:
            return
        normalized = host.rstrip(".").lower()
        if normalized == "localhost" or normalized.endswith(".local"):
            self.issue(pointer, "local or private host is forbidden in committed evidence")
            return
        try:
            address = ipaddress.ip_address(normalized.strip("[]"))
        except ValueError:
            return
        if address.is_private or address.is_link_local or address.is_loopback:
            self.issue(pointer, "local or private address is forbidden in committed evidence")


def _record_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(EVIDENCE_ROOT.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def _require_keys(validator: RecordValidator, keys: Sequence[str]) -> None:
    for key in keys:
        if key not in validator.record:
            validator.issue(f"/{key}", "required record-specific field is missing")


def _validate_checks_record(validator: RecordValidator) -> None:
    checks = validator.record.get("checks")
    validator.require(isinstance(checks, list) and bool(checks), "/checks", "record requires at least one check")


def _validate_server_images(validator: RecordValidator) -> None:
    _validate_checks_record(validator)
    checks = validator.record.get("checks", [])
    if not isinstance(checks, list):
        return
    by_id = {check.get("id"): check for check in checks if isinstance(check, dict)}
    validator.require(set(by_id) == {"current-stable", "previous-supported-line"}, "/checks", "must contain exactly the current and previous server checks")
    expected = {"current-stable": "10.11.11", "previous-supported-line": "10.10.7"}
    for check_id, version in expected.items():
        check = by_id.get(check_id)
        if not isinstance(check, dict):
            continue
        facts = check.get("facts")
        if not isinstance(facts, dict):
            continue
        validator.require(facts.get("version") == version, f"/checks/{check_id}/facts/version", f"must equal {version}")
        digest = facts.get("digest")
        validator.require(isinstance(digest, str) and bool(re.fullmatch(r"sha256:[0-9a-f]{64}", digest)), f"/checks/{check_id}/facts/digest", "must be an immutable sha256 digest")
        validator.require(facts.get("startupWizardCompleted") is True, f"/checks/{check_id}/facts/startupWizardCompleted", "must be true")


def _validate_live_contract(validator: RecordValidator) -> None:
    _require_keys(validator, ("result", "servers", "reportPrivacy"))
    validator.require(validator.record.get("schemaVersion") == 2, "/schemaVersion", "live-contract record must use schema version 2")
    validator.require(validator.record.get("result") == "PASS", "/result", 'must equal "PASS"')
    report_privacy = validator.record.get("reportPrivacy")
    validator.require(
        isinstance(report_privacy, dict)
        and report_privacy.get("result") == "PASS"
        and report_privacy.get("reportContainsSecrets") is False
        and report_privacy.get("scannedSink") == "final-json-report",
        "/reportPrivacy",
        "must prove the final JSON report scan passed without report secrets",
    )
    servers = validator.record.get("servers")
    if not isinstance(servers, list):
        validator.issue("/servers", "must be an array")
        return
    validator.require([server.get("expectedVersion") for server in servers if isinstance(server, dict)] == ["10.11.11", "10.10.7"], "/servers", "must contain current then previous supported server versions")
    for index, server in enumerate(servers):
        if not isinstance(server, dict):
            validator.issue(f"/servers/{index}", "must be an object")
            continue
        for key in ("publicIdentity", "passwordAuthentication", "authenticatedIdentityMatch", "logoutCredentialRejected"):
            validator.require(server.get(key) == "PASS", f"/servers/{index}/{key}", 'must equal "PASS"')
        rejection = server.get("credentialRejection")
        validator.require(
            isinstance(rejection, dict)
            and rejection.get("expiredOrUnrecognized") == "expired-or-invalid-reauthentication"
            and rejection.get("logoutRevocation") == "known-logout-revocation",
            f"/servers/{index}/credentialRejection",
            "must distinguish invalid/expired credentials from known logout revocation",
        )
        matrix = server.get("serverDeliveryMatrix")
        expected_fixtures = ["mp3", "aac", "alac", "flac", "vorbis", "opus"]
        validator.require(
            isinstance(matrix, list)
            and [row.get("fixture") for row in matrix if isinstance(row, dict)] == expected_fixtures,
            f"/servers/{index}/serverDeliveryMatrix",
            "must contain the six server-delivery codec rows in fixture order",
        )
        if isinstance(matrix, list):
            for row_index, row in enumerate(matrix):
                if not isinstance(row, dict):
                    continue
                original = row.get("originalDelivery")
                transcode = row.get("requestedServerTranscode")
                validator.require(
                    isinstance(original, dict)
                    and original.get("result") == "PASS"
                    and original.get("detectedCodec") == row.get("sourceCodec")
                    and original.get("audioStreamCount") == 1
                    and original.get("videoStreamCount") == 0
                    and original.get("deviceDecodeClaimed") is False,
                    f"/servers/{index}/serverDeliveryMatrix/{row_index}/originalDelivery",
                    "must prove bounded original audio structure without claiming device decode",
                )
                validator.require(
                    isinstance(transcode, dict)
                    and transcode.get("result") == "PASS"
                    and transcode.get("detectedCodec") == "aac"
                    and transcode.get("audioStreamCount") == 1
                    and transcode.get("videoStreamCount") == 0
                    and transcode.get("deviceDecodeClaimed") is False
                    and transcode.get("requestDecision") == "direct-play-and-direct-stream-disabled",
                    f"/servers/{index}/serverDeliveryMatrix/{row_index}/requestedServerTranscode",
                    "must prove requested AAC server transcode without claiming device decode",
                )


def _validate_device_execution(validator: RecordValidator) -> None:
    _require_keys(validator, ("harness", "device", "results", "capability_status", "operation_timeout_seconds"))
    results = validator.record.get("results")
    if not isinstance(results, list) or not results:
        validator.issue("/results", "must be a non-empty array")
        return
    observed_statuses: list[str] = []
    for index, result in enumerate(results):
        pointer = f"/results/{index}"
        if not isinstance(result, dict):
            validator.issue(pointer, "must be an object")
            continue
        if not isinstance(result.get("command"), str) or not result["command"].strip():
            validator.issue(pointer + "/command", "must be a non-empty command")
        status = result.get("status")
        if status not in STATUSES:
            validator.issue(pointer + "/status", f"must be one of {sorted(STATUSES)}")
        else:
            observed_statuses.append(status)
        detail_key = "reason" if status in {"blocked", "not-run"} else "evidence"
        if not isinstance(result.get(detail_key), str) or not result[detail_key].strip():
            validator.issue(pointer + f"/{detail_key}", f"{status} result must include {detail_key}")
    expected_summary = "pass"
    for candidate in ("fail", "blocked", "not-run"):
        if candidate in observed_statuses:
            expected_summary = candidate
            break
    if observed_statuses and validator.record.get("status") != expected_summary:
        validator.issue("/status", f"must summarize device result statuses as {expected_summary}")


def _validate_host_network(validator: RecordValidator) -> None:
    _require_keys(validator, ("proofs", "result", "scope"))
    validator.require(validator.record.get("result") == "PASS", "/result", 'must equal "PASS"')
    proofs = validator.record.get("proofs")
    required = {"dnsFailureClassification", "httpsDowngradeRejected", "redirectCredentialIsolation", "reverseProxyBasePath", "tls", "udpDiscoveryProtocol"}
    validator.require(isinstance(proofs, dict) and set(proofs) >= required, "/proofs", "is missing required network proof families")


def _validate_server_restart(validator: RecordValidator) -> None:
    _require_keys(validator, ("result", "serverRestartedAndReady", "publicIdentityStableAfterRestart", "authenticatedRequestSent"))
    validator.require(validator.record.get("result") == "PASS", "/result", 'must equal "PASS"')
    validator.require(validator.record.get("serverRestartedAndReady") is True, "/serverRestartedAndReady", "must be true")
    validator.require(validator.record.get("publicIdentityStableAfterRestart") is True, "/publicIdentityStableAfterRestart", "must be true")
    validator.require(validator.record.get("authenticatedRequestSent") is False, "/authenticatedRequestSent", "must be false")


def _validate_codec_matrix(validator: RecordValidator) -> None:
    _require_keys(validator, ("host", "results", "scope"))
    results = validator.record.get("results")
    if not isinstance(results, list):
        validator.issue("/results", "must be an array")
        return
    expected = {"mp3", "aac", "alac", "flac", "vorbis_ogg", "opus_ogg", "opus_mp4", "pcm_a"}
    observed = {row.get("fixtureId") for row in results if isinstance(row, dict)}
    validator.require(observed == expected, "/results", "must contain exactly the eight codec/container fixture rows")
    for index, row in enumerate(results):
        if not isinstance(row, dict):
            continue
        for transport in ("local", "remoteLoopback"):
            prepared = row.get("avFoundation", {}).get(transport) if isinstance(row.get("avFoundation"), dict) else None
            validator.require(isinstance(prepared, dict) and prepared.get("playable") is True and prepared.get("audioTrackCount", 0) > 0, f"/results/{index}/avFoundation/{transport}", "must prove a playable audio asset")


def _validate_device_status(validator: RecordValidator) -> None:
    _require_keys(validator, ("physicalDeviceDetected", "signedPlaybackProbeBuilt", "deviceProcedureExecuted", "blockedClaims", "reason"))
    claims = validator.record.get("blockedClaims")
    validator.require(isinstance(claims, list) and bool(claims) and all(isinstance(item, str) and item.strip() for item in claims), "/blockedClaims", "must list blocked device claims")


def _validate_session_order(validator: RecordValidator) -> None:
    _require_keys(validator, ("events", "passed", "scope"))
    events = validator.record.get("events")
    validator.require(validator.record.get("passed") is True, "/passed", "must be true")
    if not isinstance(events, list):
        validator.issue("/events", "must be an array")
        return
    names = [event.get("event") for event in events if isinstance(event, dict)]
    validator.require(names == ["start", "progress", "stop", "start", "progress", "stop", "start"], "/events", "must preserve replacement session ordering")


def _validate_source_policy(validator: RecordValidator) -> None:
    _require_keys(validator, ("policyStatus", "minimumOSAssumption", "rows", "constraints", "transcodeRequest"))
    if "policyStatus" in validator.record:
        validator.require(validator.record.get("policyStatus") == "provisional-until-iOS-device-matrix", "/policyStatus", "must preserve the provisional capability claim")
    rows = validator.record.get("rows")
    validator.require(isinstance(rows, list) and len(rows) == 7, "/rows", "must contain seven provisional codec/container rows")
    constraints = validator.record.get("constraints")
    validator.require(isinstance(constraints, list) and bool(constraints), "/constraints", "must state capability limitations")


def _validate_transitions(validator: RecordValidator) -> None:
    _require_keys(validator, ("acceptance", "results", "scope"))
    results = validator.record.get("results")
    expected = {"localLinearCrossfade250ms", "localPreparedHardCut", "remoteLoopbackLinearCrossfade250ms", "remoteLoopbackPreparedHardCut"}
    validator.require(isinstance(results, dict) and set(results) == expected, "/results", "must contain exactly four transition measurements")
    if not isinstance(results, dict):
        return
    for name, result in results.items():
        if not isinstance(result, dict):
            validator.issue(f"/results/{name}", "must be an object")
            continue
        validator.require(result.get("durationErrorSamples") == 0, f"/results/{name}/durationErrorSamples", "must equal zero")
        validator.require(isinstance(result.get("longestDigitalSilenceSamples"), int) and result["longestDigitalSilenceSamples"] <= 4, f"/results/{name}/longestDigitalSilenceSamples", "must not exceed four samples")


RECORD_VALIDATORS: Mapping[str, Callable[[RecordValidator], None]] = {
    "automation/server-images.json": _validate_server_images,
    "connectivity/live-contract-results.json": _validate_live_contract,
    "device/execution-status.json": _validate_device_execution,
    "network/host-network-results.json": _validate_host_network,
    "network/server-restart-results.json": _validate_server_restart,
    "platform/environment.json": _validate_checks_record,
    "platform/external-status.json": _validate_checks_record,
    "playback/results/codec-matrix.json": _validate_codec_matrix,
    "playback/results/device-status.json": _validate_device_status,
    "playback/results/session-order.json": _validate_session_order,
    "playback/results/source-policy.json": _validate_source_policy,
    "playback/results/transition-measurements.json": _validate_transitions,
}


def validate_schema_document(path: Path = SCHEMA_PATH) -> list[ValidationIssue]:
    relative = path.resolve().relative_to(ROOT.resolve()).as_posix()
    try:
        schema = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [ValidationIssue(relative, "/", f"schema is not readable JSON: {error}")]
    issues: list[ValidationIssue] = []
    required = set(schema.get("required", [])) if isinstance(schema, dict) else set()
    expected = {"schemaVersion", "proofId", "capturedAt", "command", "environment", "owner", "status", "limitations", "privacy"}
    if not isinstance(schema, dict) or schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        issues.append(ValidationIssue(relative, "/$schema", "must declare JSON Schema draft 2020-12"))
    if not expected <= required:
        issues.append(ValidationIssue(relative, "/required", f"missing common envelope requirements: {', '.join(sorted(expected - required))}"))
    return issues


def validate_record(path: Path, record: Any) -> list[ValidationIssue]:
    validator = RecordValidator(path, record)
    validator.validate_common()
    relative = _record_path(path)
    specific = RECORD_VALIDATORS.get(relative)
    if specific is None:
        validator.issue("/", "JSON evidence file has no registered record-specific validator")
    elif isinstance(record, dict):
        specific(validator)
    return sorted(set(validator.issues))


def evidence_paths(explicit: Iterable[Path] | None = None) -> list[Path]:
    if explicit:
        return sorted(path.resolve() for path in explicit)
    return sorted(path for path in EVIDENCE_ROOT.rglob("*.json") if path.resolve() != SCHEMA_PATH.resolve())


def load_and_validate(path: Path) -> list[ValidationIssue]:
    relative = path.resolve().relative_to(ROOT.resolve()).as_posix() if path.resolve().is_relative_to(ROOT.resolve()) else path.as_posix()
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [ValidationIssue(relative, "/", f"record is not readable JSON: {error}")]
    return validate_record(path, record)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, help="specific evidence JSON records (default: all)")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)

    issues = validate_schema_document()
    paths = evidence_paths(args.paths)
    registered = set(RECORD_VALIDATORS)
    discovered = {_record_path(path) for path in paths if EVIDENCE_ROOT.resolve() in path.resolve().parents}
    if not args.paths:
        schema_relative = SCHEMA_PATH.resolve().relative_to(ROOT.resolve()).as_posix()
        for missing in sorted(registered - discovered):
            issues.append(ValidationIssue(schema_relative, "/recordRegistry", f"registered evidence record is missing: {missing}"))
    for path in paths:
        issues.extend(load_and_validate(path))
    issues = sorted(set(issues))

    if args.format == "json":
        print(json.dumps({"records": len(paths), "issues": [issue.as_dict() for issue in issues]}, indent=2))
    else:
        for issue in issues:
            print(f"{issue.path}:{issue.pointer}: {issue.message}")
        if issues:
            print(f"Phase 0 evidence validation failed: {len(issues)} issue(s) across {len(paths)} record(s)", file=sys.stderr)
        else:
            print(f"Phase 0 evidence validation passed: {len(paths)} record(s)")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
