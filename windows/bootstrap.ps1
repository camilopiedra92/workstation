# The one imperative step in this repo.
#
# Everything it can hand to a declarative tool, it hands over: the whole host
# layer is configuration.winget, and this script's job is to get winget to a
# state where it can apply it, then get out of the way.
#
# Usage (PowerShell, from the repo root):
#   .\windows\bootstrap.ps1
#
# Re-running is safe. winget configure is idempotent by design: it applies only
# what is not already in the desired state.

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $PSScriptRoot 'configuration.winget'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Blue }

# winget configure landed in v1.6.2631. Asserting the floor turns "the command
# does nothing recognisable" into a sentence that says why.
Write-Step 'Checking winget version'
$wingetVersion = (winget --version).TrimStart('v')
$required = [version]'1.6.2631'
if ([version]($wingetVersion -split '-')[0] -lt $required) {
    throw "winget $wingetVersion is older than $required, which is where 'winget configure' was added. Update from the Microsoft Store (App Installer)."
}
Write-Host "    winget $wingetVersion"

# Enabling configuration is a one-time, per-machine acknowledgement. It is
# separate from applying anything, and asking for it here rather than letting
# the apply fail is the difference between a prompt and an error.
Write-Step 'Enabling winget configuration'
winget settings --enable Configuration

Write-Step 'Applying the host configuration'
winget configure $manifest --accept-configuration-agreements

Write-Step 'Host layer applied.'
Write-Host ''
Write-Host 'Next, inside Ubuntu:' -ForegroundColor Yellow
Write-Host '  git clone https://github.com/camilopiedra92/workstation ~/workstation'
Write-Host '  ~/workstation/wsl/install.sh'
