param(
    [Parameter(Mandatory = $true)][string]$Headers,
    [Parameter(Mandatory = $true)][string]$Library,
    [Parameter(Mandatory = $true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$headerPath = (Resolve-Path -LiteralPath $Headers).Path
$libraryPath = (Resolve-Path -LiteralPath $Library).Path
$sourcePath = Join-Path $PSScriptRoot 'metadata.c'
$outputPath = [IO.Path]::GetFullPath($Output)
$repoPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
if ($outputPath -eq $repoPath -or $outputPath.StartsWith($repoPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Use an output directory outside the checkout.'
}
if (Test-Path -LiteralPath $outputPath) {
    throw 'Use a new output directory.'
}
if (-not (Test-Path -LiteralPath (Join-Path $headerPath 'git2.h'))) {
    throw 'Headers must be the libgit2 include directory.'
}
$vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vsRoot = & $vsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsRoot) { throw 'MSVC x64 build tools were not found.' }
$vcVars = Join-Path $vsRoot 'VC/Auxiliary/Build/vcvars64.bat'
New-Item -ItemType Directory -Path $outputPath | Out-Null
$dllName = [IO.Path]::GetFileName($libraryPath)
Copy-Item -LiteralPath $libraryPath -Destination (Join-Path $outputPath $dllName)
$exports = @(
    'git_libgit2_init', 'git_libgit2_shutdown', 'git_libgit2_opts', 'git_error_last',
    'git_config_open_ondisk', 'git_config_lock', 'git_config_set_string',
    'git_config_delete_entry', 'git_config_get_multivar_foreach',
    'git_transaction_commit', 'git_transaction_free', 'git_config_free'
)
@("LIBRARY `"$dllName`"", 'EXPORTS') + $exports |
    Set-Content -LiteralPath (Join-Path $outputPath 'git2.def') -Encoding ascii
# Keep paths in environment variables so the generated ASCII script also works
# when a parent directory contains Unicode or percent characters.
@'
@echo off
setlocal DisableDelayedExpansion
call "%GR_NATIVE_META_VCVARS%" >nul
if errorlevel 1 exit /b %errorlevel%
cd /d "%GR_NATIVE_META_OUTPUT%"
lib /nologo /def:git2.def /out:git2.lib /machine:x64
if errorlevel 1 exit /b %errorlevel%
cl /nologo /TC /std:c11 /O2 /MT /W4 /WX /D_CRT_SECURE_NO_WARNINGS /I"%GR_NATIVE_META_HEADERS%" "%GR_NATIVE_META_SOURCE%" /Fe:git-review-meta.exe /link git2.lib
if errorlevel 1 exit /b %errorlevel%
git-review-meta.exe --protocol-version
'@ | Set-Content -LiteralPath (Join-Path $outputPath 'build.cmd') -Encoding ascii
$variables = @{
    GR_NATIVE_META_VCVARS = $vcVars
    GR_NATIVE_META_OUTPUT = $outputPath
    GR_NATIVE_META_HEADERS = $headerPath
    GR_NATIVE_META_SOURCE = $sourcePath
}
$previous = @{}
try {
    foreach ($name in $variables.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
    }
    & $env:ComSpec /d /c (Join-Path $outputPath 'build.cmd')
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $LASTEXITCODE" }
} finally {
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
