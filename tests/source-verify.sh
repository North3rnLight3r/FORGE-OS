#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
forge_source="${FORGE_SOURCE:-$HOME/FORGE}"
failures=0
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
check() { if "$@" >/dev/null 2>&1; then pass "$*"; else fail "$*"; fi; }

while IFS= read -r file; do check bash -n "$file"; done < <(find "$root/scripts" "$root/session" "$root/tests" -maxdepth 1 -type f -exec awk 'NR == 1 && /bash/ { print FILENAME; exit }' {} \; | sort)
check bash -n "$root/install.sh"
check bash -n "$root/update.sh"
check "$root/tests/session-dispatcher.sh"
check "$root/tests/update-transaction.sh"
if [[ -n "${TUIGREET_BIN:-}" || -x /usr/local/bin/tuigreet ]] || command -v tuigreet >/dev/null 2>&1; then
  check "$root/tests/greeter-contract.sh"
else
  pass 'installed tuigreet runtime contract deferred to the Arch source gate'
fi
check env FORGE_SOURCE="$forge_source" "$root/tests/clean-install-contract.sh"
check env FORGE_SOURCE="$forge_source" "$root/tests/maintenance-contract.sh"
check env FORGE_SOURCE="$forge_source" "$root/tests/hermes-runtime-contract.sh"
python_bin="$(command -v python3 || command -v python || true)"
[[ -n "$python_bin" ]] && check "$python_bin" -c 'import tomllib,sys; [tomllib.load(open(p, "rb")) for p in sys.argv[1:]]' "$root/config/greetd-config.toml" "$root/config/forge-recovery-greetd.toml" "$root/config/forge-live-greetd.toml" || fail 'Python 3 with tomllib is required for TOML validation'
if command -v systemd-analyze >/dev/null 2>&1; then
  check systemd-analyze verify "$root/config/forge-recovery.service"
else
  pass 'systemd unit verification deferred to the Linux source gate'
fi

# systemd-analyze also resolves ExecStart binaries. The live helper is staged
# into /usr/local/libexec only by the ISO/installer, so validate the source unit
# syntax with a temporary /usr/bin/true ExecStart and separately assert the real
# path plus script contract. This avoids pretending a CI container is an
# installed FORGE-OS root while still checking both halves of the unit.
live_unit_tmp="$(mktemp "${TMPDIR:-/tmp}/forge-live-unit.XXXXXX.service")"
trap 'rm -f -- "$live_unit_tmp"' EXIT
sed 's#^ExecStart=.*#ExecStart=/usr/bin/true#' "$root/config/forge-live-setup.service" >"$live_unit_tmp"
if command -v systemd-analyze >/dev/null 2>&1; then check systemd-analyze verify "$live_unit_tmp"; fi
grep -Fqx 'ExecStart=/usr/local/libexec/forge-live-setup' "$root/config/forge-live-setup.service" && pass 'live setup unit points at packaged helper' || fail 'live setup unit ExecStart is wrong'
check bash -n "$root/scripts/forge-live-setup"

grep -Fq -- "--cmd '/usr/local/bin/forge-wayland-session'" "$root/config/greetd-config.toml" && pass 'F2/default command is canonical Wayland path' || fail 'F2/default command is wrong'
grep -Fq -- '--background matrix' "$root/config/greetd-config.toml" && grep -Fq -- '--kb-background 4' "$root/config/greetd-config.toml" && pass 'Matrix default and F4 background selector are configured' || fail 'Matrix/F4 greeter behavior is incomplete'
grep -Fq -- '--doom-height 7' "$root/config/greetd-config.toml" && pass 'DOOM fire tuning is configured for F4' || fail 'DOOM fire configuration is missing'
if grep -Fq -- '--remember-session' "$root/config/greetd-config.toml"; then fail 'greeter can remember and override an old session path'; else pass 'greeter cannot override canonical path with remembered session'; fi
grep -Fqx 'Exec=/usr/local/bin/forge-wayland-session' "$root/session/forge.desktop" && pass 'F3 FORGE entry uses canonical Wayland path' || fail 'F3 FORGE entry exposes a stale dispatcher path'
grep -Fq 'exec "$forge_session"' "$root/session/startplasma-wayland" && pass 'legacy dispatcher remains available only as compatibility implementation' || fail 'compatibility dispatcher is broken'
grep -Fqx 'unset WAYLAND_DISPLAY DISPLAY XAUTHORITY' "$root/session/forge-wayland-session" && grep -Fqx 'unset WAYLAND_DISPLAY DISPLAY XAUTHORITY' "$root/session/forge-recovery-session" && pass 'top-level compositors discard stale display sockets' || fail 'session compositor can inherit a stale or nested display'
grep -Fq 'FORGE_SESSION_LOCALE:-en_US.UTF-8' "$root/session/forge-wayland-session" && pass 'FORGE session always exports a UTF-8 locale' || fail 'FORGE session can start with the non-UTF-8 C locale'

