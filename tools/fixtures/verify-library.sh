#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
MANIFEST="$ROOT/tools/fixtures/library-manifest.json"
LIBRARY=${1:-"$ROOT/infra/jellyfin/.state/media"}

for command in ffprobe jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "required command not found: $command" >&2
    exit 2
  }
done

expected_count=$(jq '.tracks | length' "$MANIFEST")
actual_count=$(find "$LIBRARY" -type f | wc -l | tr -d ' ')
test "$actual_count" = "$expected_count" || {
  echo "fixture count mismatch: expected $expected_count, found $actual_count" >&2
  exit 1
}

jq -c '.tracks[]' "$MANIFEST" | while IFS= read -r track; do
  path=$(printf '%s' "$track" | jq -r '.path')
  expected_codec=$(printf '%s' "$track" | jq -r '.codec')
  file="$LIBRARY/$path"
  test -f "$file" || { echo "missing fixture: $path" >&2; exit 1; }
  actual_codec=$(ffprobe -v error -select_streams a:0 \
    -show_entries stream=codec_name -of default=nw=1:nk=1 "$file")
  test "$actual_codec" = "$expected_codec" || {
    echo "codec mismatch for $path: expected $expected_codec, found $actual_codec" >&2
    exit 1
  }
done

echo "verified $actual_count deterministic synthetic tracks"
