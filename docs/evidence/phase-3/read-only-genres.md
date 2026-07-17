# Phase 3 read-only genre evidence

Status: Bounded destination slice complete; Phase 3 is not complete

Last updated: 2026-07-17

## Implemented boundary

- Library exposes an adaptive genre collection and genre detail with separately
  paged albums and playable tracks.
- `Genre` identity is the Jellyfin server identity, never its display name.
  Duplicate names remain separate. Detail queries use `GenreIds`, authenticated
  account identity, and the selected music-library `ParentId`.
- Jellyfin 10.10.7 and 10.11.11 return no genres when `IncludeItemTypes` is sent
  to `/Genres`; the compatible list request is music-scoped by its selected
  music-library parent. Detail requests explicitly require `MusicAlbum` and
  `Audio`, excluding video and other media.
- Track occurrences keep independent identity and deterministic display order.
  AppModel converts occurrences to queue entries and delegates selected-track,
  Play All, and Shuffle actions to the authoritative `PlaybackController`.
- Generation-guarded feature state rejects stale responses across refresh,
  navigation, genre changes, and server/account/library scope changes. Valid
  snapshots survive retryable refresh and pagination failures.
- Loading, empty, no-playable-audio, missing-artwork, retry, refresh,
  cancellation, pagination, and malformed/partial-response paths have explicit
  behavior. No genre writes, caching, favourites, downloads, or offline sync
  were added.
- Diagnostics retain only fixed operation/status metadata for `genres`,
  `genre_albums`, and `genre_tracks`; tests reject genre, item, account, library,
  endpoint, and credential values.

## Deterministic fixtures

`genres.json`, `genre-albums.json`, and `genre-tracks.json` cover duplicate
genre and album names with distinct identities, Unicode, missing artwork and
optional metadata, counts, empty results, compilations, multi-disc order,
duplicate track occurrences, unsupported/non-audio values, malformed sibling
records, and raw-row pagination offsets. UI launch fixtures additionally cover
loading, empty, retryable first-page error, pagination failure after valid
content, and empty versus non-playable detail.

## Executable evidence

The focused iPhone 17 Pro iOS 26.5 simulator command selected
`GenreGatewayTests`, `GenreFeatureStateTests`,
`GenrePlaybackIntegrationTests`, and `GenreDiagnosticsPrivacyTests`. Its
xcresult reports 20 passed, zero failed, and zero skipped.

The required repository sequence completed successfully:

```sh
./scripts/bootstrap.sh
./scripts/test.sh
./scripts/test-integration.sh
./scripts/test-ui.sh
./scripts/build-release.sh
git diff --check
```

- Bootstrap regenerated the project with pinned XcodeGen 2.46.0.
- `./scripts/test.sh` passed 110 tests with zero failures.
- `./scripts/test-integration.sh` passed 14 fixture-policy tests, repeated the
  14 proof-policy tests, passed 4 production-gateway support tests, and passed
  the digest-pinned Jellyfin 10.11.11 and 10.10.7 lanes. Both live results
  report `genreBrowsing: complete`, AAC in an MP4-family container, and the
  ordered start/progress/pause/resume/seek/stop lifecycle.
- `./scripts/test-ui.sh` passed 20 tests with zero failures on an iPhone 17 Pro
  iOS 26.5 simulator. The eight genre cases cover portrait/landscape,
  light/dark appearance, accessibility XXXL Dynamic Type, Reduce Motion,
  loading, empty and non-playable detail, retryable error, pagination failure,
  missing artwork, Play All, Shuffle, occurrence rows, hittability, labels,
  headings, hints, and privacy-safe presentation.
- A focused iPad Pro 11-inch (M5) iOS 26.5 simulator run passed the genre layout
  case in portrait and landscape: 1 passed, zero failed, zero skipped.
- `./scripts/build-release.sh` completed with `BUILD SUCCEEDED`, and
  `git diff --check` passed.

Keyboard shortcuts are present for Play All and Shuffle, and the views use
standard focusable links/buttons for pointer navigation. The current XCTest
harness does not directly inject keyboard or pointer events, so those input
events are not claimed as runtime automation evidence.

## Device and remaining gates

No physical-device run was required: this slice changes read-only metadata,
navigation, deterministic queue construction, and presentation, all of which
are representative in the simulator. It does not change the audio engine,
background execution, Bluetooth, AirPlay, CarPlay, or system Now Playing.

The externally blocked audible Phase 2 real-device gate remains open and is not
waived. The full Phase 3 destination and screenshot/accessibility matrices also
remain open.
