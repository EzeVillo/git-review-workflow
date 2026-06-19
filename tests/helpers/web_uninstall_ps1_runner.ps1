param(
    [string]$TestName,
    [string]$RepoPath,   # local repo root
    [string]$TestTmpDir  # temp dir for this test run
)

$ErrorActionPreference = 'Stop'

$_commands = @(
    'git-review', 'git-review-pr', 'git-review-next', 'git-review-prev',
    'git-review-status', 'git-review-list', 'git-review-abort',
    'git-finish-review', 'git-clean-review'
)

$_installDir = Join-Path $TestTmpDir 'install'
New-Item -ItemType Directory -Path $_installDir -Force | Out-Null
$env:PREFIX = $_installDir

# Populate the install dir with real command files, exactly as an install would.
function _populate_install_dir {
    foreach ($cmd in $_commands) {
        Copy-Item (Join-Path $RepoPath "bin/$cmd") `
                  -Destination (Join-Path $_installDir $cmd) -Force
    }
}

# Read the uninstaller with explicit UTF-8 (Windows PowerShell 5.1 needs it for
# the em-dash and other non-ASCII characters) and run it in this scope.
function _invoke_uninstaller {
    $src = [System.IO.File]::ReadAllText(
        (Join-Path $RepoPath 'web-uninstall.ps1'),
        [System.Text.Encoding]::UTF8
    )
    Invoke-Expression $src
}

switch ($TestName) {

    'remove_all_commands' {
        _populate_install_dir
        # Guard against a false positive: the files must be present first.
        foreach ($cmd in $_commands) {
            if (-not (Test-Path (Join-Path $_installDir $cmd))) {
                throw "setup failed: $cmd was not present before uninstall"
            }
        }

        _invoke_uninstaller

        foreach ($cmd in $_commands) {
            if (Test-Path (Join-Path $_installDir $cmd)) {
                throw "uninstaller left command behind: $cmd"
            }
        }
    }

    'keep_unrelated' {
        _populate_install_dir
        # An unrelated file, plus one sharing the git- prefix but not ours: a
        # naive glob would wrongly delete it.
        Set-Content (Join-Path $_installDir 'unrelated.txt') 'keep me'
        Set-Content (Join-Path $_installDir 'git-other-tool') '#'

        _invoke_uninstaller

        foreach ($f in @('unrelated.txt', 'git-other-tool')) {
            if (-not (Test-Path (Join-Path $_installDir $f))) {
                throw "uninstaller deleted an unrelated file: $f"
            }
        }
        if ((Get-Content (Join-Path $_installDir 'unrelated.txt')) -ne 'keep me') {
            throw "uninstaller altered an unrelated file's contents"
        }
    }

    'nothing_to_remove' {
        # Empty install dir: must not throw.
        _invoke_uninstaller
    }

    'path_cleanup' {
        # Exercise the User PATH cleanup. Save and restore the real value so the
        # machine is never left modified, even on failure.
        $sep   = [System.IO.Path]::PathSeparator
        $keep  = Join-Path $TestTmpDir 'keep-on-path'
        $saved = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        try {
            [System.Environment]::SetEnvironmentVariable(
                'PATH', "$_installDir$sep$keep", 'User')

            _populate_install_dir
            _invoke_uninstaller

            $after = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            $entries = $after -split [regex]::Escape($sep)
            if ($entries -contains $_installDir) {
                throw "install dir was not removed from PATH: $after"
            }
            if ($entries -notcontains $keep) {
                throw "an unrelated PATH entry was lost: $after"
            }
        } finally {
            [System.Environment]::SetEnvironmentVariable('PATH', $saved, 'User')
        }
    }

    default {
        throw "Unknown test name: $TestName"
    }
}
