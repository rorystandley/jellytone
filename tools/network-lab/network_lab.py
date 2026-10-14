#!/usr/bin/env python3
"""Deterministic Phase 0 host network lab.

This is proof tooling, not production networking code. It deliberately keeps all
listeners on loopback and records only classifications, never endpoints or IDs.
"""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass, field
import http.client
import http.server
import ipaddress
import json
from pathlib import Path
import shutil
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time
from typing import Dict, Iterator, List, Optional, Tuple
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, HTTPSHandler, ProxyHandler, Request, build_opener


DISCOVERY_QUERY = b"Who is JellyfinServer?"
AUTH_HEADERS = {"authorization", "x-emby-token", "x-mediabrowser-token", "x-emby-authorization"}
REDIRECT_CODES = (301, 302, 303, 307, 308)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        return None


def opener(context: Optional[ssl.SSLContext] = None):
    handlers = [ProxyHandler({}), NoRedirect()]
    if context is not None:
        handlers.append(HTTPSHandler(context=context))
    return build_opener(*handlers)


def fetch(url: str, *, context: Optional[ssl.SSLContext] = None,
          headers: Optional[Dict[str, str]] = None, timeout: float = 3.0) -> Tuple[int, Dict[str, str], bytes]:
    request = Request(url, headers=headers or {})
    try:
        with opener(context).open(request, timeout=timeout) as response:
            return response.status, dict(response.headers.items()), response.read()
    except HTTPError as error:
        return error.code, dict(error.headers.items()), error.read()


def public_identity(url: str, context: ssl.SSLContext) -> str:
    status, _, body = fetch(url, context=context)
    if status != 200:
        raise RuntimeError("public identity probe failed")
    value = json.loads(body).get("Id")
    if not isinstance(value, str) or not value:
        raise RuntimeError("public identity response has no non-empty Id")
    return value


@dataclass
class AuditEntry:
    listener: str
    path_class: str
    credential_present: bool


@dataclass
class LabState:
    upstream: str
    listener: str
    redirect_targets: Dict[str, str] = field(default_factory=dict)
    force_upstream_unavailable: bool = False
    audit: List[AuditEntry] = field(default_factory=list)


class LabHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "Phase0NetworkLab/1"

    @property
    def state(self) -> LabState:
        return self.server.lab_state  # type: ignore[attr-defined,no-any-return]

    def log_message(self, _format: str, *args: object) -> None:
        return

    def _audit(self, path_class: str) -> None:
        present = any(key.lower() in AUTH_HEADERS for key in self.headers.keys())
        self.state.audit.append(AuditEntry(self.state.listener, path_class, present))

    def _send(self, status: int, body: bytes = b"", headers: Optional[Dict[str, str]] = None) -> None:
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self) -> None:
        parts = self.path.split("?", 1)[0].split("/")
        if len(parts) == 4 and parts[1] == "redirect":
            code = int(parts[2])
            scenario = parts[3]
            if code not in REDIRECT_CODES or scenario not in self.state.redirect_targets:
                self._send(404)
                return
            self._audit("redirect-source")
            self._send(code, headers={"Location": self.state.redirect_targets[scenario]})
            return
        if not self.path.startswith("/jellyfin/"):
            self._send(404)
            return
        self._audit("reverse-proxy-target")
        if self.state.force_upstream_unavailable:
            self._send(503, b'{"category":"transport-unavailable"}', {"Content-Type": "application/json"})
            return
        upstream = urlsplit(self.state.upstream)
        path = self.path[len("/jellyfin"):]
        try:
            connection = http.client.HTTPConnection(upstream.hostname, upstream.port, timeout=2)
            safe_headers = {
                key: value for key, value in self.headers.items()
                if key.lower() not in {"host", "connection", "content-length"}
            }
            connection.request("GET", path, headers=safe_headers)
            response = connection.getresponse()
            body = response.read()
            response_headers = {
                key: value for key, value in response.getheaders()
                if key.lower() in {"content-type", "cache-control"}
            }
            self._send(response.status, body, response_headers)
        except OSError:
            self._send(502, b'{"category":"upstream-unavailable"}', {"Content-Type": "application/json"})
        finally:
            if "connection" in locals():
                connection.close()


