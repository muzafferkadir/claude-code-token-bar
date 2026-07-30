# claude-code-token-bar

A fast, zero-dependency status line for [Claude Code](https://claude.com/claude-code).

It reads Claude Code's status line JSON from **stdin only** — no background process,
no cache, no `ccusage`/`cs`/`node` spawn. Two `jq` passes render everything, so it
stays fast on every prompt and always reflects the **currently authenticated account's
real rate limits** (from Anthropic's official headers, Claude Code ≥ 2.1.80).

Ships as a bash script for Linux and macOS, and as a dependency-free PowerShell
script for Windows.

Not affiliated with or endorsed by Anthropic.

```
📁 dir (branch) │ 💰 $session │ 5h ████░░░░░░ 36% ⏰ 2d07h │ 7d ███░░░░░░░ 30% ⏰ 5d │ Model 89k/1.0M high⚡
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

Any segment whose data is absent from stdin is silently dropped.

## Two implementations, one output

| | `claude-code-token-bar` | `claude-code-token-bar.ps1` |
|---|---|---|
| Runtime | bash + `jq` | PowerShell 7 |
| Platforms | Linux, macOS | Windows, and anywhere `pwsh` runs |
| Per render | `2× jq + 1× git` | `1× git` |

Both render **byte-identical** output for the same input — `test/parity.ps1` pipes a
shared fixture set through each one and diffs the raw bytes, and CI runs it on every
push. Pick whichever fits your machine; nothing else changes.

## Requirements

**bash version:** `jq` (required), `git` (optional — only for the branch segment).

**PowerShell version:** PowerShell 7+ (required), `git` (optional). JSON parsing is
built into PowerShell, so there is no `jq` dependency.

No Node.js, no `ccusage`, no `cs`, in either case.

## Install

### Homebrew (Linux, macOS)

```sh
brew install muzafferkadir/tap/claude-code-token-bar
```

### Manual (Linux, macOS)

```sh
curl -fsSL https://raw.githubusercontent.com/muzafferkadir/claude-code-token-bar/main/claude-code-token-bar \
  -o /usr/local/bin/claude-code-token-bar
chmod +x /usr/local/bin/claude-code-token-bar
```

### Windows

Install PowerShell 7 if you do not have it (`winget install Microsoft.PowerShell`),
then drop the script anywhere you like:

```powershell
New-Item -ItemType Directory -Force "$HOME\.claude" | Out-Null
Invoke-WebRequest `
  -Uri https://raw.githubusercontent.com/muzafferkadir/claude-code-token-bar/main/claude-code-token-bar.ps1 `
  -OutFile "$HOME\.claude\claude-code-token-bar.ps1"
```

Git Bash and WSL are **not** required — the script runs on Windows PowerShell 7 alone.

## Configure

### Linux, macOS

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

### Windows

Invoke `pwsh` explicitly rather than relying on `.ps1` file association, so the
status line works regardless of which shell Claude Code spawns the command with.
Use forward slashes — JSON treats `\` as an escape character:

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File C:/Users/YOU/.claude/claude-code-token-bar.ps1",
    "padding": 0
  }
}
```

`-NoProfile` matters: it skips your PowerShell profile, which would otherwise add
startup latency and could print stray output into the status line.

Expect roughly **350–400 ms** per render on Windows, of which ~200 ms is PowerShell's
own process startup. That is slower than the bash version's ~40 ms, but the status
line renders asynchronously, so it does not block input.

## Development

```sh
bash test/statusline.sh       # bash implementation
pwsh -File test/statusline.ps1 # PowerShell implementation
pwsh -File test/parity.ps1     # the two must agree byte for byte
```

`parity.ps1` skips itself when `bash` or `jq` is unavailable, so Windows contributors
can still run the rest of the suite.

## License

MIT © Muzaffer Kadir Yılmaz
