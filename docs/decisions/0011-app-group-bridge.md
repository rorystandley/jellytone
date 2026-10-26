# ADR 0011: App Group snapshot and command bridge

- Status: Accepted for platform implementation; entitlement unproven
- Date: 2026-07-16

## Context

Widgets, intents, and CarPlay need consistent display state without opening the
main database or recreating the queue. Extension processes have different
lifecycle and concurrency constraints.

## Alternatives

- Extensions open the main database: tight coupling and migration/contention
  risk.
- In-process state only: unavailable during cold extension launch.
- Small versioned snapshots and command envelopes in an App Group.

## Decision

The app atomically writes a versioned Codable `PlaybackSnapshot` plus bounded,
content-addressed artwork to an App Group. Extensions read snapshots and emit
versioned command envelopes with deterministic IDs and expiry. The app remains
the sole queue/playback authority and acknowledges commands idempotently.
Snapshots hold display fields and opaque domain references. They must not hold a
token, server endpoint, authenticated URL, database path, or full library data.

## Consequences

Platform surfaces tolerate stale/missing/corrupt/unsupported snapshots and show
honest fallback state. File coordination and atomic replace prevent partial
reads. Per-surface refresh limits remain authoritative.

## Validation

Contract tests round-trip every schema version and cover partial writes, stale
commands, duplicate delivery, offline state, logout, artwork loss, and privacy
scanning. Entitlement and process behaviour require signed simulator/device proof.

## Rollback and migration

Readers accept the current and immediately previous snapshot version. Writers
upgrade only after every consumer ships compatible readers. Unknown commands
are ignored and recorded by redacted reason code.
