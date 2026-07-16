#!/bin/sh
set -eu

tag=2.1.0
expected_commit=09d8f31886b6bea1cfc4719a39bdb6eac1287344
worktree="$(mktemp -d "${TMPDIR:-/tmp}/jellyfin-sdk-swift.XXXXXX")"
trap 'rm -rf "$worktree"' EXIT HUP INT TERM

git clone --quiet --depth 1 --branch "$tag" https://github.com/jellyfin/jellyfin-sdk-swift.git "$worktree"
actual_commit="$(git -C "$worktree" rev-parse HEAD)"
test "$actual_commit" = "$expected_commit"
swift test --package-path "$worktree"
printf 'PASS jellyfin-sdk-swift tag=%s commit=%s\n' "$tag" "$actual_commit"
