# Isolated Phase 0 device proof

This directory records evidence from `Prototypes/DeviceProof`, a disposable,
non-production iOS harness. It uses only synthetic audio and a host-run LAN
fixture. Runtime device, signing, certificate, profile, and endpoint identifiers
are redacted and are never committed.

Run the complete agent-operated lane:

```sh
./tools/device-proof/run.sh
```

Individual noninteractive entry points are `generate.sh`, `test.sh`, `build.sh`,
`install.sh`, `launch.sh`, `collect.sh`, and `privacy-scan.sh`. The complete run
starts an ephemeral HTTP server on the active Mac LAN interface; its address is
kept only in temporary runtime state outside the repository. Generated Xcode
projects, bundled proof resources, signing selections, build products, and logs
also stay in a checkout-keyed temporary directory outside the File Provider
tree, preventing sync-conflict copies from entering or breaking the gate. The
app permits only ATS local networking,
not arbitrary loads or certificate bypasses. XcodeGen emits and the generation
gate verifies `NSAllowsLocalNetworking`; the signed app also declares only the
`audio` background mode. A fresh run clears prior event evidence before autorun
so stale launches cannot satisfy the current device gate.

The harness bundles manifest-pinned MP3, AAC, ALAC, FLAC, Vorbis/Ogg,
Opus/Ogg, and Opus/MP4 fixtures. A runtime lane prepares every fixture both
locally and over the ephemeral HTTP server. Its background session schedules
three manifest-identified media tasks, validates status, media type, byte count,
and digest before atomic publication, reopens the final files through
AVFoundation, persists restoration bookkeeping, and rejects duplicate delegate
acknowledgements. Cancellation/resume remains an explicit operator-only device
procedure rather than an automatic-lane claim.

Passing install and launch proves local provisioning and executable device
delivery. Event facts prove only what they report. Background download survival
through suspension/relaunch, locked-screen playback duration, accessory remote
commands, Bluetooth/AirPlay route behavior, and acoustic transition quality need
the corresponding agent-operated hardware action and must remain open otherwise.
Raw events and the generated summary remain in the checkout-keyed temporary
artifact directory. `collect.sh` exits nonzero unless the summary passes, and it
does not copy JSONL events or a new unregistered JSON record into committed
evidence. After a passing run, the coordinator reviews the redacted summary and
updates the registered Phase 0 records intentionally.

The current focused lane passes twelve simulator XCTest cases and ten deterministic
Python device-contract tests, a clean signed arm64 build, generated
transport/background settings, privacy scanning, and device installation pass.
The single bounded launch attempt is still blocked by CoreDevice 10002 because
SpringBoard reports that the paired iPhone is locked. No runtime events were
collected and none of the hardware capabilities are promoted from that install.
