#!/usr/bin/env bash
# OpenAI Codex CLI, headless: `codex exec` in its read-only sandbox, ephemeral, from an empty folder.
# Codex has no "no tools" switch: it may still run read-only shell commands inside this container,
# which holds nothing but the files' text and OPENAI_API_KEY. Reads the text on stdin, the question in $1.
set -euo pipefail
: "${OPENAI_API_KEY:?set OPENAI_API_KEY}"
VERSION=${CODEX_VERSION:-0.171.0}
docker run --rm -i --cap-drop ALL --security-opt no-new-privileges -e OPENAI_API_KEY -e CODEX_API_KEY="$OPENAI_API_KEY" \
  -e HOME=/home/node --user node -w /home/node node:22-alpine \
  sh -c 'mkdir -p empty && cd empty && npx -y "@openai/codex@$0" exec --skip-git-repo-check --ephemeral -s read-only "$1"' "$VERSION" "$1"
