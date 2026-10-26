# ADR 0010: Local diagnostics and privacy

- Status: Accepted for version 1
- Date: 2026-07-16

## Context

Self-hosted failures need mechanism-level explanation, but server addresses,
credentials, library content, and authenticated media URLs are private.

## Alternatives

- Third-party remote telemetry by default: better fleet visibility but creates
  a backend/privacy obligation.
- No diagnostics: privacy-simple but fails explainability goals.
- Structured local diagnostics with redacted export: useful without a product
  backend.

## Decision

Use OSLog/signposts and an application-owned structured event model. Redact at
event construction before persistence. Allowlisted fields include category,
stable non-private reason codes, durations, sizes, codec/profile, status class,
and salted ephemeral correlation IDs. Usernames, item names/IDs, paths, host/IP,
query strings, authorization headers, tokens, and certificate subjects are
removed or classified locally. Exports are redacted by default.

Ship version 1 without third-party crash/analytics telemetry. Adding it requires
a new ADR covering consent, retention, processors, privacy manifest, deletion,
and failure behaviour.

## Consequences

Diagnostics may be less convenient for fleet analysis but remain useful for
endpoint, cache, download, playback-plan, and reporting decisions. Debug builds
follow the same redaction boundary.

## Validation

Use seeded sensitive fixtures and assert forbidden strings never reach memory
sinks, persisted logs, OSLog formatting inputs, or exports. Secret scanning and
redaction tests fail closed.

The Phase 2 implementation now rejects unknown diagnostic events and fields,
bounds numeric values, categorizes error domains, and uses a typed playback
reporting schema for operation, status, reason, lifecycle, method, and coarse
position. Four deterministic seeded tests prove tokens, authenticated URLs,
hosts, usernames, user/item identity, query strings, authorization values, and
library content cannot enter the shared OSLog/stdout/persistence payload.

## Rollback and migration

Diagnostic schemas are versioned. Unknown records are omitted from export.
Removing a field requires no data migration; adding a field requires an explicit
privacy classification and test.
