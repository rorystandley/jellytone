# Phase 0 playback proof

Status: partial proof; real-device and versioned Jellyfin-server gates remain open.

## Reproduce host evidence

From the repository root, with Xcode command-line tools, Python 3, FFmpeg and
FFprobe available:

```sh
python3 -m unittest discover -s Tests/Phase0Playback -v
python3 tools/playback/run_codec_matrix.py
python3 tools/playback/render_transitions.py
python3 tools/playback/validate_session_order.py
```

The generator creates two 48 kHz stereo synthetic sine-wave tracks and encodes
the required audio matrix. `run_codec_matrix.py` inspects every output with
FFprobe and then asks AVFoundation to prepare each asset from a local file and a
range-capable loopback HTTP server. The report intentionally labels this a
macOS host probe, not iOS advertising proof.

FFmpeg assigns random Ogg stream serials. The generator replaces each Vorbis
and Opus stream serial with a fixture-specific constant and recomputes every Ogg
page CRC before hashing. It writes generated media and manifests only when the
bytes change. The test suite compares two independent clean generations and
then runs the full proof sequence twice, checking that all media and evidence
remain byte-identical and that report hashes still match disk. Loopback preload
evidence records deterministic byte counts; wall-clock latency is deliberately
excluded from committed JSON and belongs in separately timestamped performance
runs.

`render_transitions.py` renders a prepared hard cut and a 250 ms linear
crossfade from both files and the ranged loopback HTTP server. All four outputs
have zero duration error at 48 kHz and no digital-silence run longer than two
samples. This proves the deterministic scheduling/mixing measurement and
fixtures; it does not measure AVPlayer speaker output.

## Captured environment and findings

- Host: Apple Silicon macOS 26, Xcode 26.6 (17F113), Swift 6.3.3.
- Every generated MP3, AAC/M4A, ALAC/M4A, FLAC, Vorbis/Ogg, Opus/Ogg and
  Opus/MP4 asset was playable and exposed one audio track through host
  AVFoundation over local file and loopback HTTP.
- The ordered-session prototype emitted `progress`, then `stop`, before each
  replacement `start`. It is an invariant proof, not a Jellyfin API contract
  test.
- A paired iPhone 13 on iOS 26.5.2 and three signing identities are visible.
  An isolated playback/device probe now builds with development signing,
  declares the audio background mode, installs successfully, and has a bounded
  automated runner. It contains manifest-pinned required codecs and local plus
  remote-HTTP AVFoundation preparation paths, but those paths have only simulator
  logic/build evidence. SpringBoard denied the single launch attempt because the phone was
  locked, so no device-side playback event was collected. There is still no
  acoustic capture path. The integrated connectivity stream fetched original
  MP3, AAC, ALAC, FLAC, Ogg/Vorbis, and Ogg/Opus plus a requested AAC/MP4
  transcode for every source on both pinned Jellyfin versions. That proves the
  complete required server-delivery matrix; iOS decoding, actual gapless output,
  background, route, accessory, and endurance claims remain open.

Machine-readable outputs live in `results/`. Synthetic source hashes and byte
counts live in `Tests/Fixtures/Audio/manifest.json`.

## Primary-source basis

- Apple documents AVAudioEngine manual rendering for faster-than-real-time,
  deterministic output: <https://developer.apple.com/documentation/avfaudio/avaudioengine>
- Apple documents AVPlayer's HTTP stalling policy and the precision tradeoff:
  <https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling>
- Jellyfin's official codec table says iOS 18.4 adds Ogg-container Vorbis and
  Opus, while Opus-in-MP4 starts at iOS 17:
  <https://jellyfin.org/docs/general/clients/codec-support/>
- Jellyfin documents client-provided transcode profiles and capability-driven
  conversion: <https://jellyfin.org/docs/general/post-install/transcoding/>
