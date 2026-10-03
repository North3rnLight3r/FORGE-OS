# FORGE-OS Current Implementation

Last reconciled with `main`: **2026-08-31**.

This is the canonical current-state document for active FORGE-OS behavior. Historical build notes and old release evidence remain useful for chronology, but they do not override the current source, tests, or this implementation contract.

## Product role

FORGE-OS is the Arch-based operating-system integration layer for FORGE. Arch Linux, systemd, KWin/Plasma, NetworkManager, PipeWire/WirePlumber, PolicyKit, pacman, Flatpak, and native package databases remain the substrate. FORGE is the user-facing workspace/shell and owns the integrated desktop experience.

Current Beta release: **FORGE-OS 2.5.0-beta**, bundling FORGE **2.5.0-beta**.

## Session and login contract

Installed systems use the canonical Wayland path:

```text
greetd / tuigreet
  -> forge-wayland-session
  -> KWin Wayland + XWayland compatibility
  -> forge-wayland-client
  -> D-Bus / KDE services / PolicyKit / Plasma visuals
  -> forge-session
  -> content-addressed FORGE runtime
```

The production profile no longer depends on an experimental X11-first path. Recovery remains separately accessible from TTY/recovery tooling.

## FORGE runtime ownership

- FORGE and FORGE-OS are sibling repositories.
- Local build and install paths use the current FORGE worktree and record its commit only as build provenance.
- Installation builds/installs a content-addressed FORGE runtime and maintains current/last-known-good switching.
- Update flow checkpoints the installed system and reinstalls from the current local FORGE/FORGE-OS source without fetching, merging, resetting, or branch/dirty-tree/commit-parity gates.
- Pre-update checkpoints cover the FORGE-owned system integration layer without treating user projects or package databases as rollback payloads.

## Desktop shell and settings

- FORGE owns the primary visible workspace/shell experience.
- The FORGE-OS top bar reserves shell space rather than covering FORGE controls.
- Native KDE/KCM/KDialog settings open inside the same KWin Wayland compositor and inherit the FORGE palette/accent.
- Fixed quick actions cover Network, Audio, Display, Power, Applications, Storage, Appearance, Updates, Security, Recovery, and Advanced maintenance.
- Session actions use detached helpers so logout/restart/shutdown do not terminate their own IPC response before dispatch.
- The shared v2.5 renderer provides the northern-lights brand mark, bundled display/UI fonts, a bounded Three.js aurora field, animated glass surfaces, reliable opt-out synthesized system sounds, reduced-motion handling, and hidden-window animation suspension.
- Intelligence surfaces visualize the actual provider-neutral artifact packet, selected durable memory, semantic-memory, process-memory, correlated tool/task activity, terminals, and indexing telemetry. The renderer receives no direct process or filesystem authority.
- Direct whole-file reads stop before allocation above 32 MB, and permission failures return actionable user-owned-workspace guidance.

## Flatpak and application discovery

The current application-discovery path supports native `.desktop` applications and Flatpak exports.

- Session startup now merges `XDG_DATA_DIRS` instead of overwriting it.
- User and system Flatpak export paths are preserved alongside standard system data directories.
- Discovery honors XDG directory precedence, visibility keys, duplicate resolution, malformed-entry handling, and Flatpak `@@` launch markers.
- Application launch uses structured executable/argument handling rather than unsafe shell concatenation.
- The implementation is wired into the normal installed session, recovery/session paths, installer, and ISO so a clean install receives the same environment behavior.
- Existing sessions may require logout/login after the environment update before Plasma/FORGE sees the corrected export paths.

## Home workspace and protected paths

- FORGE-OS starts FORGE with `$HOME` as the default workspace.
- Explorer and model/tool discovery tolerate unreadable container overlay directories and other `EACCES`/`EPERM` subtrees instead of failing the whole home workspace.
- `.local/share/containers` and similar transient/protected trees are not treated as required project evidence.

## Packages and service policy

- Official Arch repositories remain authoritative; `multilib` is enabled.
- Chaotic-AUR is configured as the reviewed binary community repository and `yay` supports normal AUR access.
- Package mutation is routed through FORGE-OS wrappers for interactive use while bootstrap internals call `/usr/bin/pacman` directly to avoid wrapper recursion.
- Installed users are authenticated wheel administrators, but system paths remain root-owned. npm global tools install beneath user-owned `~/.local`, which is first on both the FORGE terminal and Fish paths.
- The integrated terminal stays mounted across bottom-panel switches so full-screen ANSI/TUI applications retain parser state; session changes reset the emulator and PTY restarts retain their fitted dimensions.
- Required services are declared in `manifests/system-services.tsv` and verified on first boot.
- NetworkManager, firewall, time sync, trim, mirrors, greetd, and PipeWire/WirePlumber are part of the required system contract; optional hardware/capability services remain selectable where documented.

## Nix monitoring layer direction

Nix is available as a reproducible environment/runtime dependency layer. The current architecture direction is to use declarative/runtime inspection to emit machine-readable state (for example JSON or SQLite metadata) that FORGE can inspect, rather than spending model/tool calls repeatedly rediscovering static runtime facts. Nix does not replace Arch/pacman as the OS package authority.

## Local AI/API environment

FORGE-OS provides the host environment for local runtimes such as Ollama and optional Hermes/other agent tooling while FORGE remains the workspace/tool authority. Local and OpenAI-compatible API endpoints are expected to be normalized through FORGE's runtime architecture rather than independently granting each client filesystem or shell authority.

## Live ISO and install flow

- The Beta ISO boots into the live FORGE/KWin environment and launches Guided Setup.
- The live `forge` account is intentionally ephemeral; passwordless sudo is restricted to the disposable live profile and removed from the installed target.
- Guided Install expects the target disk/mounts to be prepared and does not silently partition/format disks.
- Installer reproduces the pinned FORGE runtime, package/service policy, systemd-boot setup, recovery/advanced tools, and first-boot verification.

## Recovery and rollback

- Ctrl+Alt+F2 / recovery helpers provide a separate recovery path.
- Graphical login can be disabled without deleting runtimes or projects.
- Full checkpoint rollback verifies integrity before restoring FORGE-owned system integration.
- Runtime-only rollback switches current/last-known-good builds without deleting the build being left.

## Verification baseline

The active repository verification flow includes contract tests plus FORGE source verification. Relevant checks include:

```bash
./tests/greeter-contract.sh
FORGE_SOURCE=~/FORGE ./tests/clean-install-contract.sh
FORGE_SOURCE=~/FORGE ./tests/maintenance-contract.sh
./tests/source-verify.sh
./scripts/build-forge.sh ~/FORGE
./scripts/build-iso.sh
```

Feature-specific validation should also include the Flatpak/application discovery integration tests and shell syntax checks when those paths change.

## Documentation authority

When documentation disagrees, use this precedence:

1. Current source/tests and the release/CI provenance pin when a release artifact is being verified.
2. This document plus `README.md`, `ARCHITECTURE.md`, and `BUILD_STATE.md`.
3. Active user/install/recovery/security documentation under `docs/`.
4. Changelog and development notes as historical chronology.
