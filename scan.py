"""Look at a repo before your coding agent does.

Lists the files that brief AI coding agents, everything that runs when you open, trust or install
the project, and wording that tries to stop an agent from looking or from asking you.
Reads files only; runs nothing from the repo. Meant to run inside the preflight.sh container
(no network, no tokens, read-only), but works on any folder:

    python3 -I scan.py <repo-folder>            # report; exit 2 if something needs a human look
    python3 -I scan.py <repo-folder> --bundle   # the flagged files as one text block, for an agent

Indicators from Bitdefender Labs, 17 Nov 2026:
https://www.bitdefender.com/en-us/blog/labs/how-ai-agents-become-new-targets-in-github-malware-campaign
"""
import hashlib
import json
import os
import re
import sys

MAX_READ = 2_000_000          # bytes read from any one file
BUNDLE_PER_FILE = 20_000      # chars per file in --bundle
BUNDLE_TOTAL = 150_000

# Files that brief agents: their text goes into the agent's context as instructions.
INSTRUCTION_NAMES = {
    "agents.md", "claude.md", "claude.local.md", "gemini.md", ".cursorrules", ".windsurfrules",
    ".clinerules", ".aider.conf.yml", "copilot-instructions.md", "codex.md",
}
INSTRUCTION_DIRS = (".cursor/rules/", ".clinerules/", ".github/instructions/", ".kiro/", ".continue/",
                    ".roo/", ".windsurf/", ".claude/commands/", ".claude/agents/", ".claude/skills/")

# Files that can make something run when you open, trust or install the project.
CONFIG_FILES = {
    ".claude/settings.json", ".claude/settings.local.json", ".mcp.json", ".cursor/mcp.json",
    ".vscode/mcp.json", ".vscode/tasks.json", ".gemini/settings.json", ".devcontainer/devcontainer.json",
    ".devcontainer.json", "package.json",
}

RED_FLAGS = [
    ("says a file is sealed or unreadable", r"\bsealed\b|cryptographically signed|binary artifact|not human[- ]readable"),
    ("tells the agent not to look", r"\b(do not|don'?t|never)\s+(read|open|inspect|view|display|quote|show|examine|analy[sz]e|cat|print)\b"),
    ("skips asking or hides output", r"without\s+(asking|confirmation|confirming|prompting|displaying|showing|telling|output)"),
    ("keeps the user out", r"\b(do not|don'?t|never)\s+(tell|inform|mention|ask|notify|alert)\s+(the\s+)?(user|developer|human)"),
    ("runs something quietly or first thing", r"\b(silently|quietly)\b|(run|execute|launch)\b.{0,60}\b(automatically|at session start|on session start|before anything)"),
    ("pipes a download into a shell", r"(curl|wget)\b[^\n|]{0,200}\|\s*(ba|z)?sh\b|iwr\b.{0,100}\|\s*iex"),
    ("decodes or evals hidden code", r"base64\s+(-d|--decode)|\beval\s*\(|fromCharCode|atob\s*\("),
]

INSTALL_SCRIPTS = ("preinstall", "install", "postinstall", "prepare", "prepublish", "preprepare")

# MD5 of setup.js in the 22 repositories Bitdefender published (13 distinct files).
IOC_MD5 = {
    "b9a182b646c7fdff68f2ff9dfd822516", "2f54f6d41f41bb3c8e684b0f009cbcc3", "3794736979327349404171798328a38a",
    "ab7ff2f782c194953e5811d16b9e1817", "2191cbd04134839daeb6b8909725eae0", "31f1f5d9c59b950d91d05cecee20fce8",
    "908293cd1ed04cf50fbe72baf74967b6", "bbd5695c36e76538547c45fd17e6c7e4", "7ad1567180f6d5a5b317f697310a796c",
    "5c8db9bf78c6c2174ccf8a6299f9aafd", "82a8be193a41f5b17906f919a179d999", "5dc5473468ee2d8006ebdaab0c7e93fb",
    "a20a99e325226f56d7a25460a9d436ab",
}

