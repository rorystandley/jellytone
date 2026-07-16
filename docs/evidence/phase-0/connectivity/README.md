# Phase 0 connectivity and security evidence

Evidence date: 2026-07-16

This directory separates executable policy/fixture proof from live environment
proof. A green synthetic run does not claim that a real server, VPN, redirect proxy,
or iOS device passed.

## Reproducible commands

From the repository root:

```sh
python3 tools/connectivity/run_proofs.py
tools/connectivity/verify_sdk_pin.sh
python3 tools/connectivity/probe_public_endpoint.py 'https://operator-owned.example/jellyfin'
python3 tools/connectivity/live_contract_probe.py
python3 tools/phase0/validate_evidence.py docs/evidence/phase-0/connectivity/live-contract-results.json
```

The public probe sends no Jellyfin token or password, disables redirect following,
and redacts the endpoint and returned identity values. Do not pass credentials in
the URL.

## Evidence index

- [policy-and-contract-results.md](policy-and-contract-results.md): captured
  standalone policy, privacy, token, and fixture results.
- [live-environment-status.md](live-environment-status.md): exact live proof gaps,
  operator procedures, risks, owners, and fallbacks.
- [live-contract-results.json](live-contract-results.json): machine-readable,
  redacted authenticated, Quick Connect edge, token lifecycle, and six-codec
  original/forced-transcode results for both disposable server versions. The
  schema-v2 payload is wrapped in the common Phase 0 evidence envelope and passes
  its registered strict validator.
- [ADR 0002](../../../decisions/0002-jellyfin-versions-and-sdk.md): server lines and
  SDK pin.
- [ADR 0007](../../../decisions/0007-connectivity-security.md): TLS, HTTP,
  redirects, identity, authentication, and Tailscale policy.
