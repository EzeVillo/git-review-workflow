<#
.SYNOPSIS
    Build (and optionally install) the Visual Studio extension.

.DESCRIPTION
    The VSIX target framework is net472 — devenv loads in-proc extensions on .NET
    Framework — and it is built by MSBuild from a Visual Studio installation, not by
    `dotnet build`: the VSSDK build tasks are .NET Framework tasks. Everything else in
    this tree still builds with `dotnet build`; see CONTRIBUTING.md.

    The VSSDK comes from NuGet, so no Visual Studio workload is required to build.

.PARAMETER Install
    Install the built .vsix with VSIXInstaller, the same way a user installs one from
    disk. Visual Studio must be closed.

    The extension is uninstalled first when it is already there. VSIXInstaller treats
    an install of a version it already has as a no-op — it exits 0 and touches
    nothing — and during development the version is the same on every build, so
    without this the hive keeps serving the previous assembly and the IDE shows
    yesterday's code with no sign anything went wrong.

.PARAMETER Experimental
    Target the Experimental Instance hive (rootSuffix Exp) instead of the real one,
    so the extension can be tried without touching your day-to-day Visual Studio.
    Launch it afterwards with:  devenv /rootsuffix Exp

.PARAMETER Uninstall
    Remove the extension from the hive instead of installing it.

.PARAMETER Quiet
    Install or uninstall without VSIXInstaller's dialog. The exit code still reports
    what happened, so this is the form to use from a script.

.EXAMPLE
    ./build-vsix.ps1
    ./build-vsix.ps1 -Install -Experimental
    ./build-vsix.ps1 -Uninstall -Experimental
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$Install,
    [switch]$Experimental,
    [switch]$Uninstall,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifest = Join-Path $root 'src\GitReview.VS\source.extension.vsixmanifest'

function Find-VisualStudio {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found. Visual Studio 2022 or newer is required to build the VSIX."
    }
    $path = & $vswhere -latest -prerelease -products * -requires Microsoft.Component.MSBuild -property installationPath
    if (-not $path) {
        throw "No Visual Studio installation with MSBuild was found."
    }
    return $path
}

# Where the hive unpacked the extension, found by the assembly rather than by
# rebuilding the <Publisher>\<DisplayName>\<Version> path the installer chose — that
# path is the installer's business, and guessing it wrong would report "not installed"
# for an extension that is.
function Get-DeployedAssemblies([string]$suffix) {
    $hives = Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio'
    if (-not (Test-Path $hives)) { return $null }
    Get-ChildItem $hives -Directory -ErrorAction SilentlyContinue |
        Where-Object { if ($suffix) { $_.Name.EndsWith($suffix) } else { -not $_.Name.EndsWith('Exp') } } |
        ForEach-Object { Join-Path $_.FullName 'Extensions' } |
        Where-Object { Test-Path $_ } |
        ForEach-Object { Get-ChildItem $_ -Recurse -Filter 'GitReview.VS.dll' -ErrorAction SilentlyContinue }
}

$vs = Find-VisualStudio
$msbuild = Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path $msbuild)) { throw "MSBuild not found at $msbuild" }

# The extension identity is the vsixmanifest's, never a second copy of it.
$identity = (Select-String -Path $manifest -Pattern 'Identity Id="([^"]+)"').Matches[0].Groups[1].Value
$rootSuffix = if ($Experimental) { 'Exp' } else { $null }
$vsixInstaller = Join-Path $vs 'Common7\IDE\VSIXInstaller.exe'

# VSIXInstaller.exe is a GUI subsystem process, so the call operator hands control
# back the moment it launches, before a single file has been written. Left that way
# the uninstall and the install run on top of each other and whichever finishes
# last decides what is on disk — which is how a correct install could still leave
# the previous assembly in the hive.
function Invoke-Installer([string[]]$installerArgs) {
    $p = Start-Process -FilePath $vsixInstaller -ArgumentList $installerArgs -Wait -PassThru
    return $p.ExitCode
}

function Invoke-Uninstall([switch]$Tolerant) {
    $a = @("/uninstall:$identity")
    if ($rootSuffix) { $a += "/rootSuffix:$rootSuffix" }
    if ($Quiet -or $Tolerant) { $a += '/quiet' }
    $code = Invoke-Installer $a
    # 1002 / 2003: "not installed" — the normal case on a first install, not a failure.
    if (-not $Tolerant -and $code -ne 0) { exit $code }
}

