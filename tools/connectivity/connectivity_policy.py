"""Phase 0 executable connectivity policy.

This is a proof artifact, not production application code.  It deliberately uses
only the Python standard library so the policy can run before Phase 1 creates the
Swift project.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import hmac
import ipaddress
import json
from pathlib import Path
import re
from typing import Any, Mapping
from urllib.parse import parse_qsl, quote, unquote, urlencode, urlsplit, urlunsplit


SUPPORTED_SERVER_LINES = {(10, 11), (10, 10)}
SENSITIVE_KEYS = {
    "access_token", "accesstoken", "api_key", "apikey", "authorization",
    "password", "pw", "secret", "token", "username", "user_name",
}
PRIVATE_VALUE_KEYS = {
    "address", "baseurl", "endpoint", "host", "hostname", "id", "itemid",
    "itemname", "library", "name", "path", "server", "serverid", "url",
    "servername", "userid",
}
_AUTH_RE = re.compile(r"(?i)(MediaBrowser\s+[^\r\n]*?Token=)[\"']?[^,\s\"']+")
_BEARER_RE = re.compile(r"(?i)\b(Bearer)\s+[^\s,]+")
_JELLYFIN_TOKEN_HEADER_RE = re.compile(
    r"(?i)\b(X-(?:Emby|MediaBrowser)-Token\s*:\s*)[\"']?[^\s,;\r\n\"']+[\"']?"
)


class PolicyError(ValueError):
    """The candidate violates the Phase 0 connection policy."""


@dataclass(frozen=True)
class Endpoint:
    url: str
    scheme: str
    host: str
    port: int
    base_path: str

    @property
    def origin(self) -> tuple[str, str, int]:
        return (self.scheme, self.host, self.port)

    def api_url(self, api_path: str) -> str:
        if not api_path.startswith("/"):
            raise PolicyError("API paths must start with '/'")
        return f"{self.url}{api_path}"


def _normal_host(host: str) -> str:
    if "%" in host:  # IPv6 zone identifiers are meaningful and must be retained.
        address, zone = host.split("%", 1)
        ipaddress.ip_address(address)
        return f"{address.lower()}%{zone}"
    try:
        return ipaddress.ip_address(host).compressed.lower()
    except ValueError:
        try:
            return host.rstrip(".").encode("idna").decode("ascii").lower()
        except UnicodeError as error:
            raise PolicyError("host is not a valid DNS name") from error


def normalize_endpoint(raw: str) -> Endpoint:
    """Normalize a full manual/discovered URL without losing a base path."""
    candidate = raw.strip()
    if not candidate:
        raise PolicyError("endpoint is empty")
    parts = urlsplit(candidate)
    scheme = parts.scheme.lower()
    if scheme not in {"http", "https"}:
        raise PolicyError("a full http:// or https:// URL is required")
    if parts.username is not None or parts.password is not None:
        raise PolicyError("credentials must not be embedded in an endpoint URL")
    if parts.query or parts.fragment:
        raise PolicyError("endpoint URLs must not contain a query or fragment")
    if not parts.hostname:
        raise PolicyError("endpoint has no host")
    host = _normal_host(parts.hostname)
    try:
        port = parts.port or (443 if scheme == "https" else 80)
    except ValueError as error:
        raise PolicyError("endpoint port is invalid") from error

    raw_segments = [segment for segment in parts.path.split("/") if segment]
    decoded_segments = [unquote(segment) for segment in raw_segments]
    if any(segment in {".", ".."} for segment in decoded_segments):
        raise PolicyError("dot segments are forbidden in a server base path")
    if decoded_segments and decoded_segments[-1].lower() == "web":
        decoded_segments.pop()
    encoded_segments = [quote(segment, safe="!$&'()*+,;=:@-._~") for segment in decoded_segments]
    base_path = "/" + "/".join(encoded_segments) if encoded_segments else ""

    try:
        rendered_host = f"[{host}]" if ipaddress.ip_address(host.split("%", 1)[0]).version == 6 else host
    except ValueError:
        rendered_host = host
    default_port = (scheme == "https" and port == 443) or (scheme == "http" and port == 80)
    netloc = rendered_host if default_port else f"{rendered_host}:{port}"
    url = urlunsplit((scheme, netloc, base_path, "", ""))
    return Endpoint(url=url, scheme=scheme, host=host, port=port, base_path=base_path)


def same_server_identity(first: str | None, second: str | None) -> bool:
    """Server IDs are opaque, exact identifiers; names and URLs are not identity."""
    if not first or not second:
        return False
    return hmac.compare_digest(first.encode("utf-8"), second.encode("utf-8"))


class RedirectAction(str, Enum):
    FOLLOW_WITHOUT_CREDENTIALS = "follow_without_credentials"
    REISSUE_AFTER_IDENTITY_PROOF = "reissue_after_identity_proof"
    BLOCK = "block"


@dataclass(frozen=True)
class RedirectDecision:
    action: RedirectAction
    reason: str


def evaluate_redirect(
    source: Endpoint,
    destination: Endpoint,
    *,
    request_was_authenticated: bool,
    source_server_id: str | None = None,
    destination_server_id: str | None = None,
) -> RedirectDecision:
    """Decide redirect handling without ever forwarding credentials implicitly."""
    if source.scheme == "https" and destination.scheme == "http":
        return RedirectDecision(RedirectAction.BLOCK, "TLS downgrade")
    if source.origin == destination.origin:
        return RedirectDecision(
            RedirectAction.REISSUE_AFTER_IDENTITY_PROOF
            if request_was_authenticated else RedirectAction.FOLLOW_WITHOUT_CREDENTIALS,
            "same origin; authenticated requests are reconstructed, never implicitly forwarded",
        )
    if not same_server_identity(source_server_id, destination_server_id):
        return RedirectDecision(RedirectAction.BLOCK, "changed origin lacks matching public server identity")
    return RedirectDecision(
        RedirectAction.REISSUE_AFTER_IDENTITY_PROOF,
        "changed origin independently proved the same server ID",
    )


def server_line(version: str) -> tuple[int, int]:
    match = re.fullmatch(r"(\d+)\.(\d+)(?:\.\d+)?(?:[-+].*)?", version)
    if not match:
        raise PolicyError("server version is malformed")
    return int(match.group(1)), int(match.group(2))


def is_supported_server(version: str) -> bool:
    return server_line(version) in SUPPORTED_SERVER_LINES


def redact_url(value: str) -> str:
    try:
        parts = urlsplit(value)
    except ValueError:
        return "<redacted-url>"
    if not parts.scheme or not parts.netloc:
        return "<redacted>"
    query = []
    for key, item in parse_qsl(parts.query, keep_blank_values=True):
        query.append((key, "<redacted>" if _is_sensitive_key(key) else item))
    return urlunsplit((parts.scheme, "<server>", "/<redacted-path>" if parts.path else "", urlencode(query), ""))


def _normalized_key(key: str) -> str:
    return re.sub(r"[^a-z0-9]", "", key.lower())


def _is_sensitive_key(key: str) -> bool:
    """Fail closed for credential fields without matching status/result names."""
    normalized = _normalized_key(key)
    explicit = {_normalized_key(item) for item in SENSITIVE_KEYS}
    if normalized in explicit:
        return True
    # Covers the actual Jellyfin headers X-Emby-Token,
    # X-MediaBrowser-Token, and X-Emby-Authorization. Fields such as
    # Status fields such as invalidTokenRejected and reportContainsSecrets do not
    # end in these suffixes.
    return normalized.endswith(("token", "password", "authorization"))


def redact(value: Any, key: str = "") -> Any:
    """Redact secrets and private library/server identity before persistence."""
    lowered = _normalized_key(key)
    normalized_private = {_normalized_key(item) for item in PRIVATE_VALUE_KEYS}
    if _is_sensitive_key(key) or lowered in normalized_private:
        return "<redacted>"
    if isinstance(value, Mapping):
        return {str(item_key): redact(item_value, str(item_key)) for item_key, item_value in value.items()}
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, str):
        if value.startswith(("http://", "https://")):
            value = redact_url(value)
        value = _JELLYFIN_TOKEN_HEADER_RE.sub(r"\1<redacted>", value)
        value = _AUTH_RE.sub(r"\1<redacted>", value)
        value = _BEARER_RE.sub(r"\1 <redacted>", value)
        return value
    return value


class TokenState(str, Enum):
    EMPTY = "empty"
    ACTIVE = "active"
    REAUTHENTICATION_REQUIRED = "reauthentication_required"


@dataclass
class TokenContract:
    """In-memory proof of the Keychain-reference and token lifecycle contract."""
    expected_server_id: str
    keychain_reference: str | None = None
    _runtime_token: str | None = None
    state: TokenState = TokenState.EMPTY

    def accept_authentication(self, result: Mapping[str, Any]) -> str:
        token = result.get("AccessToken")
        server_id = result.get("ServerId")
        if not isinstance(token, str) or not token:
            raise PolicyError("authentication response has no access token")
        if not isinstance(server_id, str) or not same_server_identity(self.expected_server_id, server_id):
            raise PolicyError("authentication response server ID does not match the verified endpoint")
        # The production implementation writes `token` to Keychain here.  Durable
        # metadata receives only this opaque reference.
        self.keychain_reference = f"keychain:jellyfin/{self.expected_server_id}/synthetic-user"
        self._runtime_token = token
        self.state = TokenState.ACTIVE
        return self.keychain_reference

    def handle_unauthorized(self) -> None:
        self._runtime_token = None
        self.keychain_reference = None
        self.state = TokenState.REAUTHENTICATION_REQUIRED

    def sign_out(self) -> None:
        # Revocation is attempted by the gateway; local deletion is unconditional.
        self._runtime_token = None
        self.keychain_reference = None
        self.state = TokenState.EMPTY

    def durable_metadata(self) -> dict[str, str]:
        return {"tokenReference": self.keychain_reference} if self.keychain_reference else {}


REQUIRED_PUBLIC_INFO = {"Id", "ServerName", "Version", "ProductName"}
REQUIRED_AUTH_RESULT = {"AccessToken", "ServerId", "User"}
REQUIRED_QUICK_CONNECT = {"Authenticated", "Code", "Secret"}


def validate_contract_fixture(path: Path) -> dict[str, Any]:
    fixture = json.loads(path.read_text(encoding="utf-8"))
    version = fixture.get("declaredServerVersion")
    if not isinstance(version, str) or not is_supported_server(version):
        raise PolicyError(f"{path}: unsupported declared server version")
    for name, required in (
        ("publicSystemInfo", REQUIRED_PUBLIC_INFO),
        ("authenticationResult", REQUIRED_AUTH_RESULT),
        ("quickConnectResult", REQUIRED_QUICK_CONNECT),
    ):
        value = fixture.get(name)
        if not isinstance(value, dict) or not required.issubset(value):
            raise PolicyError(f"{path}: {name} lacks required keys")
    if fixture["publicSystemInfo"]["Version"] != version:
        raise PolicyError(f"{path}: public version does not match declaration")
    if not same_server_identity(
        fixture["publicSystemInfo"]["Id"], fixture["authenticationResult"]["ServerId"]
    ):
        raise PolicyError(f"{path}: authentication server ID differs from public identity")
    if not isinstance(fixture.get("audioItems"), list) or not fixture["audioItems"]:
        raise PolicyError(f"{path}: representative audio items are missing")
    return fixture
