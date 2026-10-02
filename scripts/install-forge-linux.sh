#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skip_packages=false
use_current_build=false
for argument in "$@"; do
  case "$argument" in
    --skip-packages) skip_packages=true ;;
    --use-current-build) use_current_build=true ;;
    *) echo "Unknown option: $argument" >&2; exit 64 ;;
  esac
done

target_user="${FORGE_USER:-${SUDO_USER:-$USER}}"
target_home="$(getent passwd "$target_user" | cut -d: -f6)"
[[ "$(id -u)" -ne 0 ]] || { echo 'Run this as the target desktop user; sudo is invoked only for system files.' >&2; exit 1; }
[[ -n "$target_home" && -d "$target_home" && "$target_user" != root ]] || { echo "Invalid desktop user: $target_user" >&2; exit 1; }
forge_source="${FORGE_SOURCE:-$target_home/FORGE}"

require_current_main() {
  local repository="$1" label="$2" local_head remote_head
  [[ -d "$repository/.git" ]] || { echo "$label is not a Git repository: $repository" >&2; exit 1; }
  [[ "$(git -C "$repository" branch --show-current)" == main ]] || { echo "$label must be on main for a production install." >&2; exit 1; }
  [[ -z "$(git -C "$repository" status --porcelain)" ]] || { echo "$label has uncommitted changes; refusing to package a dirty tree." >&2; exit 1; }
  git -C "$repository" fetch --quiet origin main || { echo "Unable to refresh origin/main for $label." >&2; exit 1; }
  local_head="$(git -C "$repository" rev-parse HEAD)"
  remote_head="$(git -C "$repository" rev-parse origin/main)"
  [[ "$local_head" == "$remote_head" ]] || {
    printf '%s is not current with origin/main.\n  local:  %s\n  remote: %s\n' "$label" "$local_head" "$remote_head" >&2
    echo "Run: git -C '$repository' pull --ff-only" >&2
    exit 1
  }
  printf '%s current at %s\n' "$label" "$local_head"
}

require_current_main "$root" FORGE-OS
require_current_main "$forge_source" FORGE

forge_ref="$(tr -d '[:space:]' < "$root/FORGE_REF" 2>/dev/null || true)"
forge_head="$(git -C "$forge_source" rev-parse HEAD)"
[[ "$forge_ref" =~ ^[0-9a-f]{40}$ ]] || { echo "FORGE_REF is missing or invalid: $root/FORGE_REF" >&2; exit 1; }
[[ "$forge_head" == "$forge_ref" ]] || {
  printf 'FORGE source HEAD does not match FORGE_REF.\n  HEAD: %s\n  REF:  %s\n' "$forge_head" "$forge_ref" >&2
  exit 1
}

# These are intentional installer stages, not obsolete duplicate entry points.
if [[ "$skip_packages" == false ]]; then
  "$root/scripts/bootstrap-forgeos.sh"
fi
"$root/scripts/configure-hardware.sh"

if [[ "$use_current_build" == false ]]; then
  "$root/scripts/build-forge.sh" "$forge_source"
else
  [[ -r "$root/build/latest.env" ]] || { echo 'No current local build record exists.' >&2; exit 1; }
  source "$root/build/latest.env"
  [[ "${FORGE_OS_VERSION:-}" == "$(<"$root/VERSION")" ]] || { echo 'Current build does not match this FORGE-OS version.' >&2; exit 1; }
  [[ "${FORGE_PACKAGE_SHA256:-}" == "$(sha256sum "$forge_source/package.json" | awk '{print $1}')" ]] || { echo 'Current build does not match FORGE package.json.' >&2; exit 1; }
  [[ "${FORGE_LOCK_SHA256:-}" == "$(sha256sum "$forge_source/package-lock.json" | awk '{print $1}')" ]] || { echo 'Current build does not match FORGE package-lock.json.' >&2; exit 1; }
  [[ "${FORGE_RUNTIME_SOURCE_SHA256:-}" == "$("$root/scripts/runtime-source-hash.sh" "$forge_source")" ]] || { echo 'Current build does not match FORGE runtime source.' >&2; exit 1; }
fi

