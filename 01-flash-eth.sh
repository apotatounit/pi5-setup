#!/usr/bin/env bash
# 01-flash-eth.sh — RPi OS Lite, ethernet DHCP, SSH key.
# Uses firstrun.sh — same mechanism as the official Raspberry Pi Imager.
# macOS only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${HERE}/config-eth.env"
CACHE="${HERE}/.cache"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m ok \033[0m %s\n' "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
[[ -r "$CONFIG" ]] || die "missing $CONFIG"
# shellcheck source=/dev/null
source "$CONFIG"

for v in PI_HOSTNAME PI_USER SSH_PUBKEY_PATH TIMEZONE KEYMAP IMG_URL IMG_SHA_URL; do
  [[ -n "${!v:-}" ]] || die "config-eth.env missing: $v"
done
[[ -r "$SSH_PUBKEY_PATH" ]] || die "SSH_PUBKEY_PATH not readable: $SSH_PUBKEY_PATH"

need() { command -v "$1" >/dev/null || die "missing: $1  (brew install $2)"; }
need curl    curl
need shasum  coreutils
need xz      xz
need python3 python

if [[ -x /opt/homebrew/opt/openssl@3/bin/openssl ]]; then
  OPENSSL=/opt/homebrew/opt/openssl@3/bin/openssl
elif openssl passwd -6 _probe >/dev/null 2>&1; then
  OPENSSL=openssl
else
  die "need OpenSSL with -6: brew install openssl@3"
fi

mkdir -p "$CACHE"
cd "$CACHE"

# ── 1. Download + verify ─────────────────────────────────────────────────────
info "fetching checksum manifest"
curl -fsSL -o img.sha256 "$IMG_SHA_URL"
EXPECTED_SHA="$(awk '{print $1}' img.sha256)"
EXPECTED_NAME="$(awk '{print $2}' img.sha256 | sed 's/^\*//')"
[[ -n "$EXPECTED_SHA" && -n "$EXPECTED_NAME" ]] || die "could not parse manifest"
info "image: $EXPECTED_NAME"

if [[ -f "$EXPECTED_NAME" ]] && echo "$EXPECTED_SHA  $EXPECTED_NAME" | shasum -a 256 -c - >/dev/null 2>&1; then
  ok "already downloaded and verified — skipping"
else
  info "downloading (~800 MB)"
  curl -fL --progress-bar -o "$EXPECTED_NAME" "$IMG_URL"
  echo "$EXPECTED_SHA  $EXPECTED_NAME" | shasum -a 256 -c - || die "checksum mismatch"
  ok "verified"
fi

IMG="${EXPECTED_NAME%.xz}"
if [[ ! -f "$IMG" ]]; then
  info "decompressing"
  xz -dk -- "$EXPECTED_NAME"
fi
ok "image ready: $IMG"

# ── 2. Pick SD card ──────────────────────────────────────────────────────────
info "external/physical disks:"
diskutil list external physical || true
echo
read -r -p "Enter target disk (e.g. disk4, NOT disk4s1): " TARGET
[[ "$TARGET" =~ ^disk[0-9]+$ ]] || die "expected diskN"
DEV="/dev/$TARGET"; RDEV="/dev/r$TARGET"

INFO_BLOB="$(diskutil info "$DEV")"
echo "$INFO_BLOB" | grep -qE 'Device Location:\s+External|Protocol:\s+(USB|SD|Secure Digital)' \
  || die "$DEV is not external — refusing"
SIZE_BYTES="$(echo "$INFO_BLOB" | awk -F'[()]' '/Disk Size/{print $2;exit}' | awk '{print $1}')"
[[ -z "$SIZE_BYTES" ]] || (( SIZE_BYTES < 1000000000000 )) || die ">=1TB — not an SD card"

echo
echo "  Target: $DEV"
echo "$INFO_BLOB" | grep -E 'Device / Media Name|Disk Size|Protocol|Device Location' | sed 's/^/    /'
echo
read -r -p "  Type 'ERASE $TARGET' to continue: " CONF
[[ "$CONF" == "ERASE $TARGET" ]] || die "aborted"

# ── 3. Flash ─────────────────────────────────────────────────────────────────
info "unmounting"
diskutil unmountDisk "$DEV"
info "flashing (sudo required)"
sudo dd if="$IMG" of="$RDEV" bs=4m status=progress
sync
ok "flashed"

# ── 4. Mount bootfs ──────────────────────────────────────────────────────────
info "waiting for bootfs"
for _ in $(seq 1 15); do [[ -d /Volumes/bootfs ]] && break || sleep 1; done
if [[ ! -d /Volumes/bootfs ]]; then diskutil mountDisk "$DEV"; sleep 3; fi
[[ -d /Volumes/bootfs ]] || die "bootfs didn't mount — try: diskutil mountDisk $DEV"
BOOT=/Volumes/bootfs

# ── 5. Credentials ───────────────────────────────────────────────────────────
SSH_PUBKEY="$(tr -d '\n' < "$SSH_PUBKEY_PATH")"
RANDOM_PW="$("$OPENSSL" rand -base64 30 | tr -d '=+/' | cut -c1-20)"
CRYPT_PW="$("$OPENSSL" passwd -6 "$RANDOM_PW")"
printf '%s\n' "$RANDOM_PW" > "${HERE}/.last_password"
chmod 600 "${HERE}/.last_password"

# ── 6. Write firstrun.sh ─────────────────────────────────────────────────────
# All values passed via env vars. Quoted heredoc (<<'PY') so the shell never
# touches dollar signs or backticks inside. shlex.quote() handles bash escaping.
info "writing firstrun.sh"

export PI_HOSTNAME PI_USER CRYPT_PW SSH_PUBKEY TIMEZONE KEYMAP
export OUT_PATH="$BOOT/firstrun.sh"

python3 <<'PY'
import os, shlex

h        = os.environ['PI_HOSTNAME']
user     = os.environ['PI_USER']
crypt_pw = os.environ['CRYPT_PW']
ssh_key  = os.environ['SSH_PUBKEY']
tz       = os.environ['TIMEZONE']
keymap   = os.environ['KEYMAP']
out      = os.environ['OUT_PATH']

q = shlex.quote   # safe single-quoted bash strings

lines = [
    '#!/bin/bash',
    '# firstrun.sh — written by 01-flash-eth.sh',
    '# Runs once on first boot as root, then removes itself.',
    '# No imager_custom — direct commands only.',
    'set +e',
    '',
    '# ── hostname ────────────────────────────────────────────────────────────',
    'OLD=$(cat /etc/hostname | tr -d " \\t\\n\\r")',
    'echo ' + q(h) + ' > /etc/hostname',
    'sed -i "s/127\\.0\\.1\\.1.*$OLD/127.0.1.1\\t' + h + '/g" /etc/hosts',
    '',
    '# User is created by userconf-pi.service reading /boot/firmware/userconf.txt.',
    '# We just need to find the uid-1000 user after it exists and inject the SSH key.',
    'FIRSTUSER=$(getent passwd 1000 | cut -d: -f1)',
    'FIRSTUSERHOME=$(getent passwd 1000 | cut -d: -f6)',
    '',
    '# ── SSH ─────────────────────────────────────────────────────────────────',
    'systemctl enable ssh',
    'mkdir -p "$FIRSTUSERHOME/.ssh"',
    'echo ' + q(ssh_key) + ' > "$FIRSTUSERHOME/.ssh/authorized_keys"',
    'chmod 700 "$FIRSTUSERHOME/.ssh"',
    'chmod 600 "$FIRSTUSERHOME/.ssh/authorized_keys"',
    'chown -R "$FIRSTUSER:$FIRSTUSER" "$FIRSTUSERHOME/.ssh"',
    '',
    '# ── locale / timezone ───────────────────────────────────────────────────',
    'rm -f /etc/localtime',
    'echo ' + q(tz) + ' > /etc/timezone',
    'dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true',
    '',
    '# ── clean up ────────────────────────────────────────────────────────────',
    'rm -f /boot/firmware/firstrun.sh',
    '# Remove ALL systemd.run* and systemd.unit= params we added',
    'sed -i "s| systemd\\.run[^ ]*||g" /boot/firmware/cmdline.txt',
    'sed -i "s| systemd\\.unit=[^ ]*||g" /boot/firmware/cmdline.txt',
    'exit 0',
    '',
]

with open(out, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))

