# Evidence index

Narrative evidence was consolidated on 2026-07-18 because it duplicated tests,
the product plan, and the queue, and several snapshots contradicted later runs.
Git history retains the old prose. Current claims must come from executable
commands and the machine-readable records below.

## Canonical gates

```sh
./scripts/test.sh
./scripts/test-integration.sh
./scripts/test-ui.sh
./scripts/test-device.sh
./scripts/build-release.sh
```

`PRODUCT_PLAN.md` defines acceptance and `docs/NEXT_WORK.md` records current
blockers. Do not add per-feature evidence essays; add a deterministic test,
machine record, or concise queue update.

## Retained machine evidence

Phase 0 JSON records remain under `docs/evidence/phase-0/` and are registered by
`tools/phase0/validate_evidence.py`:

- automation environment, project-generation, clean-checkout, and synthetic
  library records;
- connectivity contracts for Jellyfin 10.10.7 and 10.11.11;
- device execution status;
- host network/restart results;
- playback codec, session-order, source-policy, transition, and device records;
- platform/environment and external-status records.

Validate them with:

```sh
python3 tools/phase0/validate_evidence.py
python3 -m unittest discover -s Tests/Phase0Evidence -p 'test_*.py' -v
```

Phase 3 large-library measurements remain in
`docs/evidence/phase-3/large-library-scale.json`. Current feature proof lives in
the matching Swift gateway, state, persistence, playback-integration, privacy,
and UI test suites.

## Honest limitations

- Physical-device audible control is not yet agent-operable end to end on the
  current build; it remains a release blocker.
- Simulator evidence does not prove Bluetooth, AirPlay, CarPlay, background
  suspension, or endurance behaviour.
- The local unit runner has shown an intermittent pre-bootstrap process kill;
  a later run may pass, but repeatability is still required.
- The UI suite currently has a favourites failure to diagnose; compilation does
  not satisfy the UI/accessibility gate.
- Production signing, bundle identity, App Store distribution, and external
  entitlements are not configured.
