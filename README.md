# FORGE-OS

FORGE-OS is the Arch-based integration layer that makes FORGE the visible workspace, desktop, Explorer, settings, recovery, update, and setup experience. Arch, systemd, KWin, Plasma services, NetworkManager, PipeWire, PolicyKit, pacman, and the native package databases remain the operating-system substrate; they do not become the primary UI.

Current Beta release: **`FORGE-OS 2.5.0-beta`**, bundling the FORGE **`2.5.0-beta`** living-intelligence runtime. Release automation checks out the current shared FORGE source and records its commit in the generated runtime metadata.

## Login contract

Normal installed boot is deterministic:

```text
greetd on tty1
  -> /usr/local/bin/tuigreet
  -> /usr/local/bin/forge-wayland-session
  -> KWin Wayland + XWayland compatibility
  -> /usr/local/libexec/forge-wayland-client
  -> D-Bus, KRunner, KDE services, PolicyKit, Plasma visuals
  -> /usr/local/bin/forge-session
  -> content-addressed FORGE runtime
```

F2 defaults to `/usr/local/bin/forge-wayland-session`, and the visible F3 FORGE session entry points to the same installed path. Old X11/session-client defaults are removed from the production profile; the historical `startplasma-wayland` dispatcher remains only as a compatibility implementation.

The login UI uses canonical `tuigreet/tuigreet` **0.11.0**, pinned to its signed release commit and built with Cargo's lockfile. Matrix is the default background and F4 opens the background selector, including DOOM fire. Session remembering is deliberately disabled so an old experimental command cannot silently replace the canonical Wayland path. `tests/greeter-contract.sh` compares the configured login options with the actual pinned binary before greetd is enabled.

## Two normal maintenance commands

Clone FORGE and FORGE-OS as sibling directories in the same user's home directory. A fresh Arch/FORGE-OS machine uses:

```bash
git clone https://github.com/North3rnLight3r/FORGE.git ~/FORGE
git clone https://github.com/North3rnLight3r/FORGE-OS.git ~/FORGE-OS
cd ~/FORGE-OS
./install.sh
```

The installer is an intentional Arch system mutation: review it and use a test/disposable machine until the release checklist is complete.

```bash
cd ~/FORGE-OS
./install.sh
```

installs or repairs the current checkout. The bootstrap, build, runtime, hardware/service, and desktop scripts remain separate implementation stages because the installer executes them explicitly.

```bash
cd ~/FORGE-OS
./update.sh
```

 creates a root-owned pre-update FORGE-OS system checkpoint and runs the authoritative installer against the current local FORGE and FORGE-OS checkouts. It never fetches, merges, resets, downloads a release, or consults a stale source pin. Pull or switch to the exact commits you want before running the command; local branches, detached heads, and working-tree edits are preserved.

## Packages, mirrors, and services

Interactive Arch mutations inside the FORGE Fish environment route through `forge-install-pkg`. GUI installation routes `forge-install-program -> forge-app-install -> forge-install-pkg`. Bootstrap internals use absolute `/usr/bin/pacman` to avoid wrapper recursion.

Official Arch repositories remain the package base, `multilib` is enabled, Chaotic-AUR is configured as the reviewed binary community repository, and `yay` provides ordinary AUR access. The installer establishes the tracked HTTPS mirror baseline and then uses Reflector; `reflector.timer` maintains the Arch mirror list after reboot.

Required system units are defined in `manifests/system-services.tsv`. NetworkManager, firewalld, irqbalance, time sync, fstrim, Reflector, greetd, PipeWire, PipeWire Pulse, and WirePlumber are treated as required. Bluetooth, CUPS, Ollama, power profiles, and firmware refresh are optional capabilities and can be selected during Guided Setup. A first-boot service verifies and starts the required set before the installed graphical login becomes the normal entry path.

## FORGE-OS top bar and native settings

The FORGE-OS bar reserves its own shell space instead of covering the normal FORGE header, so Releases, GitHub, Settings, workspace controls, and other FORGE controls remain usable.

Applications and System remain on the left. The responsive center strip launches **Network, Audio, Display, Power, Applications, Storage, Appearance, Updates, Security, Recovery, and Advanced**. Time and Session remain on the right. Lock, logout, restart, and shutdown use detached OS helpers so the requested action cannot kill its own Electron IPC response.

Native KDE/KCM/KDialog surfaces run as ordinary windows inside the same KWin Wayland compositor. `/etc/xdg/kdeglobals` supplies the FORGE dark palette and green accent so native settings/setup windows belong visually to the same environment instead of looking like an unrelated desktop.

Every shared renderer button is covered by a routing contract, and every FORGE-OS quick action maps to a fixed installed `.desktop` launcher. The goal/task `+` controls and Explorer file/folder creation use in-app dialogs rather than browser-native prompts.

## Home workspace and protected directories

FORGE-OS launches FORGE with `$HOME` as the default active workspace. The same shared FORGE runtime exposes a **Home** control on macOS, Windows, and standalone Linux. Filesystem and model tools remain relative to that active workspace; selecting Home does not grant access outside it.

Some rootless container stores intentionally contain unreadable overlay directories. Explorer loads folders on demand; bounded memory and model `file.list`/`file.search` discovery skip `EACCES`/`EPERM` subtrees and `.local/share/containers` rather than aborting the whole workspace. The known failure at `.local/share/containers/storage/overlay/...` is therefore isolated while normal home files remain available.

## Advanced maintenance and rollback

