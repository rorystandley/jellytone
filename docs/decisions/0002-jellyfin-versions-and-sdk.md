# ADR 0002: Jellyfin versions and official Swift SDK

- Status: Provisionally accepted; advertised playback/device rows remain a Phase 0 gate
- Date: 2026-07-16
- Owners: Phase 0 connectivity; Phase 1 JellyfinGateway

## Context

The product needs an explicit server compatibility claim and a pinned client
dependency. Generated API availability is not proof that either server line works
end to end. Generated types must remain behind `JellyfinGateway`.

At the decision date, Jellyfin Server **10.11.11** is the current stable release.
The preceding maintained compatibility line selected for proof is **10.10.7**.
The official SDK's latest release is **2.1.0**, tagged at commit
`09d8f31886b6bea1cfc4719a39bdb6eac1287344`; its 2.1.0 release specifically fixes
client URL paths, important for reverse-proxy base paths. Its generated API is
from the 10.11 line, so 10.10 compatibility cannot be inferred from generation.

Primary sources:

- [Jellyfin Server releases](https://github.com/jellyfin/jellyfin/releases)
- [Jellyfin Server 10.11.11 release](https://github.com/jellyfin/jellyfin/releases/tag/v10.11.11)
- [Jellyfin Server 10.10.7 release](https://github.com/jellyfin/jellyfin/releases/tag/v10.10.7)
- [Official Jellyfin Swift SDK 2.1.0](https://github.com/jellyfin/jellyfin-sdk-swift/releases/tag/2.1.0)
- [SDK package manifest at 2.1.0](https://github.com/jellyfin/jellyfin-sdk-swift/blob/2.1.0/Package.swift)

## Alternatives considered

1. Track the SDK main branch. Rejected because builds would not be reproducible.
2. Generate and own a client directly from each server OpenAPI document. Deferred;
   it increases generated-code and update ownership before a proven SDK gap exists.
3. Use SDK 2.1.0 behind an owned gateway and contract-test both server lines.
   Selected because it is official, current, source-distributed, and replaceable.
4. Support only 10.11. Rejected for the Phase 0 proof target because the product
   plan requires the current and previous supported release.

## Decision

- Pin `jellyfin-sdk-swift` exactly to tag `2.1.0` and verify the resolved commit is
  `09d8f31886b6bea1cfc4719a39bdb6eac1287344`.
- Advertise the 10.11.x and 10.10.x server lines provisionally because disposable
  **10.11.11** and **10.10.7** servers pass authentication, Quick Connect,
  music-library, stream construction, playback-reporting, and all required audio
  delivery contracts. This proves server API/delivery compatibility; audio
  source/playback proofs still own decoding, timing, and device-playback criteria.
- Treat 10.11.x and 10.10.x as the provisional compatibility lines. Reject other
  major/minor lines with a diagnostic; do not make patch-number equality a runtime
  requirement.
- Quarantine SDK request/response types in `JellyfinGateway`; map them to stable
  application-owned models in Phase 1.
- Require synthetic fixture mapping tests and disposable-server contracts for an
  SDK update. Review generated API diffs before changing the pin.

## Consequences

The dependency is reproducible and base-path behavior includes the official 2.1.0
fix. Supporting 10.10 requires explicit tests because the selected SDK was generated
from a newer specification. A newly released Jellyfin server or SDK does not change
the compatibility claim automatically.

## Validation

- `tools/connectivity/verify_sdk_pin.sh` clones the official tag, checks the commit,
  and runs the SDK's own Swift tests.
- `python3 tools/connectivity/run_proofs.py` validates redacted representative
  response shapes for 10.11.11 and 10.10.7.
- Phase 0 automation provisioned both pinned images. Public identity, password,
  Quick Connect pending/disabled/denied/expired-or-unknown/timeout/cancellation/full
  exchange, music enumeration, playback-info/reporting, token rejection, logout,
  and revocation contracts passed for both versions. Original MP3, AAC, ALAC, FLAC,
  Ogg/Vorbis, and Ogg/Opus delivery and forced AAC-in-MP4 server delivery passed
  bounded `ffprobe` structure/codec inspection on both. The complete version
  decision remains provisional until separate iOS decode, timing, and device proofs
  land.

## Rollback and migration

If contract tests expose an SDK incompatibility, keep the gateway interface and
either pin the last passing official release, patch the SDK in a revision-pinned
fork with an upstream issue, or generate the minimal API surface in an owned
package. Persisted domain data must not require migration merely because SDK types
change.
