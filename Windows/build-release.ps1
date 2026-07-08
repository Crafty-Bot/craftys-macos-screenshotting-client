[CmdletBinding(DefaultParameterSetName = 'Store')]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',

    [string]$Runtime = 'win-x64',

    [string]$OutputRoot = (Join-Path $PSScriptRoot 'dist'),

    [Parameter(ParameterSetName = 'Store', Mandatory = $true)]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'Pfx', Mandatory = $true)]
    [string]$CertificatePath,

    [Parameter(ParameterSetName = 'Pfx')]
    [string]$CertificatePassword = $env:CRAFTYCANNON_SIGNING_PFX_PASSWORD,

    [string]$ExpectedPublisherSubject,

    [switch]$AllowTestCertificate,

    [switch]$IncludeDebugSymbols,

    [string]$TimestampUrl = 'http://timestamp.digicert.com',

    [string]$SignToolPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SignTool {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw "SignToolPath does not exist: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kitsRoot) {
        $candidate = Get-ChildItem -LiteralPath $kitsRoot -Recurse -Filter signtool.exe |
            Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw 'signtool.exe was not found. Install the Windows SDK or pass -SignToolPath.'
}

function Invoke-Checked {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Find-StoreCertificate {
    param([string]$Thumbprint)

    $normalized = ($Thumbprint -replace '\s', '').ToUpperInvariant()
    Get-ChildItem -Path Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { ($_.Thumbprint -replace '\s', '').ToUpperInvariant() -eq $normalized } |
        Select-Object -First 1
}

function Test-CodeSigningCertificate {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$ExpectedSubject,
        [bool]$AllowTest
    )

    if (-not $Certificate.HasPrivateKey) {
        throw "Signing certificate $($Certificate.Thumbprint) does not have an accessible private key."
    }

    $now = Get-Date
    if ($Certificate.NotBefore -gt $now -or $Certificate.NotAfter -lt $now) {
        throw "Signing certificate $($Certificate.Thumbprint) is not currently valid. Valid from $($Certificate.NotBefore) to $($Certificate.NotAfter)."
    }

    $ekuExtension = $Certificate.Extensions |
        Where-Object { $_.Oid.Value -eq '2.5.29.37' } |
        Select-Object -First 1
    if (-not $ekuExtension) {
        throw "Signing certificate $($Certificate.Thumbprint) does not declare an Enhanced Key Usage extension."
    }

    $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$ekuExtension
    $ekuOids = @($eku.EnhancedKeyUsages | ForEach-Object { $_.Value })
    if ($ekuOids -notcontains '1.3.6.1.5.5.7.3.3') {
        throw "Signing certificate $($Certificate.Thumbprint) is missing the Code Signing EKU."
    }

    if (-not $AllowTest -and $Certificate.Subject -eq $Certificate.Issuer) {
        throw "Signing certificate $($Certificate.Thumbprint) is self-signed. Pass -AllowTestCertificate only for non-production test artifacts."
    }

    if ($ExpectedSubject -and $Certificate.Subject -notlike "*$ExpectedSubject*") {
        throw "Signing certificate subject '$($Certificate.Subject)' does not contain expected publisher subject '$ExpectedSubject'."
    }
}

