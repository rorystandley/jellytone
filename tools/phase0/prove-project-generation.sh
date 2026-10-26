#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
FIXTURE="$ROOT/tools/phase0/project-generation"
XCODEGEN=${XCODEGEN_BIN:-xcodegen}

command -v "$XCODEGEN" >/dev/null 2>&1 || {
  echo "XcodeGen executable not found: $XCODEGEN" >&2
  exit 2
}

version=$($XCODEGEN --version | awk '{print $NF}')
test "$version" = "2.46.0" || {
  echo "XcodeGen 2.46.0 required, found $version" >&2
  exit 2
}

one=$(mktemp -d "${TMPDIR:-/tmp}/phase0-project-one.XXXXXX")
two=$(mktemp -d "${TMPDIR:-/tmp}/phase0-project-two.XXXXXX")
trap 'find "$one" "$two" -mindepth 1 -delete; rmdir "$one" "$two"' EXIT

cp -R "$FIXTURE/." "$one/"
cp -R "$FIXTURE/." "$two/"
(cd "$one" && "$XCODEGEN" generate --spec project.yml --project . >/dev/null)
(cd "$two" && "$XCODEGEN" generate --spec project.yml --project . >/dev/null)

normalize_and_hash() {
  directory=$1
  find "$directory/Phase0GenerationProbe.xcodeproj" -type f -print | sort | while IFS= read -r file; do
    sed "s|$directory|<ROOT>|g" "$file"
  done | shasum -a 256 | awk '{print $1}'
}

first_hash=$(normalize_and_hash "$one")
second_hash=$(normalize_and_hash "$two")
test "$first_hash" = "$second_hash" || {
  echo "XcodeGen output differs across identical clean directories" >&2
  exit 1
}

xcodebuild -quiet \
  -project "$one/Phase0GenerationProbe.xcodeproj" \
  -scheme Phase0GenerationProbe \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$one/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "XcodeGen $version deterministic generation and simulator build passed: $first_hash"
