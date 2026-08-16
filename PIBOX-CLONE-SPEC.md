# PiBox Golden Configuration

This is the reproducible configuration contract for a PiBox appliance. It
distinguishes settings that may be copied from a trusted reference appliance
from identities that must be regenerated for every device.

## Hardware and base OS

- Supported hardware is Raspberry Pi 3 Model B Rev 1.2 or Raspberry Pi 5 Model B,
  running 64-bit Raspberry Pi OS based on Debian 13.
- Built-in Broadcom radio is `wlan0` and provides the private PiBox access point.
- By default, a TP-Link Archer TX20U Nano (`35bc:0108`, `rtw89_8852bu`) is
  `wlan1` and joins the upstream/workplace Wi-Fi. The orchestrator accepts a
  different USB ID and driver when testing another adapter.
- Provisioning must be performed over wired Ethernet. The preflight refuses to
  apply changes when the active SSH path is using Wi-Fi.
- User is `pibox`, UID/GID 1000, with passwordless noninteractive sudo available
  during provisioning and SSH public-key access enabled.

## PiBox access point

- Interface: `wlan0`
- Address: `10.3.141.1/24`
- SSID: `PiBox`
- Raspberry Pi 3B: 2.4 GHz channel 6
- Raspberry Pi 5B: 5 GHz channel 36, 80 MHz width, 802.11ac
- Country `US`, hidden SSID
- WPA2-PSK with CCMP
- DHCP pool: `10.3.141.50` through `10.3.141.254`, 12-hour leases
- The AP passphrase is copied directly from the working Pi to the new Pi in
  memory. It is never written to this repository or printed by the tooling.

## Upstream Wi-Fi

- Interface: `wlan1`
- Managed by `wpa_supplicant@wlan1.service` and `dhcpcd`
- The live source Pi's network profiles are copied directly in memory so the
  new Pi knows the same upstream SSIDs and credentials.
- `/etc/wpa_supplicant/wpa_supplicant-wlan1.conf` is a symlink to
  `/etc/wpa_supplicant/wpa_supplicant.conf`.

## Normal protected routing

- IPv4 forwarding is enabled.
- Tailscale supplies the default route in table 52 through an exit node selected
  by the operator.
- Rule priority 5260 keeps traffic to `10.3.141.0/24` in the main table.
- `PIBOX-KILLSWITCH` permits `wlan0 -> tailscale0`, permits established replies,
  and rejects any other forwarded traffic from `wlan0`.
- PiBox client traffic is masqueraded on `tailscale0`.
- Forwarded TCP SYN packets leaving through `tailscale0` have MSS clamped to
  the path MTU to prevent fragmentation and asymmetric throughput loss.
- `pibox-routing.service` recreates these rules at boot.

## Guest Login Mode

- `http://10.3.141.1/portal.php` is protected by the same RaspAP administrator
  credentials and CSRF mechanism as the dashboard.
- Enabling mode authorizes only the requesting PiBox client's IPv4 address.
- For 10 minutes, that one client gets unrestricted IPv4 forwarding through
  `wlan1`, including DNS redirection to the resolver supplied to `wlan1` by
  DHCP. This broad access is intentional because captive portals vary.
- The temporary source policy rule is priority 5265.
- A systemd timer closes the exception after 10 minutes; the user can close it
  immediately from the portal as well.
- Guest Login Mode does not grant other PiBox clients direct upstream access.

## Web administration

- RaspAP version/tag: `3.5.5`
- Main repository commit: `e01a2aea27c2d49b602f1b3d043d219c16962216`
- Plugins repository commit: `c44d00e5d2e7832ebbaa69025da25b87488b546a`
- Web stack: lighttpd with PHP 8.4 FPM
- RaspAP admin authentication is copied directly from the working Pi without
  exposing the password hash.

## Tailscale

- Every PiBox must enroll as a new Tailscale node.
- Required preferences after enrollment:
  - a selected and online exit node
  - exit-node LAN access disabled
  - subnet routes not accepted
  - Tailscale DNS accepted
- The new node uses a unique hostname such as `pibox-router`.

## Raspberry Pi Connect

- `rpi-connect-lite` is installed on the working Pi.
- The second Pi must be signed in separately after provisioning. Its account and
  device identity are not copied.

## Never clone these identities

- `/etc/machine-id`
- SSH host keys under `/etc/ssh/ssh_host_*`
- `/var/lib/tailscale`
- the Linux hostname
- DHCP leases or runtime state under `/run`

The provisioning also does not force SSH password authentication on. It keeps
the target image's SSH authentication policy and requires the project public
key; this avoids weakening a key-only target just to mirror a nonessential
source setting.

Cloning any of those would make two simultaneously running devices conflict or
appear to be the same machine.

## Deployment sequence

1. Flash 64-bit Raspberry Pi OS Lite (Debian 13), create user `pibox`, enable
   SSH, and install your own SSH public key.
2. Attach the selected USB Wi-Fi adapter and connect Ethernet.
3. Run the orchestration script without `-Apply`; all preflight checks must pass.
4. Run it with `-Apply`. It installs RaspAP and the network stack, transfers the
   three private configuration areas directly from the working Pi, and installs
   the routing and portal components.
5. Reboot the new Pi, enroll it as a fresh Tailscale node, apply the exact exit
   node preferences, and run the read-only verifier.
6. Test normal protected browsing and a real captive-portal acceptance using
   Guest Login Mode; confirm another client remains blocked from direct `wlan1`.
