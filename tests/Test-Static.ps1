[CmdletBinding()]
param([string]$ScriptPath)
$ErrorActionPreference = 'Stop'
if (-not $ScriptPath) {
  $here = Split-Path -Parent $MyInvocation.MyCommand.Path
  $ScriptPath = Join-Path $here '..\scripts\Install-BrowserContentBlockers.ps1'
}
$resolved = (Resolve-Path $ScriptPath).Path
$tokens = $null; $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($resolved, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) { $errors | Format-List | Out-String | Write-Error; exit 1 }
$text = Get-Content -LiteralPath $resolved -Raw
foreach ($needle in @('DefaultPopupsSetting', 'cjpalhdlnbpafiamejdnhcphjbkeiagm', 'uBlock0@raymondhill.net', 'PopupBlocking', 'normal_installed')) {
  if ($text -notmatch [regex]::Escape($needle)) { throw "Missing expected implementation token: $needle" }
}
Write-Host 'Static PowerShell parse and implementation-token checks passed.'
