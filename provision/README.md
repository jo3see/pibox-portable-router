# Provisioning a PiBox

The scripts in this directory reproduce the PiBox behavior while creating fresh
device identities. Read `../PIBOX-CLONE-SPEC.md` before applying changes.

## Prepare the target

Use Raspberry Pi Imager to install 64-bit Raspberry Pi OS Lite based on Debian
13 on a supported Raspberry Pi 3B or Raspberry Pi 5B. In Imager customization:

- set a temporary unique hostname;
- create user `pibox`;
- enable SSH with public-key authentication; and
- install your own SSH public key, such as `$HOME\.ssh\pibox_ed25519.pub`.

Connect Ethernet and attach a TP-Link Archer TX20U Nano (`35bc:0108`) as the
USB upstream radio. Do not bootstrap through Wi-Fi. See `../docs/HARDWARE.md`
to select another adapter explicitly.

The finalizer keeps the Pi 3B client AP on 2.4 GHz channel 6. On a Pi 5B it
enables the internal radio's 5 GHz 802.11ac mode on non-DFS channel 36 with an
80 MHz width. `wlan1` remains the USB upstream adapter.

## Read-only preflight

From PowerShell in the repository root:

```powershell
.\provision\Invoke-PiBoxClone.ps1 `
  -TargetAddress 192.168.1.123 `
  -TargetIdentityFile $HOME\.ssh\pibox_ed25519 `
  -SourceAddress 100.64.0.10 `
  -SourceIdentityFile $HOME\.ssh\pibox_ed25519
```

This runs only hardware, OS, user, interface, adapter, and Ethernet-path checks.
It does not write to the Pi.

## Apply from a trusted source PiBox

After the preflight passes:

```powershell
.\provision\Invoke-PiBoxClone.ps1 `
  -TargetAddress 192.168.1.123 `
  -TargetHostname pibox-router `
  -TargetIdentityFile $HOME\.ssh\pibox_ed25519 `
  -SourceAddress 100.64.0.10 `
  -SourceIdentityFile $HOME\.ssh\pibox_ed25519 `
  -Apply
```

The apply phase changes only the target Pi. It reads AP, upstream Wi-Fi, and
RaspAP authentication settings from the trusted source and streams them to the
target in memory. Private data is not written to this repository.

## Offline encrypted bundle

If the source and target cannot be online together, export while the source is
available:

```powershell
.\provision\Export-PiBoxPrivateConfig.ps1 `
  -SourceAddress 100.64.0.10 `
  -SourceIdentityFile $HOME\.ssh\pibox_ed25519
```

The resulting `.pibox-secrets\source-private-config.dpapi` is ignored by Git and
can be decrypted only by the same Windows user account. Use it after switching
to the target:

```powershell
.\provision\Invoke-PiBoxClone.ps1 `
  -TargetAddress 192.168.1.123 `
  -TargetHostname pibox-router `
  -TargetIdentityFile $HOME\.ssh\pibox_ed25519 `
  -EncryptedSourceBundle .\.pibox-secrets\source-private-config.dpapi `
  -Apply
```

## Fresh Tailscale enrollment

After rebooting, reconnect over Ethernet and enroll the target interactively.
Substitute the desired exit-node Tailscale address:

```sh
sudo tailscale up \
  --hostname=pibox-router \
  --exit-node=100.64.0.20 \
  --exit-node-allow-lan-access=false \
  --accept-routes=false \
  --accept-dns=true
sudo systemctl restart pibox-routing.service
```

Never copy `/var/lib/tailscale` from another Pi. Sign Raspberry Pi Connect in
separately as well if you choose to use it.

## Verification

Run the verifier with the exit-node address and expected upstream driver:

```sh
sudo bash provision/pibox-verify.sh 100.64.0.20 rtw89_8852bu
```

Then perform two live client tests:

1. normal browsing exits through the selected Tailscale exit node and direct
   `wlan1` forwarding remains blocked;
2. Guest Login Mode allows only the requesting client direct IPv4 access
   through `wlan1` for ten minutes, completes a real captive portal, and closes
   cleanly afterward.
