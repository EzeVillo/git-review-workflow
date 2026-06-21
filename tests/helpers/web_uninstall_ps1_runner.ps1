param(
    [string]$TestName,
    [string]$RepoPath,   # local repo root
    [string]$TestTmpDir  # temp dir for this test run
)

$ErrorActionPreference = 'Stop'

$_commands = @(
    'git-review', 'git-review-pr', 'git-review-next', 'git-review-prev',
    'git-review-status', 'git-review-list', 'git-review-save', 'git-review-continue',
    'git-review-abort', 'git-finish-review', 'git-clean-review',
    'git-review-forget-delta', 'git-review-forget-saved'
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
        # Exercise the User PATH cleanup against a per-test PATH store file, so
        # the run never touches (or races with other tests on) the real user
        # PATH. The uninstaller honours $env:GRW_USER_PATH_STORE.
        $sep   = [System.IO.Path]::PathSeparator
        $keep  = Join-Path $TestTmpDir 'keep-on-path'
        $env:GRW_USER_PATH_STORE = Join-Path $TestTmpDir 'userpath-cleanup.txt'
        try {
            [System.IO.File]::WriteAllText(
                $env:GRW_USER_PATH_STORE, "$_installDir$sep$keep")

            _populate_install_dir
            _invoke_uninstaller

            $after = [System.IO.File]::ReadAllText($env:GRW_USER_PATH_STORE)
            $entries = $after -split [regex]::Escape($sep)
            if ($entries -contains $_installDir) {
                throw "install dir was not removed from PATH: $after"
            }
            if ($entries -notcontains $keep) {
                throw "an unrelated PATH entry was lost: $after"
            }
        } finally {
            $env:GRW_USER_PATH_STORE = $null
        }
    }

    'path_kept_when_dir_shared' {
        # When the install dir holds files we did not install (e.g. a shared
        # ~/.local/bin with pip/pipx tools), the uninstaller must NOT strip the
        # dir from PATH: web-install.ps1 never added it in that case. It should
        # still delete our own commands.
        $sep   = [System.IO.Path]::PathSeparator
        $keep  = Join-Path $TestTmpDir 'keep-on-path'
        $other = Join-Path $_installDir 'someone-elses-tool'
        $env:GRW_USER_PATH_STORE = Join-Path $TestTmpDir 'userpath-shared.txt'
        try {
            [System.IO.File]::WriteAllText(
                $env:GRW_USER_PATH_STORE, "$_installDir$sep$keep")

            _populate_install_dir
            Set-Content $other 'not ours'

            # Guard against false positives: the dir must really be on PATH and
            # our commands must really be present before we uninstall, otherwise
            # the post-conditions below would pass for the wrong reasons.
            $pre = [System.IO.File]::ReadAllText($env:GRW_USER_PATH_STORE)
            if (($pre -split [regex]::Escape($sep)) -notcontains $_installDir) {
                throw "setup failed: install dir was not on PATH before uninstall"
            }
            if (-not (Test-Path (Join-Path $_installDir 'git-review'))) {
                throw "setup failed: commands were not installed before uninstall"
            }

            _invoke_uninstaller

            # Our commands must be gone (proves the uninstaller actually ran and
            # this is not a no-op false positive).
            foreach ($cmd in $_commands) {
                if (Test-Path (Join-Path $_installDir $cmd)) {
                    throw "uninstaller left our command behind: $cmd"
                }
            }
            # The unrelated file must survive untouched.
            if (-not (Test-Path $other)) {
                throw "uninstaller deleted a file it did not install: $other"
            }
            if ((Get-Content $other) -ne 'not ours') {
                throw "uninstaller altered an unrelated file's contents"
            }
            # And, the point of this test: PATH must be left intact.
            $after   = [System.IO.File]::ReadAllText($env:GRW_USER_PATH_STORE)
            $entries = $after -split [regex]::Escape($sep)
            if ($entries -notcontains $_installDir) {
                throw "install dir was wrongly removed from a shared PATH: $after"
            }
            if ($entries -notcontains $keep) {
                throw "an unrelated PATH entry was lost: $after"
            }
        } finally {
            $env:GRW_USER_PATH_STORE = $null
        }
    }

    default {
        throw "Unknown test name: $TestName"
    }
}
