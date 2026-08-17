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

PiBox has three separate connections:

1. **PiBox Wi-Fi** is the hidden network your phone, tablet, or laptop joins.
2. **Host Wi-Fi** is the hotel, workplace, or home network joined by `wlan1`.
3. **Tailscale** carries normal PiBox internet traffic through a trusted exit
   node after any host-network login is complete.

Tailscale is not optional in this release. Without an online exit node, local
pages such as RaspAP still work, but normal client internet access is blocked.

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

## 5. Prepare Tailscale

Do this while Ethernet is still connected. It is easiest to create the
Tailscale account and home exit node before installing PiBox, but you may do it
now if needed.

If you do not already have Tailscale:

1. Go to [Tailscale](https://tailscale.com/) and select **Get Started**.
2. Sign in to create your private Tailscale network, called a *tailnet*.
3. Install Tailscale on a trusted computer or server that will stay online,
   usually at home.
4. Sign that device into the same Tailscale account.
5. Configure that device to **Run as exit node**.
6. In the Tailscale admin console, open **Machines**, find that device, open
   its route settings, and allow **Use as exit node**.
7. Write down that exit node's Tailscale IPv4 address. It normally begins with
   `100.`.

The exact exit-node screens differ by operating system. Follow Tailscale's
[official exit-node guide](https://tailscale.com/docs/features/exit-nodes).

Next, reconnect to the Pi through Ethernet or its local console. If its
Ethernet address changed after reboot, find the new address in your router's
client list. From Windows PowerShell, connect with your own address and key:

```powershell
ssh -i $HOME\.ssh\pibox_ed25519 pibox@192.168.1.123
```

Every PiBox must receive its own Tailscale identity; never copy
`/var/lib/tailscale` from another Pi. At the Pi's prompt, run:

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
the login URL printed by Tailscale and sign in with the same account. Keep the
exit-node device powered on whenever PiBox needs normal internet access.

## 6. Connect your device to PiBox Wi-Fi

On the phone, tablet, or laptop you want to protect:

1. Open its Wi-Fi settings.
2. Choose the option named **Other**, **Add network**, or **Hidden network**.
3. Enter the PiBox SSID exactly as you entered it during installation.
4. Choose WPA2/WPA-Personal security if the device asks.
5. Enter the PiBox Wi-Fi passphrase selected during installation.
6. Join the network. The device may say **No internet** at first. Stay
   connected; that is expected until the next steps are complete.

PiBox keeps the network hidden while using hostapd compatibility mode 2. This
helps phones and tablets find the hidden network reliably after you type its
exact name.

If a previously saved hidden PiBox network will not reconnect, forget or delete
that saved network and add it manually again.

## 7. Connect PiBox to the host Wi-Fi

Keep your phone, tablet, or laptop connected to PiBox Wi-Fi.

1. Open a browser and enter **`http://10.3.141.1`**. Use `http`, not `https`.
2. Sign in with administrator name `admin` and the RaspAP administrator
   password selected during installation.
3. In the RaspAP menu, select **WiFi client**.
4. Find the **Interface** box. It must say **`wlan1`**. If it does not, select
   `wlan1` and select **Set**. Never change `wlan0`; it is the PiBox Wi-Fi your
   device is using.
5. Select **Rescan**.
6. Find the host Wi-Fi under **Nearby**.
7. For a password-protected network, enter its Wi-Fi password. For an open
   guest network, leave the disabled passphrase box alone.
8. Select **Add**.
9. Find the network under **Known**, then select **Connect**.
10. Wait until the WiFi client page says **Connected**. Give DHCP up to 30
    seconds to supply an IP address and DNS information.

If the installer already saved this host network, it may appear under **Known**
immediately. Select **Connect** if it is not already connected.

## 8. Accept a hotel or workplace login page

Skip this section if the host Wi-Fi does not require a browser login or
terms-of-service page.

1. While still connected to PiBox Wi-Fi, open a new browser tab.
2. Enter **`http://10.3.141.1/portal.php`**.
3. Sign in with the same RaspAP administrator name and password if asked.
4. Select **Enable Guest Login Mode for 10 Minutes**.
5. Select **Open Workplace Login Page**. PiBox opens an ordinary HTTP page so
   the host network can redirect you to its login or terms page.
6. Complete the host network's normal login, room-number prompt, or
   terms-of-service acceptance.
7. Return to the PiBox Guest Login Mode tab.
8. Select **Close Guest Login Mode Now**. Do not leave the direct connection
   open after the host-network login is complete.

Guest Login Mode temporarily allows only the device that requested it to go
directly through `wlan1`. It closes automatically after ten minutes, but closing
it immediately returns PiBox to its protected Tailscale-only path.

If the portal reports that no IPv4 DNS resolver was supplied, return to
`http://10.3.141.1`, confirm the WiFi client page says **Connected**, wait 30
seconds, and try again.

## 9. Verify protected operation

Run the verifier on the Pi, substituting your exit-node address and USB adapter
driver:

```sh
sudo pibox-verify 100.64.0.20 rtw89_8852bu
```

After Guest Login Mode is closed, open an ordinary website from the device
connected to PiBox Wi-Fi. It should work through the selected Tailscale exit
node. Keep Ethernet or console access until the verifier and live browsing test
both pass.

## Can I skip Tailscale?

Not in this release. The PiBox kill switch permits normal client traffic only
through `tailscale0`. Guest Login Mode is a short-lived tool for completing a
legitimate host-network login; it must not be used as a permanent direct mode.

Supporting an optional non-Tailscale mode would require a separate routing and
security design. Simply omitting Tailscale will leave normal client internet
access intentionally blocked.