class IPv6HTTPServer(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6


class RunningServer:
    def __init__(self, state: LabState, cert: Path, key: Path, *, ipv6: bool = False):
        server_type = IPv6HTTPServer if ipv6 else http.server.ThreadingHTTPServer
        bind = "::1" if ipv6 else "127.0.0.1"
        self.server = server_type((bind, 0), LabHandler)
        self.server.lab_state = state  # type: ignore[attr-defined]
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(cert), str(key))
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.ipv6 = ipv6

    @property
    def port(self) -> int:
        return int(self.server.server_address[1])

    @property
    def url(self) -> str:
        host = "[::1]" if self.ipv6 else "localhost"
        return "https://{}:{}".format(host, self.port)

    def start(self) -> None:
        self.thread.start()

    def stop(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)


def run_checked(arguments: List[str], cwd: Path) -> None:
    subprocess.run(arguments, cwd=str(cwd), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def write_certificate_config(path: Path, dns_name: str, ip_sans: bool = False) -> None:
    sans = "DNS:{}".format(dns_name)
    if ip_sans:
        sans += ",IP:127.0.0.1,IP:::1"
    path.write_text(
        "[server]\nsubjectAltName={}\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\n".format(sans),
        encoding="utf-8",
    )


def make_ca(root: Path, name: str) -> Tuple[Path, Path]:
    cert, key = root / (name + "-ca.pem"), root / (name + "-ca-key.pem")
    run_checked(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
                 "-subj", "/CN=Phase0 Synthetic Test CA", "-keyout", str(key), "-out", str(cert)], root)
    return cert, key


def make_leaf(root: Path, name: str, ca_cert: Path, ca_key: Path, *, dns_name: str,
              ip_sans: bool = False, days: int = 1) -> Tuple[Path, Path]:
    key, csr, cert, ext = (root / (name + suffix) for suffix in ("-key.pem", ".csr", ".pem", ".ext"))
    write_certificate_config(ext, dns_name, ip_sans)
    run_checked(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj",
                 "/CN={}".format(dns_name), "-keyout", str(key), "-out", str(csr)], root)
    run_checked(["openssl", "x509", "-req", "-in", str(csr), "-CA", str(ca_cert),
                 "-CAkey", str(ca_key), "-CAcreateserial", "-days", str(days), "-sha256",
                 "-extfile", str(ext), "-extensions", "server", "-out", str(cert)], root)
    return cert, key


def make_expired_leaf(root: Path, ca_cert: Path, ca_key: Path) -> Tuple[Path, Path]:
    key, csr, cert, ext = (root / ("expired" + suffix) for suffix in ("-key.pem", ".csr", ".pem", ".ext"))
    write_certificate_config(ext, "localhost", True)
    run_checked(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj",
                 "/CN=localhost", "-keyout", str(key), "-out", str(csr)], root)
    database, serial, new_certs, config = root / "index.txt", root / "serial", root / "newcerts", root / "ca.cnf"
    database.write_text("", encoding="utf-8")
    serial.write_text("1000\n", encoding="utf-8")
    new_certs.mkdir()
    config.write_text(
        "[ca]\ndefault_ca=local_ca\n[local_ca]\ndatabase={db}\nserial={serial}\nnew_certs_dir={new}\n"
        "certificate={cert}\nprivate_key={key}\ndefault_md=sha256\ndefault_days=1\npolicy=policy\n"
        "[policy]\ncommonName=supplied\n".format(db=database, serial=serial, new=new_certs, cert=ca_cert, key=ca_key),
        encoding="utf-8",
    )
    run_checked(["openssl", "ca", "-batch", "-config", str(config), "-in", str(csr), "-out", str(cert),
                 "-startdate", "20200101000000Z", "-enddate", "20200102000000Z",
                 "-extfile", str(ext), "-extensions", "server"], root)
    return cert, key


@dataclass
class CertificateSet:
    root: Path
    trusted_ca: Path
    valid: Tuple[Path, Path]
    untrusted: Tuple[Path, Path]
    wrong_host: Tuple[Path, Path]
    expired: Tuple[Path, Path]


def generate_certificates(root: Path) -> CertificateSet:
    trusted_ca, trusted_key = make_ca(root, "trusted")
    untrusted_ca, untrusted_key = make_ca(root, "untrusted")
    return CertificateSet(
        root=root,
        trusted_ca=trusted_ca,
        valid=make_leaf(root, "valid", trusted_ca, trusted_key, dns_name="localhost", ip_sans=True),
        untrusted=make_leaf(root, "untrusted", untrusted_ca, untrusted_key, dns_name="localhost", ip_sans=True),
        wrong_host=make_leaf(root, "wrong-host", trusted_ca, trusted_key, dns_name="wrong.invalid"),
        expired=make_expired_leaf(root, trusted_ca, trusted_key),
    )


def trusted_context(ca: Path) -> ssl.SSLContext:
    return ssl.create_default_context(cafile=str(ca))


