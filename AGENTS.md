# Jellytone — Agent Instructions & Design Brief

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
Premium connected music player with **Apple Music–level** visual and interaction quality
(Spotify-level where it helps). Not feature parity with every Jellyfin client — quality of the primary surfaces first.

## Target Information Architecture (Apple Music model)
- Tab Bar:
  - Home (Listen Now style)
  - Browse or Library (hierarchical)
  - Search
  - (Downloads can stay as tab or move under Library — decide for consistency)
- Persistent MiniPlayer above the tab bar when playing (iOS 26 tabViewBottomAccessory preferred)
- Full-screen Now Playing that feels continuous with the MiniPlayer (expand/collapse, shared materials), not a disconnected sheet
- Hierarchical push for Album / Artist / Playlist / Genre detail
- Library categories: Playlists, Artists, Albums, Songs, Genres, Favourites, Downloads

## Priority Order (do not skip ahead without reason)
1. Unify design system — migrate Now Playing, MiniPlayer, Queue, Search, Track catalog, Connection fully onto JellytoneTheme (kill dual AudioDesign look)
2. Now Playing as primary surface — continuous expand from MiniPlayer, richer queue, silent prep (no “Preparing…” spinners)
3. Search to Apple Music level — Top Results, Songs, Albums, Artists, Playlists; rich rows; useful idle state
4. Library IA pass — dedicated Albums, denser lists/grids, consistent state chrome
5. Loading consistency — skeletons everywhere primary content appears; cache-first; no layout jumps
6. Connection / first-run polish
7. Optional later: widgets, Live Activities, CarPlay (per ADR 0011)

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