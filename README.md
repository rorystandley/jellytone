# Jellytone for iOS

A premium personal, music-only Jellyfin client for iPhone and iPad. The app currently
supports manual server sign-in, music-library browsing, cached Home content,
search, albums, tracks, playlists, genres, favourites, a durable editable queue,
background playback, system Now Playing, and playback restoration.

Version 1.0 is intentionally a polished connected player for one user-operated
server. “Spotify-level” means the quality of its visual system and interaction,
not Spotify's breadth of features. Offline downloads, multiple saved servers,
CarPlay, widgets, Siri, lyrics, and crossfade are deferred.

## Work and product status

- `PRODUCT_PLAN.md` defines the release contract.
- `docs/NEXT_WORK.md` is the live ordered queue.
- `docs/ARCHITECTURE.md` defines implementation boundaries.
- `docs/decisions/` records durable technical decisions.
- `docs/evidence/README.md` points to retained executable evidence.

Use `./scripts/next-work.sh` to select work without loading the full repository.

## Build and test

```sh
./scripts/bootstrap.sh
./scripts/test.sh
./scripts/test-integration.sh
./scripts/test-ui.sh
./scripts/build-release.sh
```

### Xcode / physical iPhone

The generated project resolves `PRODUCT_BUNDLE_IDENTIFIER` from `APP_BUNDLE_ID`
(defined in `Config/Debug.xcconfig` / `Config/Release.xcconfig`). For device
signing, copy the personal override and set your Team ID:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
# edit APP_TEAM_ID and optionally APP_BUNDLE_ID, then:
./scripts/bootstrap.sh
```

Open `Jellytone.xcodeproj`, select the **Jellytone** target → **Signing &
Capabilities**, confirm Team and Bundle Identifier are filled, then run on your
iPhone.

For a paired device from the CLI (auto-picks a local wildcard profile):

```sh
./scripts/deploy-app.sh --launch
./scripts/test-device.sh
```

Enter the complete Jellyfin base URL, including any reverse-proxy path, then
sign in. Tokens are stored in Keychain; passwords are used only for sign-in.
