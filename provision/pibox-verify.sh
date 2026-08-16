#!/bin/bash
set -euo pipefail

exit_node_ip="${1:-${PIBOX_EXIT_NODE:-}}"
expected_wlan1_driver="${2:-${PIBOX_WLAN1_DRIVER:-rtw89_8852bu}}"

valid_ipv4()
{
    printf '%s\n' "$1" | awk -F. '
        NF != 4 { exit 1 }
        {
            for (i = 1; i <= 4; i++) {
                if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) {
                    exit 1
                }
            }
        }
    '
}

if [ -n "$exit_node_ip" ] && ! valid_ipv4 "$exit_node_ip"; then
    echo "Invalid exit-node IPv4 address." >&2
    exit 2
fi

case "$expected_wlan1_driver" in
    *[!a-zA-Z0-9_]*|'')
        echo "Invalid wlan1 driver: $expected_wlan1_driver" >&2
        exit 2
        ;;
esac

fail=0
pass(){ printf 'PASS  %s\n' "$1"; }
bad(){ printf 'FAIL  %s\n' "$1"; fail=1; }
check(){ if eval "$2"; then pass "$1"; else bad "$1"; fi; }

check 'supported Raspberry Pi 3B or 5B hardware' "tr -d '\\0' </proc/device-tree/model | grep -Eq 'Raspberry Pi (3 Model B Rev 1\\.2|5 Model B Rev )'"
check 'wlan0 uses built-in Broadcom driver' "ethtool -i wlan0 2>/dev/null | grep -Fq 'driver: brcmfmac'"
check 'wlan1 uses expected USB driver' "ethtool -i wlan1 2>/dev/null | grep -Fq 'driver: $expected_wlan1_driver'"
check 'wlan0 has PiBox gateway address' "ip -4 -br addr show wlan0 | grep -Fq '10.3.141.1/24'"
model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
case "$model" in
    *"Raspberry Pi 5 Model B Rev "*)
        check 'Pi 5 AP uses 5 GHz channel 36' "hostapd_cli -i wlan0 status 2>/dev/null | grep -Fqx 'channel=36'"
        check 'Pi 5 AP uses 802.11ac' "hostapd_cli -i wlan0 status 2>/dev/null | grep -Fqx 'ieee80211ac=1'"
        check 'Pi 5 AP uses 80 MHz width' "iw dev wlan0 info | grep -Fq 'width: 80 MHz'"
        ;;
    *)
        check 'Pi 3B AP uses 2.4 GHz channel 6' "hostapd_cli -i wlan0 status 2>/dev/null | grep -Fqx 'channel=6'"
        ;;
esac
check 'IPv4 forwarding is enabled' "[ \"$(sysctl -n net.ipv4.ip_forward)\" = 1 ]"
check 'RaspAP is pinned to 3.5.5' "[ \"$(git -c safe.directory=/var/www/html -C /var/www/html rev-parse HEAD)\" = e01a2aea27c2d49b602f1b3d043d219c16962216 ]"
check 'RaspAP plugins revision is pinned' "[ \"$(git -c safe.directory=/var/www/html/plugins -C /var/www/html/plugins rev-parse HEAD)\" = c44d00e5d2e7832ebbaa69025da25b87488b546a ]"

for unit in dhcpcd hostapd dnsmasq wpa_supplicant@wlan1 tailscaled lighttpd php8.4-fpm pibox-routing ssh; do
    check "$unit is enabled" "systemctl is-enabled --quiet '$unit'"
    check "$unit is active" "systemctl is-active --quiet '$unit'"
done

check 'normal route policy rule exists' "ip -4 rule show | grep -Eq '^5260:.*to 10\\.3\\.141\\.0/24 lookup main'"
check 'PiBox kill-switch chain exists' "iptables -S PIBOX-KILLSWITCH >/dev/null 2>&1"
check 'normal path allows wlan0 to tailscale0' "iptables -C PIBOX-KILLSWITCH -i wlan0 -o tailscale0 -j ACCEPT"
check 'kill switch rejects other wlan0 forwarding' "iptables -C PIBOX-KILLSWITCH -i wlan0 -j REJECT"
check 'Tailscale masquerade exists' "iptables -t nat -C POSTROUTING -s 10.3.141.0/24 -o tailscale0 -j MASQUERADE"
check 'forwarded TCP MSS is clamped to Tailscale MTU' "iptables -t mangle -C FORWARD -o tailscale0 -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu"
check 'Guest Login Mode begins closed' "[ ! -e /run/pibox-portal-client ]"
check 'portal helper syntax is valid' "sh -n /usr/local/sbin/pibox-portal"
check 'lighttpd syntax is valid' "lighttpd -tt -f /etc/lighttpd/lighttpd.conf >/dev/null 2>&1"
check 'portal is not exposed from localhost' "[ \"$(curl -sS -o /tmp/pibox-portal-verify-body -w '%{http_code}' -H 'Host: 10.3.141.1' http://127.0.0.1/portal.php)\" = 403 ]"
rm -f -- /tmp/pibox-portal-verify-body

check 'Tailscale backend is running' "tailscale status --json | jq -e '.BackendState == \"Running\"' >/dev/null"
if [ -n "$exit_node_ip" ]; then
    check 'configured exit node is selected and online' "tailscale status --json | jq -e --arg ip '$exit_node_ip/32' '.ExitNodeStatus.Online == true and (.ExitNodeStatus.TailscaleIPs | index(\$ip))' >/dev/null"
else
    check 'an exit node is selected and online' "tailscale status --json | jq -e '.ExitNodeStatus.Online == true' >/dev/null"
fi
check 'Tailscale table 52 owns the default route' "ip -4 route show table 52 | grep -Eq '^default dev tailscale0'"
check 'Tailscale policy matches the golden settings' "tailscale debug prefs | jq -e '.RouteAll == false and .ExitNodeAllowLANAccess == false and .CorpDNS == true and .WantRunning == true and .LoggedOut == false' >/dev/null"

tailscale status
tailscale debug prefs

[ "$fail" -eq 0 ] || exit 1
echo 'VERIFY=PASS'
