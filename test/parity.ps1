#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
  Asserts that the bash and PowerShell implementations emit byte-identical
  output for the same input — the claim that justifies shipping two runtimes.

  Requires bash + jq alongside pwsh. Skips (exit 0) when they are absent, so
  Windows contributors without bash can still run the rest of the suite.

  Fixtures must render deterministically: `resets_at` is always 0 so both
  implementations floor to "0m" instead of racing across a second boundary,
  and paths point at directories that are not git work trees.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$root = Split-Path -Parent $PSScriptRoot
$bashBin = Join-Path $root 'claude-code-token-bar'
$pwshBin = Join-Path $root 'claude-code-token-bar.ps1'

$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bashCmd -or -not (Get-Command jq -ErrorAction SilentlyContinue)) {
    [Console]::Out.WriteLine('skip: parity check requires bash and jq')
    exit 0
}

# Resolve bash to a full path. Process creation follows the Win32 search order,
# which checks the system directory before PATH — leaving FileName as "bash"
# would pick up WSL's C:\Windows\System32\bash.exe, which cannot read Windows
# paths, instead of the Git for Windows bash that PATH actually points at.
$bash = $bashCmd.Source
$pwshExe = (Get-Process -Id $PID).Path

$fixtures = @(
    @{ name = 'full render'; json = '{"workspace":{"current_dir":"/nonexistent/project"},"cost":{"total_cost_usd":1.17},"rate_limits":{"five_hour":{"used_percentage":36,"resets_at":0},"seven_day":{"used_percentage":70,"resets_at":0}},"model":{"display_name":"Sonnet 4"},"context_window":{"total_input_tokens":89000,"context_window_size":1000000},"effort":{"level":"high"},"fast_mode":true}' }
    @{ name = 'empty object'; json = '{}' }
    @{ name = 'cost only'; json = '{"cost":{"total_cost_usd":0.125}}' }
    @{ name = 'cost rounds up'; json = '{"cost":{"total_cost_usd":12.3456}}' }
    @{ name = 'zero cost'; json = '{"cost":{"total_cost_usd":0}}' }
    @{ name = 'clamp high'; json = '{"rate_limits":{"five_hour":{"used_percentage":150,"resets_at":0}}}' }
    @{ name = 'clamp low'; json = '{"rate_limits":{"five_hour":{"used_percentage":-10,"resets_at":0}}}' }
    @{ name = 'bar midpoint 25'; json = '{"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":0}}}' }
    @{ name = 'bar midpoint 35'; json = '{"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":0}}}' }
    @{ name = 'color boundary 30'; json = '{"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":0}}}' }
    @{ name = 'color boundary 70'; json = '{"rate_limits":{"seven_day":{"used_percentage":70,"resets_at":0}}}' }
    @{ name = 'tokens under 1k'; json = '{"context_window":{"total_input_tokens":999,"context_window_size":0}}' }
    @{ name = 'tokens k range'; json = '{"context_window":{"total_input_tokens":89000,"context_window_size":200000}}' }
    @{ name = 'tokens 1M boundary'; json = '{"context_window":{"total_input_tokens":1999999,"context_window_size":2000000}}' }
    @{ name = 'tokens exact 1M'; json = '{"context_window":{"total_input_tokens":1000000,"context_window_size":1000000}}' }
    @{ name = 'effort only'; json = '{"effort":{"level":"medium"}}' }
    @{ name = 'fast mode only'; json = '{"fast_mode":true}' }
    @{ name = 'fast mode false'; json = '{"fast_mode":false}' }
    @{ name = 'model name'; json = '{"model":{"display_name":"Opus 5"}}' }
    @{ name = 'cwd fallback'; json = '{"cwd":"/nonexistent/api"}' }
    @{ name = 'trailing slash yields no leaf'; json = '{"cwd":"/nonexistent/"}' }
)

function Invoke-Bin([string]$Json, [string[]]$Command) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Command[0]
    foreach ($a in $Command[1..($Command.Length - 1)]) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Write($Json)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    return $stdout
}

function ConvertTo-HexString([string]$Text) {
    ([System.Text.Encoding]::UTF8.GetBytes($Text) | ForEach-Object { $_.ToString('x2') }) -join ' '
}

$failures = 0
foreach ($fixture in $fixtures) {
    $fromBash = Invoke-Bin $fixture.json @($bash, $bashBin)
    $fromPwsh = Invoke-Bin $fixture.json @($pwshExe, '-NoProfile', '-File', $pwshBin)

    if ($fromBash -cne $fromPwsh) {
        [Console]::Error.WriteLine("FAIL: $($fixture.name)")
        [Console]::Error.WriteLine("  bash: $(ConvertTo-HexString $fromBash)")
        [Console]::Error.WriteLine("  pwsh: $(ConvertTo-HexString $fromPwsh)")
        $failures++
        continue
    }
    [Console]::Out.WriteLine("ok: $($fixture.name)")
}

if ($failures -gt 0) {
    [Console]::Error.WriteLine("$failures parity mismatch(es)")
    exit 1
}
[Console]::Out.WriteLine("all $($fixtures.Count) fixtures render identically in bash and pwsh")