grep -Fqx 'Alias=autovt@tty2.service' "$root/config/forge-recovery.service" && pass 'recovery is on-demand tty2 alias' || fail 'recovery alias is wrong'
if grep -Fq 'WantedBy=graphical.target' "$root/config/forge-recovery.service"; then fail 'recovery is pulled into every graphical boot'; else pass 'recovery remains on-demand'; fi
grep -Fq 'FORGE_LIVE_RECOVERY=1' "$root/config/forge-live-greetd.toml" && pass 'live greeter enters dedicated setup/recovery mode' || fail 'live recovery flag is missing'
grep -Fq 'passwd --lock "$live_user"' "$root/scripts/forge-live-setup" && grep -Fq 'NOPASSWD: ALL' "$root/scripts/forge-live-setup" && pass 'live account is locked and sudo is explicitly live-scoped' || fail 'live account privilege boundary is wrong'
grep -Fq 'forge-live-setup-ui' "$root/scripts/build-iso.sh" && grep -Fq 'forge-live-guided-install' "$root/scripts/build-iso.sh" && grep -Fq 'forge-live-install' "$root/scripts/build-iso.sh" && pass 'ISO contains Guided Setup and recovery bundle helpers' || fail 'ISO omits live setup/recovery helpers'

if command -v desktop-file-validate >/dev/null 2>&1; then
  while IFS= read -r desktop; do check desktop-file-validate "$desktop"; done < <(find "$root/session" -maxdepth 1 -name '*.desktop' -type f | sort)
fi

for required in rust fish starship reflector pacman-contrib sudo partitionmanager plasma-firewall firewalld distrobox podman nix ollama ollama-vulkan gamescope gamemode mangohud wine-staging arch-install-scripts efibootmgr dosfstools gptfdisk; do
  grep -Fqx "$required" "$root/manifests/arch-packages.txt" && pass "manifest declares $required" || fail "manifest is missing $required"
