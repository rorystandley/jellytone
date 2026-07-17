# Phase 3 listening-experience evidence

Status: Partial early slice; Phase 3 is not complete

Last updated: 2026-07-17

## Implemented

- Native Home, Library, and local Search destinations.
- One persistent mini-player above the tab bar and one full Now Playing sheet.
- The authoritative playback controller exposes the visible queue and owns
  Play Next, Add to Queue, shuffle, repeat, queue index, and persistence.
- Album-track context menus add queue actions without duplicating playback
  state in SwiftUI.
- System Now Playing receives the same queue index and count as the app UI.
- Existing snapshots decode with shuffle off and repeat off; new snapshots
  preserve original/current queue order and playback modes.
- Queue occurrences have stable identity independent of track IDs. The Queue
  sheet protects and highlights the current track, jumps to an upcoming entry
  on tap, reorders by drag or accessibility action, removes individual entries,
  and clears Up Next without stopping the current track.
- Legacy track-array snapshots migrate duplicate occurrences independently.
  Editing while shuffled adopts the visible order as canonical and disables
  shuffle; jumping alone preserves shuffle.
- Rapid replacement serializes preparation and shields Jellyfin session
  reporting cleanup so a superseded middle selection cannot start after the
  final intent.
- Search now debounces input and queries Jellyfin beyond the initially loaded
  album page. Requests are cancellable, paged, scoped to the selected music
  library, and constrained to `MusicArtist` and `MusicAlbum`; the gateway also
  rejects unexpected response item types before mapping domain results.
- Artist results navigate to native, adaptive artist pages with authenticated
  artwork, missing-artwork fallback, paged albums, retry/empty/loading states,
  and navigation into the existing album and authoritative playback flow.
- Search replacement, dismissal cancellation, page loading, and artist loading
  do not create playback state or log search terms, item names, or identifiers.
- GRDB-backed domain artists and albums are scoped by server, account, and music
  library. The selected library is restored before network work so repeat
  launches can present cached albums immediately.
- Deterministic first-page cache matches merge with server values by exact item
  identity. Fresh duplicates replace cached metadata in stable positions,
  server-only values append in server order, and server pagination remains
  authoritative. Offline transport failures use cache-only results;
  authentication and HTTP failures are not hidden.
- On iOS 26, the persistent mini-player uses SwiftUI's tab-view bottom accessory
  and disables tab-bar minimization so Home, Library, and Search remain visible.
  Earlier supported iOS releases retain the safe-area inset fallback.

## Automated evidence

`./scripts/test.sh` passes 66 tests. In addition to deterministic queue coverage,
gateway tests prove reverse-proxy-safe search and artist-album request
construction, selected-library scoping, Unicode/query encoding, music-only
filtering, pagination offsets, artwork/year mapping, and rejection of injected
video/audio rows. UI-adjacent controller tests prove cancellation is silent and
an older delayed search cannot replace newer artist/album results. A UI
regression test launches a deterministic shell with an active mini-player,
asserts all three primary tabs remain present, opens Search, and asserts the
Search destination is visible while the tab bar persists. `./scripts/test-ui.sh`
passes all 3 UI tests, and an agent-inspected compact-iPhone render shows the
mini-player above the visible Home, Library, and Search controls.

The durable-queue focused simulator run passes deterministic tests for snapshot
round-trip and legacy migration, duplicate identity, jump/reorder/remove/clear,
shuffled edits, repeat boundaries, restoration, and rapid session ordering. A
focused Queue UI test passes on compact-iPhone and iPad simulators: it opens the
nested sheet and proves Clear Up Next removes both upcoming entries while the
protected current track remains.

