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
make bootstrap   # idempotent Pi-side setup: hardening + pyenv/uv + Docker
make audit       # read-only check: passes/fails every invariant
```

Or in one go once the card is flashed and booted:

```bash
make all
```

## What each script does

| File | Runs on | Purpose |
|---|---|---|
| `config.env` | Mac | Your inputs. Never commit. |
| `custom.toml.tmpl` | Mac | Firstboot template — rendered into `/boot/firmware/custom.toml`. |
| `01-flash.sh` | Mac | Download + SHA256 verify image, identify SD card (refuses non-removable and ≥1TB devices), flash, inject rendered `custom.toml`, eject. |
| `02-connect.sh` | Mac | Wait for `<host>.local`, prime `known_hosts`, idempotently update `~/.ssh/config` with a block-delimited entry for this Pi. |
| `03-bootstrap.sh` | Pi | `apt` base, sshd hardening drop-in, UFW, fail2ban, unattended-upgrades, pyenv + uv + pipx, Docker CE + compose plugin. Every stanza state-checks before acting. |
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
