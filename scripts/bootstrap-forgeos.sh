#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repository_root/manifests/arch-packages.txt"
source /etc/os-release
[[ "${ID:-}" == arch ]] || { echo 'This bootstrap supports Arch Linux only.' >&2; exit 1; }
[[ "$EUID" -ne 0 ]] || { echo 'Run this bootstrap as the desktop user; sudo is invoked only for system mutations.' >&2; exit 77; }
command -v /usr/bin/pacman >/dev/null || { echo 'The Arch package backend is required.' >&2; exit 1; }
mapfile -t packages < <(sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$manifest")
(( ${#packages[@]} > 0 )) || { echo 'Package manifest is empty.' >&2; exit 1; }

enable_multilib() {
  local pacman_config=/etc/pacman.conf staged
  /usr/bin/pacman-conf --repo-list | grep -Fxq multilib && return
  grep -Fxq '#[multilib]' "$pacman_config" || {
    echo 'The canonical commented [multilib] section is missing from /etc/pacman.conf; refusing an ambiguous edit.' >&2
    exit 1
  }
  staged="$(mktemp)"
  awk '
    $0 == "#[multilib]" { in_multilib = 1; print "[multilib]"; next }
    in_multilib && $0 == "#Include = /etc/pacman.d/mirrorlist" {
      print "Include = /etc/pacman.d/mirrorlist"
      in_multilib = 0
      enabled = 1
      next
    }
    { print }
    END { if (!enabled) exit 42 }
  ' "$pacman_config" >"$staged" || {
    rm -f -- "$staged"
    echo 'Unable to enable the canonical [multilib] mirror include.' >&2
    exit 1
  }
  /usr/bin/pacman-conf --config "$staged" --repo-list | grep -Fxq multilib || {
    rm -f -- "$staged"
    echo 'The staged pacman configuration does not expose [multilib].' >&2
    exit 1
  }
  sudo install -o root -g root -m 0644 "$staged" "$pacman_config"
  rm -f -- "$staged"
  echo 'Enabled the official Arch [multilib] repository.'
}

install_reference_mirrors() {
  [[ "${FORGE_PRESERVE_MIRRORS:-0}" != 1 ]] || { echo 'Preserving current mirrorlist by explicit request.'; return; }
  grep -q '^Server = https://' "$repository_root/config/mirrorlist" || { echo 'Tracked mirror list contains no HTTPS servers.' >&2; exit 1; }
  sudo install -o root -g root -m 0644 "$repository_root/config/mirrorlist" /etc/pacman.d/mirrorlist
  echo 'Installed tracked FORGE-OS HTTPS mirrors as the bootstrap baseline.'
}

refresh_ranked_mirrors() {
  command -v reflector >/dev/null 2>&1 || return 0
  [[ "${FORGE_PRESERVE_MIRRORS:-0}" != 1 ]] || {
    echo 'Preserving current mirrorlist by explicit request.'
    return 0
  }
  local temporary reflector_timeout="${FORGE_REFLECTOR_TIMEOUT_SECONDS:-30}" status
  [[ "$reflector_timeout" =~ ^[1-9][0-9]*$ ]] || {
    echo 'Warning: FORGE_REFLECTOR_TIMEOUT_SECONDS is invalid; using 30 seconds.' >&2
    reflector_timeout=30
  }
  temporary="$(mktemp)"
  if timeout --foreground "${reflector_timeout}s" reflector \
    --connection-timeout 3 --download-timeout 3 --threads 8 \
    --country 'United States' --age 24 --latest 30 --protocol https --sort rate --save "$temporary" \
    && grep -q '^Server = https://' "$temporary"; then
    sudo install -o root -g root -m 0644 "$temporary" /etc/pacman.d/mirrorlist
    echo 'Ranked current U.S. HTTPS Arch mirrors with reflector.'
  else
    status=$?
    if [[ "$status" -eq 124 ]]; then
      echo "Warning: reflector refresh timed out after ${reflector_timeout}s; retaining the current mirrorlist." >&2
    else
      echo 'Warning: reflector refresh failed; retaining the current mirrorlist.' >&2
    fi
  fi
  rm -f -- "$temporary"
}

enable_multilib
install_reference_mirrors

legacy_x11=(xorg-server xorg-xinit openbox kwin-x11 thunar thunar-volman dunst xclip polkit-gnome)
installed_legacy=()
for package in "${legacy_x11[@]}"; do
  /usr/bin/pacman -Q "$package" >/dev/null 2>&1 && installed_legacy+=("$package")
done
if (( ${#installed_legacy[@]} > 0 )); then
  echo "Removing retired X11 session packages: ${installed_legacy[*]}"
  sudo /usr/bin/pacman -Rns --noconfirm "${installed_legacy[@]}"
fi

echo "Installing ${#packages[@]} official packages from $manifest"
sudo /usr/bin/pacman -Syu --needed --noconfirm "${packages[@]}"
refresh_ranked_mirrors
"$repository_root/scripts/configure-aur.sh"

for repository in core extra multilib; do
  /usr/bin/pacman-conf --repo-list | grep -Fxq "$repository" || { echo "Required pacman repository is disabled: $repository" >&2; exit 1; }
done
if [[ "${FORGE_DISABLE_CHAOTIC_AUR:-0}" != 1 ]]; then
  /usr/bin/pacman-conf --repo-list | grep -Fxq chaotic-aur || { echo 'Chaotic-AUR repository was not enabled.' >&2; exit 1; }
fi

echo 'FORGE-OS package, mirror, AUR, and greeter bootstrap complete.'
