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

# Track which URIs Invoke-RestMethod is called with.
$script:_apiCalls = [System.Collections.Generic.List[string]]::new()

# ── mock cmdlets (visible to dot-sourced code via same scope) ─────────────────
function Invoke-RestMethod {
    param([string]$Uri)
    $script:_apiCalls.Add($Uri)
    return [pscustomobject]@{ tag_name = 'v0.0.1' }
}

function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile)
    Copy-Item $_fakeZip -Destination $OutFile -Force
}

# Read the installer with explicit UTF-8 so Windows PowerShell 5.1 handles
# non-ASCII characters (e.g. em-dash) in the file correctly.
function _invoke_installer {
    $src = [System.IO.File]::ReadAllText(
        (Join-Path $RepoPath 'web-install.ps1'),
        [System.Text.Encoding]::UTF8
    )
    Invoke-Expression $src
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
