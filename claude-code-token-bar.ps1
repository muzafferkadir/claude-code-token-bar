#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
  Claude Code statusline — pure stdin, zero cache, zero external dependencies.

.DESCRIPTION
  PowerShell port of the `claude-code-token-bar` bash script, for Windows hosts
  where `bash` and `jq` are not available. Output is byte-for-byte identical to
  the bash implementation for the same input: test/statusline.ps1 reuses the
  expectations from test/statusline.sh, and test/parity.ps1 diffs the two
  implementations' raw bytes directly.

  All data comes from the JSON Claude Code writes to stdin (including the
  currently authenticated account's real rate limits). Nothing is cached and
  no background process is spawned.

.NOTES
  Set CCTB_DEBUG=1 to surface errors on stderr. By default this script is
  silent on failure and always exits 0 — a broken statusline is worse than a
  blank one.
#>

# Native command failures are handled explicitly (git may legitimately fail).
$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'

# Deliberately no Set-StrictMode here: it costs ~45 ms of the ~390 ms render,
# by far the largest cost this script controls. Nothing depends on it, because
# every field read goes through Get-JsonPath rather than bare property access.
# The test suite does set it and dot-sources this file, so the functions are
# still verified to be strict-clean — the check happens once in CI instead of
# on every keystroke.

# The bash/jq original formats numbers with '.' as the decimal separator. Pin
# the culture so a locale such as tr-TR cannot turn "$1.17" into "$1,17".
[System.Threading.Thread]::CurrentThread.CurrentCulture =
    [System.Globalization.CultureInfo]::InvariantCulture

#region jq primitives
# Each function below mirrors one `def` in the jq program, same name order, so
# the two implementations can be diffed side by side.

# jq's `round` rounds half away from zero; .NET's default is banker's rounding.
function ConvertTo-JqRound([double]$Value) {
    [Math]::Round($Value, [MidpointRounding]::AwayFromZero)
}

# jq's `%` truncates both operands to integers before dividing.
function Get-JqMod([double]$Value, [double]$Divisor) {
    [long][Math]::Truncate($Value) % [long][Math]::Truncate($Divisor)
}

# def lpad
function Format-Lpad([long]$Value) {
    if ($Value -lt 10) { "0$Value" } else { "$Value" }
}

# def money: 1.17 -> "$1.17" (always 2 decimals)
function Format-Money([double]$Usd) {
    $cents = ConvertTo-JqRound ($Usd * 100)
    $whole = [long][Math]::Floor($cents / 100)
    $rem = [long](Get-JqMod $cents 100)
    $frac = if ($rem -lt 10) { "0$rem" } else { "$rem" }
    '$' + $whole + '.' + $frac
}

# def tok: token count -> "56k" / "1.0M"
function Format-TokenCount([double]$Count) {
    if ($Count -ge 1000000) {
        $tenths = [long](ConvertTo-JqRound ($Count / 100000))
        $whole = [long][Math]::Floor($tenths / 10)
        $digit = [long](Get-JqMod $tenths 10)
        "$whole.${digit}M"
    }
    elseif ($Count -ge 1000) {
        "$([long](ConvertTo-JqRound ($Count / 1000)))k"
    }
    else {
        # jq renders integral floats without a decimal point.
        if ($Count -eq [Math]::Floor($Count)) { "$([long]$Count)" }
        else { $Count.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    }
}

# def dur: seconds -> "4h51m" / "1d00h" / "0m"
function Format-Duration([double]$Seconds) {
    if ($Seconds -le 0) { return '0m' }
    $d = [long][Math]::Floor($Seconds / 86400)
    $h = [long][Math]::Floor((Get-JqMod $Seconds 86400) / 3600)
    $m = [long][Math]::Floor((Get-JqMod $Seconds 3600) / 60)
    if ($d -gt 0) { "${d}d$(Format-Lpad $h)h" }
    elseif ($h -gt 0) { "${h}h$(Format-Lpad $m)m" }
    else { "${m}m" }
}

# ANSI
$RESET = "`e[0m"
$DIM = "`e[2m"
$BOLD = "`e[1m"
$YELLOW = "`e[33m"
$SEP = "$DIM │ $RESET"

# def pctcolor
function Get-PctColor([double]$Pct) {
    if ($Pct -ge 70) { "`e[31m" } elseif ($Pct -ge 30) { "`e[33m" } else { "`e[32m" }
}

# def trunc(n)
# jq counts codepoints, .NET counts UTF-16 units; identical for BMP text,
# which covers every git branch name in practice.
function Format-Trunc([string]$Text, [int]$Max) {
    if ($Text.Length -gt $Max) { $Text.Substring(0, $Max) + '…' } else { $Text }
}

# def clamp0_100
function Get-Clamped([double]$Pct) {
    if ($Pct -lt 0) { 0 } elseif ($Pct -gt 100) { 100 } else { $Pct }
}

# def bar: percentage -> 10-cell colored bar
function Format-Bar([double]$Pct) {
    $filled = [long](ConvertTo-JqRound ($Pct / 10))
    $empty = 10 - $filled
    (Get-PctColor $Pct) +
    $(if ($filled -gt 0) { '█' * $filled } else { '' }) +
    $DIM +
    $(if ($empty -gt 0) { '░' * $empty } else { '' }) +
    $RESET
}

# def ratelim(lbl): label + bar + % + countdown to reset
function Format-RateLimit($Limit, [string]$Label, [double]$Now) {
    $pct = Get-Clamped ([double](Get-JsonValueOrDefault (Get-JsonPath $Limit 'used_percentage') 0))
    $resetsAt = [double](Get-JsonValueOrDefault (Get-JsonPath $Limit 'resets_at') 0)
    $remaining = [Math]::Floor($resetsAt - $Now)

    $Label + ' ' + (Format-Bar $pct) + ' ' + (Get-PctColor $pct) +
    "$([long](ConvertTo-JqRound $pct))%" + $RESET +
    $DIM + ' ⏰ ' + $RESET + (Format-Duration $remaining)
}
#endregion

#region Input access

<#
Safe nested lookup, the equivalent of jq's `.a.b` returning null instead of
erroring on a missing key. Plain `$json.a.b` would throw under Set-StrictMode
whenever Claude Code omits a field, which it routinely does.
#>
function Get-JsonPath($Node, [string[]]$Path) {
    foreach ($name in $Path) {
        if ($null -eq $Node) { return $null }
        $prop = $Node.PSObject.Properties[$name]
        if ($null -eq $prop) { return $null }
        $Node = $prop.Value
    }
    return $Node
}

# jq's `a // b`: fall back when the value is null, false, or an empty string.
function Get-JsonValueOrDefault($Value, $Default) {
    if ($null -eq $Value -or $Value -eq '' -or $Value -eq $false) { return $Default }
    return $Value
}
#endregion

#region Windows-aware helpers

<#
Mirrors jq's `split("/") | .[-1]`, but splits on '\' as well so Windows paths
resolve to their leaf. Deliberately keeps jq's semantics of returning the last
element even when empty ("/tmp/" -> ""), rather than using Split-Path -Leaf,
which would return "tmp" and break parity with the bash implementation.
#>
function Get-PathLeaf([string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) { return '' }
    $parts = $Path -split '[/\\]'
    $parts[-1]
}

# Returns @{ Branch = <string>; Dirty = <bool> } — both empty/false when the
# directory is not a git work tree, or git is unavailable.
function Get-GitState([string]$Cwd) {
    $state = @{ Branch = ''; Dirty = $false }
    if ([string]::IsNullOrEmpty($Cwd)) { return $state }

    try {
        $lines = & git -C $Cwd status --porcelain=v2 --branch 2>$null
    }
    catch {
        return $state
    }
    if (-not $lines) { return $state }

    foreach ($line in $lines) {
        if ($line -like '# branch.head *') {
            $state.Branch = ($line -split ' ')[2]
        }
        elseif ($line -notlike '#*') {
            $state.Dirty = $true
        }
    }
    return $state
}
#endregion

function Build-StatusLine($Json, [double]$Now) {
    # jq: .workspace.current_dir // .cwd // ""
    $cwd = [string](Get-JsonValueOrDefault (Get-JsonPath $Json 'workspace', 'current_dir') `
        (Get-JsonValueOrDefault (Get-JsonPath $Json 'cwd') ''))

    # --- 📁dir (branch) — dropped entirely when there is nothing to show ---
    $leaf = Get-PathLeaf $cwd
    $git = Get-GitState $cwd

    $dirseg = ''
    if ($leaf -ne '') { $dirseg += "$BOLD📁 $leaf$RESET" }
    if ($git.Branch -ne '') {
        $branchColor = if ($git.Dirty) { $YELLOW } else { $DIM }
        $dirseg += $branchColor + ' (' + (Format-Trunc $git.Branch 10) + ')' + $RESET
    }
    if ($dirseg -ne '') { $dirseg += $SEP }

    # --- 💰session cost ---
    $cost = [double](Get-JsonValueOrDefault (Get-JsonPath $Json 'cost', 'total_cost_usd') 0)
    $line = $dirseg + $YELLOW + '💰 ' + (Format-Money $cost) + $RESET

    # --- rate limit bars ---
    $fiveHour = Get-JsonPath $Json 'rate_limits', 'five_hour'
    if ($fiveHour) { $line += $SEP + (Format-RateLimit $fiveHour '5h' $Now) }

    $sevenDay = Get-JsonPath $Json 'rate_limits', 'seven_day'
    if ($sevenDay) { $line += $SEP + (Format-RateLimit $sevenDay '7d' $Now) }

    # --- model + context window + mode flags ---
    $model = [string](Get-JsonValueOrDefault (Get-JsonPath $Json 'model', 'display_name') '?')
    $used = [double](Get-JsonValueOrDefault (Get-JsonPath $Json 'context_window', 'total_input_tokens') 0)
    $size = [double](Get-JsonValueOrDefault (Get-JsonPath $Json 'context_window', 'context_window_size') 0)

    $line += $SEP + $BOLD + $model + $RESET + ' ' + $DIM +
    (Format-TokenCount $used) + '/' + (Format-TokenCount $size) + $RESET

    # def modeflags: effort level + ⚡fast mode
    $flags = [string](Get-JsonValueOrDefault (Get-JsonPath $Json 'effort', 'level') '')
    if (Get-JsonPath $Json 'fast_mode') { $flags += '⚡' }
    if ($flags -ne '') { $line += $DIM + ' ' + $flags + $RESET }

    return $line
}

# Dot-sourcing (the test suite) loads the functions above without rendering.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
    # Read stdin as raw bytes and decode UTF-8 explicitly: the console's own
    # encoding is unreliable on Windows and would mangle non-ASCII paths.
    $stdin = [Console]::OpenStandardInput()
    $buffer = [System.IO.MemoryStream]::new()
    $stdin.CopyTo($buffer)
    $raw = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())

    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $json = $raw | ConvertFrom-Json
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
    $line = Build-StatusLine $json $now

    # Write UTF-8 bytes straight to stdout, no trailing newline (jq -rj).
    $out = [Console]::OpenStandardOutput()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
    $out.Write($bytes, 0, $bytes.Length)
    $out.Flush()
}
catch {
    if ($env:CCTB_DEBUG) { [Console]::Error.WriteLine(($_ | Out-String)) }
    exit 0
}
