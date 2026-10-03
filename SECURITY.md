# Security

FORGE-OS `0.2.5-test.1` is a local acceptance candidate, not a stable or published release. Until its ISO boot and hardware checklist is approved, use it on test hardware or systems with verified backups. The production graphical path is the rootless FORGE-owned KWin Wayland session; XWayland is retained only for legacy applications.

Updates launched through FORGE are visible and use the current local FORGE/FORGE-OS checkouts. They do not fetch, merge, reset, download releases, or consult stale source pins; local branches, edits, and divergent histories are preserved at the authoritative installer boundary.

Do not include credentials, tokens, logs containing private data, or machine-specific artifacts in reports. For a suspected vulnerability, open a private GitHub security advisory in the repository rather than a public issue. See the detailed [Security Model](docs/SECURITY_MODEL.md).
