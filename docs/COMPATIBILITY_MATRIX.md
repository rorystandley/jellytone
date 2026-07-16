# Compatibility Matrix

Matrix version: 0.1.0-phase0

Evidence snapshot: 2026-07-16

Status: Phase 0 evidence in progress; not an advertised compatibility claim

This versioned matrix records observed support, not API presence. `pass` means
the row's stated scope was executed; `limited` means useful evidence exists but
the product requirement is not fully proven; `pending` means executable evidence
is absent; `externally blocked` names a dependency outside this checkout. Every
non-pass row has an owner and fail-closed fallback. Evidence paths are relative
to `docs/evidence/phase-0/`.

## Platform and server baselines

| Dimension | Candidate | Status | Executed evidence | Owner and fallback |
| --- | --- | --- | --- | --- |
| Minimum iOS/iPadOS | 18.4 proposal | limited | `device/execution-status.json`: an 18.4-targeted signed build installs on current hardware; no 18.4 runtime/device | Phase 0 device; retain proposal and do not advertise minimum support |
| Current tested iOS/iPadOS | 26.5 | limited | `platform/environment.json`: current iPhone/iPad simulators; signed iPhone 13 install only | Phase 0 device; do not promote simulator/install to runtime support |
| iPadOS device behavior | 18.4 and current | pending | No physical iPad is attached | Phase 0 platform; do not advertise device-validated iPad behavior |
| Current Jellyfin line | 10.11.11 | limited | Digest-pinned server; auth/library/reporting plus all required original and forced-AAC delivery contracts pass | Phase 0 playback/device; advertise no full media compatibility until device matrix passes |
| Previous Jellyfin line | 10.10.7 | limited | Digest-pinned server; auth/library/reporting plus all required original and forced-AAC delivery contracts pass | Phase 0 playback/device; omit the line if its device matrix fails |
| Official Swift SDK | 2.1.0 at `09d8f3…` | pass | Exact revision plus seven SDK URL/base-path tests | Phase 1 gateway; retain pin until replacement passes contracts |

## Audio delivery and transitions

All host evidence is in `playback/`; server delivery evidence is in
`connectivity/`. A host `AVURLAsset` result or decoded file is not iOS-device
playback proof.

| Codec/container | Local original | HTTP original | Jellyfin original/transcode | Gapless/crossfade | Owner and fallback |
| --- | --- | --- | --- | --- | --- |
| MP3 | limited: host prepares | limited: host prepares | pass: original MP3 + forced AAC on both servers | limited: deterministic render only | Phase 0 playback; request AAC or ordinary hard cut |
| AAC in M4A/MP4 | limited: host prepares | limited: host prepares | pass: original AAC + forced AAC on both servers | limited: deterministic render only | Phase 0 playback; request proven AAC profile or ordinary hard cut |
| ALAC in M4A/MP4 | limited: host prepares | limited: host prepares | pass: original ALAC + forced AAC on both servers | limited: deterministic render only | Phase 0 playback; request AAC or ordinary hard cut |
| FLAC | limited: host prepares | limited: host prepares | pass: original FLAC + forced AAC on both servers | limited: deterministic render only | Phase 0 playback; request AAC or ordinary hard cut |
| Ogg/Vorbis | limited: host prepares | limited: host prepares | pass: original Vorbis + forced AAC on both servers | limited: deterministic render only | Phase 0 playback; request AAC or ordinary hard cut |
| Ogg/Opus | limited: host prepares | limited: host prepares | pass: original Opus + forced AAC on both servers | limited: deterministic render only | Phase 0 playback; request AAC or ordinary hard cut |
| Next-item preload | limited | limited | pending on device | Not applicable | Phase 0 playback; prepare opportunistically and use diagnosable hard cut |

## Synthetic library shapes

Evidence: `automation/synthetic-library.md` and the disposable Jellyfin library.

| Fixture | Status | Owner and fallback |
| --- | --- | --- |
| Single-disc | pass | Phase 3 mapping retains synthetic regression fixture |
| Multi-disc | pass | Phase 3 mapping sorts by disc then track |
| Compilation | pass | Phase 3 mapping uses album-artist/compilation rules |
| Missing artwork | pass | Phase 3 UI uses deterministic accessible fallback |
| Malformed metadata | pass | Phase 3 mapping rejects/defaults invalid fields diagnostically |

## Connectivity and failure modes

