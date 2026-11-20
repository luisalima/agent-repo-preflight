#!/usr/bin/env bash
# Claude Code, headless: no tools, no hooks, no CLAUDE.md, no MCP, no saved session, no telemetry.
# Reads the files' text on stdin, the question in $1. Only ANTHROPIC_API_KEY goes into the container.
ALLOW_HOST=api.anthropic.com
KEY_VAR=ANTHROPIC_API_KEY
RAW_PROVIDER=anthropic
PKG=@anthropic-ai/claude-code@2.1.329
IMAGE=apf-claude:2.1.329

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0   # sourced by preflight.sh for the settings above
set -euo pipefail
: "${ANTHROPIC_API_KEY:?set ANTHROPIC_API_KEY}"
. "$(dirname "$0")/_common.sh"
agent_run "$IMAGE" -e ANTHROPIC_API_KEY -e HOME=/tmp \
  -e DISABLE_TELEMETRY=1 -e DISABLE_ERROR_REPORTING=1 -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 -- \
  claude -p "$1" --bare --tools "" --strict-mcp-config --no-session-persistence
