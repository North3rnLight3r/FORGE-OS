#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$EUID" -eq 0 && -z "${FORGE_UPDATE_TEST_UNPRIVILEGED:-}" ]]; then
  command -v runuser >/dev/null 2>&1 || { echo 'runuser is required to exercise the updater as a normal user.' >&2; exit 1; }
  test_home="$(mktemp -d /tmp/forge-update-test.XXXXXX)"
  chown nobody "$test_home"
  exec runuser -u nobody -- env HOME="$test_home" FORGE_UPDATE_TEST_UNPRIVILEGED=1 FORGE_UPDATE_TEST_ROOT="$test_home" bash "$0"
fi

temporary="${FORGE_UPDATE_TEST_ROOT:-$(mktemp -d)}"
cleanup() { rm -rf -- "$temporary"; }
trap cleanup EXIT

mock_bin="$temporary/mock-bin"
install -d "$mock_bin"
cat >"$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$@"
EOF
chmod 0755 "$mock_bin/sudo"
export PATH="$mock_bin:$PATH"

git_identity() {
  git -C "$1" config user.name 'FORGE Update Test'
  git -C "$1" config user.email 'forge-update-test@invalid.local'
}

create_checkout() {
  local name="$1"
  local checkout="$temporary/$name"
  git init --quiet --initial-branch=main "$checkout"
  git_identity "$checkout"
  printf '%s\n' "$name baseline" >"$checkout/state.txt"
  if [[ "$name" == FORGE-OS ]]; then
    install -d "$checkout/scripts"
    cat >"$checkout/scripts/forge-system-checkpoint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 ]] || exit 1
printf '%s %s\n' "$1" "$2" >"$FORGE_UPDATE_TEST_CHECKPOINT_MARKER"
EOF
    chmod 0755 "$checkout/scripts/forge-system-checkpoint"
    cat >"$checkout/scripts/install-forge-linux.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FORGE_UPDATE_TEST_INSTALL_FAIL:-0}" != 1 ]] || exit 42
printf '%s\n' "$(git -C "$FORGE_SOURCE_DIR" rev-parse HEAD) $(git -C "$FORGE_OS_SOURCE_DIR" rev-parse HEAD)" >"$FORGE_UPDATE_TEST_INSTALL_MARKER"
EOF
    chmod 0755 "$checkout/scripts/install-forge-linux.sh"
  fi
  git -C "$checkout" add .
  git -C "$checkout" commit --quiet -m 'initial fixture'
}

forge="$temporary/FORGE"
forge_os="$temporary/FORGE-OS"
marker="$temporary/installed"
checkpoint_marker="$temporary/checkpointed"
create_checkout FORGE
create_checkout FORGE-OS

# Detached, dirty, divergent, or remote-less checkouts are all valid. The
# updater must install the exact local commits and must not invoke Git network
# operations at all.
git -C "$forge" switch --detach --quiet HEAD
printf '%s\n' local-edit >>"$forge/state.txt"
git -C "$forge_os" commit --quiet --allow-empty -m 'local update'
git -C "$forge_os" switch --detach --quiet HEAD
touch "$forge_os/local-untracked"

env HOME="$temporary" FORGE_SOURCE_DIR="$forge" FORGE_OS_SOURCE_DIR="$forge_os" FORGE_UPDATE_TEST_MARKER=unused FORGE_UPDATE_TEST_INSTALL_MARKER="$marker" FORGE_UPDATE_TEST_CHECKPOINT_MARKER="$checkpoint_marker" "$root/scripts/forge-os-update" >/dev/null
[[ -s "$marker" && -s "$checkpoint_marker" ]] || { echo 'Updater did not checkpoint and install the current local source.' >&2; exit 1; }
read -r installed_forge installed_os <"$marker"
[[ "$installed_forge" == "$(git -C "$forge" rev-parse HEAD)" && "$installed_os" == "$(git -C "$forge_os" rev-parse HEAD)" ]] || { echo 'Updater installed a source ref other than the current local checkout.' >&2; exit 1; }
[[ -e "$forge_os/local-untracked" && "$(<"$forge/state.txt")" == *local-edit ]] || { echo 'Updater did not preserve local source state.' >&2; exit 1; }

rm -f "$marker" "$checkpoint_marker"
set +e
env HOME="$temporary" FORGE_SOURCE_DIR="$forge" FORGE_OS_SOURCE_DIR="$forge_os" FORGE_UPDATE_TEST_INSTALL_MARKER="$marker" FORGE_UPDATE_TEST_CHECKPOINT_MARKER="$checkpoint_marker" FORGE_UPDATE_TEST_INSTALL_FAIL=1 "$root/scripts/forge-os-update" >/dev/null 2>"$temporary/failure.err"
status=$?
set -e
[[ "$status" -eq 42 && -s "$checkpoint_marker" && ! -e "$marker" ]] || { echo 'Failed install did not preserve checkpoint ordering or failure status.' >&2; sed -n '1,120p' "$temporary/failure.err" >&2; exit 1; }

echo 'PASS: updater installs the exact current local FORGE and FORGE-OS checkouts without remote fetch, merge, reset, or stale release artifacts'