UNPRINTABLE = re.compile(r"[\x00-\x08\x0b-\x1f\x7f​-‏‪-‮⁦-⁩]")


def clean(s, n=200):
    """Text from the repo is untrusted: strip terminal escapes and invisible characters before printing."""
    s = UNPRINTABLE.sub("?", s).strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def walk(root):
    for d, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [x for x in dirs if x != ".git" and not os.path.islink(os.path.join(d, x))]
        for f in files:
            p = os.path.join(d, f)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            if os.path.islink(p):
                yield rel, None  # never follow a symlink out of the repo
            else:
                yield rel, p


def read(p, limit=MAX_READ):
    with open(p, "rb") as fh:
        return fh.read(limit)


def kind_of(rel):
    low = rel.lower()
    if low.rsplit("/", 1)[-1] in INSTRUCTION_NAMES or any(low.startswith(x) or f"/{x}" in low for x in INSTRUCTION_DIRS):
        return "instruction"
    if low in CONFIG_FILES or low.endswith("/.mcp.json"):
        return "config"
    return None


def config_notes(rel, text):
    """What in a config file runs on its own."""
    notes = []
    low = rel.lower()
    try:
        data = json.loads(re.sub(r"^\s*//.*$", "", text, flags=re.M)) if low.endswith(".json") else None
    except ValueError:
        return ["could not parse: read it by hand"]
    if not isinstance(data, dict):
        return notes
    hooks = data.get("hooks")
    if isinstance(hooks, dict) and hooks:
        for event, entries in hooks.items():
            for cmd in re.findall(r'"command"\s*:\s*"((?:[^"\\]|\\.)*)"', json.dumps(entries)):
                notes.append(f"hook on {event}: {clean(cmd)}")
            if not entries:
                notes.append(f"hook on {event}")
    for key in ("mcpServers", "servers"):
        servers = data.get(key)
        if isinstance(servers, dict):
            for name, s in servers.items():
                if isinstance(s, dict):
                    what = " ".join(str(x) for x in [s.get("command", ""), *s.get("args", [])] if x) or s.get("url", "")
                    notes.append(f"MCP server '{clean(str(name), 40)}' starts: {clean(str(what))}")
    if low.endswith("tasks.json"):
        for t in data.get("tasks", []) if isinstance(data.get("tasks"), list) else []:
            if isinstance(t, dict) and (t.get("runOptions") or {}).get("runOn") == "folderOpen":
                notes.append(f"VS Code task runs when the folder opens: {clean(str(t.get('command', '')))} {clean(' '.join(map(str, t.get('args', []))))}")
    if "devcontainer" in low:
        for k in ("initializeCommand", "onCreateCommand", "postCreateCommand", "postStartCommand", "postAttachCommand"):
            if data.get(k):
                notes.append(f"dev container {k}: {clean(json.dumps(data[k]))}")
    if low.endswith("package.json"):
        scripts = data.get("scripts") if isinstance(data.get("scripts"), dict) else {}
        for k in INSTALL_SCRIPTS:
            if k in scripts:
                notes.append(f"npm {k} script (runs on install): {clean(str(scripts[k]))}")
        odd = [k for k in data if k.startswith("_")]
        if odd:
            notes.append(f"unusual package.json fields: {', '.join(clean(k, 30) for k in odd)}")
    return notes


