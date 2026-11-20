#!/usr/bin/env bash
# OpenAI Codex CLI, headless: `codex exec` in its read-only sandbox, web search disabled, ephemeral,
# from an empty folder. Codex has no switch to turn its shell off: it can still run read-only commands
# inside this container, which holds only the files' text and OPENAI_API_KEY, and can reach only
# api.openai.com. Reads the text on stdin, the question in $1.
ALLOW_HOST=api.openai.com
KEY_VAR=OPENAI_API_KEY
RAW_PROVIDER=openai
PKG=@openai/codex@0.171.0
IMAGE=apf-codex:0.171.0

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0   # sourced by preflight.sh for the settings above
set -euo pipefail
: "${OPENAI_API_KEY:?set OPENAI_API_KEY}"
. "$(dirname "$0")/_common.sh"
agent_run "$IMAGE" -e OPENAI_API_KEY -e CODEX_API_KEY="$OPENAI_API_KEY" -e HOME=/home/node -- \
  codex exec --skip-git-repo-check --ephemeral -s read-only -c 'web_search="disabled"' "$1"
