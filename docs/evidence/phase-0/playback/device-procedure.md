# Agent-operated playback device procedure

An isolated XcodeGen device probe now builds with development signing, declares
the audio background mode, installs on the paired iPhone 13, and has bounded
noninteractive launch and evidence-collection commands. It bundles every
required codec and prepares each local and remote-HTTP asset while requiring an
audio track. The single bounded launch attempt is
blocked because SpringBoard reports the phone is locked, so the steps below have
not produced runtime playback evidence. Do not execute the procedure in a
simulator and promote the result to hardware evidence.

For each built-in speaker, wired, Bluetooth and AirPlay route, and for both a
local fixture and an authenticated synthetic Jellyfin stream:

1. Record redacted device model, OS build, app build, route, codec/container,
   source type, server version and fixture hash.
2. Start track A, lock the device for at least five minutes, and capture
   timestamped state transitions plus signposts. Repeat the release endurance
   run for eight hours.
3. Exercise play, pause, seek, previous and next from Lock Screen, Control
   Centre and a connected accessory. Assert the authoritative queue index,
   position and Now Playing snapshot agree after every command.
4. Trigger an interruption, observe `.began`, and assert playback pauses without
   losing the queue. On `.ended`, resume only when the system supplies the
   resume option and the user did not pause during the interruption.
5. Remove headphones and assert playback pauses. Connect and disconnect other
   routes; record route-change reason, old/new route and whether policy resumes.
6. During a remote stream, sleep/restart the server. Assert the old Jellyfin
   play session receives final progress and stop before a replacement session
   starts. Repeat with rapid queue replacement and endpoint failover.
7. Capture device-side audio through a calibrated loopback/capture path. Run the
   same sample-domain silence/overlap analysis as the host fixtures; record the
   capture chain latency separately.

Pass criteria: no orphan session, no queue divergence, commands acknowledged
exactly once, no credential/server data in logs, background playback survives,
and measured transition thresholds match the compatibility row. Failed
preloading or crossfade must emit the hard-cut fallback reason rather than claim
the requested transition occurred.
