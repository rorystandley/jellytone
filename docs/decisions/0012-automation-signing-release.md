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
The strengthened lane passes twelve simulator XCTest cases and ten Python device-contract
tests, uses a neutral proof bundle prefix, and validates manifest-backed download
state and exactly-once acknowledgement logic. Its single device launch remains
blocked by the locked phone. Later release gates must prove
clean archive reproduction, profile entitlements, privacy manifest, and upload
result.

The repository workflow now calls the same stable scripts as local execution
for application unit/simulator, UI, genuine disposable-server integration, and
unsigned Release simulator build gates, while retaining the Phase 0 Apple and
Linux lanes. The integration job does not fall back to fixture-only validation.
The first current-build device attempt failed when CoreDevice disconnected after
acquiring its tunnel. With the phone unlocked, the same gate subsequently
installed and launched successfully and redacted diagnostics proved connected
restoration plus paused start reporting. The lane remains install/launch smoke;
CI and that smoke do not substitute for agent-operated audible playback.

The local unit and UI gates select and report an available iPhone deterministically,
wait for bounded simulator readiness, serialize access to that simulator, disable
XCTest parallelization, and give every run fresh DerivedData and xcresult paths.
DerivedData is removed on exit while the result bundle is retained for diagnosis.
A gate refuses to overlap an existing xcodebuild process on its selected simulator
rather than masking an infrastructure failure with a retry. UI launch fixtures
continue to clear only their synthetic profile and Keychain state.

CI readiness checks retry only transient startup states: simulator boot recovery is
bounded to three clean boot attempts, and disposable Jellyfin provisioning waits
for the specific startup endpoint needed before retrying each bounded setup
mutation. Playback loopback probes similarly require a successful HTTP fixture
response and complete their loopback download before the native probe starts.
These retries do not mask failed tests or broaden pass criteria; they only
distinguish a service that is still starting from one that has failed to start.
The UI gate runs all test classes in three named, non-overlapping matrix shards;
each shard retains the same simulator isolation and pass criteria while keeping
the complete suite below the job timeout.

## Rollback and migration

CI changes remain reviewable and pinned. A runner/tool update first runs in a
non-required lane, compares artifacts/evidence, then replaces the pin. Revoked
signing state blocks signed lanes without weakening them.