def is_tls_verification_failure(error: BaseException) -> bool:
    candidate: Optional[BaseException] = error
    while candidate is not None:
        if isinstance(candidate, ssl.SSLCertVerificationError):
            return True
        candidate = candidate.__cause__ or candidate.__context__
    return "CERTIFICATE_VERIFY_FAILED" in str(error)


def classify_tailscale_endpoint(value: str) -> str:
    parts = urlsplit(value)
    if parts.scheme not in {"http", "https"} or not parts.hostname:
        return "invalid"
    host = parts.hostname.rstrip(".").lower()
    try:
        address = ipaddress.ip_address(host)
        return "tailnet-ip" if address in ipaddress.ip_network("100.64.0.0/10") else "non-tailnet-ip"
    except ValueError:
        pass
    if parts.scheme == "https" and host.endswith(".ts.net"):
        return "tailscale-serve-https"
    if "." not in host:
        return "magicdns-short-name-candidate"
    return "ordinary-dns-name"


def redirect_transport_allowed(source: str, destination: str) -> bool:
    """Reject a secure-to-insecure redirect before contacting its destination."""
    source_parts, destination_parts = urlsplit(source), urlsplit(destination)
    return not (source_parts.scheme == "https" and destination_parts.scheme == "http")


class DiscoveryResponder:
    def __init__(self, advertised_url: str, server_id: str):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(("127.0.0.1", 0))
        self.port = self.socket.getsockname()[1]
        self.advertised_url = advertised_url
        self.server_id = server_id
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def _serve(self) -> None:
        data, address = self.socket.recvfrom(2048)
        if data == DISCOVERY_QUERY:
            payload = json.dumps({"Address": self.advertised_url, "Id": self.server_id,
                                  "Name": "Synthetic Jellyfin"}).encode("utf-8")
            self.socket.sendto(payload, address)

    def start(self) -> None:
        self.thread.start()

    def stop(self) -> None:
        self.socket.close()
        self.thread.join(timeout=1)


def discover(port: int) -> Dict[str, str]:
    client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    client.settimeout(2)
    try:
        client.sendto(DISCOVERY_QUERY, ("127.0.0.1", port))
        payload, _ = client.recvfrom(2048)
        value = json.loads(payload)
        if not all(isinstance(value.get(key), str) and value[key] for key in ("Address", "Id", "Name")):
            raise RuntimeError("discovery response is incomplete")
        return value
    finally:
        client.close()


def assert_tls_failure(url: str, context: ssl.SSLContext) -> None:
    try:
        fetch(url, context=context)
    except URLError as error:
        if is_tls_verification_failure(error):
            return
        raise
    raise AssertionError("TLS validation unexpectedly accepted the endpoint")


def run_redirect_case(source: RunningServer, target: RunningServer, context: ssl.SSLContext,
                      code: int, scenario: str, expected_id: str, should_authorize: bool) -> None:
    source.server.lab_state.audit.clear()  # type: ignore[attr-defined]
    target.server.lab_state.audit.clear()  # type: ignore[attr-defined]
    source.server.lab_state.redirect_targets[scenario] = target.url + "/jellyfin/System/Info/Public"  # type: ignore[attr-defined]
    status, headers, _ = fetch(source.url + "/redirect/{}/{}".format(code, scenario), context=context,
                               headers={"X-Emby-Token": "process-local-synthetic-token"})
    if status != code:
        raise AssertionError("redirect status was not preserved")
    destination = headers.get("Location")
    if not destination:
        raise AssertionError("redirect had no Location")
    probe_id = public_identity(destination, context)
    if probe_id == expected_id and should_authorize:
        final_status, _, _ = fetch(destination, context=context,
                                   headers={"X-Emby-Token": "process-local-synthetic-token"})
        if final_status != 200:
            raise AssertionError("approved redirect could not be reissued")
    entries = [entry for entry in target.server.lab_state.audit  # type: ignore[attr-defined]
               if entry.path_class == "reverse-proxy-target"]
    if not entries or entries[0].credential_present:
        raise AssertionError("redirect destination received credentials before identity proof")
    if should_authorize:
        if len(entries) != 2 or not entries[1].credential_present:
            raise AssertionError("approved redirect was not explicitly reissued")
    elif len(entries) != 1:
        raise AssertionError("rejected redirect was contacted after identity mismatch")


