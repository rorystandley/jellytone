# Synthetic library reset proof

`tools/fixtures/library-manifest.json` defines 13 one-second synthetic tones at
48 kHz. It covers single-disc, multi-disc, compilation, missing-artwork,
malformed-metadata, MP3, AAC, ALAC, FLAC, Ogg/Vorbis, and Opus records. No input
media, private metadata, or random source is used.

On 2026-07-16, FFmpeg 8.1.2 generated the complete library twice in independent
clean directories. `tools/phase0/validate.sh` verified every expected codec and
produced the same path-and-content aggregate SHA-256 for both runs:

`30b87ef79ed1e263cb2c53e768f2d84f6f92da0e34bd11ba404f8795e342bebb`

FFmpeg bitexact encoder/muxer flags remove random Ogg stream serials and encoder
metadata. A toolchain update must rerun the two-directory proof; it may change
the aggregate only through an intentional evidence update after semantic media
verification.
