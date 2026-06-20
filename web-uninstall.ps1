#!/usr/bin/env pwsh
#
# One-line PowerShell uninstaller for git-review-workflow. Removes the commands
# web-install.ps1 installed and undoes the user PATH entry it added. Run with:
#
#     irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-uninstall.ps1 | iex
#
# Override the install dir with $env:PREFIX, matching how you installed:
#
#     $env:PREFIX = 'C:\tools\bin'; irm .../web-uninstall.ps1 | iex
#
# This only removes the commands and the PATH entry. It never touches any
# review/* or review-fixes/* branches you may have created.
#
$ErrorActionPreference = 'Stop'

$installDir = if ($env:PREFIX) { $env:PREFIX } else { "$env:USERPROFILE\.local\bin" }

$cmds = @(
    'git-review', 'git-review-pr', 'git-review-next', 'git-review-prev',
    'git-review-status', 'git-review-list', 'git-review-abort',
    'git-finish-review', 'git-clean-review', 'git-review-forget'
)

$removed = @()
foreach ($cmd in $cmds) {
    $p = Join-Path $installDir $cmd
    if (Test-Path $p) {
        Remove-Item $p -Force
        $removed += $cmd
    }
}

if ($removed.Count -gt 0) {
    Write-Host "Removed git review commands from ${installDir}: $($removed -join ', ')"
} else {
    Write-Host "No git review commands found in $installDir - nothing to remove."
}

# Undo the user PATH entry web-install.ps1 added, but only if this directory is
# now empty (or gone) - i.e. nothing else lives there. web-install.ps1 only adds
# the entry when it was absent, and a pre-existing .local\bin commonly holds
# other tools (pip --user, pipx, ...); stripping it from PATH then would break
# the user's setup for software we never installed. If other files remain, the
# user relies on this directory, so leave every PATH entry untouched.
$dirHasOtherFiles = (Test-Path $installDir) -and `
    ($null -ne (Get-ChildItem -Force $installDir | Select-Object -First 1))
if (-not $dirHasOtherFiles) {
    $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath) {
        $sep = [System.IO.Path]::PathSeparator
        $entries = $userPath -split [regex]::Escape($sep)
        $kept = $entries | Where-Object { $_ -ne '' -and $_ -ne $installDir }
        if ($kept.Count -ne ($entries | Where-Object { $_ -ne '' }).Count) {
            [System.Environment]::SetEnvironmentVariable('PATH', ($kept -join $sep), 'User')
            Write-Host "note: removed $installDir from your user PATH - open a new terminal for the change to take effect"
        }
    }
}
