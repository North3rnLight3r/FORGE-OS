#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
forge_source="${FORGE_SOURCE:-$HOME/FORGE}"
forge_ref="$(tr -d '[:space:]' < "$root/FORGE_REF")"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT

[[ "$forge_ref" =~ ^[0-9a-f]{40}$ ]] || { echo 'FORGE_REF is not a full commit SHA.' >&2; exit 1; }
[[ "$(git -C "$forge_source" rev-parse HEAD)" == "$forge_ref" ]] || { echo 'FORGE checkout does not match FORGE_REF.' >&2; exit 1; }
grep -Fq 'http://127.0.0.1:11434/v1' "$root/config/forge-hermes.env" || { echo 'Ollama Hermes endpoint is not configured.' >&2; exit 1; }

git -C "$forge_source" archive HEAD | tar --warning=no-timestamp -x -C "$temporary"
for overlay in "$root"/overlays/*.patch; do
  patch --dry-run --batch --forward --fuzz=0 -d "$temporary" -p1 <"$overlay" >/dev/null
  patch --batch --forward --fuzz=0 -d "$temporary" -p1 <"$overlay" >/dev/null
done

grep -Fq 'process.env.FORGE_HERMES_ENDPOINT' "$temporary/apps/desktop/src/main/settings.ts"
grep -Fq 'status?.endpointReachable === true' "$temporary/packages/agent-runtime/src/index.ts"
grep -Fq 'native ToolRouter' "$temporary/packages/agent-runtime/src/index.ts"
echo 'PASS: pinned FORGE accepts the FORGE-OS native Ollama/Hermes endpoint overlay.'
