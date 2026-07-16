# ADR 0012: Automation, signing, and release policy

- Status: Accepted; external Apple capabilities remain blocked
- Date: 2026-07-16

## Context

Agents must bootstrap, test, sign, exercise devices, and release without an
assumed human completion step. Signing, managed entitlements, hardware routes,
and App Store services remain external dependencies.

## Alternatives

- CI-only validation: weak local reproducibility and no hardware evidence.
- Local-only validation: no clean-environment enforcement.
- Shared noninteractive gates with CI plus explicit device/external evidence.

## Decision

Phase 0 uses `tools/phase0/validate.sh` as its top-level local/CI entry point and
delegates bounded proofs to `tools/connectivity`, `tools/playback`,
`tools/network-lab`, `tools/device-proof`, and `tools/fixtures`. Phase 1 will
create the stable `scripts/**` entry points named in `AGENTS.md`. CI calls the
same underlying repository gates and provisions disposable Jellyfin versions by
immutable digest. Signing material never enters the repository. Local and CI
probes report identity/profile/capability presence without subjects or hashes.

Use simulator checks for representative lifecycle/UI behavior and `devicectl`
for attached-device discovery/install/launch. Required background audio,
background download, Bluetooth, AirPlay, CarPlay, and endurance gates remain
device-only. Each evidence record follows the Phase 0 schema and uses
pass/fail/blocked/not-run honestly.

Release automation produces an unsigned simulator build and a signed archive as
separate gates. Upload, TestFlight distribution, entitlement request, and App
Store submission require explicit authority and external credentials.

## Consequences

The repository can progress safely when Apple services are unavailable without
claiming blocked gates. CI uses synthetic data and loopback/container endpoints.
Secrets are injected at runtime and logs are redacted.

## Validation

`tools/phase0/validate.sh`, the disposable-server reset/verify command, the
redacted environment probe, and `.github/workflows/phase0.yml` establish the
Phase 0 policy. The isolated `tools/device-proof` lane additionally proves a
clean simulator test, development-signed build, and paired-device installation;
The strengthened lane passes ten simulator XCTest cases and five summary-contract
tests, uses a neutral proof bundle prefix, and validates manifest-backed download
state and exactly-once acknowledgement logic. Its single device launch remains
blocked by the locked phone. Later release gates must prove
clean archive reproduction, profile entitlements, privacy manifest, and upload
result.

## Rollback and migration

CI changes remain reviewable and pinned. A runner/tool update first runs in a
non-required lane, compares artifacts/evidence, then replaces the pin. Revoked
signing state blocks signed lanes without weakening them.