print('  wrote', out)
PY

chmod 755 "$BOOT/firstrun.sh"
ok "firstrun.sh written"

# Sanity-check: print it so you can eyeball it
echo "──── firstrun.sh preview ────────────────────────────────"
cat "$BOOT/firstrun.sh"
echo "─────────────────────────────────────────────────────────"

# ── 7. Write userconf.txt — dedicated Bookworm user-creation mechanism ───────
# This is read by userconf-pi.service and is more reliable than chpasswd
# on a fresh image where no uid-1000 user may exist yet.
# firstrun.sh now only handles SSH key + hostname + locale.
info "writing userconf.txt"
printf '%s:%s\n' "$PI_USER" "$CRYPT_PW" > "$BOOT/userconf.txt"
ok "userconf.txt written ($(cat "$BOOT/userconf.txt" | cut -d: -f1):...)"

rm -f "$BOOT/custom.toml" 2>/dev/null || true

# ── 8. Enable SSH + patch cmdline.txt ────────────────────────────────────────
: > "$BOOT/ssh"

CMDLINE=""
for p in "$BOOT/cmdline.txt" "$BOOT/firmware/cmdline.txt"; do
  [[ -f "$p" ]] && CMDLINE="$p" && break
done
[[ -n "$CMDLINE" ]] || die "cmdline.txt not found on bootfs"

info "patching cmdline.txt"
python3 - "$CMDLINE" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
c = p.read_text(encoding='utf-8', errors='replace').strip()
tag = 'systemd.run=/boot/firmware/firstrun.sh'
if tag not in c:
    c = (c
         + ' ' + tag
         + ' systemd.run_success_action=reboot'
         + ' systemd.run_failure_action=reboot'
         + ' systemd.unit=kernel-command-line.target')
p.write_text(c + '\n', encoding='utf-8')
print('  cmdline:', c)
PY
ok "cmdline.txt patched"

# ── 9. Eject ─────────────────────────────────────────────────────────────────
info "ejecting"
diskutil eject "$DEV"
ok "done"

PW="$(cat "${HERE}/.last_password")"
cat <<MSG

════════════════════════════════════════════════════════════
  SD card ready. Insert into Pi 5, plug ethernet, power on.

  First boot: ~60–90 s. Screen shows login prompt when done.

  SSH in (no IP needed — mDNS):
    ssh ${PI_USER}@${PI_HOSTNAME}.local

  Password (if key fails): ${PW}
  Saved to: ${HERE}/.last_password

  Then lock in the static IP (run ON the Pi):
    bash 02-set-static-ip.sh
════════════════════════════════════════════════════════════
MSG
