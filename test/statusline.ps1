#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
  Mirrors test/statusline.sh for the PowerShell implementation.
  The first five cases use byte-identical fixtures and expectations, so any
  drift between the two implementations shows up here as well as in parity.ps1.

  No test framework required — same zero-dependency stance as the tool itself.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root 'claude-code-token-bar.ps1'
$failures = 0

function ConvertTo-PlainText([string]$Text) { $Text -replace "`e\[[0-9;]*m", '' }

# NB: the parameter must not be named $Input — that is an automatic variable
# holding the pipeline enumerator, and shadowing it silently breaks the pipe.
function Test-Case([string]$Name, [string]$Json, [string]$Expected) {
    $actual = ConvertTo-PlainText ($Json | pwsh -NoProfile -File $bin)
    if ($actual -cne $Expected) {
        [Console]::Error.WriteLine("FAIL: $Name`nexpected: $Expected`nactual:   $actual")
        $script:failures++
        return
    }
    [Console]::Out.WriteLine("ok: $Name")
}

# --- Shared fixtures: expectations copied verbatim from test/statusline.sh ---

Test-Case 'full render' @'
{
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
}
'@ '📁 project │ 💰 $1.17 │ 5h ████░░░░░░ 36% ⏰ 0m │ 7d ███████░░░ 70% ⏰ 0m │ Sonnet 4 89k/1.0M high⚡'

Test-Case '1M-boundary rounding carries into whole millions' `
    '{"context_window": {"total_input_tokens": 1999999, "context_window_size": 2000000}}' `
    '💰 $0.00 │ ? 2.0M/2.0M'

Test-Case 'percentage above 100 clamps to 100' `
    '{"rate_limits": {"five_hour": {"used_percentage": 150, "resets_at": 0}}}' `
    '💰 $0.00 │ 5h ██████████ 100% ⏰ 0m │ ? 0/0'

Test-Case 'negative percentage clamps to 0' `
    '{"rate_limits": {"five_hour": {"used_percentage": -10, "resets_at": 0}}}' `
    '💰 $0.00 │ 5h ░░░░░░░░░░ 0% ⏰ 0m │ ? 0/0'

Test-Case 'empty stdin skips absent segments but keeps cost + model' `
    '{}' `
    '💰 $0.00 │ ? 0/0'

# --- Rounding: .NET rounds midpoints to even, jq rounds away from zero ---

Test-Case 'bar midpoint rounds away from zero, not to even' `
    '{"rate_limits": {"five_hour": {"used_percentage": 25, "resets_at": 0}}}' `
    '💰 $0.00 │ 5h ███░░░░░░░ 25% ⏰ 0m │ ? 0/0'

Test-Case 'cost midpoint rounds away from zero, not to even' `
    '{"cost": {"total_cost_usd": 0.125}}' `
    '💰 $0.13 │ ? 0/0'

# --- Windows-specific path handling (the bash version never sees these) ---

Test-Case 'windows drive path resolves to leaf directory' `
    '{"workspace": {"current_dir": "C:\\Users\\Fatih\\project"}}' `
    '📁 project │ 💰 $0.00 │ ? 0/0'

Test-Case 'windows UNC path resolves to leaf directory' `
    '{"workspace": {"current_dir": "\\\\server\\share\\proj"}}' `
    '📁 proj │ 💰 $0.00 │ ? 0/0'

Test-Case 'windows drive root has no leaf, so segment is dropped' `
    '{"workspace": {"current_dir": "C:\\"}}' `
    '💰 $0.00 │ ? 0/0'

Test-Case 'cwd falls back to .cwd when workspace is absent' `
    '{"cwd": "D:\\work\\api"}' `
    '📁 api │ 💰 $0.00 │ ? 0/0'

# --- Malformed input must never break the status line ---

Test-Case 'invalid json renders nothing and exits cleanly' 'not json at all' ''
Test-Case 'empty stdin renders nothing and exits cleanly' '' ''

# --- Duration formatting ---

$future = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 86400 + (7 * 3600) + 120
Test-Case 'countdown over a day renders as XdYYh' `
    "{`"rate_limits`": {`"five_hour`": {`"used_percentage`": 0, `"resets_at`": $future}}}" `
    '💰 $0.00 │ 5h ░░░░░░░░░░ 0% ⏰ 1d07h │ ? 0/0'

# --- Locale: tr-TR uses ',' as the decimal separator ---
# Run in-process so the culture actually applies to the rendering code.

. $bin
$originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
try {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
    $json = '{"cost": {"total_cost_usd": 1.17}, "context_window": {"total_input_tokens": 1500000, "context_window_size": 2000000}}' | ConvertFrom-Json
    $actual = ConvertTo-PlainText (Build-StatusLine $json 0)
    $expected = '💰 $1.17 │ ? 1.5M/2.0M'
    if ($actual -cne $expected) {
        [Console]::Error.WriteLine("FAIL: tr-TR locale must not change number formatting`nexpected: $expected`nactual:   $actual")
        $failures++
    }
    else {
        [Console]::Out.WriteLine('ok: tr-TR locale must not change number formatting')
    }
}
finally {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
}

if ($failures -gt 0) {
    [Console]::Error.WriteLine("$failures test(s) failed")
    exit 1
}
[Console]::Out.WriteLine('all tests passed')