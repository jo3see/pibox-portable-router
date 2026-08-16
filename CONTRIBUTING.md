# Contributing

Issues and pull requests are welcome, especially for additional USB Wi-Fi
adapters, Raspberry Pi models, captive portals, documentation, and security
review.

## Ground rules

1. Never submit real Wi-Fi credentials, authentication hashes, SSH keys,
   Tailscale state, public/private addresses tied to a deployment, or captive
   portal session data.
2. Describe hardware with Raspberry Pi model, OS release, kernel, USB ID,
   driver, interface role, and whether cold boot was tested.
3. Preserve the read-only default. Destructive or network-changing behavior must
   require an explicit apply action and clearly identify its scope.
4. Keep Guest Login Mode limited to one requesting client and time-bound.
5. Add or update verification checks for behavior changes.

## Local checks

From PowerShell:

```powershell
pwsh -NoProfile -File .\tools\Test-Repository.ps1
```

If `shellcheck` is installed, the repository checker runs it automatically.
Always inspect `git diff --cached` before committing.

## Pull requests

Explain the problem, approach, security implications, hardware tested, commands
used for verification, and any remaining limitations. Do not include screenshots
or logs until they have been sanitized.
