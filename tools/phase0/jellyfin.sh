#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
INFRA="$ROOT/infra/jellyfin"
COMPOSE="$INFRA/compose.yml"
VERSIONS="$INFRA/versions.env"
STATE="$INFRA/.state"

command -v docker >/dev/null 2>&1 || {
  echo "Docker CLI is required" >&2
  exit 2
}

compose() {
  docker compose --env-file "$VERSIONS" -f "$COMPOSE" "$@"
}

wait_for_server() {
  name=$1
  url=$2
  attempts=0
  until response=$(curl --fail --silent --show-error --max-time 5 \
      "$url/System/Info/Public" 2>/dev/null); do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 90 ]; then
      echo "$name did not become ready at $url" >&2
      compose logs --tail 80 "$name" >&2 || true
      return 1
    fi
    sleep 2
  done
  printf '%s' "$response"
}

setup_server() {
  name=$1
  url=$2
  public_info=$(wait_for_server "$name" "$url")
  wizard_completed=$(printf '%s' "$public_info" | jq -r '.StartupWizardCompleted')
  if [ "$wizard_completed" = "true" ]; then
    return 0
  fi

  curl --fail --silent --show-error -X POST \
    -H 'Content-Type: application/json' \
    -d '{"UICulture":"en-US","MetadataCountryCode":"GB","PreferredMetadataLanguage":"en"}' \
    "$url/Startup/Configuration" >/dev/null
  password=$(uuidgen | tr '[:upper:]' '[:lower:]')
  username=$(curl --fail --silent --show-error "$url/Startup/User" | jq -er '.Name')
  credential_file="$STATE/$name/fixture-password"
  (umask 077 && printf '%s' "$password" > "$credential_file")

  curl --fail --silent --show-error -X POST \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg name "$username" --arg password "$password" '{Name:$name,Password:$password}')" \
    "$url/Startup/User" >/dev/null
  curl --fail --silent --show-error -X POST \
    -H 'Content-Type: application/json' \
    -d '{"EnableRemoteAccess":false,"EnableAutomaticPortMapping":false}' \
    "$url/Startup/RemoteAccess" >/dev/null
  curl --fail --silent --show-error -X POST "$url/Startup/Complete" >/dev/null

  auth=$(curl --fail --silent --show-error -X POST \
    -H 'Content-Type: application/json' \
    -H 'X-Emby-Authorization: MediaBrowser Client="Phase0Fixture", Device="Automation", DeviceId="phase0-fixture", Version="1"' \
    -d "$(jq -n --arg name "$username" --arg password "$password" '{Username:$name,Pw:$password}')" \
    "$url/Users/AuthenticateByName")
  token=$(printf '%s' "$auth" | jq -er '.AccessToken')

  # The token exists only in this process and is never printed or persisted.
  curl --fail --silent --show-error -X POST \
    -H "X-Emby-Token: $token" \
    --get --data-urlencode 'name=Synthetic Music' \
    --data-urlencode 'collectionType=music' \
    --data-urlencode 'paths=/media' \
    "$url/Library/VirtualFolders" >/dev/null
}

verify_server() {
  name=$1
  url=$2
  expected=$3
  info=$(wait_for_server "$name" "$url")
  actual=$(printf '%s' "$info" | jq -r '.Version')
  wizard=$(printf '%s' "$info" | jq -r '.StartupWizardCompleted')
  test "$actual" = "$expected" || {
    echo "$name version mismatch: expected $expected, found $actual" >&2
    return 1
  }
  test "$wizard" = "true" || {
    echo "$name startup wizard is incomplete" >&2
    return 1
  }
  echo "$name: Jellyfin $actual ready at $url"
}

# shellcheck disable=SC1090
# The version file is repository-controlled data.
. "$VERSIONS"

case "${1:-}" in
  reset)
    compose down --remove-orphans
    mkdir -p "$STATE"
    find "$STATE" -mindepth 1 -delete
    "$ROOT/tools/fixtures/generate-library.sh" "$STATE/media"
    mkdir -p "$STATE/current/config" "$STATE/current/cache" \
      "$STATE/previous/config" "$STATE/previous/cache"
    compose up -d
    setup_server current http://127.0.0.1:18096
    setup_server previous http://127.0.0.1:18097
    "$0" verify
    ;;
  up)
    if [ -d "$STATE/media" ]; then
      "$ROOT/tools/fixtures/verify-library.sh" "$STATE/media"
    else
      "$ROOT/tools/fixtures/generate-library.sh" "$STATE/media"
    fi
    mkdir -p "$STATE/current/config" "$STATE/current/cache" \
      "$STATE/previous/config" "$STATE/previous/cache"
    compose up -d
    setup_server current http://127.0.0.1:18096
    setup_server previous http://127.0.0.1:18097
    "$0" verify
    ;;
  verify)
    verify_server current http://127.0.0.1:18096 "$JELLYFIN_CURRENT_VERSION"
    verify_server previous http://127.0.0.1:18097 "$JELLYFIN_PREVIOUS_VERSION"
    ;;
  status)
    compose ps
    ;;
  down)
    compose down --remove-orphans
    ;;
  *)
    echo "usage: $0 {reset|up|verify|status|down}" >&2
    exit 2
    ;;
esac
