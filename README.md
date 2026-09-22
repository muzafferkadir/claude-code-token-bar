# claude-code-token-bar

A fast, zero-dependency status line for [Claude Code](https://claude.com/claude-code).

It reads Claude Code's status line JSON from **stdin only** — no background process,
no daemon, no `ccusage`/`cs`/`node` spawn. Three `jq` passes render everything, so it
stays fast on every prompt and always reflects the **currently authenticated account's
real rate limits** (from Anthropic's official headers, Claude Code ≥ 2.1.80).

Not affiliated with or endorsed by Anthropic.

```
📁 dir (branch) │ 💰 $session │ 5h ████░░░░░░ 36% ⏰2d07h │ 7d ███░░░░░░░ 30% ⏰5d │ Model 89k/1.0M high⚡ │ 🔥47m
```

## What it shows

- **📁 dir (branch)** — current directory + git branch. Branch is **yellow** when the
  working tree is dirty, dim when clean.
- **💰 $session** — session cost (`cost.total_cost_usd`).
- **5h / 7d** — rate-limit usage bars from `rate_limits.{five_hour,seven_day}`, with a
  countdown to reset. Bar color: green `<30%`, yellow `30–70%`, red `≥70%`. Percentages
  outside `0–100` (malformed upstream data) are clamped before rendering.
- **Model ctx/limit** — model display name + context window used / total.
- **effort / ⚡** — current `/effort` level and fast-mode indicator.
- **🔥Nm / ❄️cold** — prompt-cache warmth, same logic as the Claude Code VS Code
  extension: the last assistant message in `transcript_path` is the anchor, TTL comes
  from `usage.cache_creation` (`ephemeral_1h` → 60m, `ephemeral_5m` → 5m, otherwise the
  previous TTL is kept), a compaction after the anchor means cold. Shown only when a
  TTL is known.

Any segment whose data is absent from stdin is silently dropped.

## Requirements

- **`jq`** (required)
- **`git`** (optional — only for the branch segment; skipped if not installed)

No Node.js, no `ccusage`, no `cs`. The tool spawns at most `3× jq + 1× git + 1× tail` per render.

## Install

### Homebrew

```sh
brew install muzafferkadir/tap/claude-code-token-bar
```

### Manual

```sh
curl -fsSL https://raw.githubusercontent.com/muzafferkadir/claude-code-token-bar/main/claude-code-token-bar \
  -o /usr/local/bin/claude-code-token-bar
chmod +x /usr/local/bin/claude-code-token-bar
```

## Configure

Point Claude Code at the binary in `~/.claude/settings.json`. Find the actual path with
`command -v claude-code-token-bar` (Homebrew's prefix varies: `/opt/homebrew/bin` on
Apple Silicon, `/usr/local/bin` on Intel Macs, `/home/linuxbrew/.linuxbrew/bin` on
Linuxbrew):

```json
{
  "statusLine": {
    "type": "command",
    "command": "claude-code-token-bar",
    "padding": 0
  }
}
```

## License

MIT © Muzaffer Kadir Yılmaz
