# 05-wifi-ap.sh — Pi-side: NetworkManager Wi-Fi access point (concatenated or solo via bash -s).
# Expects env: WIFI_AP_ENABLE, WIFI_AP_SSID, WIFI_AP_PASSWORD (≥8 chars when enabled).

log()  { printf '\033[36m[wifi-ap]\033[0m %s\n' "$*"; }
skip() { printf '\033[33m[wifi-ap skip]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[wifi-ap ok]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[wifi-ap error]\033[0m %s\n' "$*" >&2; exit 1; }

en="${WIFI_AP_ENABLE:-0}"
if [[ "$en" != "1" && "$en" != "true" && "$en" != "yes" ]]; then
  skip "WIFI_AP_ENABLE is off ($en)"
else
[[ "$(id -u)" -ne 0 ]] || die "run as login user (not root); script uses sudo where needed"

command -v nmcli >/dev/null || die "nmcli not found (need NetworkManager / Raspberry Pi OS Bookworm+)"

WLAN="$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')"
[[ -n "$WLAN" ]] || WLAN="wlan0"
if ! nmcli -t -f DEVICE device status 2>/dev/null | grep -qx "$WLAN"; then
  die "no Wi-Fi interface (tried $WLAN). Use Ethernet once or check rfkill."
fi

CON_NAME="pi5-setup-ap"
SSID="$WIFI_AP_SSID"
PASS="$WIFI_AP_PASSWORD"
((${#PASS} >= 8)) || die "WIFI_AP_PASSWORD must be at least 8 characters"

if nmcli -t -f NAME connection show 2>/dev/null | grep -qx "$CON_NAME"; then
  cur_ssid="$(nmcli -g 802-11-wireless.ssid connection show "$CON_NAME" 2>/dev/null || true)"
  if [[ "$cur_ssid" != "$SSID" ]]; then
    log "replacing $CON_NAME (SSID was «$cur_ssid», want «$SSID»)"
    sudo nmcli connection delete "$CON_NAME" >/dev/null
  fi
fi

if ! nmcli -t -f NAME connection show 2>/dev/null | grep -qx "$CON_NAME"; then
  log "creating hotspot SSID=$SSID on $WLAN (2.4 GHz)"
  if ! sudo nmcli device wifi hotspot ifname "$WLAN" con-name "$CON_NAME" \
      ssid "$SSID" password "$PASS" band bg 2>/dev/null; then
    log "retry without explicit band (older nmcli)"
    sudo nmcli device wifi hotspot ifname "$WLAN" con-name "$CON_NAME" \
      ssid "$SSID" password "$PASS" || die "nmcli hotspot failed"
  fi
  sudo nmcli connection modify "$CON_NAME" connection.autoconnect yes
else
  log "bringing up existing $CON_NAME"
  sudo nmcli connection up "$CON_NAME" || die "failed to activate $CON_NAME"
fi

sleep 1
GW=""
if command -v ip >/dev/null; then
  GW="$(ip -4 -br addr show "$WLAN" 2>/dev/null | awk '{print $3}' | cut -d/ -f1)"
fi
[[ -n "$GW" ]] || GW="$(nmcli -g IP4.ADDRESS device show "$WLAN" 2>/dev/null | head -1 | cut -d/ -f1)"
[[ -n "$GW" ]] || GW="10.42.0.1"

ok "join Wi-Fi «$SSID» (WPA2), then: ssh ${PI_USER:-pi}@$GW"
echo
printf '  SSID:     %s\n' "$SSID"
printf '  Password: (WIFI_AP_PASSWORD from your Mac config.env)\n'
printf '  SSH:      ssh %s@%s\n' "${PI_USER:-pi}" "$GW"
fi
