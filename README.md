# claude-statusline

A fast, zero-dependency status line for [Claude Code](https://claude.com/claude-code).

It reads Claude Code's status line JSON from **stdin only** — no background process,
no cache, no `ccusage`/`cs`/`node` spawn. A single `jq` pass renders everything, so it
stays fast on every prompt and always reflects the **currently authenticated account's
real rate limits** (from Anthropic's official headers, Claude Code ≥ 2.1.80).

```
📁 dir (branch) │ 💰 $session │ 5h ████░░░░░░ 36% ⏰2d07h │ 7d ███░░░░░░░ 30% ⏰5d │ Model 89k/1.0M high⚡
```

## What it shows

- **📁 dir (branch)** — current directory + git branch. Branch is **yellow** when the
  working tree is dirty, dim when clean.
- **💰 $session** — session cost (`cost.total_cost_usd`).
- **5h / 7d** — rate-limit usage bars from `rate_limits.{five_hour,seven_day}`, with a
  countdown to reset. Bar color: green `<30%`, yellow `30–70%`, red `≥70%`.
- **Model ctx/limit** — model display name + context window used / total.
- **effort / ⚡** — current `/effort` level and fast-mode indicator.

Any segment whose data is absent from stdin is silently dropped.

## Requirements

- **`jq`** (required)
- **`git`** (optional — only for the branch segment; skipped if not installed)

No Node.js, no `ccusage`, no `cs`. The tool spawns at most `2× jq + 1× git` per render.

## Install

### Homebrew

```sh
brew install muzafferkadir/tap/claude-statusline
```

### Manual

```sh
curl -fsSL https://raw.githubusercontent.com/muzafferkadir/claude-statusline/main/claude-statusline \
  -o /usr/local/bin/claude-statusline
chmod +x /usr/local/bin/claude-statusline
```

## Configure

Point Claude Code at the binary in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/usr/local/bin/claude-statusline",
    "padding": 0
  }
}
```

(Homebrew installs to its prefix — use `$(brew --prefix)/bin/claude-statusline` if that
isn't on the path Claude Code uses.)

## License

MIT © Muzaffer Kadir Yılmaz
