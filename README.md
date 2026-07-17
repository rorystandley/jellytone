# Jellyfin iOS Music Player

This repository is building a native iPhone and iPad music-only client for
personal Jellyfin servers. The current priority is a Minimum Working App that
connects, authenticates, browses music, and plays a track. Earlier Phase 0 proof
work remains as evidence and risk documentation, but exhaustive hardware gates
no longer block the first usable vertical slice.

To select the next implementation slice without re-reading the entire roadmap:

```sh
./scripts/next-work.sh
```

The command combines the live [work queue](docs/NEXT_WORK.md) with branch,
worktree, and stale-routing checks. A dirty worktree is in-flight work and takes
priority over selecting another slice.

Reference authorities:

1. [AGENTS.md](AGENTS.md) defines the context-efficient selection and
   implementation workflow.
2. [PRODUCT_PLAN.md](PRODUCT_PLAN.md) defines the product, version 1.0 scope,
   quality targets, roadmap phases, and machine-verifiable exit gates.
3. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) defines state ownership, module
   boundaries, data flows, and the decisions that Phase 0 must prove.

Implementation is active on the connected-playback vertical slice defined by
the current delivery override in the product plan. Security and privacy
decisions remain mandatory; deferred device and ecosystem proofs are not
silently treated as passing.

Current execution status and reproducible proof entry points are tracked in
[docs/EXECUTION_CHECKLIST.md](docs/EXECUTION_CHECKLIST.md) and
[docs/evidence/phase-0/README.md](docs/evidence/phase-0/README.md).

## Run the app

Generate the Xcode project and run the local unit/simulator gate:

```sh
./scripts/bootstrap.sh
./scripts/test.sh
```

Open `JellyfinAudio.xcodeproj` to run in Xcode, or connect an unlocked, paired
iPhone and install a signed development build directly:

```sh
./scripts/deploy-app.sh --launch
```

Enter the full base URL of a Jellyfin server, including any reverse-proxy path,
then sign in. The current slice lists music libraries and albums, opens album
tracks, and streams a selected track with play/pause and Now Playing info.
