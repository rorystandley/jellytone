#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
MANIFEST="$ROOT/tools/fixtures/library-manifest.json"
OUTPUT=${1:-"$ROOT/infra/jellyfin/.state/media"}

for command in ffmpeg jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "required command not found: $command" >&2
    exit 2
  }
done

TEMP_ROOT=${TMPDIR:-/tmp}
TEMP_ROOT=${TEMP_ROOT%/}
case "$OUTPUT" in
  "$ROOT/infra/jellyfin/.state/media"|"$TEMP_ROOT"/phase0-library.*|"$TEMP_ROOT"//phase0-library.*|/tmp/phase0-library.*) ;;
  *)
    echo "refusing to replace output outside the repository fixture state or /tmp: $OUTPUT" >&2
    exit 2
    ;;
esac

mkdir -p "$OUTPUT"
find "$OUTPUT" -mindepth 1 -delete

jq -c '.tracks[]' "$MANIFEST" | while IFS= read -r track; do
  relative_path=$(printf '%s' "$track" | jq -r '.path')
  codec=$(printf '%s' "$track" | jq -r '.codec')
  frequency=$(printf '%s' "$track" | jq -r '.frequency')
  title=$(printf '%s' "$track" | jq -r '.title')
  album=$(printf '%s' "$track" | jq -r '.album')
  artist=$(printf '%s' "$track" | jq -r '.artist')
  album_artist=$(printf '%s' "$track" | jq -r '.albumArtist')
  disc=$(printf '%s' "$track" | jq -r '.disc')
  track_number=$(printf '%s' "$track" | jq -r '.track')
  destination="$OUTPUT/$relative_path"
  mkdir -p "$(dirname "$destination")"

  codec_arguments="-c:a $codec"
  case "$codec" in
    mp3) codec_arguments="-c:a libmp3lame -b:a 128k" ;;
    aac) codec_arguments="-c:a aac -b:a 128k" ;;
    alac) codec_arguments="-c:a alac" ;;
    flac) codec_arguments="-c:a flac -compression_level 5" ;;
    vorbis) codec_arguments="-strict -2 -c:a vorbis -q:a 4" ;;
    opus) codec_arguments="-c:a libopus -b:a 96k" ;;
  esac

  # shellcheck disable=SC2086
  # Codec arguments intentionally form an argv list.
  ffmpeg -nostdin -y -hide_banner -loglevel error \
    -f lavfi -i "sine=frequency=$frequency:sample_rate=48000:duration=1" \
    -map_metadata -1 -fflags +bitexact -flags:a +bitexact -ac 2 $codec_arguments \
    -metadata "title=$title" \
    -metadata "album=$album" \
    -metadata "artist=$artist" \
    -metadata "album_artist=$album_artist" \
    -metadata "disc=$disc" \
    -metadata "track=$track_number" \
    "$destination"
done

"$ROOT/tools/fixtures/verify-library.sh" "$OUTPUT"
