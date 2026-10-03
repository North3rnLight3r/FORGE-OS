# Remaining implementation and release gaps

## Source features not present

1. Wire bounded automatic workspace-memory reindexing to a permission-tolerant filesystem watcher. Current reindexing is user-triggered.
2. Implement the planned Explorer metadata/binary/package/executable inspector and explicit user/administrator launch modes.
3. Implement a separate FORGE-OS top-bar Workspace Intelligence popover only if it remains a product requirement; current Intelligence and chat both live in the shared right rail.
4. Add real packaged `local-model-tooling` skill assets or remove the optional installer copy hooks. Ollama tool access currently comes from the live FORGE registry and does not require that absent skill file.
5. Add and validate the referenced native cross-platform packaging workflow and runtime-parity verifier. Current source contains native packaging scripts but no `package-cross-platform.yml` or `verify-runtime-parity.mjs`.
6. Add guided partition/format behavior before describing the ISO as an end-user disk installer rather than a bootable live/recovery image.

## Acceptance and distribution still required

1. Run an unskipped bootstrap/install on a disposable clean Arch target and verify every manifest package, unit, desktop default, Fish shell, optional-skill behavior, and installed hash.
2. Boot the generated ISO in a VM and on reference hardware. Validate one KWin owner, GPU rendering, XWayland, NetworkManager, PipeWire, portals, external-window focus, suspend/resume, logout/relogin, on-demand tty2 recovery, and rollback.
3. Produce Windows and macOS packages on native runners and establish platform-specific runtime evidence.
4. Establish signing keys/certificates and a signed stable binary/OS update feed. The current FORGE-OS updater installs the current local source and retains artifact/hash verification.
5. Exercise updater/rollback cases on an installed disposable target, including wrong manifest/hash, interrupted activation, unavailable last-known-good, and repeat update after rollback. Source transaction tests cover dirty, divergent, unavailable-origin, detached, failed-install state preservation, and local-source installation behavior.

No source-only check can replace physical, native-runner, signing, and remote publication gates.
