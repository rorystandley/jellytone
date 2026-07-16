# Live connectivity environment status and remaining proof

Run date: 2026-07-16

## Environment observations

- Docker CLI exists at `/usr/local/bin/docker`.
- The initial `docker info --format '{{.ServerVersion}}'` check failed because no
  Docker daemon socket was available. Phase 0 automation subsequently restored the
  daemon and provisioned healthy pinned 10.11.11 and 10.10.7 containers.
- Credential-free, redirect-disabled public probes returned HTTP 200, the expected
  version, product name, and a non-empty public server ID from both containers.
- After setup completed, both servers passed password authentication, identity
  matching, invalid-token rejection, music enumeration, playback-info, playback
  reporting, the complete original/forced-AAC six-codec server-delivery matrix,
  Quick Connect pending/enabled/disabled/denied/expired-or-unknown/timeout/
  cancellation behavior, logout, and revoked-session rejection. Both baselines
  remained healthy and version-correct afterward.
- A signed isolated connectivity harness now builds and installs on the paired
  iPhone 13, but its latest launch was blocked by the locked device; no physical-
  device ATS/Local Network result exists.
- No connected Tailscale tailnet was supplied. MagicDNS, Serve HTTPS, VPN loss, and
  cellular-route claims remain open.

## Agent-operable live procedure

For each disposable Jellyfin 10.11.11 and 10.10.7 server, reset to a synthetic music
library and record only redacted output:

1. Run `probe_public_endpoint.py` for root, reverse-proxy base path, IPv4, IPv6, and
   `.local` URLs. Confirm the public ID is stable.
2. Run UDP 7359 local discovery and compare its advertised URL's public ID with the
   manual URL. Discovery absence across Tailscale is expected; use a manual URL.
3. After identity/TLS policy passes, authenticate a synthetic user by password;
   scan every diagnostic/output sink for the password and token. Phase 1 Keychain
   integration must separately prove durable secret handling.
4. Initiate Quick Connect, authorize from the synthetic authenticated session, poll,
   exchange the secret, and compare returned server ID. The disposable-server proof
   now covers disabled, server-disabled denial, expired-or-unknown secret, timeout,
   and cancellation states; retain those contracts in the gateway implementation.
5. Exercise 301/302/303/307/308 redirects through a controllable proxy: same origin,
   changed origin same ID, changed origin different ID, and HTTPS downgrade. Assert
   the proxy never receives a credential before identity approval.
6. Expire/revoke the token, return 401, replace the server behind the same address,
   and restart it. Confirm deterministic reauthentication and no token replay.
7. On iOS 18.4 and the current public iOS release, test platform-trusted HTTPS,
   expired/untrusted/wrong-host certificates, and the proposed
   `NSAllowsLocalNetworking` HTTP cases on IPv4, IPv6, and `.local`.
8. With Tailscale connected, repeat through a MagicDNS short name, fully qualified
   `*.ts.net` Serve HTTPS, and Tailscale IP. Disconnect the VPN during identity,
   authentication, and an authenticated request; prove failure without fallback to
   an unverified endpoint.

All fixtures and account/media values must be synthetic. Reports retain server
version, route class, status, timings, and error category, but redact addresses,
usernames, IDs, paths, item names, codes, secrets, and tokens.

## Open risks, owners, and fallbacks

| Risk / missing evidence | Owner phase | Required resolution | Safe fallback |
|---|---|---|---|
| SDK 2.1.0 generated from 10.11 may differ on unexercised 10.10.7 APIs | Phase 2 JellyfinGateway | Expand contracts for every consumed endpoint during implementation | Do not advertise an untested API surface |
| Local HTTP route classification may race network/VPN changes | Phase 1 JellyfinGateway | Device tests with path changes before auth and requests | HTTPS-only onboarding |
| Paired iPhone 13 lacks a signed connectivity harness | Phase 0 platform / Phase 1 foundation | Build/sign a URLSession harness; run minimum/current OS ATS cases | HTTPS-only; no broad ATS exception |
| Self-signed and privately issued certificates | Phase 2 onboarding UX | Explain platform trust remediation without bypass | Reject connection; use trusted reverse proxy or Serve HTTPS |
| Cross-origin proxy could mimic metadata except opaque ID | Phase 1 JellyfinGateway | Preserve first verified ID and require exact unauthenticated match before credentials | Block endpoint association |
| UDP discovery and Local Network prompt not device-tested | Phase 2 connected slice | Device/simulator permission and subnet tests | Manual full URL |
| Tailscale MagicDNS/Serve/VPN loss unavailable | Phase 0 connectivity | Run on an agent-controlled connected tailnet | Manual trusted HTTPS URL; diagnose VPN unavailable |
| Token revocation may fail while offline | Phase 1 credentials | Test revoke success/failure and local Keychain deletion | Delete locally unconditionally; server token remains an explicit diagnostic risk |
