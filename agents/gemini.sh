#!/usr/bin/env bash
# Gemini CLI, headless, with every tool denied by a policy file and usage statistics off.
# A user-tier policy ranks above Gemini's built-in rules, and a denied tool is left out of what the
# model is offered, so it can't read files, run commands, search or fetch URLs (Gemini's web_fetch
# can ask Google to fetch a URL, which would get round the network limit; this switches it off).
# Reads the files' text on stdin (Gemini appends the prompt to it), the question in $1.
ALLOW_HOST=generativelanguage.googleapis.com
KEY_VAR=GEMINI_API_KEY
RAW_PROVIDER=google
PKG=@google/gemini-cli@0.70.0
IMAGE=apf-gemini:0.70.0

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0   # sourced by preflight.sh for the settings above
set -euo pipefail
: "${GEMINI_API_KEY:?set GEMINI_API_KEY}"
. "$(dirname "$0")/_common.sh"
agent_run "$IMAGE" -e GEMINI_API_KEY -e HOME=/home/node -- sh -c '
  mkdir -p ~/.gemini/policies
  printf "[[rule]]\ntoolName = \"*\"\ndecision = \"deny\"\npriority = 999\ndenyMessage = \"agent-repo-preflight: tools are off\"\n\n[[rule]]\ntoolName = \"*\"\nmcpName = \"*\"\ndecision = \"deny\"\npriority = 999\n" > ~/.gemini/policies/apf-deny-all.toml
  printf "{\"privacy\":{\"usageStatisticsEnabled\":false},\"telemetry\":{\"enabled\":false},\"security\":{\"auth\":{\"selectedType\":\"gemini-api-key\"}}}\n" > ~/.gemini/settings.json
  exec gemini -p "$0" --approval-mode plan --skip-trust' "$1"
