# Stable release checklist

A stable tag is allowed only when every applicable item is evidenced. Source success alone is not stable acceptance.

## Source and version

- [ ] FORGE and FORGE-OS contain the intentional source for the release; branch, working-tree, and remote state are recorded separately from release provenance.
- [ ] `VERSION`, all FORGE-owned package manifests/lock entries, release notes, changelog, and current docs name the next deliberate build/version.
- [ ] No credentials, local databases, build directories, machine logs, stale scripts, or redundant current docs are tracked.
- [ ] `./tests/source-verify.sh` passes after the final source change.
- [ ] FORGE typecheck, lint, complete tests, production bundle, release-version verifier, and dependency audit pass.

## Packages and runtime

- [ ] Every entry in `manifests/arch-packages.txt` resolves and installs on a clean Arch target.
- [ ] `forge-app-install` and `forge-install-pkg` exercise `-S`, `-Syu`, search/info/query, removal, local Arch package, apt/Kali container, and Nix cases without mixing host databases.
- [ ] Installed apps use normal backend paths and appear in FORGE Applications without relogin.
- [ ] Fish is the account shell and the Dr460nized-inspired Fish/Starship theme loads.
- [ ] Final immutable runtime hashes match the build record and installed payload; sandbox is root:root `4755`.
- [ ] Update acceptance cases (dirty, divergent, detached, and local-commit checkouts), failed-install state preservation, and one local-source install pass.
- [ ] Last-known-good rollback passes, removes only the superseded runtime, and a subsequent update does not conflict.

## Login, desktop, and recovery

- [ ] Cold boot shows the matrix greetd screen on tty1.
- [ ] Default/F2 command is exactly `/usr/local/bin/forge-wayland-session`; F3 resolves to the same path and F4/F5 work. The compatibility dispatcher remains isolated.
- [ ] Login produces one KWin owner and correct XDG/FORGE/D-Bus environment; KRunner and portals are available.
- [ ] FORGE remains the visible shell; stock Plasma panel is absent; optional user panels persist.
- [ ] Applications, all eleven quick System surfaces, Workspace Intelligence, chat, terminal, tasks, agent actions, and four session controls work without overlap/focus traps.
- [ ] Explorer covers folder navigation, copy/paste, rename/delete, metadata, executable/package inspection, user/admin launch, and external app focus; it is the default file manager.
- [ ] Network, audio, display, power profiles, notifications, portals, suspend/resume, logout/relogin, native Wayland, and XWayland applications pass.
- [ ] Ctrl+Alt+F2 starts native recovery on demand, exposes logs/user terminal without login, and requires PolicyKit for mutation.

## Cross-platform packages

- [ ] Linux AppImage and DEB pass runtime metadata and native PTY verification.
- [ ] Windows NSIS passes runtime metadata and ConPTY resource verification on a Windows runner.
- [ ] macOS universal DMG/ZIP pass manifest, bundle, architecture, and native PTY verification on a macOS runner.
- [ ] A committed runtime-parity verifier confirms version, commit, deterministic build date, and shared runtime identity across Linux, Windows, and macOS. This verifier is not yet implemented.

## ISO and publication

- [ ] ISO builds from the same manifest/runtime/session files and SHA256SUMS verifies.
- [ ] ISO boots in UEFI VM and reference hardware; live `forge` account, package stack, login, desktop, recovery, networking, audio, portals, and shutdown pass.
- [ ] Guided install/partition behavior is present or the artifact is labeled truthfully as live/recovery rather than a stable installer.
- [ ] Final commit is pushed, annotated tag resolves to it, CI jobs pass at the tag, and artifacts are signed where policy requires.
- [ ] GitHub release/ISO assets and published checksums match local verified files byte-for-byte.
- [ ] A clean checkout packages and installs the exact selected local source without changing Git refs.
- [ ] Final Codex session log records commands, results, artifacts, hashes, remote URLs, and any physical evidence.
