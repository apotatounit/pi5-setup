#!/usr/bin/env bash
# Pipe one or more Pi-side scripts over ssh with Wi-Fi AP env from config.env.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
[[ -r ./config.env ]] || die "missing config.env"
# shellcheck source=/dev/null
source ./config.env

[[ -n "${PI_HOSTNAME:-}" ]] || die "PI_HOSTNAME unset"

WIFI_AP_ENABLE="${WIFI_AP_ENABLE:-1}"
WIFI_AP_SSID="${WIFI_AP_SSID:-${PI_HOSTNAME}-ap}"
PI_USER="${PI_USER:-pi}"

if [[ "$WIFI_AP_ENABLE" == "1" || "$WIFI_AP_ENABLE" == "true" || "$WIFI_AP_ENABLE" == "yes" ]]; then
  [[ -n "${WIFI_AP_PASSWORD:-}" ]] || die "WIFI_AP_PASSWORD unset (min 8 chars; used for the Pi access point)"
  ((${#WIFI_AP_PASSWORD} >= 8)) || die "WIFI_AP_PASSWORD must be at least 8 characters"
fi

[[ "$#" -ge 1 ]] || die "usage: $0 <script.sh> [script2.sh ...]"

for f in "$@"; do
  [[ -f "$HERE/$f" ]] || die "not found: $f"
done

{
  for f in "$@"; do
    cat "$HERE/$f"
    printf '\n\n'
  done
} | ssh "$PI_HOSTNAME" \
  env \
    "WIFI_AP_ENABLE=$(printf '%q' "$WIFI_AP_ENABLE")" \
    "WIFI_AP_SSID=$(printf '%q' "$WIFI_AP_SSID")" \
    "WIFI_AP_PASSWORD=$(printf '%q' "${WIFI_AP_PASSWORD:-}")" \
    "PI_USER=$(printf '%q' "$PI_USER")" \
    "PI_HOSTNAME=$(printf '%q' "$PI_HOSTNAME")" \
    bash -s
