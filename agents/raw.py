"""--raw: ask a provider's API directly, one plain request, no tools. Text in, text out.

    python3 -I raw.py <anthropic|openai|google> "<question>"  < files.txt

The files' text comes on stdin, the API key from the environment (ANTHROPIC_API_KEY, OPENAI_API_KEY,
GEMINI_API_KEY). Models: RAW_ANTHROPIC_MODEL, RAW_OPENAI_MODEL, RAW_GEMINI_MODEL. Standard library only;
the request goes through HTTPS_PROXY (preflight.sh's egress proxy). The request declares no tools, so
there is no tool loop for the files' text to hijack.
"""
import json
import os
import sys
import urllib.error
import urllib.request

MAX_TOKENS = 1500


def post(url, headers, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"content-type": "application/json", **headers}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read(2000).decode("utf-8", "replace")
        sys.exit(f"{url.split('/')[2]} answered HTTP {e.code}: {detail[:400]}")
    except urllib.error.URLError as e:
        sys.exit(f"could not reach {url.split('/')[2]}: {e.reason}")


def anthropic(question, files):
    model = os.environ.get("RAW_ANTHROPIC_MODEL", "claude-sonnet-5-5")
    r = post("https://api.anthropic.com/v1/messages",
             {"x-api-key": os.environ["ANTHROPIC_API_KEY"], "anthropic-version": "2023-06-01"},
             {"model": model, "max_tokens": MAX_TOKENS, "system": question,
              "messages": [{"role": "user", "content": files}]})
    return "".join(b.get("text", "") for b in r.get("content", []) if b.get("type") == "text")


def openai(question, files):
    model = os.environ.get("RAW_OPENAI_MODEL", "gpt-5.4-mini")
    r = post("https://api.openai.com/v1/chat/completions",
             {"authorization": "Bearer " + os.environ["OPENAI_API_KEY"]},
             {"model": model, "max_completion_tokens": MAX_TOKENS,
              "messages": [{"role": "system", "content": question}, {"role": "user", "content": files}]})
    return r["choices"][0]["message"].get("content") or ""


def google(question, files):
    model = os.environ.get("RAW_GEMINI_MODEL", "gemini-flash-latest")
    r = post(f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
             {"x-goog-api-key": os.environ["GEMINI_API_KEY"]},  # header, never in the URL
             {"systemInstruction": {"parts": [{"text": question}]},
              "contents": [{"role": "user", "parts": [{"text": files}]}],
              "generationConfig": {"maxOutputTokens": MAX_TOKENS}})
    parts = (r.get("candidates") or [{}])[0].get("content", {}).get("parts", [])
    return "".join(p.get("text", "") for p in parts)


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("anthropic", "openai", "google"):
        sys.exit(__doc__)
    files = sys.stdin.read()
    print(globals()[sys.argv[1]](sys.argv[2], files).strip())


if __name__ == "__main__":
    main()