Advanced opens the FORGE Maintenance Center. It exposes explicit administrator controls rather than silently granting every application root privileges:

- service manager for the allowlisted system/user units;
- authenticated unrestricted root shell (`sudo -i`);
- installed-build verification;
- repair of the current clean checkout;
- update + reinstall;
- full pre-update FORGE-OS system checkpoint rollback;
- runtime-only current/last-known-good switching;
- console recovery that disables graphical login without deleting projects or runtimes.

Before an update, FORGE-OS snapshots the FORGE-owned integration layer under `/var/lib/forge-os/checkpoints/previous`, records source/runtime provenance, and creates file and symlink integrity manifests. Full rollback verifies that checkpoint before restoring the FORGE runtime plus FORGE-owned greetd, Wayland session, services, theme, launchers, recovery helpers, and related system integration. User files/projects and package databases are intentionally outside that rollback boundary. Runtime switching is reversible: the build being left becomes the alternate last-known-good target instead of being deleted.

## Installed-system recovery

Ctrl+Alt+F2 requests the separate on-demand FORGE Recovery profile. If the graphical path itself is unhealthy, use another TTY and run:

```bash
cd ~/FORGE-OS
./scripts/disable-graphical-login.sh
```

That restores console-first access while preserving FORGE runtimes and user/project data.

## Live ISO: boot straight into Guided Setup

The Beta ISO uses a separate live-only profile. `forge-live-setup.service` first proves it is running on ArchISO, creates the locked ephemeral `forge` account, and grants passwordless sudo **only in that disposable live environment**. It then enters the same KWin Wayland/FORGE runtime with live flags.

Once KWin, Plasma services, PolicyKit, and FORGE are active, **FORGE-OS Setup opens automatically as a normal themed KDE/Qt window**. The live workspace remains available underneath. Setup provides:

- **Guided Install**;
- **Partition Disks** via KDE Partition Manager;
- **Network** settings;
- **Advanced Root Shell**;
- **Load ISO / ZIP** for a separate guarded installer bundle;
- restart/shutdown and the option to close Setup and continue using the live desktop.

Guided Install collects the mounted target, username, hostname, timezone, and optional-service checkboxes. Required boot/network/firewall/audio/greetd services are not optional. The installer still requires the new-user password and a literal `INSTALL` confirmation before target mutation.

The Beta installer intentionally **does not partition or format disks**. You prepare the disk and mount the target yourself; setup verifies the mount points, reproduces the exact FORGE runtime embedded in the ISO, installs the authoritative package/service policy, installs systemd-boot for UEFI, installs Advanced/recovery tools, enables the first-boot service verifier, and removes live-only sudo policy from the installed target.

See [Clean install from the Beta ISO](docs/CLEAN_INSTALL.md).

## Build and validate

```bash
./tests/greeter-contract.sh
FORGE_SOURCE=~/FORGE ./tests/clean-install-contract.sh
FORGE_SOURCE=~/FORGE ./tests/maintenance-contract.sh
./tests/source-verify.sh
./scripts/build-forge.sh ~/FORGE
./scripts/build-iso.sh
```

Run `./scripts/clean-build.sh` before a release ISO build. It removes only generated ArchISO profile/work/output and FORGE runtime staging beneath this repository's `build/` directory; it never touches repository source.

The ISO reports both versions (`/etc/forge-os-version` and the bundled FORGE runtime metadata). Ollama embeddings use the local loopback API when available and degrade to lexical context when offline. Linux may use Hermes ACP; macOS and Windows use their supported headless bridge while retaining FORGE context, audit, cancellation, and ToolRouter ownership.

### Native Ollama/Hermes runtime

FORGE-OS installs `config/forge-hermes.env` as `/usr/share/forge-os/forge-hermes.env` and sources it before the Wayland session starts. By default it selects the Hermes runtime through the Ollama OpenAI-compatible endpoint `http://127.0.0.1:11434/v1` and uses `llama3.2:3b`; set `FORGE_OLLAMA_MODEL` or `FORGE_HERMES_MODEL` in the session environment to choose another installed Ollama model. Native FORGE and Hermes remain interchangeable, and FORGE's shared context, intelligence layer, ToolRouter, workspace scope, policy checks, audit trail, and cancellation remain authoritative; no external Hermes process receives direct filesystem or shell access.

`build-forge.sh` and the installer use the current local FORGE worktree, including tracked edits and non-ignored untracked files, while recording the current commit only as provenance. The updater accepts detached, dirty, and divergent checkouts and never resets them to force commit parity.

The source workflow checks out the current FORGE `main` source, builds canonical tuigreet 0.11.0, validates greeter/setup/maintenance contracts, verifies that provider schemas omit runtime-only tool metadata, and then runs the complete FORGE typecheck, lint, tests, production build, package resolution, shell/TOML/unit checks, and source contract. The generated runtime records the exact source commit used for that run.

A separate GitHub Actions test-ISO workflow is allowed to publish only after that source workflow succeeds for `main`. The resulting GitHub release is a **prerelease**, never a stable release, and contains one versioned x86_64 ISO plus its checksum.

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Runtime/session contract](session/README.md)
- [User manual](docs/USER_MANUAL.md)
- [Clean install](docs/CLEAN_INSTALL.md)
- [Recovery](docs/RECOVERY.md)
- [Security model](docs/SECURITY_MODEL.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)
- [Changelog](CHANGELOG.md)
- [Implementation notes](Dev_Notes/Forge_updates.md)
