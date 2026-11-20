#!/usr/bin/env bash
# Claude Code, headless: no tools, no hooks, no CLAUDE.md, no MCP, no saved session.
# Reads the files' text on stdin, the question in $1. Only ANTHROPIC_API_KEY goes into the container.
set -euo pipefail
: "${ANTHROPIC_API_KEY:?set ANTHROPIC_API_KEY}"
VERSION=${CLAUDE_CODE_VERSION:-2.1.329}
docker run --rm -i --cap-drop ALL --security-opt no-new-privileges -e ANTHROPIC_API_KEY -e HOME=/tmp -w /tmp node:22-alpine \
  npx -y "@anthropic-ai/claude-code@$VERSION" -p "$1" \
  --bare --tools "" --strict-mcp-config --no-session-persistence
