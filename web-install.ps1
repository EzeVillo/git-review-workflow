#!/usr/bin/env pwsh
#
# One-line PowerShell installer for git-review-workflow.
# Downloads the commands and copies them into a directory on your PATH.
# Run with:
#
#     irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.ps1 | iex
#
# Override the install dir with $env:PREFIX, or the version with $env:REF:
#
#     $env:REF = 'v0.0.1'; irm .../web-install.ps1 | iex
#
# With no REF it installs the latest release.
#
$ErrorActionPreference = 'Stop'

# User PATH accessors. In production these read and write the real user PATH.
# Tests set $env:GRW_USER_PATH_STORE to a file to redirect them there instead,
# keeping each run isolated from the machine and from other tests (the real user
# PATH is a single shared global, which otherwise makes parallel runs flaky).
function _grw_GetUserPath {
    if ($env:GRW_USER_PATH_STORE) {
        if (Test-Path $env:GRW_USER_PATH_STORE) {
            [System.IO.File]::ReadAllText($env:GRW_USER_PATH_STORE)
        }
    } else {
        [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    }
}
function _grw_SetUserPath([string]$Value) {
    if ($env:GRW_USER_PATH_STORE) {
        [System.IO.File]::WriteAllText($env:GRW_USER_PATH_STORE, $Value)
    } else {
        [System.Environment]::SetEnvironmentVariable('PATH', $Value, 'User')
    }
}

$repo       = 'EzeVillo/git-review-workflow'
$installDir = if ($env:PREFIX) { $env:PREFIX } else { "$env:USERPROFILE\.local\bin" }
$api        = "https://api.github.com/repos/$repo"

# Resolve which ref to install.
$ref = $env:REF
if (-not $ref) {
    try {
        $release = Invoke-RestMethod "$api/releases/latest"
        $ref = $release.tag_name
    } catch {}
}
if (-not $ref) {
    Write-Error "error: could not determine a ref to install"
    exit 1
}

Write-Host "Installing git-review-workflow ($ref) into $installDir"

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    $zipUrl  = "https://github.com/$repo/archive/refs/tags/$ref.zip"
    $zipPath = Join-Path $tmp 'archive.zip'
    Invoke-WebRequest $zipUrl -OutFile $zipPath

    Expand-Archive $zipPath -DestinationPath $tmp

    $src = Get-ChildItem $tmp -Directory | Where-Object { $_.Name -like 'git-review-workflow-*' } | Select-Object -First 1
    if (-not $src) {
        Write-Error "error: unexpected archive layout"
        exit 1
    }

    New-Item -ItemType Directory -Path $installDir -Force | Out-Null

    $installed = @()
    foreach ($f in Get-ChildItem (Join-Path $src.FullName 'bin') -Filter 'git-*') {
        Copy-Item $f.FullName -Destination (Join-Path $installDir $f.Name) -Force
        $installed += $f.Name
    }

    Write-Host "Installed: $($installed -join ', ')"

    # Add installDir to the user PATH if it isn't already there.
    $userPath = _grw_GetUserPath
    if ($userPath -notlike "*$installDir*") {
        _grw_SetUserPath "$installDir;$userPath"
        Write-Host "note: added $installDir to your PATH — open a new terminal for the change to take effect"
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
