# User manual

## Login

The normal FORGE login uses the maintained rolling tuigreet fork. **Matrix is the default background** and **F4** opens the live background selector, including the DOOM fire effect.

The authenticated command is:

```text
/usr/local/bin/forge-wayland-session
```

F2 starts with that path automatically, and the visible F3 FORGE session entry points to the same path. Session remembering is intentionally disabled so an old experimental command cannot replace it on a later boot.

## Desktop top bar

FORGE-OS reserves a separate strip above the ordinary FORGE application header. Releases, GitHub, Settings, workspace controls, and other normal FORGE controls remain visible underneath instead of being covered.

Applications and System remain on the left. The quick system strip contains launchable controls for:

**Network · Audio · Display · Power · Applications · Storage · Appearance · Updates · Security · Recovery · Advanced**

The strip scales button text and scrolls horizontally on narrower displays instead of overlapping labels or modules. Time and Session remain on the right. All eleven quick surfaces and four Session actions map to fixed installed `.desktop` launchers; the source contract verifies that each launcher reaches an installed helper.

The Session menu uses detached operating-system helpers for Lock, Log out, Restart, and Shut down. That means the requested action can terminate FORGE or the login session without breaking its own Electron IPC response first.

## Explorer and applications

FORGE Explorer is the default file workflow. FORGE-OS opens `$HOME` as the initial workspace, and the shared header's **Home** control returns to it from a narrower project workspace. **New file**, Explorer `+`, **New folder**, rename, goal/task `+`, persistent-task creation, release workflow, pause, and conversation rename use in-app dialogs routed through typed IPC. A new file opens immediately in the editor.

Applications installed with desktop entries are discovered automatically. The Applications control launches normal installed applications; the top-bar system controls use fixed internal launchers for KDE/FORGE settings surfaces.

Rootless container storage can expose protected overlay directories below `~/.local/share/containers`. Explorer loads folders on demand, while bounded memory discovery and model `file.list`/`file.search` skip unreadable or container-backed subtrees instead of failing the whole home workspace. A direct attempt to read a protected file still reports the operating-system permission error, and no tool may escape the active workspace.

## Install and update

Normal maintenance uses:

```bash
cd ~/FORGE-OS
./install.sh
```

or:

```bash
cd ~/FORGE-OS
./update.sh
```

The bootstrap/build/runtime scripts remain in the repository because the installer executes them as internal stages. A normal install provisions packages, repositories, mirrors, services, FORGE runtime files, Wayland/greetd integration, recovery, and verification.

Required system services are enabled persistently. PipeWire, PipeWire Pulse, and WirePlumber are enabled globally for user sessions; network, Bluetooth, printing, time, Ollama, trim, and mirror-refresh services/timers are enabled at the system level as appropriate.

## Packages and repositories

Inside FORGE's Fish shell, interactive `pacman` commands route through `forge-install-pkg`. GUI program installation routes through `forge-install-program`, then `forge-app-install`, then `forge-install-pkg`.

The signed-in account is an authenticated `wheel` administrator. System packages remain root-owned; sudo does not make `/usr` directly writable by the user. npm global tools use the user-owned `~/.local` prefix, which is first on the terminal `PATH`. Update Codex without sudo:

```bash
npm install --global @openai/codex@latest
command -v codex
codex --version
```

```bash
forge-app-install -S steam
forge-install-pkg -S npm
forge-install-pkg -Syu
forge-install-pkg -Ss browser
forge-install-pkg -Si package
forge-install-pkg -Rns package
```

The bootstrap enables Arch `multilib`, Chaotic-AUR, and `yay`. The rolling `greetd-tuigreet-fork-git` package is used while Matrix/F4/DOOM support is ahead of the latest tagged binary release.

Official Arch mirrors start from the tracked HTTPS baseline and are then ranked by Reflector. `reflector.timer` keeps the Arch mirror list refreshed after reboot.

Compatibility package backends remain isolated:

```bash
forge-workspace-bootstrap apt
forge-workspace-bootstrap kali
forge-workspace-bootstrap nix
forge-install-pkg --backend kali -S tool-name
forge-install-pkg --backend nix -S package-name
```

## Updates

The top-bar Updates control opens the installed `forge-os-update` workflow in Konsole. It uses the current sibling `~/FORGE` and `~/FORGE-OS` checkouts regardless of branch, commit, remote availability, or local source edits, temporarily preserves local Obsidian UI state in both repositories, and never reboots automatically. On install failure it leaves the source checkouts in their current local state and restores local `.obsidian` state.

The local or hosted model supplies only semantic tool arguments. FORGE-OS creates workspace, conversation, model, audit-reason, and active task/step execution metadata internally. With Web Research enabled, `browser.read({})` and `browser.find(...)` run as bounded automatic reads; navigation, writes, shell/process execution, destructive operations, and remote mutations keep their approval requirements.

The current source does not automatically reindex workspace memory from a filesystem watcher. Use **Reindex** when you want to refresh derived workspace knowledge.

## Installed-system recovery

Ctrl+Alt+F2 requests FORGE Recovery on demand. If the graphical stack itself is unhealthy, use another text TTY such as Ctrl+Alt+F3 and run:

```bash
~/FORGE-OS/scripts/disable-graphical-login.sh
```

This restores console-first boot without deleting runtimes or user data.

## Live ISO recovery

The FORGE-OS ISO enters **FORGE Live Recovery** using the same Wayland runtime with live-only recovery flags. The live account password is locked; greetd starts its initial session directly, and passwordless sudo exists only inside that ephemeral live environment.

The recovery screen provides:

- **Open sudo root shell**
- **Load / install ISO or ZIP**
- **Restart**
- **Shut down**

ISO files are mounted read-only. ZIP paths are validated before extraction. Automatic bundle execution is limited to recognized installer entry points and requires typing `INSTALL` first.
