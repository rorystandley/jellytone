#!/bin/sh
set -eu

VERSION=2.46.0
SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
CACHE="$ROOT/tools/phase0/.cache/xcodegen-$VERSION"
ARCHIVE="$CACHE/xcodegen.zip"
BINARY="$CACHE/unpacked/xcodegen/bin/xcodegen"

if [ -x "$BINARY" ]; then
  "$BINARY" --version
  exit 0
fi

mkdir -p "$CACHE/unpacked"
curl --fail --location --silent --show-error \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip" \
  -o "$ARCHIVE"
actual=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
test "$actual" = "$SHA256" || {
  echo "XcodeGen archive checksum mismatch" >&2
  exit 1
}
ditto -x -k "$ARCHIVE" "$CACHE/unpacked"
test -x "$BINARY"
"$BINARY" --version
