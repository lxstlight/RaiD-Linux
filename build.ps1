<#
.SYNOPSIS
    Builds the RaiD Linux ISO on Windows.

.DESCRIPTION
    live-build only runs on Debian, so the build happens in a dedicated WSL
    distribution named "RaiD-Builder" (Debian 13 with live-build). It is
    created on the first run from any existing Ubuntu or Debian WSL
    distribution and stored in %LOCALAPPDATA%\RaiD-Builder.

    Remove it with:  wsl --unregister RaiD-Builder

.PARAMETER Target
    make target: iso (default), packages, update (the update of installed
    systems), release (files for GitHub, after iso and update), test or
    clean.
#>
param(
    [ValidateSet("iso", "packages", "update", "release", "test", "clean")]
    [string]$Target = "iso"
)

$ErrorActionPreference = "Stop"
$Distro = "RaiD-Builder"
$Home_ = Join-Path $env:LOCALAPPDATA "RaiD-Builder"

function Test-Distro {
    $names = (wsl.exe --list --quiet) -replace "`0", "" | Where-Object { $_ }
    return $names -contains $Distro
}

if (-not (Test-Distro)) {
    $helper = (wsl.exe --list --quiet) -replace "`0", "" |
        Where-Object { $_ -match "^(Ubuntu|Debian)" } | Select-Object -First 1
    if (-not $helper) {
        throw "Install Ubuntu or Debian from the Microsoft Store first (wsl --install -d Debian)."
    }
    Write-Host "Creating the $Distro WSL distribution with $helper..."
    New-Item -ItemType Directory -Force $Home_ | Out-Null
    $script = wsl.exe -d $helper --exec wslpath -a (Join-Path $PSScriptRoot "scripts\wsl\make-builder-rootfs.sh")
    $tar = Join-Path $Home_ "rootfs.tar"
    $tarLinux = wsl.exe -d $helper --exec wslpath -a $tar
    wsl.exe -d $helper -u root --exec bash $script $tarLinux
    if ($LASTEXITCODE -ne 0) { throw "Creating the build system failed." }
    wsl.exe --import $Distro (Join-Path $Home_ "disk") $tar --version 2
    Remove-Item $tar
}

$project = wsl.exe -d $Distro --exec wslpath -a $PSScriptRoot
wsl.exe -d $Distro --cd $project --exec make $Target
exit $LASTEXITCODE
