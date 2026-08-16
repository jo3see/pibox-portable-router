[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetAddress,

    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')]
    [string]$TargetHostname = 'pibox-router',

    [ValidateSet('pibox')]
    [string]$TargetUser = 'pibox',
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetIdentityFile,

    [ValidatePattern('^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}$')]
    [string]$ExpectedUsbId = '35bc:0108',

    [ValidatePattern('^[A-Za-z0-9_]+$')]
    [string]$ExpectedWlan1Driver = 'rtw89_8852bu',

    [string]$SourceAddress,
    [string]$SourceUser = 'pibox',
    [string]$SourceIdentityFile,
    [string]$EncryptedSourceBundle,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SshOptions = @('-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10')
$TargetEndpoint = "$TargetUser@$TargetAddress"
$SourceEndpoint = if ($SourceAddress) { "$SourceUser@$SourceAddress" } else { $null }
$RemoteRoot = "/tmp/pibox-clone-$([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath exited with code $LASTEXITCODE."
    }
}

function Invoke-TargetSsh {
    param([Parameter(Mandatory)][string]$Command)
    $arguments = @('-i', $TargetIdentityFile) + $SshOptions + @($TargetEndpoint, $Command)
    Invoke-NativeChecked -FilePath 'ssh' -ArgumentList $arguments
}

function Send-TextToTargetStdin {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$RemoteCommand
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'ssh'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in (@('-i', $TargetIdentityFile) + $SshOptions + @($TargetEndpoint, $RemoteCommand))) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $process.StandardInput.Write($Text)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($stdout) { Write-Host $stdout.TrimEnd() }
    if ($stderr) { Write-Host $stderr.TrimEnd() }
    if ($process.ExitCode -ne 0) {
        throw "SSH secret transfer exited with code $($process.ExitCode)."
    }
}

foreach ($identityFile in @($TargetIdentityFile)) {
    if (-not (Test-Path -LiteralPath $identityFile -PathType Leaf)) {
        throw "SSH identity file not found: $identityFile"
    }
}
if ([string]::IsNullOrWhiteSpace($EncryptedSourceBundle)) {
    if ([string]::IsNullOrWhiteSpace($SourceAddress)) {
        throw 'Provide -SourceAddress or use -EncryptedSourceBundle.'
    }
    if ([string]::IsNullOrWhiteSpace($SourceIdentityFile)) {
        throw 'Provide -SourceIdentityFile or use -EncryptedSourceBundle.'
    }
    if (-not (Test-Path -LiteralPath $SourceIdentityFile -PathType Leaf)) {
        throw "SSH identity file not found: $SourceIdentityFile"
    }
} elseif (-not (Test-Path -LiteralPath $EncryptedSourceBundle -PathType Leaf)) {
    throw "Encrypted source bundle not found: $EncryptedSourceBundle"
}

Write-Host "Running read-only hardware and transport preflight on $TargetEndpoint ..."
$preflightScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pibox-target.sh') -Raw
$preflightCommand = 'sudo -n env "SSH_CONNECTION=$SSH_CONNECTION" bash -s -- preflight ''{0}'' ''{1}''' -f $ExpectedUsbId, $ExpectedWlan1Driver
Send-TextToTargetStdin -Text $preflightScript -RemoteCommand $preflightCommand
$preflightScript = $null

if (-not $Apply) {
    Write-Host 'PREVIEW=PASS'
    Write-Host 'No changes were made. Re-run with -Apply after reviewing the preflight.'
    exit 0
}

Write-Host "Staging the provisioning bundle at $RemoteRoot ..."
Invoke-TargetSsh -Command "install -d -m 0700 '$RemoteRoot' '$RemoteRoot/provision'"

$copyItems = @(
    (Join-Path $ProjectRoot 'pibox-portal'),
    (Join-Path $ProjectRoot '50-raspap-router.portal.conf'),
    (Join-Path $PSScriptRoot 'pibox-target.sh'),
    (Join-Path $PSScriptRoot 'pibox-verify.sh'),
    (Join-Path $PSScriptRoot 'pibox-enable-pi5-5ghz.sh'),
    (Join-Path $PSScriptRoot 'pibox-routing'),
    (Join-Path $PSScriptRoot 'pibox-routing.service'),
    (Join-Path $PSScriptRoot 'pibox-portal-close.service'),
    (Join-Path $PSScriptRoot 'pibox-portal-close.timer'),
    (Join-Path $PSScriptRoot 'pibox-portal.sudoers'),
    (Join-Path $PSScriptRoot 'portal.php')
)

foreach ($item in $copyItems) {
    $remoteDirectory = if ((Split-Path -Parent $item) -eq $PSScriptRoot) { "$RemoteRoot/provision/" } else { "$RemoteRoot/" }
    $arguments = @('-i', $TargetIdentityFile) + $SshOptions + @($item, "${TargetEndpoint}:$remoteDirectory")
    Invoke-NativeChecked -FilePath 'scp' -ArgumentList $arguments
}

Write-Host 'Installing the pinned network and RaspAP prerequisites ...'
$prepareCommand = 'sudo -n env "SSH_CONNECTION=$SSH_CONNECTION" bash ''{0}/provision/pibox-target.sh'' prepare ''{1}'' ''{2}''' -f $RemoteRoot, $ExpectedUsbId, $ExpectedWlan1Driver
Invoke-TargetSsh -Command $prepareCommand

Write-Host 'Transferring private AP, upstream Wi-Fi, and RaspAP authentication settings directly in memory ...'
if ([string]::IsNullOrWhiteSpace($EncryptedSourceBundle)) {
    $sourceCommand = "sudo -n tar -C / -cf - etc/hostapd/hostapd.conf etc/wpa_supplicant/wpa_supplicant.conf etc/raspap/raspap.auth etc/raspap/hostapd.ini etc/raspap/networking/defaults.json | base64 -w0"
    $sourceArguments = @('-i', $SourceIdentityFile) + $SshOptions + @($SourceEndpoint, $sourceCommand)
    $secretArchiveBase64 = (& ssh @sourceArguments) -join ''
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($secretArchiveBase64)) {
        throw 'Could not read the private configuration bundle from the working PiBox.'
    }
} else {
    $entropy = [Text.Encoding]::UTF8.GetBytes('PiBoxClonePrivateConfig:v1')
    $protectedBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $EncryptedSourceBundle))
    $archiveBytes = [Security.Cryptography.ProtectedData]::Unprotect(
        $protectedBytes,
        $entropy,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    $secretArchiveBase64 = [Convert]::ToBase64String($archiveBytes)
    [Security.Cryptography.CryptographicOperations]::ZeroMemory($archiveBytes)
    $protectedBytes = $null
    $entropy = $null
}

try {
    Send-TextToTargetStdin -Text $secretArchiveBase64 -RemoteCommand "base64 -d | sudo -n tar -C / -xf -"
}
finally {
    $secretArchiveBase64 = $null
    [GC]::Collect()
}

Write-Host 'Applying the final PiBox configuration ...'
Invoke-TargetSsh -Command "sudo -n bash '$RemoteRoot/provision/pibox-target.sh' finalize '$TargetHostname'"

Write-Host 'APPLY=PASS'
Write-Host "The target is ready for reboot and fresh Tailscale enrollment as $TargetHostname."
