#!/bin/bash
set -euo pipefail

RASPBAP_TAG=3.5.5
RASPBAP_COMMIT=e01a2aea27c2d49b602f1b3d043d219c16962216
PLUGINS_COMMIT=c44d00e5d2e7832ebbaa69025da25b87488b546a
STATE_DIR=/var/lib/pibox-clone
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

die()
{
    echo "ERROR: $*" >&2
    exit 1
}

require_root()
{
    [ "$(id -u)" -eq 0 ] || die "Run this script as root."
}

driver_for()
{
    basename "$(readlink -f "/sys/class/net/$1/device/driver" 2>/dev/null)" 2>/dev/null || true
}

has_usb_adapter()
{
    expected_id="$1"
    expected_vendor="${expected_id%:*}"
    expected_product="${expected_id#*:}"
    for vendor_file in /sys/bus/usb/devices/*/idVendor; do
        [ -f "$vendor_file" ] || continue
        device_dir="${vendor_file%/idVendor}"
        [ "$(cat "$vendor_file")" = "$expected_vendor" ] || continue
        [ -f "$device_dir/idProduct" ] || continue
        [ "$(cat "$device_dir/idProduct")" = "$expected_product" ] && return 0
    done
    return 1
}

preflight()
{
    require_root
    expected_usb_id="$(printf '%s' "${1:-35bc:0108}" | tr '[:upper:]' '[:lower:]')"
    expected_wlan1_driver="${2:-rtw89_8852bu}"

    case "$expected_usb_id" in
        [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
        *) die "Invalid expected USB ID: $expected_usb_id" ;;
    esac
    case "$expected_wlan1_driver" in
        *[!a-zA-Z0-9_]*|'') die "Invalid expected wlan1 driver: $expected_wlan1_driver" ;;
    esac

    model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
    case "$model" in
        *"Raspberry Pi 3 Model B Rev 1.2"*|*"Raspberry Pi 5 Model B Rev "*) ;;
        *) die "Expected a supported Raspberry Pi 3B or 5B; found: ${model:-unknown}" ;;
    esac

    [ "$(dpkg --print-architecture)" = arm64 ] || die "The golden build requires the arm64 OS."
    # shellcheck source=/dev/null
    . /etc/os-release
    [ "${ID:-}" = debian ] || [ "${ID_LIKE:-}" = debian ] || die "Expected a Debian-family Raspberry Pi OS."
    [ "${VERSION_ID:-}" = 13 ] || die "Expected Debian 13; found VERSION_ID=${VERSION_ID:-unknown}."

    has_usb_adapter "$expected_usb_id" || die "Expected upstream USB Wi-Fi adapter $expected_usb_id is missing."
    ip link show wlan0 >/dev/null 2>&1 || die "wlan0 is missing."
    ip link show wlan1 >/dev/null 2>&1 || die "wlan1 is missing."

    wlan0_driver="$(driver_for wlan0)"
    wlan1_driver="$(driver_for wlan1)"
    [ "$wlan0_driver" = brcmfmac ] || die "wlan0 must be the built-in brcmfmac radio; found ${wlan0_driver:-unknown}."
    [ "$wlan1_driver" = "$expected_wlan1_driver" ] || die "wlan1 must use $expected_wlan1_driver; found ${wlan1_driver:-unknown}."

    if [ -n "${SSH_CONNECTION:-}" ]; then
        client_ip="${SSH_CONNECTION%% *}"
        ingress_dev="$(ip route get "$client_ip" | awk '{ for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }')"
        [ "$ingress_dev" = eth0 ] || die "Provisioning SSH must arrive over eth0; current path uses ${ingress_dev:-unknown}."
    else
        echo "WARNING: SSH_CONNECTION is absent; confirm the console or management path is wired Ethernet." >&2
    fi

    sudo -u pibox -H true 2>/dev/null || die "Required user 'pibox' is missing or unavailable."
    getent group sudo | grep -qw pibox || die "User 'pibox' must belong to the sudo group."

    echo "PREFLIGHT=PASS"
    echo "MODEL=$model"
    echo "WLAN0_DRIVER=$wlan0_driver"
    echo "WLAN1_DRIVER=$wlan1_driver"
}

backup_path()
{
    source_path="$1"
    destination_root="$2"
    [ -e "$source_path" ] || [ -L "$source_path" ] || return 0
    mkdir -p "$destination_root$(dirname "$source_path")"
    cp -a -- "$source_path" "$destination_root$source_path"
}

prepare()
{
    require_root
    preflight "$@"
    export DEBIAN_FRONTEND=noninteractive
    export TERM=xterm

    apt-get update
    apt-get install -y \
        curl git sudo openssh-server usbutils ethtool iw rfkill rsync jq qrencode isoquery \
        hostapd dnsmasq dhcpcd5 wpasupplicant iptables iptables-persistent nftables \
        lighttpd php8.4-fpm php8.4-cli php8.4-cgi php8.4-common \
        vnstat speedtest-cli rpi-connect-lite

    if ! command -v tailscale >/dev/null 2>&1; then
        tailscale_installer=/tmp/pibox-tailscale-install.sh
        curl -fsSL https://tailscale.com/install.sh -o "$tailscale_installer"
        sh "$tailscale_installer"
        rm -f -- "$tailscale_installer"
    fi

    raspap_source=/tmp/pibox-raspap-source
    rm -rf -- "$raspap_source"
    git clone --branch "$RASPBAP_TAG" --depth 1 https://github.com/RaspAP/raspap-webgui.git "$raspap_source"
    [ "$(git -C "$raspap_source" rev-parse HEAD)" = "$RASPBAP_COMMIT" ] || die "RaspAP tag did not resolve to the pinned commit."

    bash "$raspap_source/installers/raspbian.sh" \
        --yes --branch "$RASPBAP_TAG" --openvpn 0 --restapi 0 --adblock 0 --wireguard 0 --check 1

    [ "$(git -c safe.directory=/var/www/html -C /var/www/html rev-parse HEAD)" = "$RASPBAP_COMMIT" ] || die "Installed RaspAP revision differs from the golden revision."
    git -c safe.directory=/var/www/html/plugins -C /var/www/html/plugins fetch --all --tags
    git -c safe.directory=/var/www/html/plugins -C /var/www/html/plugins checkout --detach "$PLUGINS_COMMIT"

    install -d -o root -g root -m 0700 "$STATE_DIR"
    date -Is >"$STATE_DIR/prepared"
    echo "PREPARE=PASS"
}

finalize()
{
    require_root
    [ "$#" -eq 1 ] || die "Usage: $0 finalize UNIQUE_HOSTNAME"
    new_hostname="$1"
    case "$new_hostname" in
        *[!a-zA-Z0-9-]*|''|-*|*-) die "Invalid hostname: $new_hostname" ;;
    esac
    [ -f "$STATE_DIR/prepared" ] || die "Prepare phase has not completed."

    for private_file in \
        /etc/hostapd/hostapd.conf \
        /etc/wpa_supplicant/wpa_supplicant.conf \
        /etc/raspap/raspap.auth \
        /etc/raspap/hostapd.ini \
        /etc/raspap/networking/defaults.json; do
        [ -s "$private_file" ] || die "Private source transfer is incomplete: $private_file"
    done

    stamp="$(date +%Y%m%dT%H%M%S%z)"
    backup_dir="/root/pibox-clone-backups/$stamp"
    install -d -o root -g root -m 0700 "$backup_dir"
    for path in /etc/dhcpcd.conf /etc/dnsmasq.d /etc/lighttpd/conf-available/50-raspap-router.conf \
        /usr/local/sbin/pibox-routing /usr/local/sbin/pibox-portal \
        /etc/systemd/system/pibox-routing.service /etc/systemd/system/pibox-portal-close.service \
        /etc/systemd/system/pibox-portal-close.timer /etc/sudoers.d/pibox-portal /var/www/html/portal.php; do
        backup_path "$path" "$backup_dir"
    done

    hostnamectl set-hostname "$new_hostname"
    if grep -qE '^127\.0\.1\.1[[:space:]]+' /etc/hosts; then
        sed -i -E "s/^127\\.0\\.1\\.1[[:space:]]+.*/127.0.1.1\t$new_hostname/" /etc/hosts
    else
        printf '127.0.1.1\t%s\n' "$new_hostname" >>/etc/hosts
    fi

    cat >/etc/dhcpcd.conf <<'EOF'
# RaspAP default configuration
hostname
clientid
persistent
option rapid_commit
option domain_name_servers, domain_name, domain_search, host_name
option classless_static_routes
option ntp_servers
require dhcp_server_identifier
slaac private
nohook lookup-hostname

# RaspAP wlan0 configuration
interface wlan0
static ip_address=10.3.141.1/24
nogateway
static routers=10.3.141.1
static domain_name_servers=1.1.1.1 8.8.8.8
EOF

    install -d -o root -g root -m 0755 /etc/dnsmasq.d /etc/dnsmasq.disabled
    find /etc/dnsmasq.d -maxdepth 1 -type f -exec mv -t /etc/dnsmasq.disabled -- {} +
    cat >/etc/dnsmasq.d/090_raspap.conf <<'EOF'
# RaspAP default config
log-facility=/var/log/dnsmasq.log
conf-dir=/etc/dnsmasq.d
EOF
    cat >/etc/dnsmasq.d/090_wlan0.conf <<'EOF'
# RaspAP wlan0 configuration
interface=wlan0
domain-needed
dhcp-range=10.3.141.50,10.3.141.254,255.255.255.0,12h
EOF

    install -d -o root -g root -m 0755 /etc/sysctl.d
    printf '%s\n' 'net.ipv4.ip_forward=1' >/etc/sysctl.d/90_raspap.conf

    install -o root -g root -m 0755 "$SCRIPT_DIR/pibox-routing" /usr/local/sbin/pibox-routing
    install -o root -g root -m 0755 "$SCRIPT_DIR/../pibox-portal" /usr/local/sbin/pibox-portal
    install -o root -g root -m 0644 "$SCRIPT_DIR/pibox-routing.service" /etc/systemd/system/pibox-routing.service
    install -o root -g root -m 0644 "$SCRIPT_DIR/pibox-portal-close.service" /etc/systemd/system/pibox-portal-close.service
    install -o root -g root -m 0644 "$SCRIPT_DIR/pibox-portal-close.timer" /etc/systemd/system/pibox-portal-close.timer
    install -o root -g root -m 0440 "$SCRIPT_DIR/pibox-portal.sudoers" /etc/sudoers.d/pibox-portal
    install -o root -g root -m 0644 "$SCRIPT_DIR/../50-raspap-router.portal.conf" /etc/lighttpd/conf-available/50-raspap-router.conf
    install -o root -g root -m 0644 "$SCRIPT_DIR/portal.php" /var/www/html/portal.php

    chmod 0644 /etc/hostapd/hostapd.conf
    chown root:root /etc/hostapd/hostapd.conf
    chmod 0600 /etc/wpa_supplicant/wpa_supplicant.conf
    chown root:root /etc/wpa_supplicant/wpa_supplicant.conf
    ln -sfn /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-wlan1.conf
    chown www-data:www-data /etc/raspap/raspap.auth /etc/raspap/hostapd.ini /etc/raspap/networking/defaults.json
    chmod 0644 /etc/raspap/raspap.auth /etc/raspap/hostapd.ini /etc/raspap/networking/defaults.json

    rfkill unblock wlan
    case "$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)" in
        *"Raspberry Pi 5 Model B Rev "*) bash "$SCRIPT_DIR/pibox-enable-pi5-5ghz.sh" ;;
    esac

    sh -n /usr/local/sbin/pibox-routing
    sh -n /usr/local/sbin/pibox-portal
    visudo -cf /etc/sudoers.d/pibox-portal
    dnsmasq --test
    lighttpd -tt -f /etc/lighttpd/lighttpd.conf
    sysctl --system >/dev/null

    systemctl disable --now NetworkManager.service 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable dhcpcd.service hostapd.service dnsmasq.service wpa_supplicant@wlan1.service \
        tailscaled.service lighttpd.service php8.4-fpm.service pibox-routing.service ssh.service
    systemctl restart php8.4-fpm.service lighttpd.service tailscaled.service
    systemctl restart dhcpcd.service wpa_supplicant@wlan1.service hostapd.service dnsmasq.service

    rm -f -- /run/pibox-portal-client /run/pibox-portal-dns
    date -Is >"$STATE_DIR/finalized"
    echo "FINALIZE=PASS"
    echo "BACKUP_DIR=$backup_dir"
    echo "NEXT=reboot, enroll a fresh Tailscale identity, then verify"
}

case "${1:-}" in
    preflight)
        shift
        preflight "$@"
        ;;
    prepare)
        shift
        prepare "$@"
        ;;
    finalize)
        shift
        finalize "$@"
        ;;
    *) die "Usage: $0 preflight | prepare | finalize UNIQUE_HOSTNAME" ;;
esac