done
if grep -Fqx greetd-tuigreet "$root/manifests/arch-packages.txt"; then fail 'legacy official tuigreet package remains in official manifest'; else pass 'tuigreet is managed as a pinned canonical source build'; fi
grep -Fq 'TUIGREET_VERSION=0.11.0' "$root/scripts/configure-aur.sh" && grep -Fq 'TUIGREET_COMMIT=6fb15fffb794c6bd357164347d8b6d9e0aa92bbc' "$root/scripts/configure-aur.sh" && pass 'canonical tuigreet release and commit are pinned' || fail 'canonical tuigreet pin is incomplete'
grep -Fq 'https://github.com/tuigreet/tuigreet.git' "$root/scripts/configure-aur.sh" && pass 'canonical tuigreet upstream is configured' || fail 'tuigreet still references obsolete fork upstream'
grep -Fq 'cargo build --locked --release' "$root/scripts/configure-aur.sh" && pass 'canonical tuigreet uses a locked source build' || fail 'tuigreet source build is not locked'
grep -Fq 'greetd-tuigreet-fork-git' "$root/scripts/configure-aur.sh" && grep -Fq 'greetd-tuigreet-fork-bin' "$root/scripts/configure-aur.sh" && pass 'obsolete fork packages are removed during migration' || fail 'obsolete tuigreet package migration is incomplete'
grep -Fq 'chaotic-aur' "$root/scripts/configure-aur.sh" && grep -Fq '3056513887B78AEB' "$root/scripts/configure-aur.sh" && pass 'Chaotic-AUR bootstrap is explicit and pinned to primary key' || fail 'Chaotic-AUR bootstrap is incomplete'
grep -Fq 'yay-bin' "$root/scripts/configure-aur.sh" && pass 'AUR helper is provisioned' || fail 'AUR helper is missing'
grep -Fq 'install_reference_mirrors' "$root/scripts/bootstrap-forgeos.sh" && grep -Fq 'refresh_ranked_mirrors' "$root/scripts/bootstrap-forgeos.sh" && pass 'bootstrap uses tracked mirror baseline plus reflector ranking' || fail 'mirror bootstrap is incomplete'
[[ "$(awk '/^Server[[:space:]]*=/{print; exit}' "$root/config/mirrorlist")" == 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' ]] && pass 'official Tier 1 Arch geo mirror leads the tracked baseline' || fail 'tracked mirror baseline can prefer a stale community mirror'
grep -Fq "pacman -Si --config \"\$profile/pacman.conf\" broadcom-wl" "$root/scripts/build-iso.sh" && grep -Fq "sed -i '/^broadcom-wl\$/d'" "$root/scripts/build-iso.sh" && pass 'ISO tolerates upstream broadcom module transitions' || fail 'optional upstream broadcom module can block ISO publication'
grep -Fq 'split --bytes=1900M' "$root/.github/workflows/release.yml" && grep -Fq 'gh release upload v2.5.0-beta' "$root/.github/workflows/release.yml" && pass 'ISO publisher handles GitHub asset size limits' || fail 'ISO publisher cannot handle oversized GitHub assets'

service_manifest="$root/manifests/system-services.tsv"
[[ -r "$service_manifest" ]] && pass 'authoritative service manifest exists' || fail 'authoritative service manifest is missing'
grep -Fq 'manifest="$root/manifests/system-services.tsv"' "$root/scripts/configure-hardware.sh" && pass 'hardware/service stage consumes authoritative manifest' || fail 'configure-hardware does not consume service manifest'
grep -Fq '/etc/xdg/reflector/reflector.conf' "$root/scripts/configure-hardware.sh" && grep -Fq 'system|reflector.timer|required|' "$service_manifest" && pass 'Reflector policy and persistent timer are authoritative' || fail 'persistent mirror refresh policy is missing'

for unit in NetworkManager.service firewalld.service irqbalance.service systemd-timesyncd.service fstrim.timer reflector.timer; do
  grep -Fq "system|$unit|required|" "$service_manifest" && pass "required service policy includes $unit" || fail "required service policy missing $unit"
done
for unit in bluetooth.service cups.service ollama.service power-profiles-daemon.service fwupd-refresh.timer; do
  grep -Fq "system|$unit|optional|" "$service_manifest" && pass "optional service policy includes $unit" || fail "optional service policy missing $unit"
done
for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
  grep -Fq "global|$unit|required|" "$service_manifest" && pass "required global user service policy includes $unit" || fail "global user service policy missing $unit"
done
grep -Fq 'systemctl --global enable' "$root/scripts/configure-hardware.sh" && pass 'user audio service enablement persists across sessions' || fail 'global user service enablement is missing'
grep -Fq 'forge-first-boot.service' "$root/scripts/forge-clean-install-wrapper" && grep -Fq 'required_units=' "$root/scripts/forge-first-boot" && pass 'clean install enables first-boot required-service verification' || fail 'first-boot service verification is incomplete'

grep -Fq 'function pacman' "$root/config/forge-dr460nized.fish" && grep -Fq '/usr/local/bin/forge-install-pkg --backend arch' "$root/config/forge-dr460nized.fish" && pass 'interactive pacman routes through FORGE' || fail 'interactive pacman bypasses FORGE wrapper'
grep -Fq 'NPM_CONFIG_PREFIX "$HOME/.local"' "$root/config/forge-dr460nized.fish" && grep -Fq 'NPM_CONFIG_PREFIX: userPrefix' "$forge_source/packages/shell/src/index.ts" && pass 'npm global tools use the user-owned ~/.local prefix in FORGE and Konsole' || fail 'npm global tools can still target root-owned system paths'
grep -Fq 'sudo chown -R "$USER:$(id -gn)" "$user_path"' "$root/scripts/configure-user-desktop.sh" && grep -Fq '"$HOME/.local/bin"' "$root/scripts/configure-user-desktop.sh" && pass 'desktop setup repairs npm ownership and provisions the user executable path' || fail 'desktop setup does not repair user npm ownership'
grep -Fq 'exec /usr/local/bin/forge-app-install -S' "$root/scripts/forge-install-program" && pass 'program install routes through forge-app-install' || fail 'program install routing is broken'
grep -Fq '/usr/local/bin/forge-install-pkg "$@"' "$root/scripts/forge-app-install" && pass 'app install routes through forge-install-pkg' || fail 'app install routing is broken'
grep -Fq 'exec pkexec /usr/bin/pacman "$@"' "$root/scripts/forge-install-pkg" && pass 'Arch mutations cross PolicyKit wrapper' || fail 'Arch package mutation boundary is missing'

for stage in bootstrap-forgeos.sh configure-hardware.sh build-forge.sh install-runtime.sh configure-user-desktop.sh; do
  grep -Fq "$stage" "$root/scripts/install-forge-linux.sh" && pass "installer retains stage $stage" || fail "installer orphaned stage $stage"
done
grep -Fq 'forge-system-surface' "$root/scripts/install-forge-linux.sh" && grep -Fq 'forge-session-control' "$root/scripts/install-forge-linux.sh" && pass 'installer deploys system/session helpers' || fail 'installer omits system/session helpers'
grep -Fq 'forge-internal-' "$root/scripts/install-forge-linux.sh" && pass 'installer deploys hidden internal launcher contract' || fail 'internal launcher deployment is missing'
grep -Fq 'find /var/cache/tuigreet' "$root/scripts/install-forge-linux.sh" && pass 'installer clears stale greeter command/session cache' || fail 'stale greeter paths can survive install'
grep -Fq 'readlink -f /usr/local/bin/tuigreet' "$root/scripts/build-iso.sh" && pass 'ISO embeds verified canonical tuigreet binary' || fail 'ISO can package wrong tuigreet binary'
grep -Fq 'record_overlay_executable_permissions' "$root/scripts/build-iso.sh" && grep -Fq 'verify_squashfs_executables' "$root/scripts/build-iso.sh" && pass 'ISO preserves and verifies executable modes' || fail 'ISO executable verification is incomplete'
grep -Fq 'usr/local/bin/forge-live-setup-ui' "$root/scripts/build-iso.sh" && grep -Fq 'usr/local/bin/forge-maintenance-center' "$root/scripts/build-iso.sh" && pass 'ISO verifies setup and Advanced helpers inside SquashFS' || fail 'ISO does not verify setup/Advanced executable staging'

grep -Fq "['Network', 'network']" "$forge_source/apps/desktop/src/renderer/src/components/ForgeOsShell.tsx" && grep -Fq "['Advanced', 'advanced']" "$forge_source/apps/desktop/src/renderer/src/components/ForgeOsShell.tsx" && pass 'top bar declares complete quick system surface range' || fail 'top bar system surface range is incomplete'
for surface in network audio display power applications storage appearance updates security recovery advanced; do
  desktop="$root/session/forge-internal-$surface.desktop"
  [[ -r "$desktop" ]] && grep -Fqx "Exec=/usr/local/bin/forge-system-surface $surface" "$desktop" && grep -Fq "  $surface)" "$root/scripts/forge-system-surface" && pass "top bar route is complete for $surface" || fail "top bar route is incomplete for $surface"
done
for action in lock logout restart shutdown; do
  desktop="$root/session/forge-internal-session-$action.desktop"
  action_pattern="  $action)"
  [[ "$action" == restart || "$action" == shutdown ]] && action_pattern='  restart|shutdown)'
  [[ -r "$desktop" ]] && grep -Fqx "Exec=/usr/local/bin/forge-session-control $action" "$desktop" && grep -Fq "$action_pattern" "$root/scripts/forge-session-control" && pass "session route is complete for $action" || fail "session route is incomplete for $action"
done
grep -Fq 'forge-internal-session-logout.desktop' "$forge_source/apps/desktop/src/renderer/src/components/ForgeOsShell.tsx" && grep -Fq 'forge-internal-session-shutdown.desktop' "$forge_source/apps/desktop/src/renderer/src/components/ForgeOsShell.tsx" && pass 'session UI uses detached OS helpers' || fail 'session UI still depends on fragile synchronous power IPC'
grep -Fq 'forge-os-shell-active' "$forge_source/apps/desktop/src/renderer/src/components/ForgeOsShell.tsx" && grep -Fq 'margin-top: 50px' "$forge_source/apps/desktop/src/renderer/src/styles/forge-os.css" && pass 'FORGE OS top bar reserves layout space instead of covering app header' || fail 'top bar can overlap application controls'
grep -Fq 'overflow-x: auto' "$forge_source/apps/desktop/src/renderer/src/styles/forge-os.css" && grep -Fq 'font-size: clamp' "$forge_source/apps/desktop/src/renderer/src/styles/forge-os.css" && pass 'top bar scales fonts and scrolls instead of overlapping' || fail 'top bar responsive scaling is incomplete'
grep -Fq 'rescaleOverlappingGlyphs: true' "$forge_source/apps/desktop/src/renderer/src/components/TerminalPanel.tsx" && grep -Fq 'terminal.current?.reset()' "$forge_source/apps/desktop/src/renderer/src/components/TerminalPanel.tsx" && grep -Fq 'bottom-terminal-view' "$forge_source/apps/desktop/src/renderer/src/App.tsx" && pass 'integrated terminal preserves parser state and stable glyph metrics' || fail 'integrated terminal rendering/parser lifecycle regression'
grep -Fq 'trustedInternalApplication' "$forge_source/packages/os-integration/src/index.ts" && pass 'hidden fixed launchers have a trusted system-only bypass' || fail 'internal system launcher trust boundary is missing'
grep -Fq 'liveRecoveryMode' "$forge_source/packages/os-integration/src/index.ts" && grep -Fq 'Setup & Recovery' "$forge_source/apps/desktop/src/renderer/src/components/ForgeOsShell.tsx" && grep -Fq 'forge-live-setup.desktop' "$forge_source/apps/desktop/src/renderer/src/components/ForgeOsShell.tsx" && pass 'live Setup & Recovery GUI remains present' || fail 'live setup/recovery GUI is missing'
if grep -R --include='*.tsx' -Fq 'window.prompt' "$forge_source/apps/desktop/src/renderer/src"; then fail 'renderer still depends on browser-native text prompts'; else pass 'renderer text creation actions use in-app dialogs'; fi
grep -Fq "openWorkspaceFrom('workspace.open.home', forgeInvoke)" "$forge_source/apps/desktop/src/renderer/src/App.tsx" && grep -Fq "workspaceOpenHome: 'workspace.open.home'" "$forge_source/packages/ipc/src/index.ts" && pass 'Home workspace control has typed IPC' || fail 'Home workspace control is not fully routed'
grep -Fq '.local[/]share[/]containers' "$forge_source/packages/workspace/src/index.ts" && grep -Fq "'EACCES', 'EPERM', 'ENOENT'" "$forge_source/packages/workspace/src/index.ts" && pass 'home workspace traversal skips protected container paths' || fail 'home workspace permission recovery is missing'
grep -Fq 'INTERNAL_PROVIDER_ARGUMENTS' "$forge_source/packages/agent-tools/src/index.ts" && grep -Fq "'originatingConversationId'" "$forge_source/packages/agent-tools/src/index.ts" && grep -Fq 'modelVisibleToolSchema' "$forge_source/packages/agent-tools/src/index.ts" && pass 'provider schemas omit runtime-only tool metadata' || fail 'provider schemas still expose runtime-only tool metadata'
grep -Fq "name: 'browser.read'" "$forge_source/packages/agent-tools/src/index.ts" && pass 'bounded browser reads remain provider-neutral' || fail 'browser.read tool is missing'

grep -Fq 'forge-maintenance-center' "$root/scripts/forge-system-surface" && grep -Fq 'forge-system-rollback' "$root/scripts/forge-maintenance-center" && pass 'Advanced routes to maintenance and full-system rollback' || fail 'Advanced maintenance routing is incomplete'
grep -Fq 'forge-hermes.env' "$root/session/forge-wayland-session" && grep -Fq 'FORGE_HERMES_MODEL' "$root/config/forge-hermes.env" && grep -Fq 'http://127.0.0.1:11434/v1' "$root/config/forge-hermes.env" && pass 'FORGE-OS exports the native Ollama Hermes bridge defaults' || fail 'native Ollama Hermes bridge configuration is missing'
grep -Fq '/var/lib/forge-os/checkpoints' "$root/scripts/forge-system-checkpoint" && grep -Fq 'sha256sum -c' "$root/scripts/forge-system-rollback-apply" && pass 'pre-update system checkpoint is integrity verified' || fail 'system checkpoint/rollback integrity contract is incomplete'

[[ -r "$root/config/forge-starship.toml" ]] && grep -Fq 'STARSHIP_CONFIG /usr/share/forge-os/forge-starship.toml' "$root/config/forge-dr460nized.fish" && pass 'Fish/Starship theme wiring is complete' || fail 'Fish/Starship theme wiring is incomplete'
grep -Fq '[Colors:Selection]' "$root/config/kdeglobals" && grep -Fq 'DecorationFocus=55,220,125' "$root/config/kdeglobals" && pass 'native KDE windows use FORGE dark/green palette' || fail 'native KDE theme bridge is incomplete'

[[ "$(tr -d '[:space:]' < "$root/VERSION")" == '2.5.0-beta' ]] && pass 'current VERSION is the 2.5.0 beta release' || fail 'FORGE-OS VERSION is not 2.5.0-beta'
forge_ref="$(tr -d '[:space:]' < "$root/FORGE_REF" 2>/dev/null || true)"
[[ "$forge_ref" =~ ^[0-9a-f]{40}$ ]] && [[ "$(git -C "$forge_source" rev-parse HEAD 2>/dev/null)" == "$forge_ref" ]] && pass 'FORGE_REF pins the exact verified FORGE checkout' || fail 'FORGE_REF does not match the verified FORGE checkout'
grep -Fq "tags: ['v2.5.0-beta']" "$root/.github/workflows/release.yml" && grep -Fq 'gh release create v2.5.0-beta' "$root/.github/workflows/release.yml" && grep -Fq -- '--prerelease' "$root/.github/workflows/release.yml" && grep -Fq 'find FORGE-OS/build/iso' "$root/.github/workflows/release.yml" && pass '2.5.0 beta publication is exact-tag gated' || fail '2.5.0 beta publication gate is incomplete'

duplicates="$(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$root/manifests/arch-packages.txt" | sort | uniq -d)"
[[ -z "$duplicates" ]] && pass 'official package manifest has no duplicates' || fail "manifest duplicates: $duplicates"
if command -v /usr/bin/pacman >/dev/null 2>&1; then mapfile -t packages < <(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$root/manifests/arch-packages.txt"); check /usr/bin/pacman -Sp --needed --print-format '%n' "${packages[@]}"; fi
check "$root/scripts/runtime-source-hash.sh" "$forge_source"
check npm --prefix "$forge_source" run typecheck
check npm --prefix "$forge_source" run lint
check npm --prefix "$forge_source" test
check npm --prefix "$forge_source" run build
git -C "$root" diff --check >/dev/null && pass 'FORGE-OS diff whitespace is valid' || fail 'FORGE-OS diff contains whitespace errors'
git -C "$forge_source" diff --check >/dev/null && pass 'FORGE diff whitespace is valid' || fail 'FORGE diff contains whitespace errors'
printf 'SOURCE SUMMARY: %d failure(s)\n' "$failures"
(( failures == 0 ))
