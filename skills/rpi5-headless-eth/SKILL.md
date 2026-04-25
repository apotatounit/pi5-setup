---
name: rpi5-headless-eth
description: Flash and configure a Raspberry Pi 5 for headless ethernet-only SSH access from macOS. Use this skill whenever the user wants to set up a Raspberry Pi headlessly, flash an SD card for a Pi, configure SSH access to a Pi, set a static IP on a Pi, or automate Pi first-boot configuration. Triggers on: "flash SD card", "headless Pi", "SSH into Pi", "Raspberry Pi setup", "Pi ethernet", "Pi static IP".
---

# RPi5 Headless Ethernet Setup

Flash Raspberry Pi OS Lite (64-bit) for headless SSH-only access over ethernet.
No WiFi, no monitor required after first boot. macOS only.

## What works (verified on RPi OS Bookworm, April 2026)

### User creation: `userconf.txt` (not custom.toml, not firstrun.sh chpasswd)

Fresh Bookworm images have **no uid-1000 user**. These approaches fail silently:
- `custom.toml` — not processed by this OS build; falls back to interactive wizard
- `imager_custom set_user` — command not supported in this version of imager_custom
- `chpasswd -e` in firstrun.sh — fails because the target user doesn't exist yet

**What works:** `/boot/firmware/userconf.txt` with content `username:$6$hashed_password`
The `userconf-pi.service` reads this file and creates the user reliably.

### SSH key injection: `firstrun.sh` via `systemd.run`

After userconf creates the user, use `firstrun.sh` to inject the authorized key.
`firstrun.sh` must be a separate concern from user creation.

### `imager_custom` supported commands (this OS version)

Only these work:
- `set_hostname HOSTNAME`
- `enable_ssh [-k|--key-only] [-p|--pubkey KEY]`
- `set_wlan ...`
- `set_keymap KEYMAP`
- `set_timezone TIMEZONE`

**Missing:** `set_user`, `set_ssh_pubkey` — do NOT use, they print usage and exit 0.

### `cmdline.txt` patching — critical gotchas

When using `systemd.run` in cmdline.txt, you MUST set `systemd.run_success_action=reboot`.
Setting it to `none` leaves the Pi hung at `kernel-command-line.target` forever.

The cleanup `sed` in `firstrun.sh` must remove BOTH:
- `systemd.run*` entries
- `systemd.unit=kernel-command-line.target` (different prefix, easy to miss)

```bash
sed -i "s| systemd\.run[^ ]*||g" /boot/firmware/cmdline.txt
sed -i "s| systemd\.unit=[^ ]*||g" /boot/firmware/cmdline.txt
```

### Shell heredocs and password hashes — never mix

The `$6$salt$hash` format contains literal `$` characters.
**Never** interpolate `$CRYPT_PW` inside an unquoted heredoc (`<<EOF`) or a bash string.

Always use a **quoted heredoc** (`<<'EOF'`) and pass values via **exported env vars**.
Use `shlex.quote()` in Python to produce safe bash-quoted strings.

```bash
export CRYPT_PW="$(...)"
python3 <<'PY'
import os, shlex
q = shlex.quote
pw = q(os.environ['CRYPT_PW'])   # produces '$6$salt$hash' — safe in bash
PY
```

## Working flash flow

```
01-flash-eth.sh (macOS)
  ├── Download + verify RPi OS Lite arm64
  ├── Flash to SD card (dd via diskutil)
  ├── Mount /Volumes/bootfs
  ├── Write userconf.txt        → user creation on first boot
  ├── Write firstrun.sh         → SSH key + hostname + locale
  ├── Patch cmdline.txt         → systemd.run + reboot actions
  ├── touch ssh                 → enable SSH service
  └── Eject

First boot sequence:
  1. systemd boots to kernel-command-line.target
  2. firstrun.sh runs (sets hostname, SSH key, locale)
  3. systemd.run_success_action=reboot → Pi reboots
  4. Second boot: normal, userconf-pi.service creates user
  5. SSH available via DHCP IP or hostname.local
```

## Static IP

Set AFTER first SSH login — never in the image. Use nmcli:

```bash
# Run ON THE PI
CON=$(nmcli -t -f NAME,TYPE connection show --active | grep ':ethernet' | head -1 | cut -d: -f1)
sudo nmcli connection modify "$CON" \
  ipv4.method manual \
  ipv4.addresses 192.168.100.91/24 \
  ipv4.gateway  192.168.100.1 \
  ipv4.dns      "192.168.100.1,8.8.8.8" \
  ipv6.method   disabled
sudo nmcli connection down "$CON" && sudo nmcli connection up "$CON" &
```

SSH session drops. Reconnect via the static IP.

## mDNS / .local hostname

Works on home networks. **Often blocked on office/managed networks.**
Fallback: check router DHCP table, or `nmap -sn 192.168.100.0/24`.

## Files in this project

| File | Purpose |
|------|---------|
| `01-flash-eth.sh` | Main flash script (macOS) |
| `02-set-static-ip.sh` | Run on Pi to set static IP |
| `config-eth.env` | User config: hostname, user, SSH key path, IP |
| `.last_password` | Generated password (chmod 600, gitignored) |

## OpenSSL note

macOS system OpenSSL lacks `-6` (sha512crypt). Require Homebrew:
```bash
brew install openssl@3
# Script auto-detects at /opt/homebrew/opt/openssl@3/bin/openssl
```
