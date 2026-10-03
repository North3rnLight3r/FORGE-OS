# Security model

## Login and session

Normal tty1 login uses the unprivileged `greeter` account and PAM. The post-auth command is exactly `/usr/local/bin/forge-wayland-session`, which owns the one-KWin branch. The historical `/usr/local/bin/startplasma-wayland` dispatcher remains compatibility-only and falls through to the unchanged vendor executable for unrelated calls. Shell profiles are not sourced.

F2 changes the complete command for one authenticated login. F3 selects the isolated FORGE session, F4 changes the visual background, and F5 exposes power actions. None grants root.

The on-demand tty2 recovery session is intentionally pre-authenticated for diagnostics. It exposes user-owned logs and a user terminal. Runtime mutation still requires PolicyKit and is restricted to verified immutable directories under `/opt/forge/releases`.

## Files, applications, and packages

FORGE runs as a normal user. Renderer requests cross typed IPC; they never receive raw Node, shell, or package-manager access. Explorer resolves canonical workspace-contained paths and rejects traversal/symlink escapes. Administrator execution is explicit and confirmed.

Arch package mutations call the fixed `/usr/bin/pacman` through PolicyKit and use normal pacman database/cache/install paths. Apt/Ubuntu/Kali remain in rootless Distrobox containers; Nix remains in `/nix/store` and user profiles. No Debian/Kali repository is added to the Arch host. Mirrors are changed only by the explicit reviewed/ranked command.

## Runtime and updates

Runtime identity uses application version, package/lock hashes, runtime-source content, ordered overlays, executable/app archive hashes, and full payload hash. Ordinary commits do not force a version bump; commit and deterministic build date remain provenance. Activation occurs only after verification. `chrome-sandbox` remains root-owned mode `4755`; permanent `--no-sandbox` is prohibited.

The source updater accepts no renderer-supplied command or install path. It invokes the authoritative installer against the current local FORGE and FORGE-OS checkouts. It never fetches, merges, resets, downloads a release, or reboots automatically; detached, dirty, and divergent checkouts are accepted.

## Agent and secrets

The release workflow may request all registered filesystem, process, Git, network, packaging, and publication tools. It cannot create a global allow-everything permission. Every mutation follows the FORGE policy/approval/audit path described in the FORGE repository `AGENTS.md`.

Passwords, tokens, API keys, full environment dumps, and private workspace content must not enter logs or Git. Session/recovery logs record bounded runtime events and are user-readable only.
