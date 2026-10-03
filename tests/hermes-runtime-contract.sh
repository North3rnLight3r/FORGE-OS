#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
forge_source="${FORGE_SOURCE:-$HOME/FORGE}"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT

grep -Fq 'http://127.0.0.1:11434/v1' "$root/config/forge-hermes.env" || { echo 'Ollama Hermes endpoint is not configured.' >&2; exit 1; }

git -C "$forge_source" archive HEAD | tar --warning=no-timestamp -x -C "$temporary"
grep -Fq 'class HermesBridge' "$temporary/packages/ai/src/hermes.ts"
grep -Fq "DEFAULT_HERMES_ENDPOINT = 'http://127.0.0.1:11434/v1'" "$temporary/packages/ai/src/hermes.ts"
grep -Fq 'modelsEndpoint' "$temporary/packages/agent-runtime/src/index.ts"
grep -Fq 'process.env.FORGE_HERMES_ENDPOINT' "$temporary/apps/desktop/src/main/settings.ts"
grep -Fq 'FORGE intelligence layer' "$temporary/packages/ai/src/intelligence-layer.ts"
grep -Fq 'this.provider.chatWithTools' "$temporary/packages/ai/src/hermes.ts"
grep -Fq 'status?.endpointReachable === true' "$temporary/packages/agent-runtime/src/index.ts"
grep -Fq 'native ToolRouter' "$temporary/packages/agent-runtime/src/index.ts"
echo 'PASS: local FORGE contains the native Ollama/Hermes bridge and shared intelligence layer.'
