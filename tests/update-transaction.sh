#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The real updater deliberately refuses EUID 0. GitHub Actions runs the Arch
# container as root, so re-enter this test as an unprivileged account instead
# of weakening the production root-safety contract just to satisfy CI.
if [[ "$EUID" -eq 0 && -z "${FORGE_UPDATE_TEST_UNPRIVILEGED:-}" ]]; then
  command -v runuser >/dev/null 2>&1 || { echo 'runuser is required to exercise the updater as a normal user.' >&2; exit 1; }
  test_home="$(mktemp -d /tmp/forge-update-test.XXXXXX)"
  unprivileged_user=nobody
  chown "$unprivileged_user" "$test_home"
  exec runuser -u "$unprivileged_user" -- env \
    HOME="$test_home" \
    FORGE_UPDATE_TEST_UNPRIVILEGED=1 \
    FORGE_UPDATE_TEST_ROOT="$test_home" \
    bash "$0"
fi

temporary="${FORGE_UPDATE_TEST_ROOT:-$(mktemp -d)}"
cleanup() { rm -rf -- "$temporary"; }
trap cleanup EXIT

# The production updater crosses sudo only for the root-owned pre-update
# checkpoint. The transaction test runs as nobody and uses a disposable PATH
# shim that simply executes the fixture checkpoint helper. This keeps the test
# focused on updater ordering/rollback without weakening the real sudo boundary.
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

create_fixture() {
  local name="$1" expected_url="$2"
  local seed="$temporary/seed-$name" bare="$temporary/$name.git" checkout="$temporary/checkout-$name" publisher="$temporary/publisher-$name"
  git init --quiet --initial-branch=main "$seed"
  git_identity "$seed"
  printf '%s\n' "$name baseline" >"$seed/state.txt"
  if [[ "$name" == FORGE-OS ]]; then
    install -d "$seed/scripts"
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '[[ "${FORGE_UPDATE_TEST_INSTALL_FAIL:-0}" != 1 ]] || exit 42' 'touch "$FORGE_UPDATE_TEST_MARKER"' >"$seed/scripts/install-forge-linux.sh"
    chmod 0755 "$seed/scripts/install-forge-linux.sh"
    cat >"$seed/scripts/forge-system-checkpoint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 && "$1" =~ ^[0-9a-f]{40}$ && "$2" =~ ^[0-9a-f]{40}$ ]]
[[ -n "${FORGE_UPDATE_TEST_CHECKPOINT_MARKER:-}" ]] && printf '%s %s\n' "$1" "$2" >"$FORGE_UPDATE_TEST_CHECKPOINT_MARKER"
EOF
    chmod 0755 "$seed/scripts/forge-system-checkpoint"
  fi
  git -C "$seed" add .
  git -C "$seed" commit --quiet -m 'initial fixture'
  git clone --quiet --bare "$seed" "$bare"
  git clone --quiet "$bare" "$checkout"
  git clone --quiet "$bare" "$publisher"
  git_identity "$checkout"
  git_identity "$publisher"

  # The test intentionally rewrites the trusted HTTPS origin to a local bare
  # repository. This opt-in applies only to disposable fixtures; production
  # updater origin policy remains pinned to the trusted HTTPS repositories.
  git -C "$checkout" config protocol.file.allow always
  git -C "$publisher" config protocol.file.allow always
  git -C "$checkout" remote set-url origin "$expected_url"
  git -C "$checkout" config "url.file://$bare.insteadOf" "$expected_url"
}

publish_change() {
  local publisher="$1" label="$2"
  printf '%s\n' "$label" >>"$publisher/state.txt"
  git -C "$publisher" add state.txt
  git -C "$publisher" commit --quiet -m "$label"
  git -C "$publisher" push --quiet origin main
}

expect_failure() {
  local expected="$1"; shift
  set +e
  "$@" >"$temporary/failure.out" 2>"$temporary/failure.err"
  local status=$?
  set -e
  [[ "$status" -eq "$expected" ]] || {
    echo "Expected exit $expected, received $status" >&2
    sed -n '1,160p' "$temporary/failure.err" >&2
    exit 1
  }
}

forge="$temporary/checkout-FORGE"
forge_os="$temporary/checkout-FORGE-OS"
forge_publisher="$temporary/publisher-FORGE"
os_publisher="$temporary/publisher-FORGE-OS"
forge_url='https://github.com/North3rnLight3r/FORGE.git'
os_url='https://github.com/North3rnLight3r/FORGE-OS.git'
marker="$temporary/installed"
checkpoint_marker="$temporary/checkpointed"

create_fixture FORGE "$forge_url"
create_fixture FORGE-OS "$os_url"

