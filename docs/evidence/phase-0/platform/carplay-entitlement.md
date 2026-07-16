# CarPlay audio entitlement status

Status on 2026-07-16: **blocked / no locally verifiable submission evidence**.

The product requires Apple-managed capability
`com.apple.developer.carplay-audio`. There is no production target, registered
App ID, request result, or matching provisioning profile in Phase 0. The Apple
Developer portal was not accessed, so the record does not infer whether an
unrelated external request exists. Certificate presence is not entitlement
evidence. The coordinator must request the audio app entitlement only after the
bundle identity exists and external submission is authorized, then record
Apple’s actual response. Simulator UI is supplemental and cannot prove
managed-capability approval or vehicle behavior.

Primary source: [Apple — Requesting CarPlay Entitlements](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements).