The cache-backed slice adds focused tests for SQLite schema creation and
reopening, WAL/foreign-key/busy-timeout settings, failed-migration rollback,
atomic stale-album replacement, scope isolation, malformed payloads,
deterministic Unicode-aware ordering, repeat-open cache-only search, duplicate
merging, pagination preservation, and offline-versus-authentication policy.
All added values are synthetic, and cache payloads/search terms are not logged.
The complete `./scripts/test-integration.sh` gate passes against fixture and
digest-pinned disposable-server lanes, `./scripts/test-ui.sh` passes all 5 UI
tests, and `./scripts/build-release.sh` produces the simulator release build.
No device run was added because this slice changes metadata persistence and
search orchestration, for which the simulator is representative; the audible
Phase 2 real-device blocker remains unchanged.

The deterministic edge-case batch adds three privacy-safe, file-backed Jellyfin
responses under `Tests/Fixtures/Jellyfin/Phase3`: `albums.json`, `search.json`,
and `tracks.json`. They cover compilation album artists and per-track artists,
shuffled multi-disc tracks with stable tie-breakers, missing art, duplicate
artist/album names with distinct IDs, composed and decomposed Unicode plus
non-Latin text and emoji, absent optional metadata, wrong-typed optional values,
blank/missing required values, scalar/null records, and valid siblings around
malformed records. Mapping rejects records without a usable ID and name, degrades
malformed optional fields to supported nil/unknown fallbacks, advances paging by
the raw server row count, and never lets one bad row invalidate valid siblings.

Persistence coverage proves exact Unicode and nil-metadata round-trip, folded
local search, duplicate-name identity preservation, invalid-write filtering,
malformed-row isolation, repeat-refresh/upsert idempotence, and isolation of the
same item IDs across servers, accounts, and libraries. The focused mapping suite
passes 3 tests and the focused `LibraryStoreTests` suite passes 15 tests. The
final integrated run passed `./scripts/test.sh` with 66 tests and zero failures,
`./scripts/test-integration.sh` across both the fixture and disposable Jellyfin
lanes, `./scripts/test-ui.sh` with 5 tests and zero failures, and
`./scripts/build-release.sh` with `BUILD SUCCEEDED`. No device test is required
because this batch changes deterministic response mapping and metadata tests
only; the
blocked audible Phase 2 real-device gate remains open.

The deterministic scale batch generates its corpus in memory from fixture
format version 1 and explicit seed `24865808422`; it does not commit a generated
library export. The authoritative scale configuration produces 240 artists,
1,440 albums, and 23,040 tracks, including 2-disc albums, compilations,
duplicate display names, missing artwork/metadata, and Unicode names. Its
canonical sorted-key JSON SHA-256 is
`795bcd37ada99d75f880189511b2056090a4317c0bc056a5317ae69f2d17dd0b`.
Tests pin that hash, prove byte-identical repeated generation, prove seed and
configuration changes alter it. The generator uses explicit index ordering,
pure radix/padding operations, canonical sorted-key encoding, a fixed POSIX
locale for search folding, and no dates, timezones, filesystem enumeration,
dictionaries, UUIDs, or process-random sources.
The scale metadata records 131 compilation albums, 1,440 multi-disc albums, 35
artists and 240 albums without artwork, 160 albums without a year, 2,094 tracks
with at least one missing index/disc/duration field, 13 duplicate-name artist
entries, 111 duplicate-name album entries, and 600 Unicode-name entries.

The focused scale test maps all 1,440 generated album responses through
`JellyfinAPI` in 127-record pages, then proves initial cache insertion,
127-record paginated upserts, repeated-refresh idempotence, authoritative
replacement/removal, reused-ID account and server isolation, database row and
identity uniqueness, Unicode and duplicate-name local searches, stable repeated
ordering, and local/server merge de-duplication without changing server
pagination. The existing edge fixtures remain the evidence for track mapping,
compilation semantics, malformed server rows, and library-scope isolation; this
batch does not claim that all 23,040 tracks are mapped through one server
response.

