# Contributing

Issues and pull requests are welcome.

## Setup

You need a Mac with Xcode 26.6 and the iOS 18.4 SDK or newer.

```sh
./scripts/bootstrap.sh
```

Device installs need `Config/Local.xcconfig`. Copy `Config/Local.xcconfig.example` and set `APP_TEAM_ID`. Do not commit that file.

## Checks

Run the gates that cover your change before you open a pull request.

```sh
./scripts/test.sh
./scripts/test-ui.sh
./scripts/build-release.sh
```

If you change networking, downloads, or playback against a real server, also run:

```sh
./scripts/test-integration.sh
```

Python contract tests live under `Tests/Phase0*` and run as part of `tools/phase0/validate.sh`.

## Code

- Swift 6 and SwiftUI.
- `PlaybackController` owns the queue and the player. Do not add a second player.
- Keep Jellyfin wire types inside `JellyfinGateway`.
- UI colours, type, spacing, and corner radii come from `DesignSystem/Theme.swift` (`Color.jt*`, `Font.jt*`, `JellytoneTheme`).
- Haptics go through `JellytoneHaptics`.

## What not to commit

- Passwords, access tokens, API keys, or provisioning profiles.
- Server hostnames, Tailscale names, or LAN addresses from your own setup.
- Device names, UDIDs, or signing identities.
- `Config/Local.xcconfig`.

Use placeholders such as `https://jellyfin.example.com` in docs and tests.

## Reports

Use GitHub issues for bugs and feature requests. For security reports, follow [SECURITY.md](SECURITY.md).