"$root/scripts/install-runtime.sh"
source "$root/build/latest.env"
[[ "$FORGE_PACKAGE_SHA256" == "$(sha256sum "$forge_source/package.json" | awk '{print $1}')" ]] || { echo 'Installed build package identity is stale.' >&2; exit 1; }
[[ "$FORGE_LOCK_SHA256" == "$(sha256sum "$forge_source/package-lock.json" | awk '{print $1}')" ]] || { echo 'Installed build lockfile identity is stale.' >&2; exit 1; }
[[ "$FORGE_RUNTIME_SOURCE_SHA256" == "$("$root/scripts/runtime-source-hash.sh" "$forge_source")" ]] || { echo 'Installed build runtime source identity is stale.' >&2; exit 1; }

version="$(<"$root/VERSION")"
issue="$(mktemp)"
recovery_config="$(mktemp)"
trap 'rm -f -- "$issue" "$recovery_config"' EXIT
sed -e "s/@VERSION@/$version/g" -e "s/@SOURCE_COMMIT@/${FORGE_SOURCE_COMMIT:0:12}/g" "$root/config/issue" >"$issue"
sed -e "s/@USER@/$target_user/g" "$root/config/forge-recovery-greetd.toml" >"$recovery_config"

for command in greetd /usr/local/bin/tuigreet kwin_wayland plasmashell qdbus6 krunner kdialog konsole systemsettings kcmshell6 dbus-update-activation-environment /usr/bin/startplasma-wayland; do
  command -v "$command" >/dev/null || { echo "Required command is missing: $command" >&2; exit 1; }
done
"$root/tests/greeter-contract.sh"
for file in \
  session/forge-wayland-session session/forge-xdg-environment session/forge-wayland-client session/forge-recovery-session session/forge-recovery-client \
  session/forge-plasma-initialize session/forge-session scripts/forge-panel-manager scripts/forge-system-surface \
  scripts/forge-session-control scripts/configure-aur.sh scripts/forge-live-setup scripts/forge-live-install scripts/forge-live-select-installer; do
  bash -n "$root/$file"
done

sudo install -d -o root -g root -m 0755 \
  /usr/local/bin /usr/local/libexec /etc/greetd /etc/xdg /etc/xdg/reflector \
  /usr/share/applications /usr/share/xdg-desktop-portal /usr/share/forge-os /usr/share/forge-os/wayland-sessions

sudo install -o root -g root -m 0755 "$root/session/forge-wayland-session" /usr/local/bin/forge-wayland-session
sudo install -o root -g root -m 0755 "$root/session/forge-xdg-environment" /usr/local/libexec/forge-xdg-environment
sudo install -o root -g root -m 0755 "$root/session/startplasma-wayland" /usr/local/bin/startplasma-wayland
sudo install -o root -g root -m 0755 "$root/session/forge-session" /usr/local/bin/forge-session
sudo install -o root -g root -m 0755 "$root/session/forge-wayland-client" /usr/local/libexec/forge-wayland-client
sudo install -o root -g root -m 0755 "$root/session/forge-recovery-session" /usr/local/bin/forge-recovery-session
sudo install -o root -g root -m 0755 "$root/session/forge-recovery-client" /usr/local/libexec/forge-recovery-client
sudo install -o root -g root -m 0755 "$root/scripts/forge-runtime-rollback-activate" /usr/local/libexec/forge-runtime-rollback-activate
sudo install -o root -g root -m 0755 "$root/session/forge-plasma-initialize" /usr/local/libexec/forge-plasma-initialize

for tool in \
  forge-app-launcher forge-open forge-workspace-runner forge-install-program forge-app-install forge-install-pkg \
  forge-panel-manager forge-os-update forge-runtime-rollback forge-workspace-bootstrap forge-refresh-mirrors \
  install-wayland-stacks.sh forge-system-surface forge-session-control; do
  tool_source="$root/scripts/$tool"
  [[ "$tool" == forge-workspace-bootstrap ]] && tool_source="$root/scripts/forge-workspace-bootstrap.sh"
  sudo install -o root -g root -m 0755 "$tool_source" "/usr/local/bin/$tool"
done

