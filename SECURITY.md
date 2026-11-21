# Security Policy

## Supported version

Only the latest release is actively supported.

## Reporting a vulnerability

Please open a GitHub Security Advisory instead of publishing sensitive details in a public Issue.

The helper and settings applications are intentionally small and local-only. They do not make network requests, collect telemetry, or store input events.

The install script is the only component that uses the network: it downloads a pinned Mos release when Mos is missing or outdated, and verifies its size, SHA-256, Gatekeeper assessment, and developer Team ID before installing.

