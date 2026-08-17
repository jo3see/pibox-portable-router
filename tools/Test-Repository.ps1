[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    $failures.Add($Message)
    Write-Host "FAIL  $Message" -ForegroundColor Red
}

function Add-Pass {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "PASS  $Message" -ForegroundColor Green
}

Push-Location $repositoryRoot
try {
    $requiredFiles = @(
        'README.md', 'LICENSE', 'NOTICE', 'SECURITY.md', 'CONTRIBUTING.md',
        '.gitignore', 'PIBOX-CLONE-SPEC.md',
        'docs/FIRST-INSTALL.md', 'docs/USING-PIBOX.md',
        'provision/Invoke-PiBoxFirstInstall.ps1',
        'provision/Invoke-PiBoxClone.ps1', 'provision/pibox-target.sh',
        'provision/pibox-verify.sh'
    )
    foreach ($file in $requiredFiles) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Add-Pass "required file exists: $file"
        } else {
            Add-Failure "required file missing: $file"
        }
    }

    $targetScript = Get-Content -LiteralPath 'provision/pibox-target.sh' -Raw
    $hiddenCompatibilitySetting = 'ignore_broadcast_ssid=$((2 * (1 - broadcast_ap)))'
    if ($targetScript.Contains($hiddenCompatibilitySetting)) {
        Add-Pass 'hidden SSID uses client compatibility mode 2'
    } else {
        Add-Failure 'hidden SSID must use client compatibility mode 2'
    }

    $powerShellFiles = Get-ChildItem -Recurse -File -Filter '*.ps1'
    foreach ($file in $powerShellFiles) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$tokens,
            [ref]$errors
        )
        if ($errors.Count -eq 0) {
            Add-Pass "PowerShell syntax: $($file.FullName.Substring($repositoryRoot.Length + 1))"
        } else {
            foreach ($parseError in $errors) {
                Add-Failure "PowerShell syntax in $($file.Name): $($parseError.Message)"
            }
        }
    }

    $shellFiles = @(
        Get-ChildItem -Recurse -File -Filter '*.sh'
        Get-Item 'pibox-portal', 'provision/pibox-routing'
    )
    $bashPath = $null
    $gitBashCandidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )
    foreach ($candidate in $gitBashCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $bashPath = $candidate
            break
        }
    }
    if (-not $bashPath) {
        $bashCommand = Get-Command bash -ErrorAction SilentlyContinue
        if ($bashCommand -and $bashCommand.Source -notmatch '(?i)Windows[\\/]System32[\\/]bash\.exe$') {
            $bashPath = $bashCommand.Source
        }
    }
    if ($bashPath) {
        foreach ($file in $shellFiles) {
            $shellPath = $file.FullName.Replace('\', '/')
            & $bashPath -n $shellPath
            if ($LASTEXITCODE -eq 0) {
                Add-Pass "shell syntax: $($file.FullName.Substring($repositoryRoot.Length + 1))"
            } else {
                Add-Failure "shell syntax failed: $($file.FullName.Substring($repositoryRoot.Length + 1))"
            }
        }
    } else {
        Write-Host 'SKIP  bash is not installed; shell syntax will run in CI.' -ForegroundColor Yellow
    }

    $php = Get-Command php -ErrorAction SilentlyContinue
    if ($php) {
        & $php.Source -l 'provision/portal.php'
        if ($LASTEXITCODE -eq 0) {
            Add-Pass 'PHP syntax: provision/portal.php'
        } else {
            Add-Failure 'PHP syntax failed: provision/portal.php'
        }
    } else {
        Write-Host 'SKIP  PHP CLI is not installed; PHP syntax will run in CI.' -ForegroundColor Yellow
    }

    $shellcheck = Get-Command shellcheck -ErrorAction SilentlyContinue
    if ($shellcheck) {
        & $shellcheck.Source @($shellFiles.FullName)
        if ($LASTEXITCODE -eq 0) {
            Add-Pass 'ShellCheck'
        } else {
            Add-Failure 'ShellCheck reported findings.'
        }
    } else {
        Write-Host 'SKIP  ShellCheck is not installed; it will run in CI.' -ForegroundColor Yellow
    }

    $tracked = @(& git ls-files)
    $forbiddenNames = $tracked | Where-Object {
        $_ -match '(^|/)(\.pibox-secrets|\.codex-ssh|private)/' -or
        $_ -match '(?i)(\.dpapi|\.p12|\.pfx|known_hosts|id_rsa|id_ed25519)$'
    }
    if ($forbiddenNames) {
        Add-Failure "forbidden private files are tracked: $($forbiddenNames -join ', ')"
    } else {
        Add-Pass 'no forbidden private filenames are tracked'
    }

    $textFiles = Get-ChildItem -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]'
    }
    $secretPatterns = @(
        '-----BEGIN (OPENSSH|RSA|EC) PRIVATE KEY-----',
        '(?i)C:\\Users\\[^\\\s]+',
        '(?i)(^|[^A-Za-z0-9])DESKTOP-[A-F0-9]{7}([^A-Za-z0-9]|$)',
        '(?im)^\s*wpa_passphrase\s*=\s*\S+',
        '(?im)^\s*psk\s*=\s*[^$<{\s]\S*'
    )
    foreach ($file in $textFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($null -eq $content) { continue }
        foreach ($pattern in $secretPatterns) {
            if ($content -match $pattern) {
                Add-Failure "possible private data in $($file.FullName.Substring($repositoryRoot.Length + 1))"
                break
            }
        }
    }
    if (-not ($failures | Where-Object { $_ -like 'possible private data*' })) {
        Add-Pass 'content privacy patterns'
    }
}
finally {
    Pop-Location
}

if ($failures.Count -gt 0) {
    Write-Host "REPOSITORY_CHECK=FAIL ($($failures.Count) finding(s))" -ForegroundColor Red
    exit 1
}

Write-Host 'REPOSITORY_CHECK=PASS' -ForegroundColor Green
