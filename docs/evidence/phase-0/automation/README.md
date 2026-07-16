# Phase 0 automation evidence

Every JSON evidence record uses the common envelope in `evidence-schema.json`.
`tools/phase0/validate_evidence.py` enforces that envelope and the semantic
payload contract registered for each evidence path. Syntax-only JSON is not
accepted. Every record identifies its proof, timestamp, reproducing command,
environment, Phase 0 workstream owner, summary status, limitations, and
explicit committed-output privacy claims. The common privacy fields prove that
the committed evidence contains no secrets or private server data; they do not
make claims about process memory, Keychain state, or an unobserved runtime. A
check is `pass` only when the recorded command observed the required mechanism.
`blocked` names a missing external
dependency; `not-run` names work that was possible but not executed.
Limitations may narrow a result but may not convert a simulator result into
device proof. A blocked or not-run record/check must state its limitation, and
the record summary must reflect its most severe check status.

Core commands:

```sh
tools/phase0/validate.sh
tools/phase0/validate.sh apple
tools/phase0/validate.sh linux
tools/phase0/validate.sh evidence
tools/phase0/jellyfin.sh reset
tools/phase0/jellyfin.sh verify
tools/phase0/probe-environment.sh
```

The full gate has also passed from a fresh clone; see
[`clean-checkout-validation.md`](clean-checkout-validation.md) for the exact
command, commit, results, and limitations.

The first command is the combined local gate and requires both Xcode and a
running Docker daemon. The shared core runs ShellCheck, evidence-validator
regression tests, deterministic synthetic-library generation, connectivity
policy/contracts, and portable playback unit tests. The `apple` lane
adds deterministic XcodeGen generation, simulator build/tests, host
AVFoundation codec preparation, transition measurements, and session ordering.
The `linux` lane resets both digest-pinned Jellyfin containers, performs the
authenticated live contracts against both supported versions, and runs the host
network lab including disposable-server restart. `evidence` runs only the
validator tests and committed-record integrity check.

CI runs `apple` on `macos-26` and `linux` on `ubuntu-24.04`. The macOS job does
not install a Docker client without a daemon; the Linux job proves daemon
availability before invoking the same repository lane used locally. Container
cleanup is automatic on success, failure, or interruption. These host and
simulator results do not claim physical-device behavior. Network SDK cloning,
device install/launch, external routes, and entitlement operations remain
separate explicitly authorized procedures.
