# Device proof procedure and pass criteria

1. Run `./tools/device-proof/run.sh` with the paired iPhone unlocked and connected
   to the same LAN as the Mac. No Apple portal updates or entitlement submissions
   are performed.
2. Confirm `latest-results.json` contains codec preparation, trusted HTTPS ATS,
   local HTTP ATS, playback, and background-download events. A local-network
   privacy denial is a failure, not a reason to broaden ATS.
   Also require a `route/baseline` event and `remote/registered` event before
   treating route observation or command registration as exercised. Registration
   is not evidence that an external command was received.
   Require local and remote-HTTP preparation passes for MP3, AAC, ALAC, FLAC,
   Vorbis/Ogg, and Opus/Ogg. Opus/MP4 is supplemental; it cannot replace a
   required row.
3. Lock the device for five minutes while the synthetic tone loops, then issue
   Play, Pause, and Seek from Lock Screen/Control Centre. Collect again and require
   one event per command and uninterrupted queue ownership.
4. Attach/remove a supported audio route and collect the route-change reason.
   Bluetooth and AirPlay require their actual hardware routes; built-in speaker
   evidence cannot substitute.
5. For background download relaunch proof, start the three manifest-backed
   synthetic transfers, throttle the fixture server,
   suspend (do not force quit), and collect after system delegate delivery.
   Require `scheduled`, `session_restored`, `completed_atomically`, and
   `final_file_probed` for all three media identities, plus exactly one
   `events_acknowledged` event. The summary must reject a partial/corrupt file,
   status/content mismatch, wrong byte count/digest, missing audio track, or
   duplicate acknowledgement. Run cancellation/resume separately; the automatic
   launch records it as blocked until that operator action occurs.

The harness intentionally does not request CarPlay, accept untrusted TLS, use a
private Jellyfin server, or create production application modules.
