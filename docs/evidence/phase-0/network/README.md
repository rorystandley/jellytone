# Phase 0 host network evidence

Evidence date: 2026-07-16

This directory records deterministic host-network proofs against the two
digest-pinned disposable Jellyfin servers. It is intentionally separate from iOS
ATS, Local Network permission, real LAN, and live Tailscale claims.

## Reproducible commands and results

From the repository root:

```sh
tools/network-lab/run.sh
PHASE0_NETWORK_PROVE_RESTART=1 tools/network-lab/run.sh
```

The first command verifies or starts both disposable servers, generates ephemeral
certificates and HTTPS reverse proxies, writes redacted machine evidence, and runs
five focused tests. On 2026-07-16 it passed all five tests. The optional environment
variable adds a brief stop/start of only the current disposable server; that proof
also passed and left both server versions healthy.

Generated evidence:

- [host-network-results.json](host-network-results.json) records the redacted host
  proxy, redirect, TLS, discovery, resolver, outage, and Tailscale-environment
  classifications.
- [server-restart-results.json](server-restart-results.json) records the redacted
  disposable-server stop/start result.
- [procedure-and-risks.md](procedure-and-risks.md) defines the remaining live
  procedures, owners, and fail-closed fallbacks.

## What passed

| Mechanism | Evidence |
|---|---|
| Reverse-proxy base path | `/jellyfin` was preserved externally, stripped upstream, and returned the same in-memory public server ID as the direct current server. |
| IPv4 and IPv6 | Trusted-CA HTTPS public identity succeeded through IPv4 and IPv6 loopback listeners where this host supports both. |
| Redirect credential isolation | 301, 302, 303, 307, and 308 were covered for same origin, changed origin with the same server ID, and changed origin with a different server ID. Every destination's first request was credential-free; only a matching identity was explicitly reissued with a process-local synthetic token. |
| HTTPS downgrade | All five redirect codes were rejected by transport policy before destination contact. |
| TLS validation | An explicitly trusted ephemeral local CA passed. System trust rejected that private CA; the explicit context also rejected a different issuer, an expired certificate, and a trusted certificate for the wrong host. No accept-all callback exists. |
| Local discovery shape | A loopback UDP responder accepted Jellyfin's discovery query, returned the SDK-compatible response shape, and advertised a base-path endpoint whose public ID matched. |
| `.local` feasibility | The host resolver returned both IPv4 and IPv6 address families for its `.local` name. No hostname or address is persisted. |
| Unavailable and restart | The proxy classified an unavailable upstream and recovered. Separately, the current disposable Jellyfin container was stopped, observed unavailable, restarted, and returned the same public identity. |
| Tailscale URL handling | Synthetic tailnet IP, MagicDNS short-name, `*.ts.net` HTTPS, and ordinary DNS URL classes are deterministic. This does not prove a live tailnet. |
| Failure categories without a tailnet | A reserved nonexistent name classified as DNS-unavailable, independently from the TLS trust/failure and proxy transport-unavailable cases. |

## Privacy boundary

The output contains no endpoint, host name, LAN address, server ID, user ID,
credential, media name, or library path. Certificates, private keys, redirect
targets, IDs, and the synthetic token exist only in a private temporary directory
or process memory. All listeners are loopback-only.

## Limitations

- Host Python TLS validation is not proof of iOS ATS behavior.
- Loopback UDP shape and host `.local` resolution do not prove physical-device
  Local Network permission, broadcast delivery, or subnet discovery.
- No `tailscale` executable or connected tailnet exists on this host, so MagicDNS,
  Tailscale Serve certificate trust, tailnet routing, and VPN-loss behavior remain
  externally blocked.
- Server restart proves endpoint availability and stable identity, not active
  playback recovery or background reconnection on iOS.
