# Clean-checkout Phase 0 validation

Evidence date: 2026-07-16

Commit: `d88355ee360b701063da2733657753d34a744836`

The complete Phase 0 gate passed from a fresh local clone with no generated
project, XcodeGen cache, Jellyfin container state, or device-proof artifacts
copied from the working checkout.

Reproduction from the repository root:

```sh
clean_checkout=$(mktemp -d /tmp/jellyfin-ios-audio-phase0-clean.XXXXXX)
git clone --quiet --no-hardlinks . "$clean_checkout"
"$clean_checkout/tools/phase0/validate.sh" all
```

Observed result:

- 17 evidence-validator tests passed.
- 14 connectivity policy and contract tests passed.
- 6 playback proof tests passed.
- Deterministic XcodeGen generation and simulator build passed.
- 10 isolated DeviceProof XCTest cases and 5 summary-contract tests passed.
- Both digest-pinned Jellyfin versions completed authenticated live contracts,
  the six-codec original/transcode matrix, and playback reporting.
- 6 host-network tests and disposable-server restart recovery passed.
- All 12 committed JSON evidence records passed strict validation.
- Total wall time was 85.88 seconds.

Limitations:

- A local clone proves repository/bootstrap reproducibility on this Mac; it is
  not hosted CI evidence and no Git remote is configured.
- Simulator, host, and container success does not replace the open physical
  device, live Tailscale, route/accessory, or CarPlay entitlement gates.
