# Connectivity policy and contract results

Run date: 2026-07-16
Host: arm64 macOS; Python standard library
Scope: deterministic policy and synthetic redacted API shapes

## Command

```sh
python3 tools/connectivity/run_proofs.py
```

## Result

PASS: 14 tests.

| Proof | Result |
|---|---|
| Full URL requirement and rejection of URL credentials/query/fragment | PASS |
| Port, IPv4, IPv6, `.local`, Tailscale FQDN, and reverse-proxy base-path normalization | PASS |
| Same-origin authenticated redirect reconstruction | PASS |
| HTTPS-to-HTTP redirect rejection | PASS |
| Changed-origin exact server-ID proof | PASS |
| Authorization, token, URL, username, item, and endpoint redaction | PASS |
| Authentication server replacement rejection | PASS |
| Keychain-reference-only durable metadata and 401 invalidation contract | PASS |
| Final-report field/value privacy scan rejects actual secrets and identifiers | PASS |
| Quick Connect pending, denied, expired, timeout, and cancellation classification | PASS |
| Known logout revocation versus ambiguous expired/invalid 401 classification | PASS |
| Bounded FFprobe audio codec/stream validation | PASS |
| 10.11.11 and 10.10.7 representative synthetic response shapes | PASS |

Validated fixtures:

- `Tests/Fixtures/Jellyfin/10.11.11/connectivity-contract.json`: public system
  information, password/Quick Connect authentication shapes, one audio item.
- `Tests/Fixtures/Jellyfin/10.10.7/connectivity-contract.json`: the same consumed
  shapes for the preceding supported line.

These are deliberately synthetic mapping inputs, not captures from a private
library and not evidence that servers executed the requests.

## SDK source inspection

The official SDK 2.1.0 source exposes the required Phase 0 surfaces:
`/System/Info/Public`, `/Users/AuthenticateByName`, Quick Connect initiate/poll/final
authentication, token-bearing authorization headers, server discovery, and token
revocation. This establishes implementability only. Per the product gate, it is not
accepted as end-to-end proof.

The pin verification command resolved tag 2.1.0 to commit
`09d8f31886b6bea1cfc4719a39bdb6eac1287344`, built the package with Swift 6.3.3,
and passed the SDK's 7 URL/base-path tests. Generated declarations emitted
deprecation warnings; no build or test failure occurred.

## Live public identity probe

After Phase 0 automation provisioned healthy loopback containers, the
credential-free redirect-disabled probe returned HTTP 200 and required public
identity fields from both pinned images:

| Pinned image | Reported version | Public ID present | Result |
|---|---:|---:|---:|
| `jellyfin/jellyfin:10.11.11` | 10.11.11 | yes | PASS |
| `jellyfin/jellyfin:10.10.7` | 10.10.7 | yes | PASS |

Endpoint addresses, server names, and IDs are intentionally omitted. The probe
identified an initial redaction gap for generic `Id` and `ServerName` fields; the
redactor and regression test were tightened before this evidence was finalized.
## Live authenticated contracts

After automation completed setup and registered the read-only synthetic music
library, this command ran against both isolated loopback servers:

```sh
tools/phase0/jellyfin.sh reset
PYTHONDONTWRITEBYTECODE=1 python3 tools/connectivity/live_contract_probe.py \
  > docs/evidence/phase-0/connectivity/live-contract-results.json
```

Both 10.11.11 and 10.10.7 passed:

- password authentication with the mode-0600 password read process-locally;
- exact authenticated/public server identity match;
- invalid-token HTTP 401 rejection;
- authenticated audio-item enumeration and playback-info media source;
- playback start, progress, and stop reporting;
- authenticated static-original fetch for each MP3, AAC, ALAC, FLAC, Ogg/Vorbis,
  and Ogg/Opus fixture with HTTP 2xx and complete bounded bytes;
- requested AAC-in-MP4 fetch for each source with Direct Play and Direct Stream
  disabled and transcoding enabled;
- `ffprobe` verification that all 24 responses contain exactly one expected audio
  stream, no video stream, and a recognized container;
- Quick Connect configured disabled with initiation rejected as 4xx;
- Quick Connect configured enabled with a pending poll, server-disabled denial,
  expired-or-unknown-secret rejection, deterministic bounded timeout and client
  cancellation, authorize, poll, token exchange, logout, and post-logout rejection;
- primary-session logout and post-logout token rejection.

The final JSON report is scanned before output against process-local passwords,
tokens, Quick Connect codes/secrets, endpoint addresses, and user/item/server/session
IDs, as well as forbidden private field names. Its narrow claim is
`reportContainsSecrets: false`. The common evidence envelope separately records
`committedEvidenceContainsSecrets: false`, `privateServerDataPersisted: false`, the
capture command/environment/owner/status, and explicit limitations. Both claims are
backed by the same complete final-JSON sink scan; neither claims memory inspection or
Keychain persistence. The registered strict validation command is:

```sh
python3 tools/phase0/validate_evidence.py docs/evidence/phase-0/connectivity/live-contract-results.json
```

Result: PASS, one record, zero issues.

The probe restores the original Quick Connect configuration in `finally`; a
post-run server verification confirmed both disposable baselines remained healthy.

Jellyfin labels each AAC-only MP4 response `video/mp4`; the proof therefore trusts
neither MIME nor a small byte marker. It inspects the complete bounded response with
`ffprobe` and requires AAC audio with zero video streams. The static-original request
is recorded as original delivery, not as a Direct Play or iOS decode claim. This
proves server delivery, not decoding, audibility, timing, or playback on an Apple
device.
