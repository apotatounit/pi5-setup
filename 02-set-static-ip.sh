#!/usr/bin/env bash
# 02-set-static-ip.sh — Run this ON THE PI (over SSH) to set a permanent static IP.
# Usage: bash 02-set-static-ip.sh
set -euo pipefail

ETH_IP="192.168.100.91"
ETH_PREFIX="24"
ETH_GATEWAY="192.168.100.1"
ETH_DNS="192.168.100.1,8.8.8.8"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m ok \033[0m %s\n' "$*"; }

[[ "$(uname -s)" == "Linux" ]] || die "run this ON THE PI, not on your Mac"
command -v nmcli >/dev/null     || die "nmcli not found — is NetworkManager running?"

# Find the active wired connection name
CON="$(nmcli -t -f NAME,TYPE connection show --active | grep ':ethernet' | head -1 | cut -d: -f1)"
[[ -n "$CON" ]] || die "no active ethernet connection found (is the cable plugged in?)"
info "active ethernet connection: «$CON»"

info "applying static IP config"
sudo nmcli connection modify "$CON" \
  ipv4.method manual \
  ipv4.addresses "${ETH_IP}/${ETH_PREFIX}" \
  ipv4.gateway   "${ETH_GATEWAY}" \
  ipv4.dns       "${ETH_DNS}" \
  ipv6.method    disabled

sudo nmcli connection down "$CON" && sudo nmcli connection up "$CON" &
ok "done"

cat <<MSG

  Static IP set: ${ETH_IP}/${ETH_PREFIX}
  Gateway:       ${ETH_GATEWAY}
  DNS:           ${ETH_DNS}

  Connection is being restarted — your SSH session will drop.
  Reconnect with:

    ssh $(whoami)@${ETH_IP}

MSG
