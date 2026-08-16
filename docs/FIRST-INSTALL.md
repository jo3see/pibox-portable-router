# Build your first PiBox

This guide starts with a blank microSD card and does not require an existing
PiBox. The installer is designed for a dedicated Raspberry Pi because applying
it replaces the target's networking, DHCP, DNS, web-server, firewall, and
wireless configuration.

## What you need

- A Raspberry Pi 5B or Raspberry Pi 3 Model B Rev 1.2
- A supported USB Wi-Fi adapter; the default is a TP-Link Archer TX20U Nano
  (`35bc:0108`, driver `rtw89_8852bu`)
- A microSD card with 64-bit Raspberry Pi OS Lite based on Debian 13
- Temporary Ethernet access to the same network as your Windows computer
- PowerShell 7 on the Windows computer
- An SSH key on the Windows computer
- Access to a Tailscale account and an available Tailscale exit node

The internal Pi radio becomes the private PiBox Wi-Fi network. The USB adapter
joins hotel, workplace, or home Wi-Fi. Ethernet is used only for installation
and recovery.

## 1. Prepare Raspberry Pi OS

In Raspberry Pi Imager, choose the supported 64-bit Lite image. In OS
customization:

1. give the Pi a temporary unique hostname;
2. create the user `pibox`;
3. enable SSH using public-key authentication; and
4. add your own SSH public key.

Do not configure the Pi's built-in Wi-Fi in Imager. Insert the card, attach the
USB Wi-Fi adapter and Ethernet cable, and boot. Find the Ethernet IP address in
your router's client list.

## 2. Download the project

On Windows, download and extract this repository or clone it with Git. Open
PowerShell in the repository folder.

## 3. Run the safe preview

Replace the example IP address and SSH-key path:

```powershell
.\provision\Invoke-PiBoxFirstInstall.ps1 `
  -TargetAddress 192.168.1.123 `
  -TargetIdentityFile $HOME\.ssh\pibox_ed25519 `
  -TargetHostname pibox-router `
  -AccessPointSsid MyPiBox `
  -UpstreamSsid MyHomeWiFi
```

This first run is read-only. It checks that the target is a supported Pi, uses
the expected OS and radio assignments, and that SSH is arriving over Ethernet.
It ends with `PREVIEW=PASS` when the target is ready.

If you do not want to save an initial upstream network, omit
`-UpstreamSsid`. You can add Wi-Fi later from the RaspAP interface. For an open
guest network, add both `-UpstreamSsid NetworkName` and `-OpenUpstream`.

The PiBox SSID is hidden by default to match the verified appliance profile.
Add `-BroadcastAccessPoint` if you prefer a visible network.

## 4. Apply the installation

Carefully review the preview. Keep local console access available. Repeat the
same command with `-Apply` at the end:

```powershell
.\provision\Invoke-PiBoxFirstInstall.ps1 `
  -TargetAddress 192.168.1.123 `
  -TargetIdentityFile $HOME\.ssh\pibox_ed25519 `
  -TargetHostname pibox-router `
  -AccessPointSsid MyPiBox `
  -UpstreamSsid MyHomeWiFi `
  -Apply
```

The installer prompts for these values without displaying them:

1. PiBox Wi-Fi passphrase, 8 to 63 printable characters
2. RaspAP administrator password, 12 to 128 printable characters
3. Initial upstream Wi-Fi passphrase, if a protected upstream SSID was supplied

Each prompt is entered twice. The installer sends the answers inside the
encrypted SSH connection and does not save them on Windows. The Pi must store
the two Wi-Fi credentials in its protected service configuration to reconnect
after reboot. The administrator password is stored only as a bcrypt hash.

Installation downloads operating-system packages, Tailscale, and the project's
pinned RaspAP version. When it ends with `APPLY=PASS`, reboot the Pi:

```powershell
ssh -i $HOME\.ssh\pibox_ed25519 pibox@192.168.1.123 "sudo reboot"
```

## 5. Enroll Tailscale

Reconnect through Ethernet or the Pi's local console. Every PiBox must receive
its own Tailscale identity; never copy `/var/lib/tailscale` from another Pi.

```sh
sudo tailscale up \
  --hostname=pibox-router \
  --exit-node=100.64.0.20 \
  --exit-node-allow-lan-access=false \
  --accept-routes=false \
  --accept-dns=true
sudo systemctl restart pibox-routing.service
```

Replace `100.64.0.20` with the Tailscale address of your own exit node. Follow
the login URL printed by Tailscale if it requests authorization.

## 6. Connect and verify

Join the PiBox SSID using the password selected during installation. For a
hidden SSID, choose the device's option to join another or hidden network and
enter the name exactly. Open `http://10.3.141.1` and sign in using administrator
name `admin` and the password selected during installation.

If no initial upstream was supplied, use RaspAP's WiFi client page to add one on
`wlan1`. Do not change the `wlan0` and `wlan1` roles.

Finally, run the verifier on the Pi, substituting your exit-node address and USB
adapter driver:

```sh
sudo pibox-verify 100.64.0.20 rtw89_8852bu
```

Then test normal protected browsing and Guest Login Mode as described in the
main README. Keep Ethernet or console access until both tests pass.
