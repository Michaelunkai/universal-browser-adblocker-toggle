<#
.SYNOPSIS
  Enable popup blocking plus user-toggleable uBlock Origin ad / YouTube ad blocking for Chrome and Firefox.
.DESCRIPTION
  Applies browser policies for Google Chrome and Mozilla Firefox. It blocks pop-ups for all profiles,
  installs uBlock Origin in user-toggleable mode where browser policy supports it, and optionally tries
  to pin/seed toolbar UI preferences for existing local profiles. Run from an elevated PowerShell for
  machine-wide enforcement; without admin rights it falls back to current-user/profile changes where possible.

  One-liner from the project root:
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-BrowserContentBlockers.ps1 -Mode Enable
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Enable','Disable','Status')]
    [string]$Mode = 'Enable',
    [switch]$CurrentUserOnly,
    [switch]$SkipToolbarSeed,
    [switch]$NoRestartPrompt
)

$ErrorActionPreference = 'Stop'
$ChromeUblockId = 'cjpalhdlnbpafiamejdnhcphjbkeiagm'
$ChromeUpdateUrl = 'https://clients2.google.com/service/update2/crx'
$FirefoxUblockId = 'uBlock0@raymondhill.net'
$FirefoxUblockUrl = 'https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Key([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
}

function Set-RegDword([string]$Path, [string]$Name, [int]$Value) {
    Ensure-Key $Path
    if ($PSCmdlet.ShouldProcess("$Path\\$Name", "set DWORD $Value")) {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
    }
}

function Set-RegString([string]$Path, [string]$Name, [string]$Value) {
    Ensure-Key $Path
    if ($PSCmdlet.ShouldProcess("$Path\\$Name", "set string")) {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
    }
}

function Remove-RegValueSafe([string]$Path, [string]$Name) {
    if (Test-Path $Path) {
        if ($PSCmdlet.ShouldProcess("$Path\\$Name", 'remove value')) {
            Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        }
    }
}

function Remove-RegTreeSafe([string]$Path) {
    if (Test-Path $Path) {
        if ($PSCmdlet.ShouldProcess($Path, 'remove key tree')) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ChromeProfileRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    $candidates = @(
        (Join-Path $local 'Google\Chrome\User Data'),
        (Join-Path $local 'Google\Chrome Beta\User Data'),
        (Join-Path $local 'Google\Chrome Dev\User Data'),
        (Join-Path $local 'Google\Chrome SxS\User Data')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { [void]$roots.Add($c) } }
    return $roots
}

function Get-FirefoxProfiles {
    $roaming = [Environment]::GetFolderPath('ApplicationData')
    $ini = Join-Path $roaming 'Mozilla\Firefox\profiles.ini'
    $profiles = New-Object System.Collections.Generic.List[string]
    if (Test-Path $ini) {
        $current = @{}
        foreach ($line in Get-Content -LiteralPath $ini) {
            if ($line -match '^\[') {
                if ($current.ContainsKey('Path')) {
                    $p = $current['Path']
                    if ($current['IsRelative'] -eq '1') { $p = Join-Path (Split-Path $ini -Parent) $p }
                    if (Test-Path $p) { [void]$profiles.Add($p) }
                }
                $current = @{}
            } elseif ($line -match '^(.*?)=(.*)$') {
                $current[$matches[1]] = $matches[2]
            }
        }
        if ($current.ContainsKey('Path')) {
            $p = $current['Path']
            if ($current['IsRelative'] -eq '1') { $p = Join-Path (Split-Path $ini -Parent) $p }
            if (Test-Path $p) { [void]$profiles.Add($p) }
        }
    }
    return $profiles | Select-Object -Unique
}

function Set-ChromePolicies([ValidateSet('Enable','Disable')]$Action, [bool]$Machine) {
    $hive = if ($Machine) { 'HKLM:' } else { 'HKCU:' }
    $base = "$hive\Software\Policies\Google\Chrome"
    $forcelist = "$base\ExtensionInstallForcelist"
    $settings = "$base\ExtensionSettings"
    if ($Action -eq 'Enable') {
        # Native popup blocking: all profiles. This is managed and cannot be bypassed accidentally.
        Set-RegDword $base 'DefaultPopupsSetting' 2
        # uBlock Origin as a normal installed policy extension: installed automatically, but user may disable it.
        # If a Chrome build ignores normal_installed, the forcelist fallback below keeps protection present.
        $extSettings = @{ $ChromeUblockId = @{ installation_mode = 'normal_installed'; update_url = $ChromeUpdateUrl; toolbar_pin = 'force_pinned' } } | ConvertTo-Json -Depth 8 -Compress
        Set-RegString $settings $ChromeUblockId $extSettings
        Set-RegString $forcelist '1' "$ChromeUblockId;$ChromeUpdateUrl"
    } else {
        Remove-RegValueSafe $base 'DefaultPopupsSetting'
        Remove-RegTreeSafe $forcelist
        Remove-RegTreeSafe $settings
    }
}

function Set-FirefoxPolicies([ValidateSet('Enable','Disable')]$Action) {
    $policy = @{
        policies = @{
            PopupBlocking = @{ Default = $true; Locked = $false }
            ExtensionSettings = @{
                $FirefoxUblockId = @{
                    installation_mode = 'normal_installed'
                    install_url = $FirefoxUblockUrl
                }
            }
        }
    }
    $json = $policy | ConvertTo-Json -Depth 12
    $installRoots = @(
        "$env:ProgramFiles\Mozilla Firefox",
        "${env:ProgramFiles(x86)}\Mozilla Firefox"
    ) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($root in $installRoots) {
        $dist = Join-Path $root 'distribution'
        $file = Join-Path $dist 'policies.json'
        if ($Action -eq 'Enable') {
            if ($PSCmdlet.ShouldProcess($file, 'write Firefox policy')) {
                New-Item -ItemType Directory -Path $dist -Force | Out-Null
                Set-Content -LiteralPath $file -Value $json -Encoding UTF8
            }
        } else {
            if (Test-Path $file) {
                if ($PSCmdlet.ShouldProcess($file, 'remove Firefox policy')) { Remove-Item -LiteralPath $file -Force }
            }
        }
    }
}

function Set-FirefoxProfilePopupPrefs([ValidateSet('Enable','Disable')]$Action) {
    foreach ($profile in Get-FirefoxProfiles) {
        $userjs = Join-Path $profile 'user.js'
        $markerStart = '// BEGIN universal-browser-adblocker-toggle'
        $markerEnd = '// END universal-browser-adblocker-toggle'
        $existing = if (Test-Path $userjs) { Get-Content -LiteralPath $userjs -Raw } else { '' }
        $clean = [regex]::Replace($existing, "(?ms)^\Q$markerStart\E.*?^\Q$markerEnd\E\r?\n?", '')
        if ($Action -eq 'Enable') {
            $block = @"
$markerStart
user_pref("dom.disable_open_during_load", true);
user_pref("privacy.popups.showBrowserMessage", true);
$markerEnd
"@
            if ($PSCmdlet.ShouldProcess($userjs, 'write Firefox profile popup prefs')) { Set-Content -LiteralPath $userjs -Value ($clean.TrimEnd() + "`r`n" + $block) -Encoding UTF8 }
        } else {
            if ($PSCmdlet.ShouldProcess($userjs, 'remove managed popup prefs block')) { Set-Content -LiteralPath $userjs -Value $clean -Encoding UTF8 }
        }
    }
}

function Seed-ChromeToolbarPins {
    foreach ($root in Get-ChromeProfileRoots) {
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } | ForEach-Object {
            $pref = Join-Path $_.FullName 'Preferences'
            if (Test-Path $pref) {
                try {
                    $json = Get-Content -LiteralPath $pref -Raw | ConvertFrom-Json
                    if (-not $json.extensions) { $json | Add-Member -NotePropertyName extensions -NotePropertyValue ([pscustomobject]@{}) }
                    if (-not $json.extensions.toolbar) { $json.extensions | Add-Member -NotePropertyName toolbar -NotePropertyValue ([pscustomobject]@{}) }
                    if (-not $json.extensions.toolbar.pinned_extensions) { $json.extensions.toolbar | Add-Member -NotePropertyName pinned_extensions -NotePropertyValue @() }
                    if ($json.extensions.toolbar.pinned_extensions -notcontains $ChromeUblockId) { $json.extensions.toolbar.pinned_extensions += $ChromeUblockId }
                    if ($PSCmdlet.ShouldProcess($pref, 'seed Chrome toolbar pin preference')) {
                        $json | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $pref -Encoding UTF8
                    }
                } catch { Write-Warning "Could not seed Chrome toolbar pin for $pref : $($_.Exception.Message)" }
            }
        }
    }
}

