# Security

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |

## Reporting a vulnerability

Do not open a public issue for a security report.

Use GitHub private vulnerability reporting:

https://github.com/rorystandley/jellytone/security/advisories/new

Include what you can about the impact, the version, and how to reproduce it. The maintainer is Rory Standley (@rorystandley).

## What this app stores

The Jellyfin access token is stored in the iOS Keychain. The password is used for sign-in and is not written to disk by the app. Diagnostics are written to avoid tokens, credentials, and server addresses.

If you believe a token or a server address leaked into a log, a screenshot, or a commit, say so in the report. Rotate that Jellyfin password and sign in again so the server issues a new token.
