#!/usr/bin/env python3
"""Unauthenticated, redacted live endpoint probe for an operator-owned server."""

from __future__ import annotations

import argparse
import json
import ssl
import sys
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

from connectivity_policy import PolicyError, normalize_endpoint, redact


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("endpoint", help="full http(s) Jellyfin URL, including reverse-proxy base path")
    args = parser.parse_args()
    try:
        endpoint = normalize_endpoint(args.endpoint)
    except PolicyError as error:
        print(json.dumps({"result": "invalid_endpoint", "reason": str(error)}))
        return 2
    request = Request(endpoint.api_url("/System/Info/Public"), headers={"Accept": "application/json"})
    try:
        response = build_opener(NoRedirect).open(request, timeout=10)
        payload = json.load(response)
    except HTTPError as error:
        if error.code in {301, 302, 303, 307, 308}:
            print(json.dumps({"result": "redirect_blocked_for_policy_evaluation", "location": redact(error.headers.get("Location", ""))}))
            return 2
        print(json.dumps({"result": "http_failure", "status": error.code}))
        return 2
    except (URLError, ssl.SSLError, TimeoutError) as error:
        print(json.dumps({"result": "transport_or_tls_failure", "errorType": type(error).__name__}))
        return 2
    report = {
        "result": "public_identity_received",
        "endpoint": redact(endpoint.url, "endpoint"),
        "server": redact(payload),
        "identityFieldsPresent": all(payload.get(key) for key in ("Id", "Version", "ProductName")),
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["identityFieldsPresent"] else 3


if __name__ == "__main__":
    sys.exit(main())
