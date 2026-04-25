#!/bin/bash
# Diag: join lab-pi5-ap, run verbose SSH probe, capture log, rejoin prior Wi-Fi.
# Your Mac will be offline from Anthropic for ~60-90s while this runs.
# Usage:  bash ./diag-ap.sh
# Output: /tmp/ssh_diag.log  (readable after you're back online)

set -uo pipefail

AP_SSID="lab-pi5-ap"
AP_PSK="chocolate8"
PI_IP="10.42.0.1"
PI_USER="pi"
KEY="$HOME/.ssh/id_ed25519"
IF=en0
LOG=/tmp/ssh_diag.log

log() { printf '[%s] %s\n' "$(date +%T)" "$*" | tee -a "$LOG"; }

: > "$LOG"
log "Mac baseline ============================================="
networksetup -getairportnetwork "$IF" 2>&1 | tee -a "$LOG"
ipconfig getifaddr "$IF" 2>&1 | tee -a "$LOG"
route -n get default 2>&1 | awk '/interface|gateway/' | tee -a "$LOG"

log "Joining $AP_SSID ============================================="
networksetup -setairportnetwork "$IF" "$AP_SSID" "$AP_PSK" 2>&1 | tee -a "$LOG"

log "Waiting up to 25s for 10.42.0.x DHCP lease..."
GOT_IP=""
for i in $(seq 1 25); do
  ip=$(ipconfig getifaddr "$IF" 2>/dev/null || true)
  ssid=$(networksetup -getairportnetwork "$IF" 2>/dev/null | awk -F": " '{print $2}')
  if [[ "$ssid" == "$AP_SSID" && "$ip" == 10.42.* ]]; then
    GOT_IP="$ip"
    log "Associated to $ssid, IP=$ip (after ${i}s)"
    break
  fi
  sleep 1
done
if [[ -z "$GOT_IP" ]]; then
  log "NEVER got 10.42.0.x lease. Current:"
  networksetup -getairportnetwork "$IF" 2>&1 | tee -a "$LOG"
  ipconfig getifaddr "$IF" 2>&1 | tee -a "$LOG"
fi

log "ping / arp ============================================="
ping -c 3 -W 1500 "$PI_IP" 2>&1 | tee -a "$LOG"
arp -n "$PI_IP" 2>&1 | tee -a "$LOG"

log "TCP 22 reachability ============================================="
# /dev/tcp is a bash built-in: opens a socket without needing nc
(echo > /dev/tcp/"$PI_IP"/22) >>"$LOG" 2>&1 && log "port 22 OPEN" || log "port 22 BLOCKED/closed"

log "Methods sshd advertises (none-auth probe) ============================"
ssh -v -o BatchMode=yes -o ConnectTimeout=6 \
    -o PreferredAuthentications=none \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${PI_USER}@${PI_IP}" true >>"$LOG" 2>&1 || true

log "Public-key auth probe (expect success) ============================="
ssh -vvv -o BatchMode=yes -o ConnectTimeout=6 \
    -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes -i "$KEY" \
    "${PI_USER}@${PI_IP}" \
    'echo OK_KEY; id; hostname; uname -a; head -3 /etc/os-release' >>"$LOG" 2>&1
KEY_RC=$?
log "key-auth exit: $KEY_RC"

log "Leaving AP & restoring prior Wi-Fi ============================="
# Cycle the radio so macOS picks your remembered home network back up.
networksetup -setairportpower "$IF" off 2>&1 | tee -a "$LOG"
sleep 2
networksetup -setairportpower "$IF" on 2>&1 | tee -a "$LOG"

log "Waiting up to 20s for home Wi-Fi to come back..."
for i in $(seq 1 20); do
  ssid=$(networksetup -getairportnetwork "$IF" 2>/dev/null | awk -F": " '{print $2}')
  ip=$(ipconfig getifaddr "$IF" 2>/dev/null || true)
  if [[ -n "$ssid" && "$ssid" != "$AP_SSID" && -n "$ip" && "$ip" != 10.42.* ]]; then
    log "Back on $ssid, IP=$ip"
    break
  fi
  sleep 1
done

log "Done. Full log: $LOG"
echo
echo "Next: tell Claude 'diag done' — I'll read /tmp/ssh_diag.log and plan the fix."