touch "$forge/dirty-untracked"
expect_failure 65 env HOME="$temporary" FORGE_SOURCE_DIR="$forge" FORGE_OS_SOURCE_DIR="$forge_os" FORGE_UPDATE_TEST_MARKER="$marker" FORGE_UPDATE_TEST_CHECKPOINT_MARKER="$checkpoint_marker" "$root/scripts/forge-os-update"
rm "$forge/dirty-untracked"

git -C "$forge" config remote.origin.url 'https://untrusted.invalid/FORGE.git'
expect_failure 65 env HOME="$temporary" FORGE_SOURCE_DIR="$forge" FORGE_OS_SOURCE_DIR="$forge_os" FORGE_UPDATE_TEST_MARKER="$marker" FORGE_UPDATE_TEST_CHECKPOINT_MARKER="$checkpoint_marker" "$root/scripts/forge-os-update"
git -C "$forge" config remote.origin.url "$forge_url"

publish_change "$forge_publisher" 'remote-divergence'
git -C "$forge" commit --quiet --allow-empty -m 'local divergence'
expect_failure 65 env HOME="$temporary" FORGE_SOURCE_DIR="$forge" FORGE_OS_SOURCE_DIR="$forge_os" FORGE_UPDATE_TEST_MARKER="$marker" FORGE_UPDATE_TEST_CHECKPOINT_MARKER="$checkpoint_marker" "$root/scripts/forge-os-update"
git -C "$forge" fetch --quiet origin main
git -C "$forge" reset --quiet --hard origin/main

install -d "$forge/.obsidian" "$forge_os/.obsidian"
printf '%s\n' 'local FORGE graph state' >"$forge/.obsidian/graph.json"
printf '%s\n' 'local FORGE-OS workspace state' >"$forge_os/.obsidian/workspace.json"

publish_change "$forge_publisher" 'transaction candidate'
publish_change "$os_publisher" 'transaction candidate'
forge_before="$(git -C "$forge" rev-parse HEAD)"
os_before="$(git -C "$forge_os" rev-parse HEAD)"
expect_failure 42 env HOME="$temporary" FORGE_SOURCE_DIR="$forge" FORGE_OS_SOURCE_DIR="$forge_os" FORGE_UPDATE_TEST_MARKER="$marker" FORGE_UPDATE_TEST_CHECKPOINT_MARKER="$checkpoint_marker" FORGE_UPDATE_TEST_INSTALL_FAIL=1 "$root/scripts/forge-os-update"
[[ -s "$checkpoint_marker" ]] || { echo 'Updater did not create the pre-update checkpoint before installation.' >&2; exit 1; }
read -r checkpoint_forge checkpoint_os <"$checkpoint_marker"
[[ "$checkpoint_forge" == "$forge_before" && "$checkpoint_os" == "$os_before" ]] || { echo 'Checkpoint did not record both pre-update source commits.' >&2; exit 1; }
[[ "$(git -C "$forge" rev-parse HEAD)" == "$forge_before" && "$(git -C "$forge_os" rev-parse HEAD)" == "$os_before" ]] || { echo 'Failed install did not restore both source commits.' >&2; exit 1; }
[[ ! -e "$marker" ]] || { echo 'Failed installer unexpectedly produced its success marker.' >&2; exit 1; }
[[ "$(<"$forge/.obsidian/graph.json")" == 'local FORGE graph state' && "$(<"$forge_os/.obsidian/workspace.json")" == 'local FORGE-OS workspace state' ]] || { echo 'Failed update did not preserve local Obsidian state.' >&2; exit 1; }

rm -f "$checkpoint_marker"
env HOME="$temporary" FORGE_SOURCE_DIR="$forge" FORGE_OS_SOURCE_DIR="$forge_os" FORGE_UPDATE_TEST_MARKER="$marker" FORGE_UPDATE_TEST_CHECKPOINT_MARKER="$checkpoint_marker" "$root/scripts/forge-os-update" >/dev/null
[[ -s "$checkpoint_marker" ]] || { echo 'Clean update did not checkpoint the pre-update system state.' >&2; exit 1; }
[[ -e "$marker" ]] || { echo 'Clean fast-forward update did not run the installer.' >&2; exit 1; }
[[ "$(git -C "$forge" rev-parse HEAD)" == "$(git -C "$forge" rev-parse origin/main)" && "$(git -C "$forge_os" rev-parse HEAD)" == "$(git -C "$forge_os" rev-parse origin/main)" ]] || { echo 'Clean update did not activate both origin/main commits.' >&2; exit 1; }
[[ "$(<"$forge/.obsidian/graph.json")" == 'local FORGE graph state' && "$(<"$forge_os/.obsidian/workspace.json")" == 'local FORGE-OS workspace state' ]] || { echo 'Clean update did not preserve local Obsidian state.' >&2; exit 1; }

echo 'PASS: updater refuses dirty/untrusted/divergent source input, preserves local Obsidian state, checkpoints pre-update state, rolls both sources back after installer failure, and completes a clean fast-forward update'
