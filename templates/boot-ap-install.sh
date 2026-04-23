#!/bin/bash
# Runs once from kernel cmdline (systemd.run) after the stock firstboot init is gone.
# Installs a NetworkManager Wi-Fi AP profile from the boot partition, then continues boot.
set -uo pipefail

BOOTFW=/boot/firmware
[[ -d $BOOTFW ]] || BOOTFW=/boot

SRC_HOT="$BOOTFW/pi5-hotspot.nmconnection"
SELF="$BOOTFW/pi5-boot-install-ap.sh"
COUNTRY_FILE="$BOOTFW/pi5-ap-country"
CMDLINE="$BOOTFW/cmdline.txt"
[[ -f "$CMDLINE" ]] || CMDLINE=/boot/cmdline.txt

strip_cmdline() {
  [[ -f "$CMDLINE" ]] || return 0
  # Remove our pi5-setup flags. Do NOT use systemd\.run=[^ ]* — values can contain spaces
  # (older flashes used "/bin/bash /boot/firmware/...") and partial strips corrupt cmdline.
  sed -i.bak \
    -e 's|[[:space:]]*systemd\.run=/bin/bash */boot/firmware/pi5-boot-install-ap\.sh||g' \
    -e 's|[[:space:]]*systemd\.run=/boot/firmware/pi5-boot-install-ap\.sh||g' \
    -e 's|[[:space:]]*systemd\.run_success_action=[^[:space:]]*||g' \
    -e 's|[[:space:]]*systemd\.run_failure_action=[^[:space:]]*||g' \
    -e 's|[[:space:]]*systemd\.unit=[^[:space:]]*||g' \
    "$CMDLINE"
  rm -f "${CMDLINE}.bak" 2>/dev/null || true
}

if [[ ! -f "$SRC_HOT" ]]; then
  strip_cmdline
  systemctl start --no-block multi-user.target 2>/dev/null || true
  exit 0
fi

install -d -m 755 /etc/NetworkManager/system-connections
install -m 600 -o root -g root "$SRC_HOT" /etc/NetworkManager/system-connections/pi5-setup-ap.nmconnection || exit 1

if [[ -f "$COUNTRY_FILE" ]]; then
  CC="$(tr -d '[:space:]' < "$COUNTRY_FILE" | head -c 2)"
  if [[ -n "$CC" ]] && command -v raspi-config >/dev/null; then
    raspi-config nonint do_wifi_country "$CC" || true
  fi
fi

strip_cmdline
sync

systemctl restart NetworkManager || true
sleep 4
nmcli con reload || true
nmcli connection up pi5-setup-ap 2>/dev/null || nmcli con up pi5-setup-ap 2>/dev/null || true

rm -f "$SRC_HOT" "$SELF" "$COUNTRY_FILE" 2>/dev/null || true
sync
systemctl start --no-block multi-user.target 2>/dev/null || true
exit 0
