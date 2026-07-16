# Network completion procedures and risks

Run date: 2026-07-16

## Agent-operable remaining procedures

### Physical iOS ATS and local discovery

1. Run the signed connectivity harness on the proposed minimum iOS/iPadOS and the
   current public release, with all output passed through the repository redactor.
2. Trust a private test CA through the device's normal profile and full-trust
   controls; prove its valid leaf works and expired, wrong-host, and untrusted leaves
   fail. Do not install an accept-all challenge handler.
3. Exercise `NSAllowsLocalNetworking = YES` with IPv4, IPv6, and `.local` plain HTTP.
   Verify that no arbitrary-load or media-wide ATS exception exists.
4. Deny and then allow Local Network permission. Prove UDP discovery is absent when
   denied, works on the same subnet when allowed, and that manual full URL remains
   available in both cases.
5. Replace or restart the disposable server between public identity and
   authentication; prove no password or token is sent until the original identity
   is restored.

### Connected Tailscale tailnet

1. Install and connect an agent-controlled Tailscale test node; do not use a private
   production tailnet or retain its addresses in evidence.
2. Run the same credential-free public-ID proof through a synthetic MagicDNS short
   name, a Tailscale IP, and a `*.ts.net` Tailscale Serve HTTPS URL. Prove the latter
   passes platform trust without certificate bypass.
3. Authenticate only after the identity matches. Disconnect the VPN during public
   identity, authentication, and an authenticated request. Each must fail as a VPN
   or transport category without falling back to a different unverified endpoint.
4. Reconnect and prove recovery retains the expected public server identity before
   reissuing any authenticated request.

The current machine has no `tailscale` CLI. That is the exact live-tailnet blocker;
synthetic classification tests remain useful but do not waive the procedure.

## Risks, owners, and safe fallbacks

| Risk / missing evidence | Owner | Required evidence | Fail-closed fallback |
|---|---|---|---|
| Host TLS behavior differs from iOS ATS | Phase 0 platform / Phase 1 foundation | Signed minimum/current-OS URLSession matrix | HTTPS-only onboarding; no broad ATS exception |
| Local HTTP classification races a route or VPN change | Phase 1 JellyfinGateway | Re-evaluate path immediately before auth and endpoint changes under device network transitions | Reject HTTP and require trusted HTTPS |
| Device Local Network permission or subnet blocks UDP discovery | Phase 2 onboarding | Deterministic allowed/denied same-subnet device runs | Manual full URL |
| A changed origin exposes a different server behind valid TLS | Phase 1 JellyfinGateway | Independent unauthenticated exact public-ID match before credential reissue | Block redirect and endpoint association |
| Tailscale is absent or disconnected | Phase 0 connectivity / Phase 2 diagnostics | Connected synthetic tailnet MagicDNS, IP, Serve HTTPS, and VPN-loss runs | Diagnose VPN unavailable; retain verified LAN/HTTPS endpoint without speculative fallback |
| Tailnet IP uses plain HTTP without confidentiality | Phase 1 security | Device route classifier plus explicit interception warning | Prefer trusted Tailscale Serve HTTPS |
| Server restarts during an authenticated request or stream | Phase 2 playback | Deterministic 401/transport separation and playback-session recovery | Stop request, do not replay token to another origin, offer retry after identity proof |
| Private CA, expired, or wrong-host certificate is presented | Phase 2 onboarding UX | Platform error-category UI tests | Reject; explain trust remediation or trusted reverse proxy/Serve HTTPS |