Host proofs are in `network/`; authenticated server contracts are in
`connectivity/`. Host TLS and loopback discovery do not substitute for iOS ATS,
Local Network permission, or real-route behavior.

| Scenario | Status | Executed evidence | Owner and fail-closed fallback |
| --- | --- | --- | --- |
| Manual URL, port, reverse-proxy base path | pass | Policy/SDK tests plus live `/jellyfin` proxy identity | Phase 1 gateway; reject ambiguous URLs |
| IPv4 | limited | Trusted host HTTPS proxy passes | Phase 0 device; require manual trusted HTTPS if device route fails |
| IPv6 | limited | Trusted host HTTPS proxy passes | Phase 0 device; require manual trusted HTTPS if device route fails |
| `.local` | limited | Host resolves IPv4/IPv6; UDP protocol shape passes | Phase 0 device; manual full URL |
| Trusted HTTPS | limited | Test CA succeeds only when explicitly trusted | Phase 0 device; platform trust only, no bypass |
| Expired/untrusted/wrong-host TLS | limited | All fail closed in host lab | Phase 0 device; reject and explain remediation |
| Redirects 301/302/303/307/308 | limited | Same/cross-origin identity and credential isolation pass on host | Phase 0 device; block redirect until exact identity proof |
| Plain local HTTP / ATS | pending | Narrow ADR and harness configuration exist; no device runtime | Phase 0 device; HTTPS-only onboarding |
| Local UDP discovery | limited | Loopback Jellyfin response/identity shape passes | Phase 0 device; manual full URL |
| Tailscale IP | limited | URL classification only; no client/tailnet | Phase 0 connectivity; diagnose VPN unavailable |
| Tailscale MagicDNS | externally blocked | No `tailscale` CLI or connected synthetic tailnet | Phase 0 connectivity; manual verified URL |
| Tailscale Serve HTTPS | externally blocked | No connected synthetic tailnet/Serve endpoint | Phase 0 connectivity; platform-trusted reverse proxy |
| Wi-Fi route | pending | No device runtime event | Phase 0 device; retain current verified endpoint only |
| Cellular/expensive route | pending | No device runtime event | Phase 0 device; conservative quality and no insecure HTTP |
| Low Data Mode/constrained route | pending | No device runtime event | Phase 0 device; conservative quality and deferred prefetch |
| VPN unavailable/loss | externally blocked | No connected synthetic tailnet | Phase 0 connectivity; no speculative endpoint/token replay |
| Captive network | pending | No controlled route | Phase 0 network; classify as transport/captive and do not authenticate |
| Server unavailable/restart | limited | Real container stop/restart preserves public identity | Phase 2 playback; stop/re-prove identity before retry |
| Server sleep | pending | No controllable sleeping host | Phase 2 playback; diagnosable unavailable state |
| Invalid/logged-out token | pass | Both server versions reject invalid and logged-out tokens | Phase 1 credentials; delete local token and reauthenticate |
| Expired/revoked token | limited | Session logout rejection passes; expiry/admin revocation incomplete | Phase 1 credentials; pause and reauthenticate |
| Offline operation | pending | No device cold-launch playback evidence | Phase 5 offline; expose only verified manifest-backed local state |

## Audio routes and Apple surfaces

| Route/surface | Status | Executed evidence | Owner and fallback |
| --- | --- | --- | --- |
| Built-in speaker | pending | Signed harness installs but locked-device launch blocks playback | Phase 0 device; do not claim hardware playback |
| Wired output | externally blocked | No compatible accessory attached | Phase 4 device; ordinary route-change fallback |
| Bluetooth | externally blocked | No controlled Bluetooth route attached | Phase 4 device; pause/recover per route reason |
| AirPlay | externally blocked | No controlled AirPlay route available | Phase 4 device; retain local route or stop diagnostically |
| Lock Screen/remote commands | pending | Harness registration exists; no command receipt | Phase 0 device; do not claim command behavior |
| Background audio/download | pending | Harness build/install only; no runtime/suspension/relaunch evidence | Phase 0 device; foreground-only proof is insufficient |
| CarPlay | externally blocked | Entitlement request/approval is not locally verifiable; compatible hardware is unavailable | Phase 0/6 platform; do not ship CarPlay target without entitlement |

## Open-evidence release rule

This matrix may be committed while incomplete as an honest versioned evidence
snapshot. It must not be treated as the final advertised compatibility table.
A later revision may change a row to `pass` only when its full product scope has
executed evidence, and must retain prior evidence for comparison.
