# pi5-setup

Reproducible, idempotent setup for a Raspberry Pi 5 running Raspberry Pi OS Lite
(64-bit), flashed from macOS, headless over Wi-Fi, SSH-key only.

## One-time on the Mac

```bash
brew install coreutils xz openssl@3
cp config.env.example config.env
$EDITOR config.env            # fill in hostname, user, Wi-Fi, key path, timezone
```

Generate a key if you don't have one:

```bash
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

## Run it

```bash
make flash       # downloads + verifies image, prompts for SD target, flashes,
                 # drops custom.toml into /boot/firmware for firstboot
# --- move card to Pi, power on, wait ~90s ---
make connect     # resolves <hostname>.local, writes ~/.ssh/config entry
make bootstrap   # Pi-side setup + optional Wi-Fi AP (see WIFI_AP_* in config.env)
make wifi-ap     # only (re)configure the Pi as a Wi-Fi hotspot you can join
make audit       # read-only check: passes/fails every invariant
```

Set `WIFI_AP_PASSWORD` (≥8 characters) and optional `WIFI_AP_SSID` / `WIFI_AP_ENABLE` in `config.env`. The first `make wifi-ap` or `make bootstrap` still needs **some way to SSH into the Pi once** (Ethernet, USB‑gadget/serial, or working infra Wi‑Fi). After that, join the Pi’s AP (default SSID `<hostname>-ap`) and SSH to the printed address — often `10.42.0.1`.

### No Ethernet and you cannot see the Pi on the network

1. **`WIFI_AP_BOOT_ONLY=1` in `config.env`** — `make flash` then skips `[wlan]` in `custom.toml` and stages a **NetworkManager hotspot** on the boot partition. The Pi still does the normal **first-boot** (`init=` resize + `custom.toml` for user/SSH). After that reboot, **second boot** runs a one-shot installer from `cmdline.txt`, copies a hotspot profile, starts it, and strips the `systemd.run=` line. On your phone, join **`${PI_HOSTNAME}-ap`** (or `WIFI_AP_SSID` if set) with **`WIFI_AP_PASSWORD`**, then **`ssh <user>@10.42.0.1`**. The AP SSID must be ASCII letters, digits, or hyphen only (default fits). Expect **one automatic reboot** after first boot (~2–5 minutes); the AP usually appears only after that **second** boot. The **green activity LED** often goes mostly **off when the CPU/SD are idle**; that does not by itself mean Wi‑Fi failed. If no AP appears, pull the SD, open **`cmdline.txt`** on the boot volume on your Mac: if you see a **orphaned** fragment like `/boot/firmware/pi5-boot-install-ap.sh` **without** `systemd.run=` in front, the old flash script left a broken cmdline — **`git pull`**, re-run **`make flash`**, and try again (the strip logic and `systemd.run=` path are fixed in repo).
2. **USB‑serial to GPIO** (3.3 V): connect GND, **GPIO15 (RXD0)** to adapter **TX**, **GPIO14 (TXD0)** to adapter **RX**, enable serial in Raspberry Pi Imager or use a monitor once — then you can log in and fix Wi‑Fi even if the rescue AP path fails.

Or in one go once the card is flashed and booted:

```bash
make all
```

## What each script does

| File | Runs on | Purpose |
|---|---|---|
| `config.env` | Mac | Your inputs. Never commit. |
| `custom.toml.tmpl` | Mac | Firstboot template — rendered into `/boot/firmware/custom.toml`. |
| `01-flash.sh` | Mac | Download + SHA256 verify image, identify SD card (refuses non-removable and ≥1TB devices), flash, inject rendered `custom.toml`, optional **boot-only rescue AP** (`WIFI_AP_BOOT_ONLY`), eject. |
| `templates/boot-ap-install.sh` | Mac → bootfs | Consumed on the Pi’s **second** boot when `WIFI_AP_BOOT_ONLY=1`; installs `pi5-hotspot.nmconnection` and removes the extra `cmdline.txt` flags. |
| `02-connect.sh` | Mac | Wait for `<host>.local`, prime `known_hosts`, idempotently update `~/.ssh/config` with a block-delimited entry for this Pi. |
| `03-bootstrap.sh` | Pi | `apt` base, sshd hardening drop-in, UFW, fail2ban, unattended-upgrades, pyenv + uv + pipx, Docker CE + compose plugin. Every stanza state-checks before acting. |
| `05-wifi-ap.sh` | Pi | Optional NetworkManager hotspot (`nmcli device wifi hotspot`): join the Pi’s SSID, SSH to its gateway IP (often `10.42.0.1`). Wired over `make bootstrap` / `make wifi-ap`. |
| `04-audit.sh` | Pi | Read-only posture check. Exits non-zero on any failure. |
| `Makefile` | Mac | Orchestration. |

## Safety model

- `01-flash.sh` will refuse to touch a disk that is not external, and any disk ≥1TB. It requires the user to type `ERASE diskN` verbatim.
- `custom.toml` is written mode 600. The plaintext Wi-Fi password never leaves the bootfs after firstboot consumes and deletes it.
- SSH is key-only from first boot; password auth is disabled both in `custom.toml` and reinforced by `sshd_config.d/10-hardening.conf`.
- The user password in `custom.toml` is random per flash (base64, 40 chars), stored in `.last_password` on the Mac only, and written to `/etc/shadow` as SHA-512. You never need it unless you plug in a keyboard and monitor.

## Reproducing from scratch

The checked-in files plus `config.env` are the full recipe. Re-running any
script is safe:
- `flash` re-prompts for the target and re-uses the cached, verified image.
- `connect` replaces its managed block in `~/.ssh/config` (markers: `# >>> pi5-setup:<host> >>>`).
- `bootstrap` is idempotent stanza by stanza.
- `audit` is read-only.

## What I can't automate for you

- Physically inserting the SD card into the Mac, and then into the Pi.
- Power.
- Confirming the `ERASE diskN` prompt — this is intentional, so a broken script
  can't silently destroy data.

Everything else is scripted.
