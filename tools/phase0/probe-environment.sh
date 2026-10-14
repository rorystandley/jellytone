#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
OUTPUT=${1:-"$ROOT/docs/evidence/phase-0/platform/environment.json"}
mkdir -p "$(dirname "$OUTPUT")"

temporary_devices=$(mktemp "${TMPDIR:-/tmp}/phase0-devices.XXXXXX.json")
trap 'find "$temporary_devices" -delete' EXIT

captured_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
host_os=$(sw_vers -productVersion 2>/dev/null || printf 'unavailable')
xcode=$(xcodebuild -version 2>/dev/null | paste -sd ' ' - || printf 'unavailable')
swift=$(xcrun swift --version 2>/dev/null | head -1 || printf 'unavailable')

if simulator_json=$(xcrun simctl list devices available -j 2>/dev/null); then
  simulator_status=pass
  simulator_limitations='[]'
  simulator_facts=$(printf '%s' "$simulator_json" | jq '{
    availableCount: ([.devices[][]] | length),
    runtimes: (.devices | to_entries | map({runtime: .key, count: (.value | length)}))
  }')
else
  simulator_status=blocked
  simulator_facts='{}'
  simulator_limitations='["No available iOS simulator runtime was discovered; simulator automation is blocked on this host."]'
fi

if xcrun devicectl list devices --json-output "$temporary_devices" >/dev/null 2>&1; then
  device_facts=$(jq '{
    attachedCount: ([.result.devices[] | select(.hardwareProperties.reality == "physical")] | length),
    devices: [.result.devices[] | select(.hardwareProperties.reality == "physical") | {
      model: .hardwareProperties.marketingName,
      platform: .hardwareProperties.platform,
      osVersion: .deviceProperties.osVersionNumber,
      developerMode: .deviceProperties.developerModeStatus,
      pairingState: .connectionProperties.pairingState
    }]
  }' "$temporary_devices")
  attached_count=$(printf '%s' "$device_facts" | jq '.attachedCount')
  if [ "$attached_count" -gt 0 ]; then
    device_status=pass
    device_limitations='["Discovery does not prove install, launch, background execution, routes, or endurance."]'
  else
    device_status=blocked
    device_limitations='["No attached physical iOS device was discovered; device-only gates remain blocked."]'
  fi
else
  device_status=blocked
  device_facts='{"attachedCount":0,"devices":[]}'
  device_limitations='["CoreDevice discovery did not complete; device-only gates remain blocked."]'
fi

identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
development_count=$(printf '%s\n' "$identities" | grep -c 'Apple Development:' || true)
distribution_count=$(printf '%s\n' "$identities" | grep -c 'Apple Distribution:' || true)
developer_id_count=$(printf '%s\n' "$identities" | grep -c 'Developer ID Application:' || true)
if [ "$development_count" -gt 0 ]; then
  signing_status=pass
  signing_limitations='["Identity presence does not prove an App ID, provisioning profile, or managed entitlement."]'
else
  signing_status=blocked
  signing_limitations='["No Apple Development signing identity was discovered; signed device automation is blocked on this host."]'
fi
signing_facts=$(jq -n \
  --argjson development "$development_count" \
  --argjson distribution "$distribution_count" \
  --argjson developerId "$developer_id_count" \
  '{developmentIdentityCount:$development, distributionIdentityCount:$distribution, developerIdIdentityCount:$developerId}')

if docker_server=$(docker version --format '{{json .Server}}' 2>/dev/null); then
  docker_status=pass
  docker_facts=$(printf '%s' "$docker_server" | jq '{engineVersion:.Version, os:.Os, architecture:.Arch}')
  docker_limitations='[]'
else
  docker_status=blocked
  docker_facts='{}'
  docker_limitations='["No reachable Docker daemon was discovered; disposable-server automation is blocked on this host."]'
fi

jq -n \
  --arg capturedAt "$captured_at" \
  --arg hostOS "$host_os" \
  --arg xcode "$xcode" \
  --arg swift "$swift" \
  --arg simulatorStatus "$simulator_status" \
  --argjson simulatorFacts "$simulator_facts" \
  --argjson simulatorLimitations "$simulator_limitations" \
  --arg deviceStatus "$device_status" \
  --argjson deviceFacts "$device_facts" \
  --argjson deviceLimitations "$device_limitations" \
  --arg signingStatus "$signing_status" \
  --argjson signingFacts "$signing_facts" \
  --argjson signingLimitations "$signing_limitations" \
  --arg dockerStatus "$docker_status" \
  --argjson dockerFacts "$docker_facts" \
  --argjson dockerLimitations "$docker_limitations" \
  '{
    schemaVersion:1,
    proofId:"phase0-platform-environment",
    capturedAt:$capturedAt,
    command:"tools/phase0/probe-environment.sh docs/evidence/phase-0/platform/environment.json",
    environment:{hostOS:$hostOS,xcode:$xcode,swift:$swift},
    owner:{phase:"Phase 0",workstream:"platform"},
    status:([ $simulatorStatus,$deviceStatus,$signingStatus,$dockerStatus ] as $statuses |
      if ($statuses | index("fail")) then "fail"
      elif ($statuses | index("blocked")) then "blocked"
      elif ($statuses | index("not-run")) then "not-run"
      else "pass" end),
    limitations:["Environment discovery proves tool and dependency presence only; it does not prove runtime capabilities."],
    checks:[
      {id:"simulator-discovery",status:$simulatorStatus,facts:$simulatorFacts,limitations:$simulatorLimitations},
      {id:"attached-device-discovery",status:$deviceStatus,facts:$deviceFacts,limitations:$deviceLimitations},
      {id:"code-signing-identities",status:$signingStatus,facts:$signingFacts,limitations:$signingLimitations},
      {id:"container-runtime",status:$dockerStatus,facts:$dockerFacts,limitations:$dockerLimitations}
    ],
    privacy:{
      redacted:true,
      committedEvidenceContainsSecrets:false,
      privateServerDataPersisted:false,
      omitted:["device names","device identifiers","serial numbers","certificate subjects","certificate hashes","server addresses other than loopback"]
    }
  }' > "$OUTPUT"

echo "wrote redacted environment evidence to $OUTPUT"
