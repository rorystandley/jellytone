# ADR 0007: Connectivity, local HTTP, TLS, redirects, and endpoint identity

- Status: Provisionally accepted; device and live-network evidence remains open
- Date: 2026-07-16
- Owners: Phase 0 connectivity; Phase 1 JellyfinGateway and Diagnostics

## Context

Self-hosted Jellyfin installations use LAN addresses, IPv4/IPv6, `.local` names,
reverse-proxy paths, and Tailscale endpoints. Those configurations must not cause
passwords or tokens to cross a server boundary or weaken platform TLS validation.

Apple App Transport Security (ATS) requires secure `URLSession` connections by
default, advises the narrowest possible exception, and documents
`NSAllowsLocalNetworking` for unqualified names, `.local` names, and IP addresses.
Jellyfin warns that authentication data may appear in URL query parameters. Tailscale
documents that MagicDNS provides device names and that Tailscale Serve can terminate
HTTPS with an automatically provisioned certificate.

Primary sources:

- [Apple: Preventing insecure network connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections)
- [Apple: NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
- [Jellyfin reverse-proxy security guidance](https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/)
- [Jellyfin Quick Connect](https://jellyfin.org/docs/general/server/quick-connect/)
- [Tailscale MagicDNS](https://tailscale.com/docs/features/magicdns)
- [Tailscale Serve HTTPS](https://tailscale.com/docs/reference/tailscale-cli/serve)

## Alternatives considered

1. Disable ATS or accept all certificates. Rejected: it exposes credentials and
   makes endpoint identity meaningless.
2. HTTPS only. Safest, but rejected as the only onboarding path because many local
   Jellyfin servers use HTTP and the product explicitly includes an approved local
   HTTP design.
3. Certificate pinning. Rejected as the default because self-hosted certificates
   rotate and public CA validation already supplies the appropriate trust model.
4. Platform TLS plus an explicit LAN-only HTTP exception and identity proof.
   Selected provisionally, pending real-device ATS and Local Network validation.

## Decision

### URL and identity

- Require a full `http://` or `https://` URL. Reject embedded credentials, queries,
  fragments, and dot segments. Preserve ports, IPv4/IPv6, and reverse-proxy base
  paths; remove only a terminal `/web` UI path.
- Probe `System/Info/Public` without credentials and use its opaque `Id` as server
  identity. Names, DNS results, certificates, and URLs are not server identity.
- Associate an alternative endpoint only when it independently returns the exact
  same non-empty server ID.

### Redirects and credentials

- Disable implicit redirects for authentication and authenticated requests.
- Block HTTPS-to-HTTP downgrade redirects.
- A same-origin redirect is reconstructed by the gateway; credentials are never
  left to framework redirect behavior.
- A changed-origin destination is probed without credentials. Reissue an
  authenticated request only after the destination proves the same server ID.
- Password login posts the password only after TLS/HTTP policy and identity checks;
  on success, discard the password and place only the access token in Keychain.
- Quick Connect initiation and polling use the verified endpoint. Store the token
  returned by final Quick Connect authentication exactly like a password-login
  token. Codes and secrets are sensitive diagnostics fields.
- On authentication failure/401, remove runtime and Keychain token material and
  require reauthentication. Sign-out attempts server revocation, but local token
  deletion is unconditional.

### TLS, HTTP, and Tailscale

- Use platform TLS trust with no accept-all delegate and no silent HTTPS-to-HTTP
  fallback. A user-facing certificate failure remains a failure.
- Prefer trusted HTTPS everywhere, including a fully qualified `*.ts.net` name
  served by Tailscale Serve HTTPS.
- Permit plain HTTP only for a user-entered or locally discovered endpoint while
  the active network path is non-cellular and the resolved destination is local or
  tailnet-scoped. Display an interception warning before credentials are submitted.
  Re-evaluate the route before each authentication flow and authenticated endpoint
  change. Phase 1 must implement and device-test this classifier before HTTP ships.
- Proposed ATS configuration is `NSAllowsLocalNetworking = YES`, never
  `NSAllowsArbitraryLoads` and never a media-wide exception. Phase 1 must prove the
  exact iOS 18.4 behavior with `nscurl`, `URLSession`, IPv4, IPv6, `.local`, and a
  physical device before finalizing project configuration.
- The app does not embed or manage Tailscale. UDP discovery is LAN/subnet scoped;
  Tailscale endpoints are manual URLs resolved through the connected VPN.

### Diagnostics

Redact authorization headers, `X-Emby-Token`, `X-MediaBrowser-Token`, tokens in
free-form header lines, Quick Connect secret/code, usernames, server addresses,
paths, IDs, and library/item names before logging or persistence. Never log a full
authenticated media URL. Phase 0 live-contract evidence uses the common evidence
envelope and scans the complete JSON output against the actual process-local
credentials, endpoints, and identities before emitting it. Its privacy claim is
limited to the committed report sink; it is not evidence of memory erasure or
Keychain behavior.

## Consequences

Origin-changing reverse proxies take an extra unauthenticated identity request.
Self-signed HTTPS is unsupported rather than bypassed. Local HTTP remains possible
but receives no confidentiality claim and cannot be enabled by a broad ATS escape
hatch. Endpoint failover is slower but cannot silently send a token to a different
server.

## Validation

`python3 tools/connectivity/run_proofs.py` exercises normalization, base paths,
redirect origin changes and downgrade, exact server equivalence, redaction, token
lifecycle, and two versioned synthetic contracts. `probe_public_endpoint.py` is a
credential-free operator probe that blocks redirects and emits only redacted output.

`tools/network-lab/run.sh` adds an executable host network lab against both pinned
disposable servers. Ephemeral loopback HTTPS proxies proved a preserved reverse-
proxy base path, IPv4 and IPv6, and credential isolation across 301/302/303/307/308
for same-origin, changed-origin same-ID, and changed-origin different-ID redirects.
All HTTPS downgrade cases were rejected before destination contact. A locally
trusted ephemeral CA passed while system-untrusted, different-issuer, expired, and
wrong-host leaves failed closed. Jellyfin-shaped UDP discovery and host `.local`
resolution were feasible without persisting names, addresses, or IDs. The optional
`PHASE0_NETWORK_PROVE_RESTART=1` run stopped and restored the current disposable
server and proved stable public identity after transport recovery.

Public identity, password, Quick Connect pending/enabled/disabled/full exchange,
server-disabled denial, expired-or-unknown secret rejection, bounded timeout, and
client cancellation contracts passed against disposable 10.11.11 and 10.10.7
loopback containers. Invalid/possibly-expired credentials and known logout
revocation both produced rejection; evidence keeps the first classification
deliberately ambiguous because Jellyfin's 401 does not disclose an expiry reason.
Music enumeration, playback-info/reporting, and full codec delivery contracts also
passed. Host redirect-proxy, TLS
validation/failure, dual-stack loopback, discovery-protocol shape, `.local` resolver,
and disposable-server restart proofs now pass. Physical-device ATS and Local Network
permission, real-subnet discovery, MagicDNS, Serve HTTPS, VPN loss, and cellular-route
behavior remain open. A signed isolated connectivity harness now builds with the narrow
`NSAllowsLocalNetworking` key, installs on the paired iPhone 13, and contains no
broad ATS override. Its latest launch was rejected because the device was locked,
so no physical-device ATS result exists. This host has no Tailscale CLI or connected
tailnet; synthetic URL/DNS classification is not reported as live connectivity.

## Rollback and migration

Endpoint records are server-ID scoped. Tightening HTTP policy disables an endpoint
without deleting its account or offline state. If `NSAllowsLocalNetworking` cannot
support the required narrow HTTP cases, ship HTTPS-only onboarding and direct users
to a trusted reverse proxy or Tailscale Serve HTTPS; do not broaden ATS globally.