def scan(root):
    found = {"instruction": [], "config": [], "flags": [], "packed": [], "ioc": []}
    for rel, p in walk(root):
        if p is None:
            if kind_of(rel):
                found["flags"].append((rel, 0, "symlink, not followed: read where it points", ""))
            continue
        try:
            size = os.path.getsize(p)
        except OSError:
            continue
        k = kind_of(rel)
        is_code = rel.lower().endswith((".js", ".mjs", ".cjs", ".ts", ".py", ".sh"))
        if not (k or is_code):
            continue
        raw = read(p)
        text = raw.decode("utf-8", "replace")
        if k:
            found[k].append((rel, size))
            for no, line in enumerate(text.splitlines(), 1):
                for label, rx in RED_FLAGS:
                    if re.search(rx, line, re.I):
                        found["flags"].append((rel, no, label, clean(line)))
            if k == "config":
                found["config"][-1] = (rel, size, config_notes(rel, text))
        if is_code:
            if size > 500_000 and raw.count(b"\n") < 5:
                found["packed"].append((rel, size))
            if rel.lower().endswith((".js", ".mjs", ".cjs")) and size < 50_000_000:
                h = hashlib.md5()
                with open(p, "rb") as fh:
                    for chunk in iter(lambda: fh.read(1 << 20), b""):
                        h.update(chunk)
                if h.hexdigest() in IOC_MD5:
                    found["ioc"].append((rel, h.hexdigest()))
    return found


def report(found):
    out = []
    out.append(f"Files that brief coding agents ({len(found['instruction'])}):")
    out += [f"  {clean(r, 120)}  ({s:,} bytes)" for r, s in found["instruction"]] or ["  none"]
    out.append(f"\nFiles that can run something when you open, trust or install ({len(found['config'])}):")
    for r, s, notes in found["config"]:
        out.append(f"  {clean(r, 120)}")
        out += [f"    - {n}" for n in notes] or ["    - nothing that runs on its own"]
    if not found["config"]:
        out.append("  none")
    out.append(f"\nWording that tries to stop the agent from looking or from asking you ({len(found['flags'])}):")
    out += [f"  {clean(r, 120)}{f':{n}' if n else ''}  [{label}]  {line}".rstrip() for r, n, label, line in found["flags"]] or ["  none"]
    out.append(f"\nPacked code (one huge line, often obfuscated; minified bundles can be legit) ({len(found['packed'])}):")
    out += [f"  {clean(r, 120)}  ({s:,} bytes)" for r, s in found["packed"]] or ["  none"]
    out.append(f"\nKnown malicious setup.js from the Bitdefender report ({len(found['ioc'])}):")
    out += [f"  {clean(r, 120)}  md5 {h}  <- DO NOT OPEN THIS REPO WITH AN AGENT" for r, h in found["ioc"]] or ["  none"]
    runs = sum(1 for _, _, notes in found["config"] for n in notes if not n.startswith("unusual"))
    attention = len(found["flags"]) + len(found["packed"]) + len(found["ioc"]) + runs
    out.append("\n" + ("Read the files above by hand before you open this repo with an agent or click trust."
                       if attention else "Nothing flagged. Still skim the instruction files: this is a grep, not a guarantee."))
    return "\n".join(out), attention


def bundle(root, found):
    paths = [r for r, *_ in found["instruction"]] + [r for r, *_ in found["config"]]
    paths += sorted({r for r, *_ in found["flags"]} - set(paths))
    out, total = [], 0
    for rel in paths:
        p = os.path.join(root, rel)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        body = UNPRINTABLE.sub("?", read(p, BUNDLE_PER_FILE * 4).decode("utf-8", "replace"))[:BUNDLE_PER_FILE]
        chunk = f"===== FILE: {clean(rel, 200)} =====\n{body}\n===== END FILE =====\n"
        if total + len(chunk) > BUNDLE_TOTAL:
            out.append("===== (more files left out: size limit) =====\n")
            break
        out.append(chunk)
        total += len(chunk)
    for r, s in found["packed"]:
        out.append(f"===== NOTE: {clean(r, 200)} is packed code, {s:,} bytes on few lines (not included) =====\n")
    return "".join(out) or "(no agent instruction or config files found)\n"


def main(argv):
    if len(argv) < 2 or not os.path.isdir(argv[1]):
        print(__doc__, file=sys.stderr)
        return 1
    root = argv[1]
    found = scan(root)
    if "--bundle" in argv:
        sys.stdout.write(bundle(root, found))
        return 0
    text, attention = report(found)
    print(text)
    return 2 if attention else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
