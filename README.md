<p align="center">
  <img src="assets/banner.png" alt="headroom" width="100%">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Claude%20Code-statusline-8a2be2" alt="Claude Code">
</p>

# headroom

You're deep in a session. Claude starts dropping earlier context. Compaction fires mid-turn and takes work in progress with it. You had no warning. Claude Code gives you nothing on context usage.

headroom fixes that. A live bar in your statusline, updated after every tool call.

```
████████░░ 78.3%
```

Now you can see the window filling up. Pace the session, decide when to `/compact`, or start fresh before things go sideways.

Reads your actual session JSONL, not an estimate. Tracks the model you're running (not the env var), so it stays accurate when you switch mid-session. Per-directory, so multiple Claude Code windows don't bleed into each other.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/henchmarketing-rgb/headroom/main/install.sh | bash
```

Restart Claude Code to activate.

**Requires:** Python 3, Claude Code

---

## How it works

A `PostToolUse` hook fires after every `Bash`, `Agent`, or `Write` call. It finds the most recently modified session JSONL in your project directory, reads the last token usage entry, and writes it to `~/.claude/`. The statusline picks that up and renders the bar.

The model is read from the JSONL, not the `ANTHROPIC_MODEL` env var, so it tracks correctly when you run `/model` mid-session.

**Sonnet 4.6 and the 1M context window:** standard Sonnet 4.6 runs at 200k context. Only max effort mode (`/model` then select max) unlocks the full 1M. Claude Code logs that as `claude-sonnet-4-6[1m]` in the session JSONL and headroom adjusts the ceiling automatically. High thinking still logs as `claude-sonnet-4-6` and stays at 200k.

---

## Manual install

```bash
bash install.sh
```

Or copy the files yourself:

| File | Destination |
|------|-------------|
| `context-counter.py` | `~/.claude/hooks/context-counter.py` |
| `statusline.sh` | `~/.claude/statusline.sh` |

Then add to `~/.claude/settings.json`:

```json
{
  "statusline": { "command": "bash ~/.claude/statusline.sh" },
  "hooks": {
    "PostToolUse": [{
      "matcher": "Bash|Agent|Write",
      "hooks": [{ "type": "command", "command": "python3 ~/.claude/hooks/context-counter.py", "timeout": 3 }]
    }]
  }
}
```

---

## Uninstall

```bash
rm ~/.claude/hooks/context-counter.py ~/.claude/statusline.sh
```

Remove the `statusline` and hook entries from `~/.claude/settings.json`.
