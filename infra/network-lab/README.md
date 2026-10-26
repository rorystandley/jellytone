# Phase 0 network lab

The lab is intentionally host-local and ephemeral. `tools/network-lab/run.sh`
starts or verifies the two digest-pinned disposable Jellyfin servers, then creates
loopback reverse proxies and per-run certificates in a private temporary directory.
Nothing in this directory is a production service or a trusted certificate asset.

The current and previous Jellyfin containers remain owned by `infra/jellyfin/`.
The lab proxies `/jellyfin/System/Info/Public` to those servers, preserving the
reverse-proxy base path externally while stripping it upstream. A second origin
targets the same server ID and a third targets the other disposable server ID.
This makes redirect identity decisions executable without storing either ID.

All listeners bind to `127.0.0.1` or `::1`; certificates, private keys, endpoints,
credentials, and server IDs are deleted with the temporary directory or retained
only in process memory.
