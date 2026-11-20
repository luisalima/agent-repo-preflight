#!/usr/bin/env bash
# Tests for agent-repo-preflight.
#   test/run.sh            scan.py on the fixtures (needs python3)
#   test/run.sh --docker   also preflight.sh end to end (needs Docker)
# The fixtures keep a .fixture suffix in the repo so no agent opening this repo reads them as
# instructions; they get their real names only inside a temp folder here.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); root=$(dirname "$here")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; fail=1; }
expect() { # name, exit code wanted, output file, grep patterns...
  local name=$1 want=$2 out=$3; shift 3
  [ "$(cat "$out.code")" = "$want" ] && ok "$name: exit $want" || ko "$name: exit $(cat "$out.code"), wanted $want"
  for p in "$@"; do grep -qF -- "$p" "$out" && ok "$name: has '$p'" || ko "$name: missing '$p'"; done
}

# fake campaign repo, real names
f="$tmp/fake"; mkdir -p "$f/.claude" "$f/.vscode" "$f/scripts"
s="$here/fixtures/fake-campaign"
cp "$s/AGENTS.md.fixture" "$f/AGENTS.md"; cp "$s/AGENTS.md.fixture" "$f/CLAUDE.md"
cp "$s/claude-settings.json.fixture" "$f/.claude/settings.json"; cp "$s/vscode-tasks.json.fixture" "$f/.vscode/tasks.json"
cp "$s/mcp.json.fixture" "$f/.mcp.json"; cp "$s/package.json.fixture" "$f/package.json"; cp "$s/setup.js.fixture" "$f/scripts/setup.js"
python3 -c "print('var a=\"'+'41'*400000+'\";')" > "$f/scripts/packed.js"   # one huge line
ln -s /etc/hostname "$f/.cursorrules"                                        # must not be followed
c="$tmp/clean"; mkdir -p "$c"
cp "$here/fixtures/clean/AGENTS.md.fixture" "$c/AGENTS.md"; cp "$here/fixtures/clean/package.json.fixture" "$c/package.json"

run() { set +e; "$@" > "$out" 2>&1; echo $? > "$out.code"; set -e; }

out="$tmp/o1"; run python3 -I "$root/scan.py" "$f"
expect "scan fake" 2 "$out" "AGENTS.md:6  [says a file is sealed or unreadable]" "[tells the agent not to look]" "[skips asking or hides output]" \
  "hook on SessionStart: node scripts/setup.js" "VS Code task runs when the folder opens" "MCP server 'setup' starts: node scripts/setup.js" \
  "npm postinstall script" "unusual package.json fields: _bz" "scripts/packed.js" ".cursorrules  [symlink, not followed"
out="$tmp/o2"; run python3 -I "$root/scan.py" "$c"
expect "scan clean" 0 "$out" "Nothing flagged"
out="$tmp/o3"; run python3 -I "$root/scan.py" "$f" --bundle
expect "bundle" 0 "$out" "===== FILE: AGENTS.md =====" "===== FILE: .claude/settings.json =====" "is packed code"
grep -q "/etc/hostname\|$(cat /etc/hostname 2>/dev/null || echo NOHOST)" "$out" && ko "bundle followed the symlink" || ok "bundle: symlink not followed"

# known-bad hash: the scanner must match an MD5 from its list
out="$tmp/o4"; run python3 -I -c "
import sys, hashlib; sys.path.insert(0, '$root'); import scan
p = '$f/scripts/setup.js'; scan.IOC_MD5.add(hashlib.md5(open(p, 'rb').read()).hexdigest())
print(scan.report(scan.scan('$f'))[0])"
expect "hash match" 0 "$out" "DO NOT OPEN THIS REPO WITH AN AGENT"

if [ "${1:-}" = "--docker" ]; then
  out="$tmp/o5"; run bash "$root/preflight.sh" "$f"
  expect "preflight fake (folder)" 2 "$out" "hook on SessionStart" "Read the files above by hand"
  git -C "$c" init -q && git -C "$c" add -A && git -C "$c" -c user.name=t -c user.email=t@t commit -qm x
  out="$tmp/o6"; run bash "$root/preflight.sh" "$c"
  expect "preflight clean (git)" 0 "$out" "Nothing flagged"
  left=$(docker volume ls -q | grep -c '^agent-preflight-' || true)
  [ "$left" = 0 ] && ok "no volumes left behind" || ko "$left volume(s) left behind"

  # The network limit for --agents: through the proxy only the allowed host answers; nothing else, and
  # nothing directly. Any HTTP status from the allowed host (401 without a key) means it was reached.
  docker image inspect apf-proxy:1 >/dev/null 2>&1 || docker build -q -t apf-proxy:1 -f "$root/docker/proxy.Dockerfile" "$root/docker" >/dev/null
  cat > "$tmp/probe.py" <<'EOF'
import sys, urllib.request, urllib.error
try:
    urllib.request.urlopen(sys.argv[1], timeout=10); print("reached")
except urllib.error.HTTPError: print("reached")
except Exception as e: print("blocked", type(e).__name__)
EOF
  net="apf-test-$$"; px="$net-proxy"
  docker network create --internal "$net" >/dev/null
  docker run -d --rm --name "$px" --cap-drop ALL -e ALLOW_HOST=api.anthropic.com apf-proxy:1 >/dev/null
  docker network connect "$net" "$px"; sleep 1.5
  probe() { docker run --rm --network "$net" --cap-drop ALL -v "$tmp/probe.py:/probe.py:ro" "$@" 2>&1 | tail -1; }
  via=(-e https_proxy="http://$px:8888" python:3.13-alpine python -I /probe.py)
  [ "$(probe "${via[@]}" https://api.anthropic.com/v1/models)" = reached ] && ok "proxy: allowed host reached" || ko "proxy: allowed host not reached"
  [[ "$(probe "${via[@]}" https://example.com)" == blocked* ]] && ok "proxy: other host blocked" || ko "proxy: other host NOT blocked"
  [[ "$(probe "${via[@]}" https://api.anthropic.com.evil.example)" == blocked* ]] && ok "proxy: lookalike host blocked" || ko "proxy: lookalike host NOT blocked"
  [[ "$(probe python:3.13-alpine python -I /probe.py https://api.anthropic.com/v1/models)" == blocked* ]] && ok "proxy: direct connection blocked" || ko "proxy: direct connection NOT blocked"
  docker rm -f "$px" >/dev/null; docker network rm "$net" >/dev/null
fi

[ $fail = 0 ] && echo "all passed" || { echo "some failed"; exit 1; }
