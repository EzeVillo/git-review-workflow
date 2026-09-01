param(
    [string]$TestName,
    [string]$RepoPath,   # local repo root (named to avoid clash with $repo inside web-install.ps1)
    [string]$TestTmpDir  # temp dir for this test run
)

$ErrorActionPreference = 'Stop'

# Build a zip whose layout matches a GitHub archive:
# git-review-workflow-v0.0.1/bin/git-*
$_archiveDir = Join-Path $TestTmpDir "git-review-workflow-v0.0.1"
New-Item -ItemType Directory -Path (Join-Path $_archiveDir "bin") -Force | Out-Null
Get-ChildItem (Join-Path $RepoPath "bin") |
    Copy-Item -Destination (Join-Path $_archiveDir "bin") -Recurse -Force
$_fakeZip = Join-Path $TestTmpDir "archive.zip"
Compress-Archive -Path $_archiveDir -DestinationPath $_fakeZip -Force

$_tuiDir = Join-Path $TestTmpDir 'tui-release'
New-Item -ItemType Directory -Path $_tuiDir -Force | Out-Null
Set-Content (Join-Path $_tuiDir 'git-review-ui.exe') 'tui-probe'
$_fakeTuiZip = Join-Path $TestTmpDir 'git-review-ui_0.1.0_windows_amd64.zip'
Compress-Archive -Path (Join-Path $_tuiDir 'git-review-ui.exe') -DestinationPath $_fakeTuiZip -Force
$_tuiHash = (Get-FileHash $_fakeTuiZip -Algorithm SHA256).Hash.ToLowerInvariant()
$script:_badTuiHash = $false

$_installDir = Join-Path $TestTmpDir "install"
New-Item -ItemType Directory -Path $_installDir -Force | Out-Null
$env:PREFIX = $_installDir

# Pre-add install dir to the process PATH (cosmetic: keeps the installed
# commands callable within this run).
$_savedPath = $env:PATH
$env:PATH = "$_installDir$([System.IO.Path]::PathSeparator)$_savedPath"

# The installer reads/writes the *User*-scope PATH. Redirect it to a per-run
# store file (honoured via $env:GRW_USER_PATH_STORE) so the test never touches
# or races on the real user PATH.
$env:GRW_USER_PATH_STORE = Join-Path $TestTmpDir 'userpath.txt'

# Track which URIs Invoke-RestMethod / Invoke-WebRequest are called with.
$script:_apiCalls = [System.Collections.Generic.List[string]]::new()
$script:_webCalls = [System.Collections.Generic.List[string]]::new()
# When set, releases/latest fails so the installer must fall back to default_branch.
$script:_noRelease = $false

# ── mock cmdlets (visible to dot-sourced code via same scope) ─────────────────
function Invoke-RestMethod {
    param([string]$Uri)
    $script:_apiCalls.Add($Uri)
    if ($Uri -like '*/releases/latest*') {
        if ($script:_noRelease) {
            throw "404 no release"
        }
        return [pscustomobject]@{ tag_name = 'v0.0.1' }
    }
    if ($Uri -like '*/releases?per_page=100*') {
        return @(
            [pscustomobject]@{ tag_name = 'tui-v0.1.0' },
            [pscustomobject]@{ tag_name = 'v0.0.1' }
        )
    }
    if ($Uri -match '/repos/[^/]+/[^/]+$') {
        return [pscustomobject]@{ default_branch = 'main' }
    }
    return [pscustomobject]@{ tag_name = 'v0.0.1' }
}

function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile)
    $script:_webCalls.Add($Uri)
    if ($Uri -like '*/releases/download/tui-v0.1.0/SHA256SUMS') {
        $hash = if ($script:_badTuiHash) { '0' * 64 } else { $_tuiHash }
        Set-Content $OutFile "$hash  git-review-ui_0.1.0_windows_amd64.zip"
        return
    }
    if ($Uri -like '*/releases/download/tui-v0.1.0/git-review-ui_0.1.0_windows_amd64.zip') {
        Copy-Item $_fakeTuiZip -Destination $OutFile -Force
        return
    }
    # Accept archive/$ref.zip, refs/tags/, and refs/heads/ layouts.
    if ($Uri -notmatch '/archive/') {
        throw "unexpected archive URL: $Uri"
    }
    Copy-Item $_fakeZip -Destination $OutFile -Force
}

