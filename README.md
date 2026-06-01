# universal-browser-adblocker-toggle

Repository: https://github.com/Michaelunkai/universal-browser-adblocker-toggle

A Windows PowerShell project that applies browser-wide pop-up blocking plus uBlock Origin ad blocking / YouTube ad filtering for Chrome and Firefox profiles from one command.

The main entry point is:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-BrowserContentBlockers.ps1 -Mode Enable
```

Run that from the project root. For full machine-wide enforcement, open PowerShell **as Administrator** first.

## What it does

- Google Chrome:
  - Sets the managed `DefaultPopupsSetting = 2` policy so pop-ups are blocked for every Chrome profile that uses the normal Google Chrome policy path.
  - Adds uBlock Origin (`cjpalhdlnbpafiamejdnhcphjbkeiagm`) through Chrome extension policy.
  - Seeds existing local profile preferences to pin the uBlock toolbar icon where Chrome accepts the preference.
- Mozilla Firefox:
  - Writes a Firefox `policies.json` using `PopupBlocking` and uBlock Origin (`uBlock0@raymondhill.net`).
  - Updates existing Firefox profile `user.js` files to keep pop-up blocking enabled.
- Toggle behavior:
  - uBlock Origin supplies the visible top-right browser extension button/menu for disabling/enabling filtering on a site.
  - This project also includes a script-level global toggle: run `-Mode Disable` to remove the policies/prefs written by this tool, or `-Mode Enable` to re-apply them.

## Prerequisites

- Windows 10/11.
- Windows PowerShell 5.1 or PowerShell 7+.
- Google Chrome and/or Mozilla Firefox installed.
- Internet access so the browser can download uBlock Origin from the Chrome Web Store / Mozilla Add-ons.
- Administrator PowerShell is recommended for all-machine Chrome/Firefox policy writes.

## Setup

No package installation is required. Clone or download this repo, then open PowerShell in the repo root.

## Usage

Enable protection:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-BrowserContentBlockers.ps1 -Mode Enable
```

Disable/remove the policies and profile prefs created by this project:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-BrowserContentBlockers.ps1 -Mode Disable
```

Show status:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-BrowserContentBlockers.ps1 -Mode Status
```

Current-user fallback when you do not have admin rights:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-BrowserContentBlockers.ps1 -Mode Enable -CurrentUserOnly
```

Dry-run with PowerShell `WhatIf`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-BrowserContentBlockers.ps1 -Mode Enable -WhatIf
```

## Inputs and outputs

Inputs:

- `-Mode Enable`, `Disable`, or `Status`.
- Optional `-CurrentUserOnly`, `-SkipToolbarSeed`, and `-NoRestartPrompt` switches.

Outputs:

- Chrome policy registry keys under `HKLM:\Software\Policies\Google\Chrome` when elevated, or `HKCU:\Software\Policies\Google\Chrome` for current-user fallback.
- Firefox `distribution\policies.json` under installed Firefox directories when permission allows.
- Firefox profile `user.js` marker block for popup prevention.
- Console status showing detected Chrome roots, Firefox profiles, and policy files.

## Important files

- `scripts/Install-BrowserContentBlockers.ps1` — the runnable installer/toggler.
- `run-enable-from-project-root.ps1` — tiny one-line wrapper example.
- `tests/Test-Static.ps1` — static parse/token check for the PowerShell script.
- `.gitignore` — excludes logs, caches, secrets, and transient files.

## Troubleshooting

- Restart Chrome and Firefox after enabling or disabling. Browser policies are commonly read at startup.
- If Firefox policy write fails, rerun PowerShell as Administrator.
- If uBlock does not appear immediately, open `chrome://policy` or `about:policies`, reload policies, and restart the browser.
- Chrome may place the extension under the extensions menu instead of directly pinned to the toolbar on some builds. The uBlock button is still accessible from the top-right extensions/puzzle-piece menu.
- Fully force-installed extensions cannot always be user-disabled. This project uses user-toggleable policy installation for uBlock where supported, while keeping popup blocking enforced by policy/profile preferences.

## Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .	ests\Test-Static.ps1
```

This verifies that the main script parses and includes the expected Chrome, Firefox, popup, and uBlock policy implementation tokens.
