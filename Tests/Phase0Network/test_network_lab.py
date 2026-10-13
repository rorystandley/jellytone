from __future__ import annotations

import json
from pathlib import Path
import socket
import sys
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "network-lab"))

from network_lab import classify_dns_resolution, classify_tailscale_endpoint, local_name_families, run_proofs  # noqa: E402


class NetworkLabTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = run_proofs()

    def test_host_network_proofs_pass_without_persisting_private_values(self) -> None:
        self.assertEqual(self.report["result"], "PASS")
        rendered = json.dumps(self.report, sort_keys=True).lower()
        for forbidden in (
            "x-emby-token", "authorization", "access_token", '"serverid":', '"userid":',
            "127.0.0.1", "::1", "localhost", ".local",
        ):
            self.assertNotIn(forbidden, rendered)
        self.assertFalse(self.report["privacy"]["credentialsPersisted"])
        self.assertFalse(self.report["privacy"]["serverAddressesPersisted"])
        self.assertTrue(self.report["privacy"]["redacted"])
        self.assertFalse(self.report["privacy"]["committedEvidenceContainsSecrets"])
        self.assertFalse(self.report["privacy"]["privateServerDataPersisted"])

    def test_all_redirect_statuses_enforce_identity_before_credentials(self) -> None:
        redirects = self.report["proofs"]["redirectCredentialIsolation"]
        self.assertEqual(redirects["statuses"], [301, 302, 303, 307, 308])
        self.assertEqual(redirects["sameOrigin"], "PASS")
        self.assertEqual(redirects["crossOriginSameServer"], "PASS")
        self.assertEqual(redirects["crossOriginDifferentServer"], "PASS")
        self.assertEqual(self.report["proofs"]["httpsDowngradeRejected"]["result"], "PASS")

    def test_certificate_failures_are_distinct_and_fail_closed(self) -> None:
        tls = self.report["proofs"]["tls"]
        self.assertEqual(tls["explicitTestCATrust"], "PASS")
        self.assertEqual(tls["untrustedIssuerRejected"], "PASS")
        self.assertEqual(tls["wrongHostRejected"], "PASS")
        self.assertEqual(tls["expiredRejected"], "PASS")

    def test_tailscale_url_classes_do_not_imply_live_connectivity(self) -> None:
        self.assertEqual(classify_tailscale_endpoint("http://100.64.0.1:8096"), "tailnet-ip")
        self.assertEqual(classify_tailscale_endpoint("http://synthetic-node:8096"), "magicdns-short-name-candidate")
        self.assertEqual(
            classify_tailscale_endpoint("https://synthetic-node.synthetic-tail.ts.net"),
            "tailscale-serve-https",
        )
        environment = self.report["proofs"]["tailscaleEnvironment"]
        self.assertIn(environment["liveProof"], {"AVAILABLE", "BLOCKED"})
        self.assertEqual(classify_dns_resolution("phase0-network-proof.invalid"), "dns-unavailable")
        self.assertEqual(self.report["proofs"]["dnsFailureClassification"], "PASS")

    def test_missing_multicast_dns_registration_is_an_environment_limitation(self) -> None:
        with mock.patch("network_lab.socket.getaddrinfo", side_effect=socket.gaierror("synthetic resolver failure")):
            self.assertEqual(local_name_families(), [])

    def test_committed_machine_evidence_matches_privacy_contract(self) -> None:
        path = ROOT / "docs" / "evidence" / "phase-0" / "network" / "host-network-results.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(report["schemaVersion"], 1)
        self.assertEqual(report["result"], "PASS")
        self.assertEqual(report["privacy"], self.report["privacy"])

        restart_path = ROOT / "docs" / "evidence" / "phase-0" / "network" / "server-restart-results.json"
        restart = json.loads(restart_path.read_text(encoding="utf-8"))
        self.assertEqual(restart["result"], "PASS")
        self.assertTrue(restart["publicIdentityStableAfterRestart"])
        self.assertFalse(restart["authenticatedRequestSent"])
        serialized = json.dumps(restart).lower()
        for forbidden in ("127.0.0.1", "localhost", '"serverid":', '"url":', '"token":'):
            self.assertNotIn(forbidden, serialized)


if __name__ == "__main__":
    unittest.main()