function Get-PackageFileManifest {
    param([string]$Root)

    Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object { $_.Name -ne 'release-manifest.json' } |
        Sort-Object FullName |
        ForEach-Object {
            $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            [pscustomobject]@{
                path = [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
                sha256 = $hash.Hash.ToLowerInvariant()
                length = $_.Length
            }
        }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $PSScriptRoot 'CraftyCannon.App\CraftyCannon.App.csproj'
$publishDir = Join-Path $OutputRoot (Join-Path 'publish' "$Runtime-$Configuration")
$artifactDir = Join-Path $OutputRoot 'artifacts'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$manifestPath = Join-Path $artifactDir "CraftyCannon-$Runtime-$Configuration-signed-$stamp-manifest.json"
$zipPath = Join-Path $artifactDir "CraftyCannon-$Runtime-$Configuration-signed-$stamp.zip"
$signtool = Resolve-SignTool -ExplicitPath $SignToolPath

if ($PSCmdlet.ParameterSetName -eq 'Store') {
    if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        throw 'CertificateThumbprint cannot be empty.'
    }

    $certificate = Find-StoreCertificate -Thumbprint $CertificateThumbprint
    if (-not $certificate) {
        throw "CertificateThumbprint was not found in CurrentUser\\My or LocalMachine\\My: $CertificateThumbprint"
    }
}
else {
    if (-not (Test-Path -LiteralPath $CertificatePath)) {
        throw "CertificatePath does not exist: $CertificatePath"
    }

    $pfxPassword = if ($CertificatePassword) { $CertificatePassword } else { '' }
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        (Resolve-Path -LiteralPath $CertificatePath).Path,
        $pfxPassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
}

Test-CodeSigningCertificate -Certificate $certificate -ExpectedSubject $ExpectedPublisherSubject -AllowTest $AllowTestCertificate.IsPresent

if (Test-Path -LiteralPath $publishDir) {
    Remove-Item -LiteralPath $publishDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $publishDir, $artifactDir | Out-Null

$debugType = if ($IncludeDebugSymbols) { 'embedded' } else { 'none' }
Push-Location $repoRoot
try {
    dotnet publish $project --configuration $Configuration --runtime $Runtime --self-contained false --output $publishDir /p:PublishSingleFile=false /p:DebugType=$debugType
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$signTargets = Get-ChildItem -LiteralPath $publishDir -Recurse -File |
    Where-Object { $_.Extension -in @('.exe', '.dll') } |
    Sort-Object FullName

if ($signTargets.Count -eq 0) {
    throw "No executable artifacts were produced under $publishDir."
}

$signedManifest = @()

foreach ($target in $signTargets) {
    if ($PSCmdlet.ParameterSetName -eq 'Pfx') {
        $args = @('sign', '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256', '/f', (Resolve-Path -LiteralPath $CertificatePath).Path)
        if ($CertificatePassword) {
            $args += @('/p', $CertificatePassword)
        }
        $args += $target.FullName
        Invoke-Checked -FilePath $signtool -Arguments $args
    }
    else {
        Invoke-Checked -FilePath $signtool -Arguments @('sign', '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256', '/sha1', $certificate.Thumbprint, $target.FullName)
    }

    Invoke-Checked -FilePath $signtool -Arguments @('verify', '/pa', '/all', $target.FullName)
    Invoke-Checked -FilePath $signtool -Arguments @('verify', '/pa', '/all', '/tw', $target.FullName)
    $hash = Get-FileHash -LiteralPath $target.FullName -Algorithm SHA256
    $signedManifest += [pscustomobject]@{
        path = [System.IO.Path]::GetRelativePath($publishDir, $target.FullName).Replace('\', '/')
        sha256 = $hash.Hash.ToLowerInvariant()
        length = $target.Length
    }
}

$packageManifest = @(Get-PackageFileManifest -Root $publishDir)
$manifest = [pscustomobject]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('O')
    runtime = $Runtime
    configuration = $Configuration
    timestampUrl = $TimestampUrl
    certificateThumbprint = $certificate.Thumbprint
    certificateSubject = $certificate.Subject
    signedFiles = $signedManifest
    packageFiles = $packageManifest
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $publishDir 'release-manifest.json') -Force

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zipPath
$zipHash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
$manifest | Add-Member -NotePropertyName zipArtifact -NotePropertyValue ([pscustomobject]@{
    path = [System.IO.Path]::GetFileName($zipPath)
    sha256 = $zipHash.Hash.ToLowerInvariant()
    length = (Get-Item -LiteralPath $zipPath).Length
})
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Signed release artifact: $zipPath"
Write-Host "Release manifest: $manifestPath"