@contextmanager
def network_lab(current_upstream: str = "http://127.0.0.1:18096",
                different_upstream: str = "http://127.0.0.1:18097") -> Iterator[Tuple[CertificateSet, Dict[str, RunningServer]]]:
    with tempfile.TemporaryDirectory(prefix="phase0-network-lab-") as temporary:
        certs = generate_certificates(Path(temporary))
        definitions = {
            "source": (LabState(current_upstream, "source"), certs.valid, False),
            "same": (LabState(current_upstream, "same-server-origin"), certs.valid, False),
            "different": (LabState(different_upstream, "different-server-origin"), certs.valid, False),
            "ipv6": (LabState(current_upstream, "ipv6"), certs.valid, True),
            "untrusted": (LabState(current_upstream, "untrusted"), certs.untrusted, False),
            "wrong_host": (LabState(current_upstream, "wrong-host"), certs.wrong_host, False),
            "expired": (LabState(current_upstream, "expired"), certs.expired, False),
        }
        servers = {name: RunningServer(state, pair[0], pair[1], ipv6=ipv6)
                   for name, (state, pair, ipv6) in definitions.items()}
        try:
            for server in servers.values():
                server.start()
            yield certs, servers
        finally:
            for server in servers.values():
                server.stop()


def tailscale_environment() -> Dict[str, object]:
    executable = shutil.which("tailscale")
    if executable is None:
        return {
            "cliAvailable": False,
            "connectedTailnet": False,
            "liveProof": "BLOCKED",
            "blocker": "Tailscale CLI is not installed, so no connected tailnet, MagicDNS answer, or Serve HTTPS endpoint can be exercised.",
        }
    result = subprocess.run([executable, "status", "--json"], capture_output=True, text=True, timeout=5)
    connected = result.returncode == 0
    return {
        "cliAvailable": True,
        "connectedTailnet": connected,
        "liveProof": "AVAILABLE" if connected else "BLOCKED",
        "blocker": None if connected else "Tailscale CLI is present but does not report a connected tailnet.",
    }


def local_name_families() -> List[str]:
    local_name = socket.gethostname().split(".", 1)[0] + ".local"
    try:
        families = {item[0] for item in socket.getaddrinfo(local_name, None)}
    except socket.gaierror:
        return []
    result = []
    if socket.AF_INET in families:
        result.append("IPv4")
    if socket.AF_INET6 in families:
        result.append("IPv6")
    return result


def classify_dns_resolution(name: str) -> str:
    """Classify resolver success separately from HTTPS and transport failures."""
    try:
        answers = socket.getaddrinfo(name, None)
    except socket.gaierror:
        return "dns-unavailable"
    return "resolved" if answers else "dns-unavailable"


def wait_for_public(upstream: str, timeout: float = 20.0) -> str:
    deadline = time.monotonic() + timeout
    last_error: Optional[BaseException] = None
    while time.monotonic() < deadline:
        try:
            status, _, body = fetch(upstream + "/System/Info/Public", timeout=2)
            if status == 200:
                value = json.loads(body).get("Id")
                if isinstance(value, str) and value:
                    return value
        except (OSError, URLError, ValueError) as error:
            last_error = error
        time.sleep(0.25)
    raise RuntimeError("Jellyfin upstream did not become ready") from last_error


