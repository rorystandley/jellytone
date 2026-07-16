from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools" / "phase0" / "validate_evidence.py"
SPEC = importlib.util.spec_from_file_location("validate_evidence", MODULE_PATH)
assert SPEC and SPEC.loader
validate_evidence = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validate_evidence
SPEC.loader.exec_module(validate_evidence)


def valid_environment_record() -> dict:
    return {
        "schemaVersion": 1,
        "proofId": "phase0-test-record",
        "capturedAt": "2026-07-16T12:00:00Z",
        "command": "tools/phase0/test-proof.sh",
        "environment": {"runtime": "synthetic"},
        "owner": {"phase": "Phase 0", "workstream": "platform"},
        "status": "pass",
        "limitations": ["Synthetic unit-test record; no capability claim."],
        "privacy": {
            "redacted": True,
            "committedEvidenceContainsSecrets": False,
            "privateServerDataPersisted": False,
        },
        "checks": [
            {
                "id": "synthetic",
                "status": "pass",
                "facts": {"observed": True},
                "limitations": ["Unit-test-only observation."],
            }
        ],
    }


def issues_for(record: dict, relative: str = "platform/environment.json") -> list:
    path = validate_evidence.EVIDENCE_ROOT / relative
    return validate_evidence.validate_record(path, record)


class CommonEnvelopeTests(unittest.TestCase):
    def test_valid_common_envelope_and_registered_record_pass(self) -> None:
        self.assertEqual(issues_for(valid_environment_record()), [])

    def test_missing_command_is_rejected(self) -> None:
        record = valid_environment_record()
        del record["command"]
        self.assertTrue(any(issue.pointer == "/command" for issue in issues_for(record)))

    def test_missing_owner_is_rejected(self) -> None:
        record = valid_environment_record()
        del record["owner"]
        self.assertTrue(any(issue.pointer == "/owner" for issue in issues_for(record)))

    def test_missing_limitations_is_rejected(self) -> None:
        record = valid_environment_record()
        del record["limitations"]
        self.assertTrue(any(issue.pointer == "/limitations" for issue in issues_for(record)))

    def test_blocked_record_requires_a_limitation(self) -> None:
        record = valid_environment_record()
        record["status"] = "blocked"
        record["limitations"] = []
        self.assertTrue(any(issue.pointer == "/limitations" and "blocked" in issue.message for issue in issues_for(record)))

    def test_blocked_check_requires_its_own_limitation(self) -> None:
        record = valid_environment_record()
        record["checks"][0]["status"] = "blocked"
        record["checks"][0]["limitations"] = []
        self.assertTrue(any(issue.pointer == "/checks/0/limitations" for issue in issues_for(record)))

    def test_summary_status_must_reflect_blocked_check(self) -> None:
        record = valid_environment_record()
        record["checks"][0]["status"] = "blocked"
        issues = issues_for(record)
        self.assertTrue(any(issue.pointer == "/status" and "blocked" in issue.message for issue in issues))

    def test_privacy_persistence_claims_are_required(self) -> None:
        record = valid_environment_record()
        del record["privacy"]["committedEvidenceContainsSecrets"]
        self.assertTrue(any(issue.pointer == "/privacy/committedEvidenceContainsSecrets" for issue in issues_for(record)))

    def test_naive_timestamp_is_rejected(self) -> None:
        record = valid_environment_record()
        record["capturedAt"] = "2026-07-16T12:00:00"
        self.assertTrue(any(issue.pointer == "/capturedAt" for issue in issues_for(record)))

    def test_private_credential_key_is_rejected_at_any_depth(self) -> None:
        record = valid_environment_record()
        record["checks"][0]["facts"]["accessToken"] = "redacted"
        self.assertTrue(any(issue.pointer.endswith("/accessToken") for issue in issues_for(record)))

    def test_private_credentials_and_endpoint_in_string_value_are_rejected(self) -> None:
        record = valid_environment_record()
        record["checks"][0]["facts"]["diagnostic"] = (
            "Authorization: Bearer live-secret https://10.0.0.2/music?api_key=live-secret"
        )
        issues = issues_for(record)
        self.assertTrue(any("credential-bearing text" in issue.message for issue in issues))
        self.assertTrue(any("credential query parameter" in issue.message for issue in issues))
        self.assertTrue(any("private address" in issue.message for issue in issues))


class RecordSpecificTests(unittest.TestCase):
    def test_unregistered_evidence_record_is_rejected(self) -> None:
        issues = issues_for(valid_environment_record(), "automation/unregistered.json")
        self.assertTrue(any("no registered record-specific validator" in issue.message for issue in issues))

    def test_live_contract_requires_both_supported_versions(self) -> None:
        record = valid_environment_record()
        record["owner"]["workstream"] = "connectivity"
        record.pop("checks")
        record.update({"result": "PASS", "servers": []})
        issues = issues_for(record, "connectivity/live-contract-results.json")
        self.assertTrue(any(issue.pointer == "/servers" for issue in issues))

    def test_device_result_requires_blocker_reason(self) -> None:
        record = valid_environment_record()
        record["owner"]["workstream"] = "device"
        record.pop("checks")
        record.update(
            {
                "harness": "synthetic",
                "device": {"identifier": "redacted"},
                "results": [{"command": "probe", "status": "blocked"}],
                "capability_status": {"background_audio": "blocked"},
                "operation_timeout_seconds": 30,
            }
        )
        issues = issues_for(record, "device/execution-status.json")
        self.assertTrue(any(issue.pointer == "/results/0/reason" for issue in issues))

    def test_device_summary_status_cannot_hide_blocked_result(self) -> None:
        record = valid_environment_record()
        record["owner"]["workstream"] = "device"
        record.pop("checks")
        record.update(
            {
                "harness": "synthetic",
                "device": {"identifier": "redacted"},
                "results": [{"command": "probe", "status": "blocked", "reason": "synthetic blocker"}],
                "capability_status": {"background_audio": "blocked"},
                "operation_timeout_seconds": 30,
            }
        )
        record["status"] = "pass"
        issues = issues_for(record, "device/execution-status.json")
        self.assertTrue(any(issue.pointer == "/status" and "blocked" in issue.message for issue in issues))

    def test_schema_declares_every_common_requirement(self) -> None:
        self.assertEqual(validate_evidence.validate_schema_document(), [])

    def test_transition_evidence_requires_native_preload_measurements(self) -> None:
        path = validate_evidence.EVIDENCE_ROOT / "playback/results/transition-measurements.json"
        record = json.loads(path.read_text())
        del record["results"]["nativeRemotePreloadedHardCut"]
        issues = issues_for(record, "playback/results/transition-measurements.json")
        self.assertTrue(any(issue.pointer == "/results" and "native" in issue.message for issue in issues))

    def test_registry_matches_committed_evidence_json(self) -> None:
        discovered = {
            path.relative_to(validate_evidence.EVIDENCE_ROOT).as_posix()
            for path in validate_evidence.EVIDENCE_ROOT.rglob("*.json")
            if path.resolve() != validate_evidence.SCHEMA_PATH.resolve()
        }
        self.assertEqual(discovered, set(validate_evidence.RECORD_VALIDATORS))


if __name__ == "__main__":
    unittest.main()
