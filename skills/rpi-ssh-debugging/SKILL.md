---
name: rpi-ssh-debugging
description: >-
  Connects to a Raspberry Pi over SSH for remote debugging: host discovery
  (mDNS vs static IP), ssh config, non-interactive checks, persistent tmux
  sessions, port forwarding, and common failures. Use when the user wants to
  SSH into a Pi, debug headless, remote shell, lab-pi5, Raspberry Pi 5, or pair
  SSH with on-Pi serial or tooling without a monitor.
---

# SSH to Raspberry Pi for debugging

## Scope

This skill covers **getting and keeping a reliable SSH session** to a Pi and **running debug commands remotely**. For **serial through the Pi to a device**, use [rpi-serial-agent-dev](../rpi-serial-agent-dev/SKILL.md). For **SD image, keys, and static IP on first boot**, use [rpi5-headless-eth](../rpi5-headless-eth/SKILL.md).

## Resolve the host

| Method | Example | Notes |
|--------|---------|--------|
| mDNS | `ssh pi@lab-pi5.local` | Often fails on **managed / office** Wi‑Fi; Ethernet is more predictable. |
| Static IP | `ssh pi@192.168.100.91` | After `02-set-static-ip.sh` (see rpi5-headless-eth). |
| `~/.ssh/config` **Host** | `ssh lab-pi5` | pi5-setup `02-connect.sh` writes a block with `HostName`, `User`, `IdentityFile`, `ServerAliveInterval 30`. |

If **`Could not resolve hostname`**: fix Pi **network** (correct Wi‑Fi country / rfkill, cable, DHCP) before chasing SSH.

## First connection and keys

- **Host key changed** after re-flash: `ssh-keygen -R lab-pi5.local` (and `-R` the IP if used).
- **Non-interactive probe:** `ssh -o BatchMode=yes -o ConnectTimeout=10 pi@HOST 'echo ok'` — use for CI/agents; requires key auth.
- **Tip:** `ServerAliveInterval 30` in config reduces drops on flaky Wi‑Fi.

## Agent-friendly patterns

1. **One-shot command:** `ssh user@HOST 'command'` — good for `uname -a`, `dmesg | tail`, `journalctl -u servicename -n 50 --no-pager`.
2. **Long logs / REPL:** start **`tmux new -s dbg`** on the Pi, attach with `ssh -t user@HOST tmux attach -t dbg` so disconnects do not kill work.
3. **Copy logs off Pi:** `scp user@HOST:~/serial.log .` or `rsync -az user@HOST:path/ ./local/`.
4. **Forward a Pi-local service to the laptop:** `ssh -L 8080:127.0.0.1:8080 user@HOST` then open `http://localhost:8080` on the dev machine.

## Debugging checklist

```
- [ ] Ping or resolve host (mDNS vs static IP).
- [ ] SSH with key; fix known_hosts if re-imaged.
- [ ] On Pi: `groups` includes dialout if using USB serial tools.
- [ ] Heavy work in tmux; capture output to a file when reporting failures.
```

## Common failures

- **`Permission denied (publickey)`:** wrong user (`pi` vs custom), missing key on Pi `~/.ssh/authorized_keys`, or wrong `IdentityFile` in config.
- **`Connection timed out`:** wrong IP, Pi off-network, or firewall between subnets.
- **`Wi-Fi is currently blocked by rfkill`:** set regulatory domain / enable Wi‑Fi (`raspi-config` locality) — Ethernet may still work.

## Optional: pi5-setup helpers

From the **pi5-setup** repo root (macOS): `02-connect.sh` discovers **`${PI_HOSTNAME}.local`**, updates **`~/.ssh/config`**, and tests SSH using **`config.env`**. Use that project’s `config-eth.env` / scripts when the Pi was flashed with those conventions.
