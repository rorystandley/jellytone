# ADR 0003: Declarative project generation

- Status: Accepted
- Date: 2026-07-16

## Context

Autonomous agents need reviewable, reproducible project changes. Hand-edited
`.xcodeproj` state is noisy and conflicts easily.

## Alternatives

- XcodeGen: focused declarative generation, mature Swift implementation.
- Tuist: broader workspace tooling with more concepts and service surface.
- Commit hand-maintained Xcode projects: no extra tool, poor determinism.

## Decision

Pin XcodeGen 2.46.0. Its release archive SHA-256 is
`4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`.
`project.yml` is authoritative. Generated projects are derived. Do not commit
`Jellytone.xcodeproj`. Commit the Swift package lockfile at
`Config/Package.resolved`. `scripts/bootstrap.sh` copies that file into the
generated project after `xcodegen generate`. A partial `Jellytone.xcodeproj`
that only contains the lockfile makes Xcode look for a missing
`project.pbxproj`. CI generates into a clean path, builds that output, and
runs the same underlying repository gates.

## Consequences

Every target, entitlement, build setting, and package must be expressed in the
specification. XcodeGen is a build tool dependency, not an app dependency.

## Validation

`tools/phase0/fetch-xcodegen.sh` verifies the release archive. The isolated
`tools/phase0/prove-project-generation.sh` generates identical specs in two
clean directories and compares normalized output. It deliberately does not
scaffold the production project.

## Rollback and migration

Keep the declarative specification during any generator migration, compare
build settings and schemes, and require a clean release build before removal.
An XcodeGen update requires archive checksum review and deterministic generation
proof.
