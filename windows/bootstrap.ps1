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

# $ErrorActionPreference = 'Stop' only catches PowerShell-level errors: a
# cmdlet throwing, or a command that does not exist. It does nothing for a
# native executable -- winget.exe here -- that runs, writes to stdout or
# stderr, and returns a non-zero exit code; PowerShell treats that call as
# having succeeded and moves on to the next line regardless. This is not
# theoretical: the first real run of this script called an obsolete winget
# flag, which printed a wall of usage text to the console and let the script
# carry on as if nothing were wrong, because nothing here was checking
# $LASTEXITCODE. Every winget invocation below is followed by a call to this
# so a real failure stops the script instead of being silently absorbed.
function Assert-WingetSuccess([string]$What) {
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed (winget exited $LASTEXITCODE)."
    }
}

# winget configure landed in v1.6.2631. Asserting the floor turns "the command
# does nothing recognisable" into a sentence that says why.
Write-Step 'Checking winget version'
$wingetVersion = (winget --version).TrimStart('v')
Assert-WingetSuccess 'winget --version'
$required = [version]'1.6.2631'
if ([version]($wingetVersion -split '-')[0] -lt $required) {
    throw "winget $wingetVersion is older than $required, which is where 'winget configure' was added. Update from the Microsoft Store (App Installer)."
}
Write-Host "    winget $wingetVersion"

# Configuration used to require a one-time `winget settings --enable
# Configuration` acknowledgement on older winget. It does not on this
# machine's winget (1.29.280): the setting no longer exists, and passing it
# is rejected with a wall of usage text -- which is exactly what exposed the
# missing exit-code check above. Configuration is enabled by default now, so
# there is nothing to do here. Left as a comment, not silently deleted, so
# nobody re-adds this line from an old blog post.

Write-Step 'Applying the host configuration'
winget configure $manifest --accept-configuration-agreements
Assert-WingetSuccess 'winget configure'

Write-Step 'Host layer applied.'
Write-Host ''
Write-Host 'Next, inside Ubuntu:' -ForegroundColor Yellow
Write-Host '  git clone https://github.com/camilopiedra92/workstation ~/workstation'
Write-Host '  ~/workstation/wsl/install.sh'
