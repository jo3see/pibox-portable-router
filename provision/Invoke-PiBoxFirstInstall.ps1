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

    [ValidateNotNullOrEmpty()]
    [string]$AccessPointSsid = 'PiBox',

    [ValidatePattern('^[A-Z]{2}$')]
    [string]$CountryCode = 'US',

    [ValidatePattern('^[A-Za-z0-9_.-]{1,32}$')]
    [string]$AdminUser = 'admin',

    [string]$UpstreamSsid,
    [switch]$OpenUpstream,
    [switch]$BroadcastAccessPoint,

    [Security.SecureString]$AccessPointPassphrase,
    [Security.SecureString]$AdminPassword,
    [Security.SecureString]$UpstreamPassphrase,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SshOptions = @('-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10')
$TargetEndpoint = "$TargetUser@$TargetAddress"
$RemoteRoot = "/tmp/pibox-first-install-$([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"

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
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
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
        throw "SSH input transfer exited with code $($process.ExitCode)."
    }
}

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][Security.SecureString]$SecureValue)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Assert-PrintableAscii {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][int]$MinimumLength,
        [Parameter(Mandatory)][int]$MaximumLength
    )

    if ($Value.Length -lt $MinimumLength -or $Value.Length -gt $MaximumLength) {
        throw "$Name must contain between $MinimumLength and $MaximumLength characters."
    }
    if ($Value -notmatch '^[\x20-\x7E]+$') {
        throw "$Name must use printable ASCII characters only."
    }
}

function Read-ConfirmedSecret {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][int]$MinimumLength,
        [Parameter(Mandatory)][int]$MaximumLength
    )

    while ($true) {
        $firstSecure = Read-Host -Prompt $Prompt -AsSecureString
        $secondSecure = Read-Host -Prompt 'Enter it again to confirm' -AsSecureString
        $first = ConvertTo-PlainText -SecureValue $firstSecure
        $second = ConvertTo-PlainText -SecureValue $secondSecure
        try {
            Assert-PrintableAscii -Name $Prompt -Value $first -MinimumLength $MinimumLength -MaximumLength $MaximumLength
            if ($first -ne $second) {
                Write-Warning 'The two entries did not match. Please try again.'
                continue
            }
            return $first
        }
        catch {
            Write-Warning $_.Exception.Message
        }
        finally {
            $second = $null
            $firstSecure = $null
            $secondSecure = $null
        }
    }
}

function Get-ValidatedSecret {
    param(
        [Security.SecureString]$ProvidedValue,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][int]$MinimumLength,
        [Parameter(Mandatory)][int]$MaximumLength
    )

    if ($ProvidedValue) {
        $plainValue = ConvertTo-PlainText -SecureValue $ProvidedValue
        Assert-PrintableAscii -Name $Prompt -Value $plainValue -MinimumLength $MinimumLength -MaximumLength $MaximumLength
        return $plainValue
    }
    Read-ConfirmedSecret -Prompt $Prompt -MinimumLength $MinimumLength -MaximumLength $MaximumLength
}

function ConvertTo-Base64Utf8 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

if (-not (Test-Path -LiteralPath $TargetIdentityFile -PathType Leaf)) {
    throw "SSH identity file not found: $TargetIdentityFile"
}
Assert-PrintableAscii -Name 'Access-point SSID' -Value $AccessPointSsid -MinimumLength 1 -MaximumLength 32
if ($UpstreamSsid) {
    Assert-PrintableAscii -Name 'Upstream SSID' -Value $UpstreamSsid -MinimumLength 1 -MaximumLength 32
} elseif ($OpenUpstream -or $UpstreamPassphrase) {
    throw '-OpenUpstream and -UpstreamPassphrase require -UpstreamSsid.'
}
if ($OpenUpstream -and $UpstreamPassphrase) {
    throw 'Do not supply -UpstreamPassphrase for an open upstream network.'
}

Write-Host "Running read-only hardware and transport preflight on $TargetEndpoint ..."
$preflightScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pibox-target.sh') -Raw
$preflightCommand = 'sudo -n env "SSH_CONNECTION=$SSH_CONNECTION" bash -s -- preflight ''{0}'' ''{1}''' -f $ExpectedUsbId, $ExpectedWlan1Driver
Send-TextToTargetStdin -Text $preflightScript -RemoteCommand $preflightCommand
$preflightScript = $null

Write-Host "Planned hostname: $TargetHostname"
Write-Host "Planned PiBox Wi-Fi: $AccessPointSsid"
Write-Host "Planned PiBox Wi-Fi visibility: $(if ($BroadcastAccessPoint) { 'broadcast' } else { 'hidden' })"
Write-Host "Planned initial upstream: $(if ($UpstreamSsid) { $UpstreamSsid } else { 'none; configure later in RaspAP' })"
if (-not $Apply) {
    Write-Host 'PREVIEW=PASS'
    Write-Host 'No changes were made. Re-run with -Apply after reviewing the preflight and plan.'
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

$apPlaintext = $null
$adminPlaintext = $null
$upstreamPlaintext = $null
$payload = $null
$payloadLines = $null
try {
    $apPlaintext = Get-ValidatedSecret -ProvidedValue $AccessPointPassphrase `
        -Prompt 'Enter the PiBox Wi-Fi passphrase' -MinimumLength 8 -MaximumLength 63
    $adminPlaintext = Get-ValidatedSecret -ProvidedValue $AdminPassword `
        -Prompt 'Enter the RaspAP administrator password' -MinimumLength 12 -MaximumLength 128

    $upstreamSecurity = 'none'
    if ($UpstreamSsid) {
        if ($OpenUpstream) {
            $upstreamSecurity = 'open'
            $upstreamPlaintext = ''
        } else {
            $upstreamSecurity = 'wpa-psk'
            $upstreamPlaintext = Get-ValidatedSecret -ProvidedValue $UpstreamPassphrase `
                -Prompt 'Enter the initial upstream Wi-Fi passphrase' -MinimumLength 8 -MaximumLength 63
        }
    } else {
        $upstreamPlaintext = ''
    }

    $payloadLines = @(
        'PIBOX_FIRST_CONFIG_V1',
        (ConvertTo-Base64Utf8 -Value $CountryCode),
        (ConvertTo-Base64Utf8 -Value $AccessPointSsid),
        (ConvertTo-Base64Utf8 -Value $apPlaintext),
        (ConvertTo-Base64Utf8 -Value $AdminUser),
        (ConvertTo-Base64Utf8 -Value $adminPlaintext),
        (ConvertTo-Base64Utf8 -Value $(if ($UpstreamSsid) { $UpstreamSsid } else { '' })),
        (ConvertTo-Base64Utf8 -Value $upstreamPlaintext),
        $upstreamSecurity,
        $(if ($BroadcastAccessPoint) { '1' } else { '0' })
    )
    $payload = ($payloadLines -join "`n") + "`n"

    Write-Host 'Generating private configuration directly on the target ...'
    Send-TextToTargetStdin -Text $payload `
        -RemoteCommand "sudo -n bash '$RemoteRoot/provision/pibox-target.sh' configure-new"
}
finally {
    $payload = $null
    $payloadLines = $null
    $apPlaintext = $null
    $adminPlaintext = $null
    $upstreamPlaintext = $null
    [GC]::Collect()
}

Write-Host 'Applying the final PiBox configuration ...'
Invoke-TargetSsh -Command "sudo -n bash '$RemoteRoot/provision/pibox-target.sh' finalize '$TargetHostname'"

Write-Host 'APPLY=PASS'
Write-Host "The target is ready for reboot and fresh Tailscale enrollment as $TargetHostname."
