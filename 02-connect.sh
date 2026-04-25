#!/usr/bin/env bash
# 02-connect.sh — Discover Pi, verify SSH, add ~/.ssh/config entry.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${HERE}/config.env"
[[ -r "$CONFIG" ]] || { echo "missing config.env"; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m ok\033[0m %s\n' "$*"; }

HOST_MDNS="${PI_HOSTNAME}.local"
info "resolving ${HOST_MDNS}"
IP=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if command -v dscacheutil >/dev/null; then
    IP="$(dscacheutil -q host -a name "$HOST_MDNS" 2>/dev/null | awk '/ip_address/ {print $2; exit}')"
  elif command -v getent >/dev/null; then
    IP="$(getent hosts "$HOST_MDNS" | awk '{print $1; exit}')"
  fi
  [[ -n "$IP" ]] && break
  sleep 5
done
[[ -n "$IP" ]] || die "could not resolve $HOST_MDNS — give it another minute or check DHCP."
ok "found $HOST_MDNS at $IP"

info "recording host key"
ssh-keygen -R "$HOST_MDNS" >/dev/null 2>&1 || true
ssh-keygen -R "$IP"        >/dev/null 2>&1 || true
ssh-keyscan -t ed25519,rsa -T 5 "$HOST_MDNS" "$IP" 2>/dev/null >> "$HOME/.ssh/known_hosts"

SSH_CONF="$HOME/.ssh/config"
touch "$SSH_CONF"; chmod 600 "$SSH_CONF"
BEGIN="# >>> pi5-setup:${PI_HOSTNAME} >>>"
END="# <<< pi5-setup:${PI_HOSTNAME} <<<"
tmp="$(mktemp)"
awk -v b="$BEGIN" -v e="$END" '
  $0==b {skip=1}
  !skip {print}
  $0==e {skip=0}
' "$SSH_CONF" > "$tmp"
{
  cat "$tmp"
  cat <<EOF
$BEGIN
Host ${PI_HOSTNAME}
  HostName ${HOST_MDNS}
  User ${PI_USER}
  IdentityFile ${SSH_PUBKEY_PATH%.pub}
  IdentitiesOnly yes
  ServerAliveInterval 30
$END
EOF
} > "$SSH_CONF"
rm -f "$tmp"
ok "~/.ssh/config updated"

info "testing ssh"
ssh -o BatchMode=yes -o ConnectTimeout=10 \
  -o PreferredAuthentications=publickey -o PubkeyAuthentication=yes \
  "$PI_HOSTNAME" 'echo "connected as $(whoami)@$(hostname)"' \
  || die "ssh failed. First boot can take 90s; retry."

ok "ready. Next: ./03-bootstrap.sh"