function Show-Status {
    $isAdmin = Test-IsAdmin
    [pscustomobject]@{
        IsAdministrator = $isAdmin
        ChromePolicyHKLM = Test-Path 'HKLM:\Software\Policies\Google\Chrome'
        ChromePolicyHKCU = Test-Path 'HKCU:\Software\Policies\Google\Chrome'
        ChromeProfileRoots = @(Get-ChromeProfileRoots)
        FirefoxProfiles = @(Get-FirefoxProfiles)
        FirefoxPolicyFiles = @("$env:ProgramFiles\Mozilla Firefox\distribution\policies.json", "${env:ProgramFiles(x86)}\Mozilla Firefox\distribution\policies.json") | Where-Object { $_ -and (Test-Path $_) }
    } | Format-List
}

if ($Mode -eq 'Status') { Show-Status; return }

$admin = Test-IsAdmin
$machine = $admin -and (-not $CurrentUserOnly)
if (-not $admin -and -not $CurrentUserOnly) {
    Write-Warning 'Not running elevated. Chrome machine policy and Firefox Program Files policy may require admin. Applying current-user/profile-safe parts; rerun as Administrator for full machine-wide enforcement.'
}

Set-ChromePolicies -Action $Mode -Machine:$machine
if (-not $machine) { Set-ChromePolicies -Action $Mode -Machine:$false }
Set-FirefoxPolicies -Action $Mode
Set-FirefoxProfilePopupPrefs -Action $Mode
if ($Mode -eq 'Enable' -and -not $SkipToolbarSeed) { Seed-ChromeToolbarPins }

Write-Host "Mode $Mode completed. Restart Chrome and Firefox for managed policies to reload."
Write-Host 'uBlock Origin provides the top-right browser button/menu toggle for ad blocking and YouTube ad filtering; popup blocking is enforced by browser policy/preferences.'
if (-not $NoRestartPrompt) { Write-Host 'Tip: run with -NoRestartPrompt for unattended deployment.' }
Show-Status
