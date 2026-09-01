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
# With no REF it installs the latest release, falling back to the default branch
# (same policy as web-install.sh).
#
param(
    [switch]$WithUi
)

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

# Resolve which ref to install: explicit REF, else latest release, else default branch.
$ref = $env:REF
if (-not $ref) {
    try {
        $release = Invoke-RestMethod "$api/releases/latest"
        $ref = $release.tag_name
    } catch {}
}
if (-not $ref) {
    try {
        $repoInfo = Invoke-RestMethod $api
        $ref = $repoInfo.default_branch
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
    # GitHub archive URLs accept tags, branch names, and short SHAs under
    # archive/<ref>.zip (and under refs/tags/ or refs/heads/ when needed).
    # Prefer archive/$ref.zip first so REF=main works; fall back to tags/heads.
    $zipPath = Join-Path $tmp 'archive.zip'
    $candidates = @(
        "https://github.com/$repo/archive/$ref.zip",
        "https://github.com/$repo/archive/refs/tags/$ref.zip",
        "https://github.com/$repo/archive/refs/heads/$ref.zip"
    )
    $downloaded = $false
    foreach ($zipUrl in $candidates) {
        try {
            Invoke-WebRequest $zipUrl -OutFile $zipPath
            $downloaded = $true
            break
        } catch {
            # try next layout
        }
    }
    if (-not $downloaded) {
        Write-Error "error: could not download archive for ref '$ref'"
        exit 1
    }

    Expand-Archive $zipPath -DestinationPath $tmp

    $src = Get-ChildItem $tmp -Directory | Where-Object { $_.Name -like 'git-review-workflow-*' } | Select-Object -First 1
    if (-not $src) {
        Write-Error "error: unexpected archive layout"
        exit 1
    }

    New-Item -ItemType Directory -Path $installDir -Force | Out-Null

    $installed = @()
    foreach ($f in Get-ChildItem (Join-Path $src.FullName 'bin') -Filter 'git-*') {
        $dest = Join-Path $installDir $f.Name
        if ($f.PSIsContainer) {
            # Private verbs directory: copy it whole into a subdirectory of the
            # install dir (libexec, NOT on PATH — git must not discover a verb as
            # `git <verb>`). The dispatcher finds it, and git-review-lib.sh,
            # beside itself once installed here.
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            Copy-Item $f.FullName -Destination $dest -Recurse -Force
            continue
        }
        Copy-Item $f.FullName -Destination $dest -Force
        $installed += $f.Name
    }

    Write-Host "Installed: $($installed -join ', ')"

    if ($WithUi) {
        try {
            $releases = @(Invoke-RestMethod "$api/releases?per_page=100")
            $tuiRelease = $releases |
                Where-Object { $_.tag_name -like 'tui-v*' } |
                Select-Object -First 1
            if (-not $tuiRelease) {
                Write-Host 'note: no terminal TUI release is available; the CLI is installed.'
            } else {
                $tuiTag = $tuiRelease.tag_name
                $tuiVersion = $tuiTag -replace '^tui-v', ''
                $runtimeArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
                $tuiArch = switch ($runtimeArch) {
                    'X64' { 'amd64' }
                    'Arm64' { 'arm64' }
                    default { $null }
                }
                if (-not $tuiArch) {
                    Write-Host 'note: no terminal TUI asset is published for this platform; the CLI is installed.'
                } else {
                    $tuiAsset = "git-review-ui_${tuiVersion}_windows_${tuiArch}.zip"
                    $tuiBase = "https://github.com/$repo/releases/download/$tuiTag"
                    $sumPath = Join-Path $tmp 'SHA256SUMS'
                    $tuiZip = Join-Path $tmp $tuiAsset
                    Invoke-WebRequest "$tuiBase/SHA256SUMS" -OutFile $sumPath
                    Invoke-WebRequest "$tuiBase/$tuiAsset" -OutFile $tuiZip
                    $sumLine = Get-Content $sumPath |
                        Where-Object { $_ -match "^[0-9a-fA-F]{64}\s+\*?$([regex]::Escape($tuiAsset))$" } |
                        Select-Object -First 1
                    if (-not $sumLine) {
                        Write-Host 'note: the terminal TUI checksum list does not cover this platform; the CLI is installed.'
                    } else {
                        $want = ($sumLine -split '\s+')[0].ToLowerInvariant()
                        $got = (Get-FileHash $tuiZip -Algorithm SHA256).Hash.ToLowerInvariant()
                        if ($got -ne $want) {
                            Write-Host 'note: terminal TUI checksum mismatch; the CLI is installed and the TUI was skipped.'
                        } else {
                            $tuiExtract = Join-Path $tmp 'tui'
                            Expand-Archive $tuiZip -DestinationPath $tuiExtract
                            $tuiBinary = Get-ChildItem $tuiExtract -Filter 'git-review-ui.exe' -Recurse |
                                Select-Object -First 1
                            if (-not $tuiBinary) {
                                Write-Host 'note: the terminal TUI archive has an unexpected layout; the CLI is installed.'
                            } else {
                                Copy-Item $tuiBinary.FullName -Destination (Join-Path $installDir 'git-review-ui.exe') -Force
                                Write-Host "Installed terminal TUI ($tuiTag): git-review-ui.exe"
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Host "note: terminal TUI installation failed; the CLI remains installed. $($_.Exception.Message)"
        }
    }

    # Add installDir to the user PATH if it isn't already there.
    $userPath = _grw_GetUserPath
    if ($userPath -notlike "*$installDir*") {
        _grw_SetUserPath "$installDir;$userPath"
        Write-Host "note: added $installDir to your PATH — open a new terminal for the change to take effect"
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
