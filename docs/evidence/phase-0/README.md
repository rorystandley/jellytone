# Phase 0 Evidence Index

Status: In progress

Phase authority: [PRODUCT_PLAN.md](../../../PRODUCT_PLAN.md#phase-0-product-proof-and-decision-records)

Evidence is grouped by independently reproducible workstream:

- `environment.md`: initial local toolchain and external-dependency state.
- `connectivity/`: Jellyfin contracts, SDK, authentication, endpoints, and TLS.
- `playback/`: codec, Direct Play/transcode, transition, and audio-system proofs.
- `automation/`: disposable servers, fixtures, generation, CI, and validation.
- `platform/`: simulator, device, signing, background, and entitlement status.
- `device/`: isolated signed harness, simulator logic, device install, and
  blocked runtime capability procedures.
- `network/`: host TLS, proxy, redirect, discovery, resolver, and server-restart
  proofs with device and live-tailnet limitations.

An evidence record must identify its command or procedure, inputs, observed
result, limitations, and the owning roadmap phase for unresolved risk. A claimed
capability requires observed behavior; documentation or API presence alone is
not proof.

All JSON records also require the common integrity envelope documented under
`automation/`. Run `tools/phase0/validate.sh evidence` for schema, provenance,
status/limitation, privacy, and record-specific semantic checks. The validator
rejects unregistered JSON evidence paths so a new record cannot silently bypass
semantic validation.
