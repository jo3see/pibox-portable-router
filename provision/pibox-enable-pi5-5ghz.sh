#!/bin/bash
set -euo pipefail

die()
{
    echo "ERROR: $*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || die "Run this script as root."

model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
case "$model" in
    *"Raspberry Pi 5 Model B Rev "*) ;;
    *) die "This 5 GHz profile is only for a Raspberry Pi 5B; found: ${model:-unknown}" ;;
esac

conf=/etc/hostapd/hostapd.conf
[ -s "$conf" ] || die "Missing hostapd configuration: $conf"

stamp="$(date +%Y%m%dT%H%M%S%z)"
backup_dir="/root/pibox-ap-backups/$stamp"
install -d -o root -g root -m 0700 "$backup_dir"
cp -a -- "$conf" "$backup_dir/hostapd.conf"

upsert()
{
    key="$1"
    value="$2"
    if grep -qE "^${key}=" "$conf"; then
        sed -i -E "s|^${key}=.*|${key}=${value}|" "$conf"
    else
        printf '%s=%s\n' "$key" "$value" >>"$conf"
    fi
}

upsert country_code US
upsert hw_mode a
upsert channel 36
upsert ieee80211n 1
upsert ht_capab '[HT40+]'
upsert ieee80211ac 1
upsert vht_oper_chwidth 1
upsert vht_oper_centr_freq_seg0_idx 42
upsert wmm_enabled 1

ready=false
if systemctl restart hostapd.service; then
    for attempt in $(seq 1 20); do
        if systemctl is-active --quiet hostapd.service && \
           hostapd_cli -i wlan0 status 2>/dev/null | grep -Fqx 'state=ENABLED'; then
            ready=true
            break
        fi
        sleep 1
    done
fi

if [ "$ready" != true ]; then
    cp -a -- "$backup_dir/hostapd.conf" "$conf"
    systemctl restart hostapd.service || true
    die "The 5 GHz AP failed to start; the previous configuration was restored."
fi

echo "PI5_5GHZ=PASS"
echo "BACKUP_DIR=$backup_dir"
hostapd_cli -i wlan0 status 2>/dev/null | grep -E '^(state|channel|ieee80211n|ieee80211ac)='
iw dev wlan0 info | grep -E '^\s*channel '
