[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceAddress,

    [string]$SourceUser = 'pibox',

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceIdentityFile,

    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.pibox-secrets\source-private-config.dpapi')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourceIdentityFile -PathType Leaf)) {
    throw "SSH identity file not found: $SourceIdentityFile"
}

$sourceEndpoint = "$SourceUser@$SourceAddress"
$sshOptions = @(
    '-i', $SourceIdentityFile,
    '-o', 'IdentitiesOnly=yes',
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=10',
    $sourceEndpoint
)
$sourceCommand = "sudo -n tar -C / -cf - etc/hostapd/hostapd.conf etc/wpa_supplicant/wpa_supplicant.conf etc/raspap/raspap.auth etc/raspap/hostapd.ini etc/raspap/networking/defaults.json | base64 -w0"

Write-Host "Reading the private configuration from $sourceEndpoint without writing plaintext locally ..."
$archiveBase64 = (& ssh @sshOptions $sourceCommand) -join ''
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($archiveBase64)) {
    throw 'Could not read the private configuration bundle from the source PiBox.'
}

$archiveBytes = [Convert]::FromBase64String($archiveBase64)
$archiveBase64 = $null
$entropy = [Text.Encoding]::UTF8.GetBytes('PiBoxClonePrivateConfig:v1')
$protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
    $archiveBytes,
    $entropy,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
)
$roundTrip = [Security.Cryptography.ProtectedData]::Unprotect(
    $protectedBytes,
    $entropy,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
)

$sourceHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($archiveBytes)).ToLowerInvariant()
$roundTripHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($roundTrip)).ToLowerInvariant()
if ($sourceHash -ne $roundTripHash) {
    throw 'DPAPI round-trip validation failed.'
}

$outputDirectory = Split-Path -Parent $OutputPath
[void](New-Item -ItemType Directory -Force -Path $outputDirectory)
[IO.File]::WriteAllBytes($OutputPath, $protectedBytes)

[Security.Cryptography.CryptographicOperations]::ZeroMemory($archiveBytes)
[Security.Cryptography.CryptographicOperations]::ZeroMemory($roundTrip)
$protectedBytes = $null
$entropy = $null
[GC]::Collect()

Write-Host 'EXPORT=PASS'
Write-Host "ENCRYPTED_BUNDLE=$([IO.Path]::GetFullPath($OutputPath))"
Write-Host "PLAINTEXT_SHA256=$sourceHash"
