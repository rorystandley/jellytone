# Phase 3 playlist rename evidence

The bounded write changes only `Name` through `POST /Playlists/{id}` after a
read of current state. The durable outbox is scoped to server/account/playlist,
coalesces rapid edits, and is safe across relaunch; membership and order are
never represented or sent.

Deterministic coverage targets validation and Unicode, migration/persistence,
payload classification, online/already-applied success, offline retry,
expired-auth pause/resume, conflicts and both choices, coalescing, stale
completion, logout/isolation, shared list/detail state, and redacted diagnostics.
UI coverage targets VoiceOver, Dynamic Type, compact/regular widths, light/dark,
Reduce Motion, validation, and conflict states. Compatibility evidence targets
Jellyfin 10.10.7 and 10.11.11. The Phase 3 write exit gate remains open until
the complete required command suite passes.