On the development host (`Mac16,10`, 24 GiB, macOS 26.5.2, Xcode 26.6) using an
iPhone 17 Pro iOS 26.5 simulator, a focused successful run observed 105.444 ms
for generation, 28.049 ms for paginated album mapping, 54.362 ms for initial
refresh, 109.414 ms for paginated idempotent refresh, and 126.051 ms for
representative searches. Peak whole-test-process resident memory ranged from
273,481,728 to 282,279,936 bytes. The test retains the same values as a
machine-readable JSON xcresult attachment and prints compact JSON to the log;
the committed observation is in `large-library-scale.json`. Assertions use
deliberately generous 20-30 second and 1.5 GB fail-safe ceilings so supported CI
hosts can detect severe regressions without turning host scheduling noise into
failures. These are absolute process-RSS and development-host observations, not
per-operation allocation measurements or universal device-performance claims.
The integrated focused generator/scale run passes 6 tests with zero failures.
The final repository validation passes `./scripts/test.sh` with 72 tests and
zero failures, `./scripts/test-integration.sh` across fixture and disposable
Jellyfin 10.11.11/10.10.7 lanes, `./scripts/test-ui.sh` with 5 tests and zero
failures, and `./scripts/build-release.sh` with `BUILD SUCCEEDED`. No device run
was added because this batch changes deterministic test infrastructure and
metadata evidence only; the audible Phase 2 real-device blocker remains open.

## Device state

The signed build installed and launched on the paired iPhone. It restored the
live server session, a single-entry queue, and a non-zero 131-second playback
position, then reported successful progress after playback resumed. No new
JellyfinAudio crash report appeared. Visual inspection of every new surface,
locked-screen playback duration, and Lock Screen commands remain open device
evidence.

The 2026-07-17 server-search slice also built, installed, and launched through
`./scripts/deploy-app.sh --launch` on the paired phone. The 09:23 BST launch
restored the session and playback, received HTTP 200 for playback information,
music views, and the first album page, and received HTTP 204 for playback start.
The collected diagnostics contained 403 schema-valid `JA_DIAG` rows and zero
URL, address, UUID, or token/header pattern matches. The newest device crash
report remains the already-diagnosed 08:57 `MPMediaItemArtwork` main-actor
`SIGTRAP`, predating this build; no crash report was created by the search-slice
launch. At that point, search interaction and visual inspection on the physical
phone had not been automated and remained unclaimed.

A user-provided 09:31 device screenshot then exposed that the safe-area
mini-player consumed the bottom shell on iOS 26: the mini-player was visible but
the complete tab bar was absent, making Library and Search unreachable. The
regression fix uses the iOS 26 tab-view bottom accessory with minimization
disabled and retains the safe-area fallback for iOS 18 through 25. The corrected
build installed and launched on the paired phone at 09:38 BST. Its redacted
post-launch diagnostics include a real `music_search` operation, contain zero
URL/address/UUID/token pattern matches, and produced no new crash report.

The durable-queue build installed and launched through
`./scripts/deploy-app.sh --launch` on the paired iPhone. The copied diagnostics
contained 62 schema-valid `JA_DIAG` rows and zero URL, IPv4, UUID, authorization,
token/header, API-key, or username pattern matches. The device still contained
the same seven historical JellyfinAudio crash reports; the newest remained the
08:57:07 artwork crash from before this slice. Queue interaction on the physical
phone was not automated, so installation, launch, redaction, and absence of a
new crash are the only device observations claimed here.

After the final shuffle-history and repeat-all correction, the final build
installed successfully on the same paired iPhone. The requested launch was
denied by SpringBoard only because the phone had relocked (`CoreDeviceError
10002`, locked). Therefore the final source is simulator-gate and install
verified, but its launch is not promoted to final-build device evidence.

## Deliberately not claimed

- Playlist, genre, favourites, downloads, or multi-profile screens.
- Full screenshot/accessibility matrix coverage for every Phase 3 destination.
- Completion of Phase 2 or Phase 3.
