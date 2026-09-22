#!/bin/bash
# Expected strings below hold literal '$' dollar amounts, not variables.
# shellcheck disable=SC2016
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bin="$root/claude-code-token-bar"

strip_ansi() {
  sed $'s/\033\\[[0-9;]*m//g'
}

check() {
  local name="$1" input="$2" expected="$3"
  local actual
  actual=$(printf '%s' "$input" | "$bin" | strip_ansi)
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$name" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'ok: %s\n' "$name"
}

check "full render" \
  '{
    "workspace": {"current_dir": "/tmp/project"},
    "cost": {"total_cost_usd": 1.17},
    "rate_limits": {
      "five_hour": {"used_percentage": 36, "resets_at": 0},
      "seven_day": {"used_percentage": 70, "resets_at": 0}
    },
    "model": {"display_name": "Sonnet 4"},
    "context_window": {
      "total_input_tokens": 89000,
      "context_window_size": 1000000
    },
    "effort": {"level": "high"},
    "fast_mode": true
  }' \
  '📁project │ 💰$1.17 │ 5h ████░░░░░░36% ⏰0m │ 7d ███████░░░70% ⏰0m │ Sonnet 4 89k/1.0M high⚡'

check "1M-boundary rounding carries into whole millions" \
  '{"context_window": {"total_input_tokens": 1999999, "context_window_size": 2000000}}' \
  '💰$0.00 │ ? 2.0M/2.0M'

check "percentage above 100 clamps to 100" \
  '{"rate_limits": {"five_hour": {"used_percentage": 150, "resets_at": 0}}}' \
  '💰$0.00 │ 5h ██████████100% ⏰0m │ ? 0/0'

check "negative percentage clamps to 0" \
  '{"rate_limits": {"five_hour": {"used_percentage": -10, "resets_at": 0}}}' \
  '💰$0.00 │ 5h ░░░░░░░░░░0% ⏰0m │ ? 0/0'

check "empty stdin skips absent segments but keeps cost + model" \
  '{}' \
  '💰$0.00 │ ? 0/0'

# --- prompt cache warmth (transcript_path) ---
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
now_iso=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

printf '%s\n' \
  '{"type":"user","timestamp":"'"$now_iso"'","message":{"role":"user","content":"hi"}}' \
  '{"type":"assistant","timestamp":"'"$now_iso"'","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":500,"cache_creation_input_tokens":20,"cache_creation":{"ephemeral_1h_input_tokens":20,"ephemeral_5m_input_tokens":0}}}}' \
  > "$tmp/warm1h.jsonl"
check "cache warm 1h shows 60m" \
  '{"transcript_path":"'"$tmp/warm1h.jsonl"'"}' \
  '💰$0.00 │ ? 0/0 │ 🔥60m'

printf '%s\n' \
  '{"type":"assistant","timestamp":"'"$now_iso"'","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":500,"cache_creation_input_tokens":20,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":20}}}}' \
  > "$tmp/warm5m.jsonl"
check "cache warm 5m shows 5m" \
  '{"transcript_path":"'"$tmp/warm5m.jsonl"'"}' \
  '💰$0.00 │ ? 0/0 │ 🔥5m'

printf '%s\n' \
  '{"type":"assistant","timestamp":"2020-01-01T00:00:00.000Z","message":{"usage":{"cache_read_input_tokens":500,"cache_creation_input_tokens":0,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}}}}' \
  '{"type":"assistant","timestamp":"2020-01-01T00:00:01.000Z","message":{"usage":{"cache_read_input_tokens":500,"cache_creation_input_tokens":0}}}' \
  > "$tmp/expired.jsonl"
# ttl never learned -> unknown -> no segment
check "cache ttl unknown shows nothing" \
  '{"transcript_path":"'"$tmp/expired.jsonl"'"}' \
  '💰$0.00 │ ? 0/0'

printf '%s\n' \
  '{"type":"assistant","timestamp":"2020-01-01T00:00:00.000Z","message":{"usage":{"cache_read_input_tokens":500,"cache_creation_input_tokens":20,"cache_creation":{"ephemeral_5m_input_tokens":20}}}}' \
  > "$tmp/cold.jsonl"
check "cache expired shows cold" \
  '{"transcript_path":"'"$tmp/cold.jsonl"'"}' \
  '💰$0.00 │ ? 0/0 │ ❄️cold'

printf '%s\n' \
  '{"type":"assistant","timestamp":"'"$now_iso"'","message":{"usage":{"cache_read_input_tokens":500,"cache_creation_input_tokens":20,"cache_creation":{"ephemeral_1h_input_tokens":20}}}}' \
  '{"type":"user","isCompactSummary":true,"timestamp":"'"$now_iso"'","message":{"content":"summary"}}' \
  > "$tmp/compact.jsonl"
check "compaction after last assistant shows cold" \
  '{"transcript_path":"'"$tmp/compact.jsonl"'"}' \
  '💰$0.00 │ ? 0/0 │ ❄️cold'

check "missing transcript skips cache segment" \
  '{"transcript_path":"/nonexistent/x.jsonl"}' \
  '💰$0.00 │ ? 0/0'
