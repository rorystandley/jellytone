# Agent-operated background download proof

The signed isolated device harness now schedules three manifest-backed tasks and
implements restoration bookkeeping; response/content, byte-count, and digest
validation; staged atomic publication; final-file AVFoundation probing; and
exactly-once acknowledgement instrumentation. Deterministic tests reject partial,
corrupt, wrong-digest, wrong-status/content, and duplicate-acknowledgement cases.
Cancellation/resume is deliberately operator-only. Its single bounded device
launch attempt was denied because the paired phone was
locked, so the corresponding runtime gate remains blocked as recorded in
`external-status.json`.

1. Reset a disposable Jellyfin server and record its version/media fixture.
2. Install a signed build on the recorded device through noninteractive
   `devicectl`; do not record the device identifier in committed evidence.
3. Schedule at least three `URLSessionConfiguration.background` download tasks
   in one stable, app-owned session. Record task IDs, expected byte counts, and
   manifest identities using synthetic media only.
4. Suspend the app, wait for one task to progress, then terminate the process.
   Do not force-quit from the app switcher because that changes relaunch policy.
5. Observe that `nsurlsessiond` continues transfer. On completion, verify the
   system relaunches/resumes the app through
   `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
6. Verify atomic publication, byte/digest validation, manifest-backed state, playable local
   source, and exactly-once completion acknowledgement after relaunch.
7. Repeat for cancellation/resume data, server restart, insufficient storage,
   token expiry, process eviction, device lock, and Wi-Fi policy.
8. Capture a redacted evidence JSON record with device model/OS, server version,
   command/harness revision, pass/fail facts, timings, and limitations.

Apple documents that background sessions continue while an app is suspended
and may relaunch it for delegate delivery, while rate limiting and user
force-quit behavior remain system-controlled:
[Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background).
