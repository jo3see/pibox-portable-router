# Security policy

## Supported versions

Until the first tagged release, security fixes apply to the latest commit on
the default branch.

## Reporting a vulnerability

Do not open a public issue containing credentials, private network details,
authentication bypasses, or an exploit against a deployed PiBox. Contact the
maintainer privately through the security-reporting channel configured on the
GitHub repository. Include affected files, reproduction steps, impact, and a
minimal proof of concept when safe.

## Operator responsibilities

- Use SSH public-key authentication and protect the private key.
- Keep `.pibox-secrets/`, `.codex-ssh/`, exports, logs, and live configuration
  outside version control.
- Use a unique hostname, SSH host keys, machine ID, and Tailscale identity for
  every device.
- Review the read-only preflight before applying changes.
- Keep console or Ethernet recovery access during provisioning.
- Treat Guest Login Mode as a deliberate, temporary reduction in isolation for
  one client and close it immediately after captive-portal authentication.
- Update Raspberry Pi OS, RaspAP, Tailscale, and this project after reviewing
  release notes and testing on non-production hardware.

## Secret handling

The first-device installer accepts passwords as hidden `SecureString` input and
streams a short-lived encoded payload through SSH standard input. Encoding is
not encryption; SSH supplies transport protection. The target necessarily
stores Wi-Fi credentials in its protected service configuration, while RaspAP's
administrator password is stored as a bcrypt hash.

The clone orchestrator can stream configuration directly from a trusted source
PiBox or use a Windows DPAPI CurrentUser-encrypted bundle. DPAPI encryption is
not a substitute for access control or backups. Never commit the bundle,
decrypted configuration, Wi-Fi credentials, RaspAP hashes, SSH keys, or
Tailscale state.

Before publishing any change, run the repository checks and inspect the entire
staged diff for personal addresses, SSIDs, hostnames, and credentials.
