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

## Automated evidence

`./scripts/test.sh` passes 15 tests. Added coverage proves deterministic shuffle
membership/current-track behavior, the repeat-state cycle, and backward
compatibility for the prior playback snapshot schema.

## Device state

The signed build installed and launched on the paired iPhone. The live server
session remains restored. Visual inspection of all new surfaces, locked-screen
playback duration, Lock Screen commands, and a non-zero terminate/relaunch
restoration remain open device evidence.

## Deliberately not claimed

- Server-backed search across unloaded pages.
- Artist, playlist, genre, favourites, downloads, or multi-profile screens.
- Drag reordering or removal of queue entries.
- Completion of Phase 2 or Phase 3.
