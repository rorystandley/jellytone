# Project-generation proof

On 2026-07-16, the official XcodeGen 2.46.0 release archive was downloaded and
matched SHA-256
`4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`.

`XCODEGEN_BIN=<verified binary> tools/phase0/prove-project-generation.sh`
generated an isolated iOS application spec twice in independent clean
directories and compared normalized project contents. The production app was
not scaffolded. Both outputs produced normalized SHA-256
`33069a625178438d48a45f8b39d38f774515a276216875bc7f364549480cd3fa`.
The first generated project also completed a code-signing-disabled generic iOS
Simulator build under Xcode 26.6. Re-run `tools/phase0/validate.sh` for the
current result.

Source: [XcodeGen 2.46.0 release](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0).
