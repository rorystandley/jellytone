# Initial Environment Evidence

Observed: 2026-07-16 Europe/London

Privacy note: signing names, certificate fingerprints, device names, hostnames,
and device identifiers are intentionally omitted.

## Repository

- Absolute checkout: `/Users/rorystandley/Documents/jellyfin-ios-audio-player`
- Branch: `main`, with no commits yet.
- Remotes: none configured.
- Initial tracked state: planning documents are present as untracked user-owned
  files; no production application, generated project, scripts, tests, or CI
  configuration existed.

Reproduce:

```sh
pwd
git branch --show-current
git status --short --branch
git remote -v
find . -maxdepth 3 -type f -print | sort
```

## Apple toolchain

- Host: Apple silicon, macOS 26.5.2 (build 25F84).
- Xcode: 26.6 (build 17F113), selected from `/Applications/Xcode.app`.
- Swift: 6.3.3.
- Installed iOS SDK: 26.5.
- Available simulator runtimes: iOS 26.2 and 26.5, with iPhone and iPad models.
- Real devices: one paired and available iPhone 13.
- Code signing: three valid code-signing identities detected; identities were
  redacted before recording.

Reproduce without exposing identity details:

```sh
xcode-select -p
xcodebuild -version
swift --version
xcodebuild -showsdks
xcrun simctl list runtimes available
xcrun simctl list devices available
xcrun devicectl list devices
security find-identity -v -p codesigning | tail -1
```

## Supporting tools

- Present: Git 2.50.1, GitHub CLI 2.92.0, XcodeGen 2.44.1, Docker CLI
  29.5.3, jq 1.7.1, curl 8.7.1, FFmpeg/ffprobe 8.1.2, Python 3.9.6,
  Ruby 2.6.10, and Bundler 1.17.2.
- Missing: mise, Mint, SwiftLint, SwiftFormat, Podman, Colima, and yq.
- Docker daemon: unavailable during the initial probe. Phase 0 automation later
  started Docker Desktop 29.5.3 without stopping unrelated containers, then ran
  the digest-pinned Jellyfin 10.11.11 and 10.10.7 disposable servers successfully.
  Current container evidence is recorded under `automation/` and `connectivity/`.

## External statuses

- CarPlay audio entitlement: not proven. Owner: Phase 0 automation/platform.
  Fallback: simulator and adapter contracts are supplemental only; Phase 6
  real-hardware acceptance remains blocked until entitlement and hardware are
  available.
- App Store Connect/TestFlight authority: not inspected because Phase 0 does not
  require an external release mutation and the user did not authorize one.
- Real-device capability: a compatible paired iPhone exists, but background,
  route, Bluetooth, AirPlay, download, and endurance procedures have not yet
  run. Presence is not acceptance evidence.