sudo install -o root -g root -m 0644 "$root/config/kwinrc" /etc/xdg/kwinrc
sudo install -o root -g root -m 0644 "$root/config/kdeglobals" /etc/xdg/kdeglobals
sudo install -o root -g root -m 0644 "$root/config/reflector.conf" /etc/xdg/reflector/reflector.conf
sudo install -o root -g root -m 0644 "$root/config/forge-portals.conf" /usr/share/xdg-desktop-portal/forge-portals.conf
sudo install -o root -g root -m 0644 "$root/config/mirrorlist" /usr/share/forge-os/mirrorlist
sudo install -o root -g root -m 0644 "$root/config/forge-dr460nized.fish" /usr/share/forge-os/forge-dr460nized.fish
sudo install -o root -g root -m 0644 "$root/config/forge-starship.toml" /usr/share/forge-os/forge-starship.toml

for desktop in forge-app-launcher.desktop forge-explorer.desktop forge-system-settings.desktop forge-workspace-runner.desktop forge-install-program.desktop forge-panel-manager.desktop; do
  sudo install -o root -g root -m 0644 "$root/session/$desktop" "/usr/share/applications/$desktop"
done
for desktop in "$root"/session/forge-internal-*.desktop; do
  sudo install -o root -g root -m 0644 "$desktop" "/usr/share/applications/$(basename "$desktop")"
done
sudo install -o root -g root -m 0644 "$root/session/forge.desktop" /usr/share/forge-os/wayland-sessions/forge.desktop

# Remove retired/default-visible session paths. The installed Wayland path is
# the sole default in both F2 and the FORGE F3 session entry.
sudo rm -f /usr/share/xsessions/forge.desktop /usr/share/forge-os/xsessions/forge.desktop \
  /usr/local/bin/forge-xsession /usr/local/libexec/forge-session-client
sudo install -o root -g root -m 0644 "$root/config/greetd-config.toml" /etc/greetd/config.toml
sudo install -o root -g root -m 0644 "$recovery_config" /etc/greetd/forge-recovery.toml
sudo install -o root -g root -m 0644 "$root/config/forge-recovery.service" /etc/systemd/system/forge-recovery.service
sudo install -o root -g root -m 0644 "$issue" /etc/issue

# Reset stale remembered command/session data so a previous experimental path
# cannot override the canonical --cmd after this install. Username remembering
# resumes normally after the next successful login.
sudo install -d -o greeter -g greeter -m 0755 /var/cache/tuigreet
sudo find /var/cache/tuigreet -mindepth 1 -maxdepth 1 -type f -delete

printf '%s\n' "$version" | sudo tee /etc/forge-os-version >/dev/null
sudo chown root:root /etc/forge-os-version
sudo chmod 0644 /etc/forge-os-version
install -d -m 0700 "$target_home/.local/state/forge"

ollama_skills_root="$forge_source/apps/desktop/resources/ollama"
if [[ -r "$ollama_skills_root/skills.json" ]]; then
  install -d -m 0700 "$target_home/.config/ollama/skills/local-model-tooling/agents"
  install -m 0644 "$ollama_skills_root/skills.json" "$target_home/.config/ollama/skills.json"
  [[ ! -r "$ollama_skills_root/skills/local-model-tooling/SKILL.md" ]] || install -m 0644 "$ollama_skills_root/skills/local-model-tooling/SKILL.md" "$target_home/.config/ollama/skills/local-model-tooling/SKILL.md"
  [[ ! -r "$ollama_skills_root/skills/local-model-tooling/agents/openai.yaml" ]] || install -m 0644 "$ollama_skills_root/skills/local-model-tooling/agents/openai.yaml" "$target_home/.config/ollama/skills/local-model-tooling/agents/openai.yaml"
else
  echo 'FORGE Ollama skill bundle is not present; skipping optional skill installation.'
fi

sudo rm -f /etc/profile.d/forge-autostart.sh /etc/forge/session.env
if [[ -f "$target_home/.xinitrc" ]] && grep -q '/usr/local/bin/forge-session' "$target_home/.xinitrc" && grep -q 'FORGE_OS_SESSION=1' "$target_home/.xinitrc"; then
  rm -f "$target_home/.xinitrc"
fi

