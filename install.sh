#!/bin/bash
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
DIM='\033[2m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}headroom${RESET}"
echo -e "${DIM}context window usage for Claude Code${RESET}"
echo ""

# Requires Python 3
if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is required." >&2
  exit 1
fi

mkdir -p ~/.claude/hooks

# ── context-counter.py ──────────────────────────────────────────────────────
cat > ~/.claude/hooks/context-counter.py << 'PYEOF'
#!/usr/bin/env python3
import json, os, re, sys, glob, time

MODEL_CONTEXT = {
    "claude-sonnet-4-6[1m]":     1_000_000,
    "claude-opus-4-7":           1_000_000,
    "claude-sonnet-4-6":           200_000,
    "claude-haiku-4-5-20251001":   200_000,
    "claude-haiku-4-5":            200_000,
}

try:
    data = json.load(sys.stdin)
    session_id = data.get("session_id", "")
    cwd = data.get("cwd", "")
except Exception:
    sys.exit(0)

if not session_id or not cwd:
    sys.exit(0)

sanitized = re.sub(r"[^a-zA-Z0-9]", "-", cwd).lstrip("-")
project_dir = os.path.expanduser(f"~/.claude/projects/-{sanitized}")

candidates = glob.glob(os.path.join(project_dir, "*.jsonl"))
if not candidates:
    sys.exit(0)
jsonl_path = max(candidates, key=os.path.getmtime)

last_usage = None
last_model = None
try:
    with open(jsonl_path) as f:
        for line in f:
            try:
                d = json.loads(line)
                if d.get("type") == "assistant":
                    msg = d.get("message", {})
                    usage = msg.get("usage", {})
                    if usage:
                        last_usage = usage
                        last_model = msg.get("model") or last_model
            except Exception:
                pass
except Exception:
    sys.exit(0)

_model = last_model or os.environ.get("ANTHROPIC_MODEL", "")
CONTEXT_MAX = MODEL_CONTEXT.get(_model, 1_000_000)

if not last_usage:
    sys.exit(0)

total = (
    last_usage.get("input_tokens", 0)
    + last_usage.get("cache_read_input_tokens", 0)
    + last_usage.get("cache_creation_input_tokens", 0)
)
pct = round(total / CONTEXT_MAX * 100, 1)

payload = {"tokens": total, "pct": pct, "session_id": session_id}

for path in [
    os.path.expanduser(f"~/.claude/context-tokens-{session_id}.json"),
    os.path.expanduser("~/.claude/context-tokens.json"),
    os.path.expanduser(f"~/.claude/context-tokens-cwd-{re.sub(r'[^a-zA-Z0-9]', '-', cwd).lstrip('-')}.json"),
]:
    try:
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(payload, f)
        os.replace(tmp, path)
    except Exception:
        pass

cutoff = time.time() - 86400
for old in glob.glob(os.path.expanduser("~/.claude/context-tokens-*.json")):
    try:
        if os.path.getmtime(old) < cutoff:
            os.unlink(old)
    except OSError:
        pass
PYEOF

# ── statusline.sh ────────────────────────────────────────────────────────────
cat > ~/.claude/statusline.sh << 'SHEOF'
#!/bin/bash
CWD_SANITIZED=$(python3 -c "import sys,re; print(re.sub(r'[^a-zA-Z0-9]', '-', '$(pwd)').lstrip('-'))" 2>/dev/null)
TOKEN_FILE="$HOME/.claude/context-tokens-cwd-${CWD_SANITIZED}.json"

if [ ! -f "$TOKEN_FILE" ]; then
    TOKEN_FILE="$HOME/.claude/context-tokens.json"
fi

if [ -f "$TOKEN_FILE" ]; then
    python3 -c "
import json
d = json.load(open('$TOKEN_FILE'))
pct = d['pct']
filled = round(pct / 10)
bar = '█' * filled + '░' * (10 - filled)
print(f'{bar} {pct}%')
" 2>/dev/null || echo "░░░░░░░░░░ --"
else
    echo "░░░░░░░░░░ --"
fi
SHEOF
chmod +x ~/.claude/statusline.sh

# ── settings.json ────────────────────────────────────────────────────────────
python3 << 'EOF'
import json, os

path = os.path.expanduser("~/.claude/settings.json")
settings = {}
if os.path.exists(path):
    with open(path) as f:
        try:
            settings = json.load(f)
        except Exception:
            pass

hooks = settings.setdefault("hooks", {})
post = hooks.setdefault("PostToolUse", [])

hook_cmd = "python3 ~/.claude/hooks/context-counter.py"
already = any(
    h.get("command") == hook_cmd
    for entry in post
    for h in entry.get("hooks", [])
)
if not already:
    post.append({
        "matcher": "Bash|Agent|Write",
        "hooks": [{"type": "command", "command": hook_cmd, "timeout": 3}]
    })

settings["statusline"] = {"command": "bash ~/.claude/statusline.sh"}

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
os.replace(tmp, path)
EOF

echo -e "  ${GREEN}✓${RESET} context-counter.py → ~/.claude/hooks/"
echo -e "  ${GREEN}✓${RESET} statusline.sh      → ~/.claude/"
echo -e "  ${GREEN}✓${RESET} settings.json patched"
echo ""
echo -e "Restart Claude Code to activate."
echo ""