def run_proofs() -> Dict[str, object]:
    current = "http://127.0.0.1:18096"
    previous = "http://127.0.0.1:18097"
    direct_current_id = wait_for_public(current)
    direct_previous_id = wait_for_public(previous)
    if direct_current_id == direct_previous_id:
        raise AssertionError("disposable servers unexpectedly share identity")
    results: Dict[str, object] = {}
    with network_lab(current, previous) as (certs, servers):
        context = trusted_context(certs.trusted_ca)
        source_id = public_identity(servers["source"].url + "/jellyfin/System/Info/Public", context)
        if source_id != direct_current_id:
            raise AssertionError("reverse-proxy base path changed server identity")
        results["reverseProxyBasePath"] = "PASS"

        if public_identity(servers["ipv6"].url + "/jellyfin/System/Info/Public", context) != source_id:
            raise AssertionError("IPv6 proxy identity differs")
        results["loopbackAddressFamilies"] = {"IPv4": "PASS", "IPv6": "PASS"}

        for code in REDIRECT_CODES:
            run_redirect_case(servers["source"], servers["source"], context, code, "same-origin", source_id, True)
            run_redirect_case(servers["source"], servers["same"], context, code, "same-server", source_id, True)
            run_redirect_case(servers["source"], servers["different"], context, code, "different-server", source_id, False)
        results["redirectCredentialIsolation"] = {
            "statuses": list(REDIRECT_CODES),
            "sameOrigin": "PASS",
            "crossOriginSameServer": "PASS",
            "crossOriginDifferentServer": "PASS",
        }

        downgrade_target = "http://127.0.0.1:9/jellyfin/System/Info/Public"
        servers["source"].server.lab_state.redirect_targets["downgrade"] = downgrade_target  # type: ignore[attr-defined]
        for code in REDIRECT_CODES:
            status, headers, _ = fetch(servers["source"].url + "/redirect/{}/downgrade".format(code),
                                       context=context, headers={"X-Emby-Token": "process-local-synthetic-token"})
            destination = headers.get("Location", "")
            if status != code or urlsplit(destination).scheme != "http":
                raise AssertionError("downgrade redirect fixture malformed")
            if redirect_transport_allowed(servers["source"].url, destination):
                raise AssertionError("safe redirect policy accepted HTTPS downgrade")
        results["httpsDowngradeRejected"] = {"statuses": list(REDIRECT_CODES), "result": "PASS"}

        if public_identity(servers["source"].url + "/jellyfin/System/Info/Public", context) != source_id:
            raise AssertionError("trusted local CA failed")
        assert_tls_failure(servers["source"].url + "/jellyfin/System/Info/Public", ssl.create_default_context())
        assert_tls_failure(servers["untrusted"].url + "/jellyfin/System/Info/Public", context)
        assert_tls_failure(servers["wrong_host"].url + "/jellyfin/System/Info/Public", context)
        assert_tls_failure(servers["expired"].url + "/jellyfin/System/Info/Public", context)
        results["tls"] = {
            "explicitTestCATrust": "PASS",
            "systemTrustDoesNotTrustTestCA": "PASS",
            "untrustedIssuerRejected": "PASS",
            "wrongHostRejected": "PASS",
            "expiredRejected": "PASS",
        }

        discovery = DiscoveryResponder(servers["source"].url + "/jellyfin", source_id)
        discovery.start()
        try:
            found = discover(discovery.port)
            discovered_id = public_identity(found["Address"] + "/System/Info/Public", context)
            if found["Id"] != source_id or discovered_id != source_id:
                raise AssertionError("discovery identity does not match advertised endpoint")
        finally:
            discovery.stop()
        results["udpDiscoveryProtocol"] = "PASS"

        families = local_name_families()
        results["localNameResolution"] = {
            "result": "PASS" if families else "BLOCKED",
            "addressFamilies": families,
            "limitation": None if families else "Host multicast-DNS registration is unavailable in this runner.",
        }
        if classify_dns_resolution("phase0-network-proof.invalid") != "dns-unavailable":
            raise AssertionError("reserved invalid name did not classify as DNS unavailable")
        results["dnsFailureClassification"] = "PASS"

        state = servers["source"].server.lab_state  # type: ignore[attr-defined]
        state.force_upstream_unavailable = True
        unavailable_status, _, unavailable_body = fetch(
            servers["source"].url + "/jellyfin/System/Info/Public", context=context)
        state.force_upstream_unavailable = False
        recovered_id = public_identity(servers["source"].url + "/jellyfin/System/Info/Public", context)
        if unavailable_status != 503 or b"transport-unavailable" not in unavailable_body or recovered_id != source_id:
            raise AssertionError("server unavailable/recovery classification failed")
        results["serverUnavailableRecovery"] = "PASS"

    results["tailscaleClassification"] = {
        "tailnetIP": classify_tailscale_endpoint("http://100.64.0.1:8096"),
        "magicDNS": classify_tailscale_endpoint("http://synthetic-node:8096"),
        "serveHTTPS": classify_tailscale_endpoint("https://synthetic-node.synthetic-tail.ts.net"),
        "ordinaryDNS": classify_tailscale_endpoint("https://example.invalid"),
    }
    results["tailscaleEnvironment"] = tailscale_environment()
    return {
        "schemaVersion": 1,
        "evidenceDate": "2026-07-16",
        "scope": "host-loopback-and-local-resolver",
        "result": "PASS",
        "privacy": {
            "redacted": True,
            "committedEvidenceContainsSecrets": False,
            "privateServerDataPersisted": False,
            "credentialsPersisted": False,
            "serverAddressesPersisted": False,
            "serverIdentifiersPersisted": False,
        },
        "proofs": results,
        "limitations": [
            "Host TLS validation is not iOS ATS or physical-device evidence.",
            "UDP discovery uses the Jellyfin discovery request/response shape on loopback; Local Network permission remains a device gate.",
            "Live Tailscale proof remains blocked unless tailscaleEnvironment reports AVAILABLE.",
        ],
    }
