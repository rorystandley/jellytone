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
- Search now debounces input and queries Jellyfin beyond the initially loaded
  album page. Requests are cancellable, paged, scoped to the selected music
  library, and constrained to `MusicArtist` and `MusicAlbum`; the gateway also
  rejects unexpected response item types before mapping domain results.
- Artist results navigate to native, adaptive artist pages with authenticated
  artwork, missing-artwork fallback, paged albums, retry/empty/loading states,
  and navigation into the existing album and authoritative playback flow.
- Search replacement, dismissal cancellation, page loading, and artist loading
  do not create playback state or log search terms, item names, or identifiers.
- On iOS 26, the persistent mini-player uses SwiftUI's tab-view bottom accessory
  and disables tab-bar minimization so Home, Library, and Search remain visible.
  Earlier supported iOS releases retain the safe-area inset fallback.

## Automated evidence

`./scripts/test.sh` passes 19 tests. In addition to deterministic queue coverage,
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

## Deliberately not claimed

- Cached/local search merged with server results or offline search.
- Playlist, genre, favourites, downloads, or multi-profile screens.
- Full screenshot/accessibility matrix coverage for every Phase 3 destination.
- Drag reordering or removal of queue entries.
- Completion of Phase 2 or Phase 3.