# Read the installer with explicit UTF-8 so Windows PowerShell 5.1 handles
# non-ASCII characters (e.g. em-dash) in the file correctly.
function _invoke_installer([switch]$WithUi) {
    $src = [System.IO.File]::ReadAllText(
        (Join-Path $RepoPath 'web-install.ps1'),
        [System.Text.Encoding]::UTF8
    )
    $block = [scriptblock]::Create($src)
    if ($WithUi) {
        & $block -WithUi
    } else {
        & $block
    }
}

try {
    switch ($TestName) {

        'install_all_commands' {
            _invoke_installer
            $cmds = @('git-review')
            foreach ($cmd in $cmds) {
                $p = Join-Path $_installDir $cmd
                if (-not (Test-Path $p)) {
                    throw "Missing installed file: $cmd"
                }
            }
        }

        'ref_skips_api' {
            $env:REF = 'v0.0.1'
            try {
                _invoke_installer
            } finally {
                $env:REF = ''
            }
            $hit = $script:_apiCalls | Where-Object { $_ -like '*/releases/latest*' }
            if ($hit) {
                throw "releases/latest was called even though REF was set: $hit"
            }
        }

        'falls_back_to_default_branch' {
            $script:_noRelease = $true
            _invoke_installer
            $repoCall = $script:_apiCalls | Where-Object { $_ -match '/repos/[^/]+/[^/]+$' -and $_ -notlike '*/releases/*' }
            if (-not $repoCall) {
                throw "repo API (default_branch) was not called after releases/latest failed"
            }
            $arch = $script:_webCalls | Where-Object { $_ -like '*/archive/main.zip' -or $_ -like '*/archive/refs/heads/main.zip' }
            if (-not $arch) {
                throw "expected archive download for default branch main; got: $($script:_webCalls -join ', ')"
            }
            $p = Join-Path $_installDir 'git-review'
            if (-not (Test-Path $p)) {
                throw "Missing installed file: git-review"
            }
        }

        'ref_main_uses_heads_or_archive' {
            $env:REF = 'main'
            try {
                _invoke_installer
            } finally {
                $env:REF = ''
            }
            $arch = $script:_webCalls | Where-Object {
                $_ -like '*/archive/main.zip' -or
                $_ -like '*/archive/refs/heads/main.zip' -or
                $_ -like '*/archive/refs/tags/main.zip'
            }
            if (-not $arch) {
                throw "REF=main must download an archive for main; got: $($script:_webCalls -join ', ')"
            }
        }

        'default_skips_ui' {
            _invoke_installer
            if (Test-Path (Join-Path $_installDir 'git-review-ui.exe')) {
                throw 'default install unexpectedly wrote git-review-ui.exe'
            }
            $hit = $script:_apiCalls + $script:_webCalls | Where-Object {
                $_ -like '*/releases?per_page=100*' -or $_ -like '*/releases/download/tui-v*'
            }
            if ($hit) {
                throw "default install unexpectedly requested TUI URLs: $hit"
            }
        }

        'with_ui_installs_verified' {
            _invoke_installer -WithUi
            if (-not (Test-Path (Join-Path $_installDir 'git-review'))) {
                throw 'CLI was not installed'
            }
            if (-not (Test-Path (Join-Path $_installDir 'git-review-ui.exe')) ) {
                throw 'TUI was not installed'
            }
            $latest = $script:_apiCalls | Where-Object { $_ -like '*/releases/latest*' }
            $tuiList = $script:_apiCalls | Where-Object { $_ -like '*/releases?per_page=100*' }
            if (-not $latest -or -not $tuiList) {
                throw 'CLI latest ref and TUI release list must be resolved independently'
            }
        }

        'with_ui_checksum_mismatch' {
            $script:_badTuiHash = $true
            _invoke_installer -WithUi
            if (-not (Test-Path (Join-Path $_installDir 'git-review'))) {
                throw 'CLI install was lost after TUI checksum failure'
            }
            if (Test-Path (Join-Path $_installDir 'git-review-ui.exe')) {
                throw 'TUI was installed despite checksum mismatch'
            }
        }

        default {
            throw "Unknown test name: $TestName"
        }
    }
} finally {
    $env:PATH = $_savedPath
    # The installer's user-PATH writes went to the store file, not the registry,
    # so there is nothing to undo on the real machine.
    $env:GRW_USER_PATH_STORE = $null
}