# Verify installed files before enabling the boot path.
for pair in \
  "$root/session/forge-wayland-session:/usr/local/bin/forge-wayland-session" \
  "$root/session/forge-xdg-environment:/usr/local/libexec/forge-xdg-environment" \
  "$root/session/forge-wayland-client:/usr/local/libexec/forge-wayland-client" \
  "$root/session/forge-session:/usr/local/bin/forge-session" \
  "$root/scripts/forge-system-surface:/usr/local/bin/forge-system-surface" \
  "$root/scripts/forge-session-control:/usr/local/bin/forge-session-control" \
  "$root/scripts/forge-install-program:/usr/local/bin/forge-install-program" \
  "$root/scripts/forge-install-pkg:/usr/local/bin/forge-install-pkg" \
  "$root/config/greetd-config.toml:/etc/greetd/config.toml" \
  "$root/config/reflector.conf:/etc/xdg/reflector/reflector.conf" \
  "$root/session/forge.desktop:/usr/share/forge-os/wayland-sessions/forge.desktop" \
  "$root/config/forge-recovery.service:/etc/systemd/system/forge-recovery.service"; do
  sudo cmp -s "${pair%%:*}" "${pair#*:}" || { echo "Installed file mismatch: ${pair#*:}" >&2; exit 1; }
done

installed_executable="/opt/forge/current/${FORGE_EXECUTABLE_RELATIVE_PATH}"
[[ -x "$installed_executable" && -r /opt/forge/current/resources/app.asar ]] || { echo 'Installed runtime is incomplete.' >&2; exit 1; }
[[ "$(sha256sum "$installed_executable" | awk '{print $1}')" == "$FORGE_EXECUTABLE_SHA256" ]] || { echo 'Installed FORGE executable does not match the build record.' >&2; exit 1; }
[[ "$(sha256sum /opt/forge/current/resources/app.asar | awk '{print $1}')" == "$FORGE_APP_ASAR_SHA256" ]] || { echo 'Refusing to enable greetd with stale app.asar.' >&2; exit 1; }

getent passwd greeter >/dev/null || { echo 'The dedicated greeter account is missing.' >&2; exit 1; }
grep -q '^source_profile = false$' /etc/greetd/config.toml || { echo 'greetd profile sourcing is not disabled.' >&2; exit 1; }
grep -Fq -- "--cmd '/usr/local/bin/forge-wayland-session'" /etc/greetd/config.toml || { echo 'F2/default Wayland command is wrong.' >&2; exit 1; }
grep -Fq -- '--background matrix' /etc/greetd/config.toml || { echo 'Matrix is not the default greeter background.' >&2; exit 1; }
grep -Fq -- '--kb-background 4' /etc/greetd/config.toml || { echo 'F4 background selector is missing.' >&2; exit 1; }
if grep -Fq -- '--remember-session' /etc/greetd/config.toml; then
  echo 'Session remembering can override the canonical Wayland path; refusing to enable greetd.' >&2
  exit 1
fi
grep -Fq 'Exec=/usr/local/bin/forge-wayland-session' /usr/share/forge-os/wayland-sessions/forge.desktop || { echo 'F3 FORGE session still exposes an old runtime path.' >&2; exit 1; }

sudo systemctl daemon-reload
sudo systemctl disable getty@tty1.service getty@tty2.service >/dev/null 2>&1 || true
sudo systemctl enable greetd.service
sudo rm -f /etc/systemd/system/autovt@tty2.service
sudo ln -sfn /etc/systemd/system/forge-recovery.service \
  /etc/systemd/system/autovt@tty2.service
sudo systemctl daemon-reload
sudo ln -sfn /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
sudo systemctl set-default graphical.target
sudo systemctl daemon-reload

# On a console-first install there is no graphical session to disrupt, so start
# greetd immediately. When upgrading from an active desktop/FORGE session it is
# already active or intentionally deferred until the next boot.
if ! systemctl is-active --quiet greetd.service && [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
  sudo systemctl start greetd.service
fi

"$root/scripts/configure-user-desktop.sh"
"$root/tests/verify.sh"
echo 'FORGE-OS installation verified. Required services are enabled persistently; reboot only when you want to enter a new kernel/runtime session.'
