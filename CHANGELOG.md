# Changelog

## Unreleased

- Made `Item.ArtistItems` and `Item.AlbumArtists` private. They use the private nested `NameIdPair` type, which Swift rejects on an internal property.
- Device proof remote-command handlers touch the player on the main actor.
- Isolated `JellytoneHaptics` to the main actor so the feedback generators and test observer satisfy Swift 6 strict concurrency.
- Getting started now says to install XcodeGen 2.46.0 and run `xcodegen generate` before opening the project.
- Removed the committed `Jellytone.xcodeproj` directory. It only contained `Package.resolved`, so Xcode could not find `project.pbxproj`. The lockfile is `Config/Package.resolved`, and `scripts/bootstrap.sh` copies it into the generated project.

## 1.0.0 - 2026-10-13

First public release of Jellytone, a native iOS music client for one Jellyfin server.

- Sign in to a server, browse the library, search, and play music.
- Queue, shuffle, repeat, background playback, and system Now Playing.
- Lyrics when the server provides them.
- Verified downloads, with playback from the local file when the check passes.
- Cache-first browsing so saved library data can show before the network responds.
