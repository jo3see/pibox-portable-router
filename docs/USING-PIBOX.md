# Use PiBox at a hotel or workplace

Use this checklist each time you take an already-installed PiBox to a new
network.

## Know the three connections

- **PiBox Wi-Fi:** the private hidden SSID your phone, tablet, or laptop joins.
- **Host Wi-Fi:** the hotel or workplace network joined by the USB adapter on
  `wlan1`.
- **Tailscale exit node:** the trusted device that carries normal PiBox internet
  traffic after the host-network login is finished.

The Tailscale exit node must be online. PiBox does not have a permanent
non-Tailscale internet mode.

## 1. Power on PiBox

Connect power and wait about two minutes for PiBox to boot. Ethernet is not
needed during normal travel use.

## 2. Join the hidden PiBox Wi-Fi

1. Open Wi-Fi settings on your phone, tablet, or laptop.
2. Choose **Other**, **Add network**, or **Hidden network**.
3. Enter your PiBox SSID exactly.
4. Choose WPA2/WPA-Personal if asked.
5. Enter your PiBox Wi-Fi password and join.

Stay connected if the device says **No internet**. The host network is not
ready yet. If the saved PiBox network will not reconnect, forget it and add the
hidden network manually again.

PiBox uses hostapd hidden-network compatibility mode 2. The network remains
hidden, but its beacon keeps the SSID length so phones and tablets can discover
it more reliably when you enter the exact network name.

## 3. Connect `wlan1` to the host Wi-Fi

1. Open **`http://10.3.141.1`** in a browser. Use `http`, not `https`.
2. Sign in as `admin` with your RaspAP administrator password.
3. Select **WiFi client**.
4. Confirm **Interface** is **`wlan1`**. If needed, choose `wlan1` and select
   **Set**. Never select `wlan0` here.
5. Select **Rescan**.
6. Find the hotel or workplace network under **Nearby**.
7. Enter its Wi-Fi password if it has one.
8. Select **Add**.
9. Find it under **Known** and select **Connect**.
10. Wait until the page says **Connected**, then wait up to 30 more seconds for
    an IP address and DNS information.

For an open guest network, leave the disabled passphrase box alone. If the
network is already saved under **Known**, select **Connect** without adding it
again.

## 4. Complete the host-network login

Do this only when the host Wi-Fi requires a browser login or terms acceptance.

1. Open a new browser tab.
2. Go to **`http://10.3.141.1/portal.php`**.
3. Sign in with your RaspAP administrator credentials if asked.
4. Select **Enable Guest Login Mode for 10 Minutes**.
5. Select **Open Workplace Login Page**.
6. Complete the hotel's or workplace's normal login or accept its terms.
7. Return to the PiBox Guest Login Mode tab.
8. Select **Close Guest Login Mode Now**.

Closing Guest Login Mode is important. It removes the temporary direct path and
locks PiBox back to the normal Tailscale-only path. PiBox will close it
automatically after ten minutes if you forget.

If you see **No valid IPv4 DNS resolver was supplied to wlan1 by DHCP**, return
to RaspAP, confirm **WiFi client** says **Connected**, wait 30 seconds, and try
again.

## 5. Confirm normal protected browsing

With Guest Login Mode closed, open an ordinary website. If it loads, PiBox is
using the Tailscale exit path normally.

If browsing stops as soon as Guest Login Mode closes, check that:

1. the Tailscale exit-node device is powered on and online;
2. PiBox is connected to the host Wi-Fi on `wlan1`; and
3. PiBox still has its selected Tailscale exit node.

Do not work around this failure by repeatedly reopening Guest Login Mode. That
mode exists only to complete the host network's legitimate login process.
