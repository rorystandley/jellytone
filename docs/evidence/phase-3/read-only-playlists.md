# Phase 3 read-only playlist evidence

Status: Bounded destination slice complete; Phase 3 is not complete

Last updated: 2026-07-17

## Implemented boundary

- The Library destination opens an adaptive, paginated playlist collection and
  paginated playlist detail.
- Stable playlist identity is separate from stable playlist-entry occurrence
  identity. Repeated tracks retain distinct occurrence IDs and server order.
- Play, Play All, Shuffle, and selected-occurrence actions create `QueueEntry`
  values and delegate to the existing authoritative `PlaybackController`.
- Empty playlists, playlists containing no playable audio rows, missing
  artwork, and absent optional metadata have explicit fallbacks.
- Requests are cancellable and generation guarded across refresh, retry,
  playlist selection, and server/account/library scope changes. Older responses
  cannot replace newer state.
- The diagnostic operation allowlist includes only fixed `playlists` and
  `playlist_entries` names. Tests prove URLs, user/item identifiers, tokens, and
  response metadata are not retained.
- This slice adds no playlist mutation, cache, download, offline sync, or
  playback-engine redesign.

## Executable evidence

The focused simulator unit command was:

```sh
xcodebuild -quiet -project JellyfinAudio.xcodeproj -scheme JellyfinAudio \
  -destination 'platform=iOS Simulator,id=B094F329-320D-4DA2-8353-DD8B1E5633F9' \
  -derivedDataPath /tmp/jellyfin-playlist-focused-unit \
  APP_TEAM_ID=LOCALONLY00 APP_BUNDLE_ID=org.example.jellyfinaudio.tests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:JellyfinAudioTests/PlaylistGatewayTests \
  -only-testing:JellyfinAudioTests/PlaylistFeatureStateTests \
  -only-testing:JellyfinAudioTests/PlaylistPlaybackIntegrationTests \
  -only-testing:JellyfinAudioTests/DiagnosticsPrivacyTests test
```

Its xcresult reports 22 passed, zero failed, and zero skipped. These tests cover
list/detail pagination, raw-row cursor advancement, stable identity and fallback
occurrence identity, malformed/non-audio rows, cancellation, transport retry,
authentication expiry, rapid refresh, stale-response suppression, scope
isolation, duplicate ordering, authoritative-queue start positions, and
privacy-safe diagnostics.

The complete command sequence was:

```sh
./scripts/bootstrap.sh
./scripts/test.sh
./scripts/test-integration.sh
./scripts/test-ui.sh
./scripts/build-release.sh
git diff --check
```

Bootstrap regenerated `JellyfinAudio.xcodeproj` through pinned XcodeGen 2.46.0.
`./scripts/test.sh` passed 90 tests with zero failures.
`./scripts/test-integration.sh` passed its 14 fixture-policy tests, repeated the
14 proof-policy tests, passed 3 live playback-support tests, and passed both
digest-pinned disposable Jellyfin server lanes: 10.11.11 and 10.10.7. The live
lanes prove the shared authenticated gateway/playback infrastructure and AAC in
MP4 lifecycle; playlist endpoint semantics are covered by deterministic
`URLProtocol` gateway contract tests rather than claimed as live-server proof.
`./scripts/build-release.sh` completed with `BUILD SUCCEEDED`.

`./scripts/test-ui.sh` passed 12 tests with zero failures on an iPhone 17 Pro
iOS 26.5 simulator. Seven playlist UI tests cover navigation, loading/error and
retry, empty and non-playable playlists, missing artwork, Play All, Shuffle,
selected-occurrence playback, privacy-safe presentation, and compact portrait
and landscape layouts. A focused regular-width run passed 2 tests with zero
failures on an iPad Pro 13-inch (M5) iOS 26.5 simulator. Default and dark
appearance, accessibility XXXL Dynamic Type, accessibility labels/values,
hittable controls, and minimum control sizing are asserted.

The exact regular-width command was:

```sh
xcodebuild -quiet -project JellyfinAudio.xcodeproj -scheme JellyfinAudioUI \
  -destination 'platform=iOS Simulator,id=4AD609AC-FB33-44A4-ABD9-935E34377D3F' \
  -derivedDataPath /tmp/jellyfin-playlist-focused-ipad \
  APP_TEAM_ID=LOCALONLY00 APP_BUNDLE_ID=org.example.jellyfinaudio.uitests \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:JellyfinAudioUITests/PlaylistUITests/testPlaylistFixtureSupportsBrowsingAndPlaybackActions \
  -only-testing:JellyfinAudioUITests/PlaylistUITests/testPlaylistLayoutSupportsDarkAppearanceAndLargeDynamicType test
```

Its xcresult reports 2 passed, zero failed, and zero skipped. The first full UI
rerun exposed one pre-existing queue test's implicit orientation assumption
(11 passed, 1 failed). Setting that test's device orientation explicitly to
portrait made its focused regression pass 1 of 1; the repeated full UI command
then passed 12 of 12. `git diff --check` passed as the final whitespace gate.

## Device and remaining gates

No new physical-device run is required for this read-only metadata,
navigation, and queue-construction slice: its behavior is representable in the
simulator and it does not change the audio engine, background lifecycle,
Bluetooth, AirPlay, or CarPlay. The existing Phase 2 audible real-device gate
remains blocked and is not waived. The full Phase 3 destination and
screenshot/accessibility matrices also remain open.
