# Disposable Jellyfin servers

This compose project provisions two loopback-only, disposable servers against
the same generated synthetic library:

- current stable: Jellyfin 10.11.11 on `http://127.0.0.1:18096`;
- previous supported line: Jellyfin 10.10.7 on `http://127.0.0.1:18097`.

Both image tags are locked to registry manifest digests in `versions.env`.
There is no private media and no reusable repository credential. Initialisation
generates a local-only fixture password under ignored `.state` with mode 0600.
Never expose these ports outside loopback or reuse this configuration for a real
server.

From the repository root:

```sh
tools/phase0/jellyfin.sh reset
tools/phase0/jellyfin.sh status
tools/phase0/jellyfin.sh down
```

`reset` removes only `infra/jellyfin/.state`, recreates the synthetic library,
starts both pinned containers, completes their startup API, and adds `/media` as
a music library. The operation is destructive only to this disposable compose
project. Docker Desktop or another Docker Compose-compatible daemon is required.

`tools/phase0/jellyfin.sh verify` checks each public system-info endpoint and
fails if its reported version differs from `versions.env`.
