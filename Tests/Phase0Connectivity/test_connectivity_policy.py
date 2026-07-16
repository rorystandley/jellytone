from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "connectivity"))

from connectivity_policy import (  # noqa: E402
    PolicyError,
    RedirectAction,
    TokenContract,
    TokenState,
    evaluate_redirect,
    normalize_endpoint,
    redact,
    same_server_identity,
    validate_contract_fixture,
)
from live_contract_probe import (  # noqa: E402
    ContractFailure,
    QuickConnectPollOutcome,
    classify_quick_connect_poll,
    classify_token_rejection,
    inspect_audio,
    prove_report_contains_no_sensitive_values,
)


class URLNormalizationTests(unittest.TestCase):
    def test_base_path_ports_ipv4_ipv6_and_dot_local(self) -> None:
        cases = {
            " HTTPS://Music.Example.COM:443/jellyfin/web/ ": "https://music.example.com/jellyfin",
            "http://192.0.2.10:8096/": "http://192.0.2.10:8096",
            "http://[2001:db8::7]:8096/music": "http://[2001:db8::7]:8096/music",
            "https://Media.Local/base%20path": "https://media.local/base%20path",
            "https://node.tail.example.ts.net/jellyfin": "https://node.tail.example.ts.net/jellyfin",
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                endpoint = normalize_endpoint(raw)
                self.assertEqual(endpoint.url, expected)
                self.assertEqual(endpoint.api_url("/System/Info/Public"), expected + "/System/Info/Public")

    def test_ambiguous_or_credential_bearing_urls_are_rejected(self) -> None:
        for value in (
            "music.local:8096", "ftp://music.local", "https://user:pw@music.local",
            "https://music.local/?api_key=secret", "https://music.local/#login",
            "https://music.local/base/../admin",
        ):
            with self.subTest(value=value), self.assertRaises(PolicyError):
                normalize_endpoint(value)


class RedirectAndIdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = normalize_endpoint("https://lan.example/jellyfin")

    def test_authenticated_same_origin_is_reconstructed(self) -> None:
        destination = normalize_endpoint("https://lan.example/new-base")
        decision = evaluate_redirect(self.source, destination, request_was_authenticated=True)
        self.assertEqual(decision.action, RedirectAction.REISSUE_AFTER_IDENTITY_PROOF)

    def test_tls_downgrade_is_always_blocked(self) -> None:
        destination = normalize_endpoint("http://lan.example/jellyfin")
        decision = evaluate_redirect(
            self.source, destination, request_was_authenticated=False,
            source_server_id="server-a", destination_server_id="server-a",
        )
        self.assertEqual(decision.action, RedirectAction.BLOCK)

    def test_changed_origin_requires_exact_public_server_identity(self) -> None:
        destination = normalize_endpoint("https://music.tail.example.ts.net/jellyfin")
        denied = evaluate_redirect(
            self.source, destination, request_was_authenticated=True,
            source_server_id="server-a", destination_server_id="server-b",
        )
        allowed = evaluate_redirect(
            self.source, destination, request_was_authenticated=True,
            source_server_id="server-a", destination_server_id="server-a",
        )
        self.assertEqual(denied.action, RedirectAction.BLOCK)
        self.assertEqual(allowed.action, RedirectAction.REISSUE_AFTER_IDENTITY_PROOF)
        self.assertFalse(same_server_identity("Server-A", "server-a"))


class PrivacyAndTokenTests(unittest.TestCase):
    def test_redaction_removes_credentials_and_private_values(self) -> None:
        source = {
            "Authorization": 'MediaBrowser Client="Proof", Token="token-123"',
            "X-Emby-Token": "live-emby-token",
            "x-mediabrowser-token": "live-mediabrowser-token",
            "X-Emby-Authorization": 'MediaBrowser Client="Proof", Token="live-authorization-token"',
            "url": "https://private.example/Items/secret-item?api_key=token-456&safe=yes",
            "username": "private-user",
            "Id": "private-server-id",
            "ServerName": "private-server-name",
            "nested": [
                "Bearer token-789",
                "X-Emby-Token: free-form-emby-token",
                "x-mediabrowser-token: 'free-form-mediabrowser-token'",
                {"itemName": "Private Song"},
            ],
            "invalidTokenRejected": "PASS",
            "reportContainsSecrets": False,
        }
        redacted = redact(source)
        rendered = json.dumps(redacted, sort_keys=True)
        for secret in (
            "token-123", "token-456", "token-789", "live-emby-token",
            "live-mediabrowser-token", "live-authorization-token",
            "free-form-emby-token", "free-form-mediabrowser-token",
            "private.example", "private-user", "private-server-id",
            "private-server-name", "Private Song", "secret-item",
        ):
            self.assertNotIn(secret, rendered)
        self.assertEqual(redacted["invalidTokenRejected"], "PASS")
        self.assertIs(redacted["reportContainsSecrets"], False)

    def test_live_report_scan_rejects_private_fields_and_actual_values(self) -> None:
        prove_report_contains_no_sensitive_values(
            {"result": "PASS", "reportContainsSecrets": False}, {"actual-secret-value"}
        )
        with self.assertRaises(ContractFailure):
            prove_report_contains_no_sensitive_values(
                {"result": "actual-secret-value"}, {"actual-secret-value"}
            )
        with self.assertRaises(ContractFailure):
            prove_report_contains_no_sensitive_values({"AccessToken": "redacted"}, set())

    def test_authentication_retains_only_keychain_reference_in_metadata(self) -> None:
        contract = TokenContract(expected_server_id="synthetic-server")
        reference = contract.accept_authentication({
            "AccessToken": "synthetic-access-token",
            "ServerId": "synthetic-server",
            "User": {"Id": "synthetic-user"},
        })
        self.assertEqual(contract.state, TokenState.ACTIVE)
        self.assertEqual(contract.durable_metadata(), {"tokenReference": reference})
        self.assertNotIn("synthetic-access-token", json.dumps(contract.durable_metadata()))
        contract.handle_unauthorized()
        self.assertEqual(contract.state, TokenState.REAUTHENTICATION_REQUIRED)
        self.assertEqual(contract.durable_metadata(), {})

    def test_authentication_from_replaced_server_is_rejected(self) -> None:
        contract = TokenContract(expected_server_id="expected")
        with self.assertRaises(PolicyError):
            contract.accept_authentication({"AccessToken": "token", "ServerId": "replacement"})


class VersionedContractTests(unittest.TestCase):
    def test_supported_version_fixtures(self) -> None:
        fixtures = sorted((ROOT / "Tests" / "Fixtures" / "Jellyfin").glob("*/connectivity-contract.json"))
        self.assertEqual([path.parent.name for path in fixtures], ["10.10.7", "10.11.11"])
        for path in fixtures:
            validate_contract_fixture(path)

    def test_live_contract_report_is_redacted_and_complete(self) -> None:
        path = ROOT / "docs" / "evidence" / "phase-0" / "connectivity" / "live-contract-results.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(report["proofId"], "phase0-connectivity-live-contracts")
        self.assertRegex(report["capturedAt"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        self.assertEqual(report["owner"], {"phase": "Phase 0", "workstream": "connectivity"})
        self.assertEqual(report["status"], "pass")
        self.assertTrue(report["command"])
        self.assertTrue(report["environment"])
        self.assertGreaterEqual(len(report["limitations"]), 4)
        self.assertEqual(report["summary"]["originalDeliveries"], 12)
        self.assertEqual(report["summary"]["requestedServerTranscodes"], 12)
        self.assertEqual(
            report["privacy"],
            {
                "redacted": True,
                "committedEvidenceContainsSecrets": False,
                "privateServerDataPersisted": False,
                "omitted": report["privacy"]["omitted"],
                "notes": report["privacy"]["notes"],
            },
        )
        self.assertEqual(report["result"], "PASS")
        self.assertEqual(
            [server["expectedVersion"] for server in report["servers"]],
            ["10.11.11", "10.10.7"],
        )
        serialized = json.dumps(report).lower()
        for forbidden_key in ('"token"', '"password"', '"secret"', '"code"', '"url"', '"address"', '"serverid"', '"userid"', '"itemid"'):
            self.assertNotIn(forbidden_key, serialized)
        for server in report["servers"]:
            self.assertEqual(server["playbackReporting"], {"progress": "PASS", "start": "PASS", "stop": "PASS"})
            self.assertEqual(server["quickConnect"]["enabledFullExchange"], "PASS")
            self.assertEqual(server["quickConnect"]["disabledState"], "PASS")
            self.assertTrue(server["quickConnect"]["restoredOriginalState"])
            self.assertEqual(server["quickConnect"]["pendingPoll"], "pending")
            self.assertEqual(server["quickConnect"]["boundedTimeout"], "timed_out")
            self.assertEqual(server["quickConnect"]["clientCancellation"], "cancelled")
            self.assertEqual(len(server["serverDeliveryMatrix"]), 6)
            self.assertEqual(
                [row["fixture"] for row in server["serverDeliveryMatrix"]],
                ["mp3", "aac", "alac", "flac", "vorbis", "opus"],
            )
            for row in server["serverDeliveryMatrix"]:
                original = row["originalDelivery"]
                transcode = row["requestedServerTranscode"]
                self.assertEqual(original["detectedCodec"], row["sourceCodec"])
                self.assertEqual(original["audioStreamCount"], 1)
                self.assertEqual(original["videoStreamCount"], 0)
                self.assertFalse(original["deviceDecodeClaimed"])
                self.assertEqual(transcode["detectedCodec"], "aac")
                self.assertEqual(transcode["audioStreamCount"], 1)
                self.assertEqual(transcode["videoStreamCount"], 0)
                self.assertEqual(
                    transcode["requestDecision"], "direct-play-and-direct-stream-disabled"
                )
                self.assertFalse(transcode["deviceDecodeClaimed"])
        self.assertEqual(report["schemaVersion"], 2)
        self.assertFalse(report["reportPrivacy"]["reportContainsSecrets"])
        self.assertEqual(report["reportPrivacy"]["result"], "PASS")


class LiveProbePolicyTests(unittest.TestCase):
    def test_quick_connect_poll_outcomes_are_deterministic(self) -> None:
        cases = (
            (200, {"Authenticated": False}, 1, 2, False, QuickConnectPollOutcome.PENDING),
            (200, {"Authenticated": True}, 1, 2, False, QuickConnectPollOutcome.AUTHORIZED),
            (401, None, 1, 2, False, QuickConnectPollOutcome.DENIED),
            (404, None, 1, 2, False, QuickConnectPollOutcome.EXPIRED),
            (200, {"Authenticated": False}, 2, 2, False, QuickConnectPollOutcome.TIMED_OUT),
            (200, {"Authenticated": False}, 1, 2, True, QuickConnectPollOutcome.CANCELLED),
        )
        for status, payload, now, deadline, cancelled, expected in cases:
            with self.subTest(expected=expected):
                self.assertEqual(
                    classify_quick_connect_poll(
                        status, payload, now=now, deadline=deadline, cancelled=cancelled
                    ),
                    expected,
                )

    def test_token_401_distinguishes_known_logout_from_ambiguous_rejection(self) -> None:
        self.assertEqual(
            classify_token_rejection(locally_revoked=True), "known-logout-revocation"
        )
        self.assertEqual(
            classify_token_rejection(locally_revoked=False),
            "expired-or-invalid-reauthentication",
        )

    def test_ffprobe_requires_expected_audio_codec_and_no_video(self) -> None:
        payload = (ROOT / "Tests" / "Fixtures" / "Audio" / "tone-a.flac").read_bytes()
        result = inspect_audio(payload, expected_codec="flac")
        self.assertEqual(result["detectedCodec"], "flac")
        self.assertEqual(result["audioStreamCount"], 1)
        self.assertEqual(result["videoStreamCount"], 0)
        with self.assertRaises(ContractFailure):
            inspect_audio(payload, expected_codec="aac")


if __name__ == "__main__":
    unittest.main()
