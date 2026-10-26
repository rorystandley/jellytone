# Jellytone agent instructions

## Project
Native iOS music client for a single Jellyfin server.
XcodeGen project: Jellytone (project.yml authoritative).
Swift 6, SwiftUI-first, iOS 18.4+, iPhone + iPad.
Product SPM: GRDB only. No other third-party runtime deps in the app target.
Hand-rolled JellyfinAPI (URLSession). No official Jellyfin SDK in product build.

Targets: Jellytone (app), JellytoneTests, JellytoneUITests.
No widgets / CarPlay / App Intents shipping yet (ADR 0011 design only).

## Architecture (do not break)
SwiftUI Features → AppModel → Domain → JellyfinGateway → LibraryStore (GRDB)
PlaybackController is the **sole** queue/player owner.
Cache-first browse. Fail-closed TLS. No wire types outside the gateway.
Downloads verified via manifest; playback prefers local URL when verified.

## Goal
Aim at the care of Apple Music, and of Spotify where that is the better pattern. Do the main screens well before chasing every Jellyfin feature.

## Target Information Architecture (Apple Music model)
- Tab Bar:
  - Home (Listen Now style)
  - Browse or Library (hierarchical)
  - Search
  - Downloads can stay a tab or move under Library. Pick one and use it everywhere.
- Persistent MiniPlayer above the tab bar when playing (iOS 26 tabViewBottomAccessory preferred)
- Full-screen Now Playing that feels continuous with the MiniPlayer (expand/collapse, shared materials), not a disconnected sheet
- Hierarchical push for Album / Artist / Playlist / Genre detail
- Library categories: Playlists, Artists, Albums, Songs, Genres, Favourites, Downloads

## Priority Order (do not skip ahead without reason)
1. The design system is unified. The sole system is JellytoneTheme / `jt*` (`Theme.swift` + `Haptics.swift`). Do not reintroduce a parallel design layer.
2. Now Playing opens by expanding continuously from the MiniPlayer, with a queue you can edit, and silent prep (no “Preparing…” spinners).
3. Search lists Top Results, Songs, Albums, Artists, and Playlists, with detailed rows and a useful idle state.
4. Library IA: dedicated Albums, denser lists and grids, and consistent state chrome.
5. Loading consistency: skeletons everywhere primary content appears, cache-first, and no layout jumps.
6. Connection and first-run pass.
7. Optional later: widgets, Live Activities, CarPlay (per ADR 0011).

## UI & Loading Rules
- One design system only: JellytoneTheme / jt* tokens.
- Prefer skeletons / last-known content over ProgressView cards and full-screen spinners.
- Silent buffering in the player; never block the chrome with “Preparing playback” labels if avoidable.
- Match Apple Music density, spacing, materials, and typography as closely as practical.

## Coding Rules
- Keep PlaybackController as the only player/queue authority.
- Do not rewrite networking, GRDB, or download verification unless explicitly asked.
- Prefer SwiftUI + existing navigationDestination patterns.
- Respect @MainActor and generation guards.
- Update tests when changing view models / mappers / navigation.
- After structural UI changes, confirm build + existing playback / lock-screen path still work.

## When making changes
- Focused, reviewable diffs.
- Extract shared components early (rows, headers, skeletons).
- Reference this file in every major change.
