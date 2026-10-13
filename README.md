# Jellytone

Jellytone is a native iOS music player for a single Jellyfin server. It runs on iPhone and iPad, on iOS 18.4 or later.

You sign in to a server you run, browse the music library, and play tracks. The app keeps one queue, uses the system Now Playing surface, and can keep a verified local copy of tracks you download.

## Features

- Sign in with a server URL, username, and password. The access token stays in the Keychain.
- Home, Library, and Search, with albums, artists, songs, playlists, genres, favourites, and downloads.
- Playback with pause, seek, skip, shuffle, repeat, and a queue you can edit.
- Lock Screen and Control Centre controls, and playback that continues in the background.
- Line-level lyrics when the server has them.
- Downloads checked against a manifest. Playback uses the local file when that check passes.
- A cache of library data so screens can open before the network responds.

Jellytone is a music client. It does not play video, and it does not manage the Jellyfin server.

## Requirements

- A Jellyfin server. The automated contracts cover 10.11.11 and 10.10.7.
- For development: a Mac with Xcode 26.6, and the iOS 18.4 SDK or newer.

## Install

There is no App Store build yet. Build it from source and install it with Xcode.

```sh
git clone https://github.com/rorystandley/jellytone.git
cd jellytone
./scripts/bootstrap.sh
open Jellytone.xcodeproj
```

`bootstrap.sh` downloads pinned XcodeGen 2.46.0 and generates the Xcode project.

To run on a device, set your Apple team:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Edit `APP_TEAM_ID`. Change `APP_BUNDLE_ID` if you want a bundle id other than `org.example.jellytone`. `Config/Local.xcconfig` is gitignored.

Then open the project, select the Jellytone target, and run it on your iPhone or iPad.

From the command line, with a paired device:

```sh
./scripts/deploy-app.sh --launch
```

## Usage

1. Enter the full Jellyfin base URL, including the port and any reverse-proxy path. Example: `https://jellyfin.example.com` or `https://jellyfin.example.com:8920/jellyfin`.
2. Sign in with the username and password for that server.
3. Browse or search, then play a track.

Sign out from the app when you want to connect to a different server. Only one server is stored at a time.

Plain HTTP is allowed only when you confirm it. Prefer HTTPS. The app does not disable TLS validation.

## Configuration

The app has no config file for the server address. You enter that on the sign-in screen.

Signing for a device install uses `Config/Local.xcconfig`:

| Setting | Purpose |
| --- | --- |
| `APP_TEAM_ID` | Your Apple Development Team ID |
| `APP_BUNDLE_ID` | Bundle identifier. Default in the example file is `org.example.jellytone` |

Debug and Release builds without that file use `org.example.jellytone.local` from `Config/Debug.xcconfig` and `Config/Release.xcconfig`.

The disposable Jellyfin versions used by integration tests are pinned in `infra/jellyfin/versions.env`. Those are public image pins, not credentials.

## Development

```sh
./scripts/bootstrap.sh
./scripts/test.sh
./scripts/test-ui.sh
./scripts/test-integration.sh
./scripts/build-release.sh
```

`test.sh` and `test-ui.sh` need Xcode and an iOS Simulator. `test-integration.sh` runs against disposable Jellyfin containers and needs Docker. `build-release.sh` produces an unsigned simulator Release build.

The product target depends on GRDB.swift 7.11.1 and Apple frameworks. Jellyfin HTTP is implemented in this repo. XcodeGen is a build tool only.

UI work uses the tokens in `DesignSystem/Theme.swift`. See `docs/design/design-system.md`.

Do not commit `Config/Local.xcconfig`, tokens, server addresses, or device logs.

## Licence

MIT. See [LICENSE](LICENSE).
