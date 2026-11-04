#Requires -Version 7
<#
.SYNOPSIS
    Checks Store package validation, bundle identity, and subsequent dev package identity.

.DESCRIPTION
    Builds packages without installing or launching the app. Deletes temporary output on completion.
#>
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BuildScript = Join-Path $PSScriptRoot 'Build-StorePackage.ps1'
$ManifestPath = Join-Path $RepoRoot 'src\Soriseom.App\Package.appxmanifest'
$originalBytes = [IO.File]::ReadAllBytes($ManifestPath)
$TempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$TempDir = Join-Path $TempRoot "soriseom-store-test-$([guid]::NewGuid())"
[void](New-Item -ItemType Directory -Path $TempDir)

function Assert-ManifestUnchanged {
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($ManifestPath)) -cne [Convert]::ToBase64String($originalBytes)) {
        throw 'The source manifest bytes changed.'
    }
}

Push-Location $RepoRoot
try {
    $buildArguments = @{
        Version = '1.2.3'
        IdentityName = 'Test.Soriseom'
        Publisher = 'CN=00000000-0000-0000-0000-000000000000'
        PublisherDisplayName = 'TestPublisher'
        OutDir = Join-Path $TempDir 'store'
    }
    $invalidInputs = @(
        @{ Version = '0.1.0' }
        @{ Version = '1.2' }
        @{ Version = '1.2.3.4' }
        @{ Version = '1.2.70000' }
        @{ Version = 'v1.2.3' }
        @{ Version = '1.2.3-beta' }
        @{ Version = '01.2.3' }
        @{ Publisher = '00000000-0000-0000-0000-000000000000' }
        @{ IdentityName = 'Soriseom.Dev' }
    )
    foreach ($invalidInput in $invalidInputs) {
        $arguments = $buildArguments.Clone()
        foreach ($key in $invalidInput.Keys) { $arguments[$key] = $invalidInput[$key] }
        $threw = $false
        try { & $BuildScript @arguments | Out-Host } catch { $threw = $true }
        if (-not $threw) { throw "Invalid input was accepted: $($invalidInput | ConvertTo-Json -Compress)" }
        Assert-ManifestUnchanged
    }
    Write-Host 'PASS invalid inputs leave the manifest unchanged'

    $packagePath = & $BuildScript @buildArguments
    Assert-ManifestUnchanged
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'The returned Store package does not exist.' }
    $upload = [IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $bundles = @($upload.Entries | Where-Object { $_.FullName.EndsWith('.msixbundle') })
        if ($bundles.Count -ne 1) { throw 'Expected exactly one .msixbundle in the Store upload.' }
        $memory = [IO.MemoryStream]::new()
        try {
            $stream = $bundles[0].Open()
            try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
            $memory.Position = 0
            $bundle = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Read, $true)
            try {
                $entry = $bundle.GetEntry('AppxMetadata/AppxBundleManifest.xml')
                if (-not $entry) { throw 'The bundle manifest is missing.' }
                $stream = $entry.Open()
                try {
                    $manifest = [xml]::new()
                    $manifest.Load($stream)
                }
                finally { $stream.Dispose() }
                $identity = $manifest.Bundle.Identity
                if ($identity.Name -cne $buildArguments.IdentityName -or
                    $identity.Publisher -cne $buildArguments.Publisher -or
                    $identity.Version -cne '1.2.3.0') {
                    throw "Unexpected Store bundle identity: $($identity.OuterXml)"
                }
            }
            finally { $bundle.Dispose() }
        }
        finally { $memory.Dispose() }
    }
    finally { $upload.Dispose() }
    Write-Host 'PASS Store bundle identity and source manifest restoration'

    $devDir = Join-Path $TempDir 'dev'
    [void](New-Item -ItemType Directory -Path $devDir)
    & dotnet build src/Soriseom.App -c Release -p:Platform=x64 -p:GenerateAppxPackageOnBuild=true -p:AppxPackageSigningEnabled=false -p:AppxBundle=Never "-p:AppxPackageDir=$devDir\" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Dev package build failed with exit code $LASTEXITCODE." }
    # The output also contains Windows App SDK dependency packages.
    $devPackages = @(Get-ChildItem -LiteralPath $devDir -Recurse -File -Filter 'Soriseom.App_*.msix')
    if ($devPackages.Count -ne 1) { throw "Expected one dev MSIX, found: $($devPackages.FullName -join ', ')" }
    $devPackage = [IO.Compression.ZipFile]::OpenRead($devPackages[0].FullName)
    try {
        $entry = $devPackage.GetEntry('AppxManifest.xml')
        if (-not $entry) { throw 'The dev package manifest is missing.' }
        $stream = $entry.Open()
        try {
            $manifest = [xml]::new()
            $manifest.Load($stream)
        }
        finally { $stream.Dispose() }
        $identity = $manifest.Package.Identity
        if ($identity.Name -cne 'Soriseom.Dev' -or $identity.Version -cne '1.0.0.0') {
            throw "Unexpected dev package identity after the Store build: $($identity.OuterXml)"
        }
    }
    finally { $devPackage.Dispose() }
    Assert-ManifestUnchanged
    Write-Host 'PASS subsequent dev package uses Soriseom.Dev 1.0.0.0'
}
finally {
    Pop-Location
    $resolvedTempDir = (Resolve-Path -LiteralPath $TempDir).Path
    if (-not $resolvedTempDir.StartsWith($TempRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete a directory outside the temp root: $resolvedTempDir"
    }
    Remove-Item -LiteralPath $resolvedTempDir -Recurse -Force
}
