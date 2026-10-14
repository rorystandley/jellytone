# ADR 0004: SQLite persistence and migrations

- Status: Accepted for Phase 1
- Date: 2026-07-16

## Context

Metadata, queue restoration, and ordered offline mutations need transactional,
queryable persistence independent of Jellyfin SDK types. Secrets and media must
not enter the database.

## Alternatives

- SQLite through GRDB: explicit schema/SQL with strong Swift transaction and
  migration support.
- Raw SQLite C API: minimal dependency but substantially more owned plumbing.
- SwiftData/Core Data: integrated frameworks but less explicit migration and
  cross-process determinism for this workload.

## Decision

Use GRDB.swift 7.11.1 behind `LibraryStore` repository protocols. Maintain
forward-only, numbered, transactional migrations. Enable foreign keys, WAL, and
busy timeout on each connection. Persist domain values, never generated SDK
models. Scope every server-derived row by server and account. Keep tokens in
Keychain and downloaded media in managed files.

## Consequences

GRDB is the only persistence library exposed to the store implementation.
Migration fixtures must cover each released schema to current, interruption,
and rollback-on-error. Database snapshots contain synthetic data only.

## Validation

Phase 1 must pin the package revision, commit `Package.resolved`, run migrations
from every schema fixture twice, execute foreign-key checks, and prove a failed
migration leaves the prior schema/data intact.

The initial implementation pins GRDB.swift 7.11.1 and its resolved revision,
creates scoped artist and album tables through migration `001`, and verifies
WAL, foreign keys, busy timeout, idempotent reopening, foreign-key integrity,
atomic replacement, and failed-migration rollback with synthetic tests.
Invalid domain values are rejected before writes; malformed or
identity-mismatched payloads are skipped on reads without exposing row types.

Small, device-local UI preferences that do not need transactional or scoped
storage use `UserDefaults` through `AppStorage`. The app-wide appearance
preference is stored as the stable raw values `system`, `light`, or `dark`;
an absent value defaults to `system`. It contains no account, server, media, or
credential data and is deliberately retained across normal app launches.

Migration `002_create_home_shelf_snapshots` adds one atomic, versioned
application-owned Home payload per server/account/music-library key. It stores
no Jellyfin wire model, secret, media path, or managed file reference; malformed
or unsupported payloads are treated as a cache miss without affecting another
scope.

## Rollback and migration

Application releases do not downgrade schemas. Rollback uses a compatible app
build or restores a pre-migration backup. Replacing GRDB retains SQLite files and
repository contracts, with parallel read tests before switching writers.
