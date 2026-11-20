#!/usr/bin/env bash
# Gemini CLI, headless: `gemini -p` in plan mode (read-only), from an empty folder.
# Reads the files' text on stdin (Gemini appends the prompt to it), the question in $1.
# Only GEMINI_API_KEY goes into the container.
set -euo pipefail
: "${GEMINI_API_KEY:?set GEMINI_API_KEY}"
VERSION=${GEMINI_CLI_VERSION:-0.70.0}
docker run --rm -i --cap-drop ALL --security-opt no-new-privileges -e GEMINI_API_KEY \
  -e HOME=/home/node --user node -w /home/node node:22-alpine \
  sh -c 'mkdir -p empty && cd empty && npx -y "@google/gemini-cli@$0" -p "$1" --approval-mode plan' "$VERSION" "$1"
