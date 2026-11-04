#Requires -Version 7
<#
.SYNOPSIS
    Builds an unsigned x64 Store upload package using Partner Center identity values.

.DESCRIPTION
    Temporarily updates the source manifest and restores its original bytes even if the build fails.
    Returns the full path of the single .msixupload file directly under OutDir.

.PARAMETER Version
    Release version in X.Y.Z form. The Store package uses X.Y.Z.0.

.PARAMETER IdentityName
    Package identity name from Partner Center, not Soriseom.Dev.

.PARAMETER Publisher
    Publisher identity from Partner Center, starting with CN=.

.PARAMETER PublisherDisplayName
    Publisher display name from Partner Center.

.PARAMETER OutDir
    Output directory. Use a separate directory for each release to avoid stale packages.

.EXAMPLE
    ./Build-StorePackage.ps1 -Version 1.2.3 -IdentityName Test.Soriseom -Publisher CN=Test -PublisherDisplayName TestPublisher -OutDir ./artifacts/store
#>
param(
    [Parameter(Mandatory)] [string] $Version,
    [Parameter(Mandatory)] [string] $IdentityName,
    [Parameter(Mandatory)] [string] $Publisher,
    [Parameter(Mandatory)] [string] $PublisherDisplayName,
    [Parameter(Mandatory)] [string] $OutDir
)

$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^[1-9]\d*\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw 'Version must be X.Y.Z without leading zeroes, and X must be greater than zero.'
}
foreach ($part in $Version.Split('.')) {
    $number = 0
    if (-not [int]::TryParse($part, [ref]$number) -or $number -gt 65535) {
        throw 'Each version component must be at most 65535.'
    }
}
if (-not $Publisher.StartsWith('CN=')) { throw 'Publisher must start with CN=.' }
if ($IdentityName -eq 'Soriseom.Dev') { throw 'IdentityName must be the Partner Center identity, not Soriseom.Dev.' }

[void](New-Item -ItemType Directory -Force -Path $OutDir)
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ManifestPath = Join-Path $RepoRoot 'src\Soriseom.App\Package.appxmanifest'
$originalBytes = [IO.File]::ReadAllBytes($ManifestPath)

Push-Location $RepoRoot
try {
    $manifest = [xml]::new()
    $manifest.PreserveWhitespace = $true
    $manifest.Load($ManifestPath)
    $manifest.Package.Identity.Name = $IdentityName
    $manifest.Package.Identity.Publisher = $Publisher
    $manifest.Package.Identity.Version = "$Version.0"
    $manifest.Package.Properties.PublisherDisplayName = $PublisherDisplayName
    $manifest.Save($ManifestPath)

    # The upload manifest copy target does not track changes to Package.appxmanifest.
    # Clean Release outputs so a previous identity cannot leak into the upload bundle.
    & dotnet clean src/Soriseom.App -c Release -p:Platform=x64 -v minimal | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Store package clean failed with exit code $LASTEXITCODE." }

    & dotnet build src/Soriseom.App -c Release -p:Platform=x64 -p:GenerateAppxPackageOnBuild=true -p:AppxPackageSigningEnabled=false -p:UapAppxPackageBuildMode=StoreUpload -p:AppxBundle=Always -p:AppxBundlePlatforms=x64 -p:AppxSymbolPackageEnabled=false "-p:AppxPackageDir=$OutDir\" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Store package build failed with exit code $LASTEXITCODE." }
}
finally {
    [IO.File]::WriteAllBytes($ManifestPath, $originalBytes)
    Pop-Location
}

$packages = @(Get-ChildItem -LiteralPath $OutDir -File -Filter '*.msixupload')
if ($packages.Count -ne 1) { throw "Expected exactly one .msixupload in $OutDir, found $($packages.Count)." }
Write-Output $packages[0].FullName
