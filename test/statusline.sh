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
  '📁 project │ 💰 $1.17 │ 5h ████░░░░░░ 36% ⏰ 0m │ 7d ███████░░░ 70% ⏰ 0m │ Sonnet 4 89k/1.0M high⚡'

check "1M-boundary rounding carries into whole millions" \
  '{"context_window": {"total_input_tokens": 1999999, "context_window_size": 2000000}}' \
  '💰 $0.00 │ ? 2.0M/2.0M'

check "percentage above 100 clamps to 100" \
  '{"rate_limits": {"five_hour": {"used_percentage": 150, "resets_at": 0}}}' \
  '💰 $0.00 │ 5h ██████████ 100% ⏰ 0m │ ? 0/0'

check "negative percentage clamps to 0" \
  '{"rate_limits": {"five_hour": {"used_percentage": -10, "resets_at": 0}}}' \
  '💰 $0.00 │ 5h ░░░░░░░░░░ 0% ⏰ 0m │ ? 0/0'

check "empty stdin skips absent segments but keeps cost + model" \
  '{}' \
  '💰 $0.00 │ ? 0/0'
