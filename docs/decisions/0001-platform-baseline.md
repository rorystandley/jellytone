# ADR 0001: Platform baseline

- Status: Accepted for Phase 1; device capability claims remain provisional
- Date: 2026-07-16

## Context

The product needs modern Swift concurrency, SwiftUI, background URLSession,
MediaPlayer, App Intents, WidgetKit, and CarPlay while retaining a meaningful
device range. Phase 0 found Xcode 26.6 (Swift 6.3.3), iOS 26.5 simulator
runtimes, and a paired iPhone 13 running iOS 26.5.2. Discovery is not proof of
background, route, codec, endurance, or CarPlay behaviour.

## Alternatives

- iOS/iPadOS 18.4 minimum: the architecture proposal and a reversible baseline.
- iOS/iPadOS 17: wider reach but greater compatibility surface with no Phase 0
  evidence yet.
- Current OS only: simplest implementation but unjustifiably excludes devices.

## Decision

Use Xcode 26.6 and Swift 6 language mode with iOS/iPadOS 18.4 as the proposed
minimum deployment target. Maintain tests on 18.4 when that runtime is
available and the current public iOS runtime. Support iPhone and iPad; do not
advertise a device/OS combination until its compatibility rows have evidence.

## Consequences

Phase 1 can use current concurrency and platform APIs with availability guards
where required. The 18.4 minimum remains a proposal until codec, background,
download, and platform surfaces pass on representative hardware.

## Validation

Run `tools/phase0/probe-environment.sh`; evidence is redacted in
`docs/evidence/phase-0/platform/environment.json`. Phase-specific device scripts
must record model, OS, command, status, and limitations without identifiers.

## Rollback and migration

Raising the minimum is a project-spec change plus compatibility-matrix update.
Lowering it requires clean builds and the complete test matrix on the older
runtime. Persisted data must never depend on OS-version-only encodings.
