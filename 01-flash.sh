#!/usr/bin/env bash
# 01-flash.sh — Download Raspberry Pi OS Lite (64-bit), verify checksum,
# flash to an SD card, and inject a reproducible firstboot config. macOS only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${HERE}/config.env"
TMPL="${HERE}/custom.toml.tmpl"
CACHE="${HERE}/.cache"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m ok\033[0m %s\n' "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS-only (uses diskutil)."
[[ -r "$CONFIG" ]] || die "missing $CONFIG — copy config.env.example and fill it in."
[[ -r "$TMPL"   ]] || die "missing $TMPL."

# shellcheck source=/dev/null
source "$CONFIG"

BOOT_AP="${WIFI_AP_BOOT_ONLY:-0}"
is_boot_ap() { [[ "$BOOT_AP" == "1" || "$BOOT_AP" == "true" || "$BOOT_AP" == "yes" ]]; }

if is_boot_ap; then
  for v in PI_HOSTNAME PI_USER SSH_PUBKEY_PATH WIFI_COUNTRY TIMEZONE KEYMAP IMG_URL IMG_SHA_URL; do
    [[ -n "${!v:-}" ]] || die "config.env missing $v"
  done
  APSSID="${WIFI_AP_SSID:-${PI_HOSTNAME}-ap}"
  [[ "$APSSID" =~ ^[A-Za-z0-9-]{1,32}$ ]] \
    || die "WIFI_AP_SSID (default \$PI_HOSTNAME-ap) must be ASCII letters, digits, or hyphen only for boot AP (got: $APSSID)"
  [[ -n "${WIFI_AP_PASSWORD:-}" ]] || die "WIFI_AP_BOOT_ONLY=1 requires WIFI_AP_PASSWORD (min 8 chars)"
  ((${#WIFI_AP_PASSWORD} >= 8)) || die "WIFI_AP_PASSWORD must be at least 8 characters"
else
  for v in PI_HOSTNAME PI_USER SSH_PUBKEY_PATH WIFI_SSID WIFI_PASSWORD WIFI_COUNTRY TIMEZONE KEYMAP IMG_URL IMG_SHA_URL; do
    [[ -n "${!v:-}" ]] || die "config.env missing $v"
  done
fi
[[ -r "$SSH_PUBKEY_PATH" ]] || die "SSH_PUBKEY_PATH not readable: $SSH_PUBKEY_PATH"

need() { command -v "$1" >/dev/null || die "missing tool: $1 (try: brew install $2)"; }
need curl curl
need shasum coreutils
need xz    xz
# prefer brew openssl (has sha512crypt); fall back via PATH only if it works with -6
if [[ -x /opt/homebrew/opt/openssl@3/bin/openssl ]]; then
  OPENSSL=/opt/homebrew/opt/openssl@3/bin/openssl
elif openssl passwd -6 _probe >/dev/null 2>&1; then
  OPENSSL=openssl
else
  die "need OpenSSL with -6 (sha512crypt). Run: brew install openssl@3"
fi
need python3 python
need diskutil ""

mkdir -p "$CACHE"
cd "$CACHE"

# ---------- 1. download + verify image ----------
info "fetching checksum manifest"
curl -fsSL -o img.sha256 "$IMG_SHA_URL"
EXPECTED_SHA="$(awk '{print $1}' img.sha256)"
EXPECTED_NAME="$(awk '{print $2}' img.sha256)"
EXPECTED_NAME="${EXPECTED_NAME#\*}"
[[ -n "$EXPECTED_SHA" && -n "$EXPECTED_NAME" ]] || die "could not parse checksum manifest"
info "target: $EXPECTED_NAME ($EXPECTED_SHA)"

if [[ -f "$EXPECTED_NAME" ]] && echo "$EXPECTED_SHA  $EXPECTED_NAME" | shasum -a 256 -c - >/dev/null 2>&1; then
  ok "image already present and verified"
else
  info "downloading image (~800MB)"
  curl -fL --progress-bar -o "$EXPECTED_NAME" "$IMG_URL"
  echo "$EXPECTED_SHA  $EXPECTED_NAME" | shasum -a 256 -c - || die "checksum mismatch"
  ok "image verified"
fi

IMG="${EXPECTED_NAME%.xz}"
if [[ ! -f "$IMG" ]]; then
  info "decompressing"
  xz -dk -- "$EXPECTED_NAME"
fi
ok "image ready: $IMG"

# ---------- 2. identify SD card ----------
info "external/physical disks:"
diskutil list external physical || true
echo
read -r -p "Enter target disk identifier (e.g. disk4, NOT disk4s1): " TARGET
[[ "$TARGET" =~ ^disk[0-9]+$ ]] || die "expected 'diskN' (no slice suffix)"
DEV="/dev/$TARGET"
RDEV="/dev/r$TARGET"

INFO_BLOB="$(diskutil info "$DEV")"
echo "$INFO_BLOB" | grep -qE 'Device Location:\s+External|Protocol:\s+(USB|SD|Secure Digital)' \
  || die "$DEV is not external. Refusing to flash."
SIZE_BYTES="$(echo "$INFO_BLOB" | awk -F'[()]' '/Disk Size/ {print $2; exit}' | awk '{print $1}')"
if [[ -n "$SIZE_BYTES" ]] && (( SIZE_BYTES >= 1000000000000 )); then
  die "$DEV is >=1TB. That's not an SD card. Aborting."
fi

echo
echo "About to ERASE and flash:"
echo "  $DEV"
echo "$INFO_BLOB" | grep -E 'Device / Media Name|Disk Size|Protocol|Device Location' | sed 's/^/    /'
read -r -p "Type 'ERASE $TARGET' to continue: " CONF
[[ "$CONF" == "ERASE $TARGET" ]] || die "aborted"

# ---------- 3. flash ----------
info "unmounting"
diskutil unmountDisk "$DEV"
info "writing image (sudo required)"
sudo dd if="$IMG" of="$RDEV" bs=4m status=progress
sync
ok "flashed"

# ---------- 4. render and install custom.toml ----------
info "waiting for bootfs to auto-mount"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -d /Volumes/bootfs ]] && break || sleep 1
done
[[ -d /Volumes/bootfs ]] || { diskutil mountDisk "$DEV"; sleep 2; }
[[ -d /Volumes/bootfs ]] || die "bootfs did not mount"

SSH_PUBKEY="$(tr -d '\n' < "$SSH_PUBKEY_PATH")"
RANDOM_PW="$("$OPENSSL" rand -base64 30 | tr -d '=+/' | cut -c1-40)"
CRYPT_PW="$("$OPENSSL" passwd -6 "$RANDOM_PW")"
echo "$RANDOM_PW" > "${HERE}/.last_password"
chmod 600 "${HERE}/.last_password"

export WIFI_AP_BOOT_ONLY="${WIFI_AP_BOOT_ONLY:-0}"
export SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH:-}"
export PI_HOSTNAME PI_USER CRYPT_PW SSH_PUBKEY WIFI_COUNTRY TIMEZONE KEYMAP
if is_boot_ap; then
  export WIFI_SSID="${WIFI_SSID:-unused}"
  export WIFI_PASSWORD="${WIFI_PASSWORD:-unused}"
else
  export WIFI_SSID WIFI_PASSWORD
fi

python3 - "$TMPL" /Volumes/bootfs/custom.toml <<'PYEOF'
import os, re, sys, json

tpl_path, out_path = sys.argv[1], sys.argv[2]
boot_ap = os.environ.get("WIFI_AP_BOOT_ONLY", "").lower() in ("1", "true", "yes")


def t(v):
    return json.dumps(v, ensure_ascii=False)


s = open(tpl_path, encoding="utf-8").read()
if boot_ap:
    s = re.sub(r"\n\[wlan\]\s*\n(?:.|\n)*?(?=\n\[locale\])", "\n", s)
    mapping = {
        "PI_HOSTNAME": os.environ["PI_HOSTNAME"],
        "PI_USER": os.environ["PI_USER"],
        "PI_PASSWORD_CRYPT": os.environ["CRYPT_PW"],
        "SSH_PUBKEY": os.environ["SSH_PUBKEY"],
        "TIMEZONE": os.environ["TIMEZONE"],
        "KEYMAP": os.environ["KEYMAP"],
    }
else:
    mapping = {
        "PI_HOSTNAME": os.environ["PI_HOSTNAME"],
        "PI_USER": os.environ["PI_USER"],
        "PI_PASSWORD_CRYPT": os.environ["CRYPT_PW"],
        "SSH_PUBKEY": os.environ["SSH_PUBKEY"],
        "WIFI_SSID": os.environ["WIFI_SSID"],
        "WIFI_PASSWORD": os.environ["WIFI_PASSWORD"],
        "WIFI_COUNTRY": os.environ["WIFI_COUNTRY"],
        "TIMEZONE": os.environ["TIMEZONE"],
        "KEYMAP": os.environ["KEYMAP"],
    }
for k, v in mapping.items():
    s = s.replace(f'"__{k}__"', t(v))
pwauth = os.environ.get("SSH_PASSWORD_AUTH", "").lower() in ("1", "true", "yes")
s = s.replace("__SSH_PASSWORD_AUTH__", "true" if pwauth else "false")
open(out_path, "w", encoding="utf-8").write(s)
PYEOF
chmod 600 /Volumes/bootfs/custom.toml
ok "custom.toml written"
if [[ "${SSH_PASSWORD_AUTH:-}" == "1" || "${SSH_PASSWORD_AUTH:-}" == "true" || "${SSH_PASSWORD_AUTH:-}" == "yes" ]]; then
  info "SSH password auth ON for first boot — use: cat ${HERE}/.last_password   (run ./03-bootstrap.sh later to lock sshd again)"
fi

: > /Volumes/bootfs/ssh

if is_boot_ap; then
  info "WIFI_AP_BOOT_ONLY: staging NetworkManager AP for second boot (no infra Wi-Fi in custom.toml)"
  BOOTROOT="/Volumes/bootfs"
  [[ -d "$BOOTROOT" ]] || die "boot volume missing"
  CMDLINE=""
  for p in "$BOOTROOT/cmdline.txt" "$BOOTROOT/firmware/cmdline.txt"; do
    [[ -f "$p" ]] && CMDLINE="$p" && break
  done
  [[ -n "$CMDLINE" ]] || die "cmdline.txt not found on boot volume"
  APSSID="${WIFI_AP_SSID:-${PI_HOSTNAME}-ap}"
  export APSSID WIFI_AP_PASSWORD
  python3 - <<'PY'
import hashlib
import os
import pathlib
import uuid

root = pathlib.Path("/Volumes/bootfs")
ssid = os.environ["APSSID"]
pw = os.environ["WIFI_AP_PASSWORD"]
psk = hashlib.pbkdf2_hmac(
    "sha1", pw.encode("utf-8"), ssid.encode("utf-8"), 4096, 32
).hex()
uid = str(uuid.uuid4())
text = f"""[connection]
id=pi5-setup-ap
uuid={uid}
type=wifi
autoconnect=true
interface-name=wlan0

[wifi]
mode=ap
ssid={ssid}

[wifi-security]
key-mgmt=wpa-psk
psk={psk}

[ipv4]
method=shared

[ipv6]
method=ignore
"""
(root / "pi5-hotspot.nmconnection").write_text(text, encoding="utf-8")
PY
  printf '%s' "$WIFI_COUNTRY" > "$BOOTROOT/pi5-ap-country"
  cp "${HERE}/templates/boot-ap-install.sh" "$BOOTROOT/pi5-boot-install-ap.sh"
  chmod 0755 "$BOOTROOT/pi5-boot-install-ap.sh"
  marker="pi5-boot-install-ap.sh"
  python3 - "$CMDLINE" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
c = p.read_text(encoding="utf-8", errors="replace").strip().replace("\n", " ")
if "pi5-boot-install-ap.sh" not in c:
    # Single path (shebang in script). Do not use "/bin/bash /path" — strip_cmdline and
    # kernel cmdline parsing treat spaces poorly and can corrupt cmdline.txt.
    c += (
        " systemd.run=/boot/firmware/pi5-boot-install-ap.sh"
        " systemd.run_success_action=none"
        " systemd.run_failure_action=reboot"
        " systemd.unit=kernel-command-line.target"
    )
p.write_text(c + "\n", encoding="utf-8")
PY
  ok "boot AP staged (join SSID «${APSSID}» after ~2 min: first boot expands FS + custom.toml, reboot, second boot starts AP)"
fi

info "ejecting"
diskutil eject "$DEV"
ok "done. Insert the card into the Pi and power on."
echo
if is_boot_ap; then
  echo "Rescue AP: after first automatic reboot, join Wi-Fi «${APSSID}» (WIFI_AP_PASSWORD), then: ssh ${PI_USER}@10.42.0.1"
else
  echo "Next: ./02-connect.sh"
fi