if ($Uninstall) {
    if (-not (Test-Path $vsixInstaller)) { throw "VSIXInstaller not found at $vsixInstaller" }
    Write-Host "Uninstalling $identity$(if ($rootSuffix) { " from the $rootSuffix hive" })..."
    Invoke-Uninstall
    exit 0
}

Write-Host "Building with $msbuild ($Configuration)..."
& $msbuild (Join-Path $root 'GitReview.sln') `
    -restore `
    -p:GitReviewPackVsix=true `
    -p:Configuration=$Configuration `
    -v:minimal `
    -nologo
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$vsix = Join-Path $root "src\GitReview.VS\bin\$Configuration\net472\GitReview.VS.vsix"
if (-not (Test-Path $vsix)) { throw "Build succeeded but no .vsix at $vsix" }
Write-Host ""
Write-Host "VSIX: $vsix"

if (-not $Install) {
    Write-Host "Install it with: ./build-vsix.ps1 -Install$(if ($Experimental) { ' -Experimental' })"
    exit 0
}

if (-not (Test-Path $vsixInstaller)) { throw "VSIXInstaller not found at $vsixInstaller" }
if (Get-Process devenv -ErrorAction SilentlyContinue) {
    Write-Warning "Visual Studio is running. Close it first: an in-proc extension cannot be replaced while devenv has it loaded."
}

if (Get-DeployedAssemblies $rootSuffix) {
    Write-Host "Removing the installed copy first (same version reinstalls are a no-op)..."
    Invoke-Uninstall -Tolerant
}

$installerArgs = @($vsix)
if ($rootSuffix) { $installerArgs += "/rootSuffix:$rootSuffix" }
if ($Quiet) { $installerArgs += '/quiet' }
Write-Host "Installing$(if ($rootSuffix) { " into the $rootSuffix hive" })..."
$code = Invoke-Installer $installerArgs
if ($code -ne 0) { exit $code }

# VSIXInstaller reports success for work it decided not to do, so the thing that
# actually matters — the hive now holds the assembly that was just built — is checked
# rather than assumed.
$built = Get-Item (Join-Path $root "src\GitReview.VS\bin\$Configuration\net472\GitReview.VS.dll")
$deployed = @(Get-DeployedAssemblies $rootSuffix)
$stale = @($deployed | Where-Object { (Get-FileHash $_.FullName).Hash -ne (Get-FileHash $built.FullName).Hash })
if ($deployed.Count -eq 0) {
    Write-Warning "Installed, but no GitReview.VS.dll was found in the$(if ($rootSuffix) { " $rootSuffix" }) hive."
}
elseif ($stale.Count -gt 0) {
    Write-Warning "The hive still holds a different GitReview.VS.dll. Visual Studio may load that one, not the build you just made:"
    $stale | ForEach-Object { Write-Warning "  $($_.FullName)" }
}
else {
    $deployed | ForEach-Object { Write-Host "Verified: $($_.FullName)" }
}

# The installer unpacks into a folder name of its own choosing, so every reinstall
# lands somewhere new while the hive's merged configuration still points at the folder
# the previous one used — which the uninstall just deleted. Visual Studio then fails to
# load the package outright ("GitReviewPackage did not load correctly", a
# FileNotFoundException in ActivityLog.xml) instead of merely running stale code, so
# the re-merge is part of installing, not a troubleshooting step.
$devenv = Join-Path $vs 'Common7\IDE\devenv.exe'
if (Test-Path $devenv) {
    Write-Host "Updating the$(if ($rootSuffix) { " $rootSuffix" }) hive configuration (this takes a moment)..."
    $updateArgs = @()
    if ($rootSuffix) { $updateArgs += @('/rootsuffix', $rootSuffix) }
    $updateArgs += '/updateconfiguration'
    $u = Start-Process -FilePath $devenv -ArgumentList $updateArgs -Wait -PassThru
    if ($u.ExitCode -ne 0) {
        Write-Warning "devenv /updateconfiguration exited $($u.ExitCode). If the package fails to load, delete the hive: Remove-Item -Recurse `"$env:LOCALAPPDATA\Microsoft\VisualStudio\<version>$rootSuffix`""
    }
}
else {
    Write-Warning "devenv.exe not found at $devenv; skipping the configuration update. Visual Studio may fail to load the package until it is run with /updateconfiguration."
}

if ($rootSuffix) {
    Write-Host ""
    Write-Host "Start the Experimental Instance with:  devenv /rootsuffix Exp"
}
