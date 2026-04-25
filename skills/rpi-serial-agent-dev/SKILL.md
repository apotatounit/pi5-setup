---
name: rpi-serial-agent-dev
description: >-
  Develops, flashes, and debugs firmware on a device reached through a Raspberry
  Pi serial port while the agent uses SSH only (no physical console). Covers
  discovering TTY devices, non-interactive serial capture, tmux persistence,
  optional port forwarding, and safe iteration loops. Use when the user mentions
  agentic development, SSH to Pi, serial console, MCU over UART, minicom/picocom,
  /dev/ttyUSB, deploy through Raspberry Pi, or remote serial logging.
---

# Agentic dev: SSH → Raspberry Pi → serial device

## Scope

The agent runs on a **developer machine** and executes commands **over SSH on the Pi**, which is **cabled to the target** (USB-serial adapter, UART header, or onboard USB CDC). The Pi is a **serial bridge and build/flash host**, not a substitute for SWD unless the user explicitly adds that workflow.

**Pi bring-up (image, SSH keys, static IP):** use the sibling skill [rpi5-headless-eth](../rpi5-headless-eth/SKILL.md) first.

## Topology

```
[Agent / dev machine] --SSH--> [Raspberry Pi] --serial--> [MCU or module]
```

## Operating principles for agents

1. **Assume SSH works** (`ssh <Host>` from `~/.ssh/config`, or `user@host`). Prefer **non-interactive** flags (`ssh -o BatchMode=yes` for checks; omit for long sessions if keys are loaded).
2. **Never require a local USB serial device** on the dev machine unless the user asks; the canonical TTY is **on the Pi**.
3. **Long-running reads** (firmware logs, boot traces): run inside **`tmux` or `screen`** on the Pi so disconnects do not kill the capture.
4. **One source of truth for the serial device**: discover on the Pi each session if adapters move; avoid hardcoding `/dev/ttyUSB0` in docs without verification.

## Discover the serial device (on the Pi)

Run over SSH:

```bash
ls -l /dev/serial/by-id/ 2>/dev/null || true
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true
```

Stable paths: prefer **`/dev/serial/by-id/...`** in scripts. If only `ttyUSBn` exists, note the index can change after reboot.

**Permissions:** user must be in group **`dialout`** on the Pi:

```bash
groups
sudo usermod -aG dialout "$USER"
# then re-login or newgrp dialout
```

## Interactive terminal (human or quick probe)

- **`picocom`** (simple): `picocom -b 115200 /dev/serial/by-id/<id>` — quit with `Ctrl-a Ctrl-x`.
- **`minicom`**: configure once (`minicom -s`) or pass device on CLI per distro docs.

Agents should prefer **non-interactive capture** (next section) instead of driving picocom/minicom keystrokes.

## Non-interactive serial capture (agent-friendly)

**Short sample** (timeout exits):

```bash
timeout 5s cat /dev/serial/by-id/<id>
```

**Baud-styled line** (raw 8N1 at 115200 — adjust rate to project):

```bash
stty -F /dev/serial/by-id/<id> 115200 cs8 -cstopb -parenb raw -echo
timeout 8s cat /dev/serial/by-id/<id> | tee /tmp/serial-capture.txt
```

**Continuous log** in tmux (detach with `Ctrl-b d` from an interactive ssh, or start detached):

```bash
tmux new-session -d -s serial "stty -F /dev/serial/by-id/<id> 115200 raw -echo && cat /dev/serial/by-id/<id> | tee -a ~/serial.log"
tmux capture-pane -pt serial -S -100   # last 100 lines to stdout
```

**Inject a line** (if the device reads from the same TTY — many MCUs use a separate USB CDC RX; test before relying on this):

```bash
printf 'help\r\n' > /dev/serial/by-id/<id>
```

If writes hang or corrupt output, the port may be in use — only one reader/writer at a time unless using `socat` or a multiplexer the project documents.

## Build / flash loop (agent checklist)

Copy this checklist and adapt commands to the project’s toolchain (CMake/Make, `west`, `idf.py`, vendor CLI, etc.).

```
- [ ] SSH: confirm `uname -a` on Pi and disk space (`df -h`).
- [ ] Serial: resolve stable `/dev/serial/by-id/...`; confirm `dialout`.
- [ ] Sync: rsync or git pull **on the Pi** (or build on dev machine and copy artifact).
- [ ] Flash: run documented flash command **from the Pi** if the probe/serial bootloader is Pi-local.
- [ ] Verify: capture boot/log output via `timeout`+`cat` or `tmux capture-pane`.
- [ ] Iterate: on failure, save full log to file and grep for panic/assert/baud garbage.
```

**Baud / line ending mismatches** often look like **Mojibake or continuous garbage**; fix rate (`stty`), parity, or CRLF vs LF in the firmware’s serial init and the host `stty`.

## Optional: expose Pi serial as TCP to the dev machine

When a **desktop tool on the Mac** must speak to the device as a TCP serial port:

```bash
# On Pi (example): TCP 7001 -> serial
socat TCP-LISTEN:7001,reuseaddr,fork FILE:/dev/serial/by-id/<id>,b115200,cs8,raw,echo=0
```

Then from the dev machine:

```bash
ssh -N -L 7001:127.0.0.1:7001 user@pi-host
```

Point the local tool at `localhost:7001`. **Security:** bind only on the Pi’s loopback unless the network is trusted.

## Optional: copy logs to the dev machine

```bash
scp user@pi-host:~/serial.log .
```

## Safety and hygiene

- Do not paste **passwords, tokens, or production keys** into serial sessions; logs may be captured in project artifacts.
- **Firmware update modes** (bootloader GPIO, double-tap reset): document hardware steps; the agent cannot toggle buttons without user confirmation.
- If **OpenOCD/SWD** is required, that is a different skill path (GDB port, probe udev); this skill stays **UART/USB-serial centric**.

## When to escalate

- **No `/dev/ttyUSB*` or `/dev/ttyACM*`** after plug-in: check `dmesg | tail -50`, cable, and whether the MCU firmware has enumerated USB CDC.
- **`Permission denied` on TTY:** `dialout` group or udev rules for the adapter.
- **Empty read but device works on Windows:** wrong device node, or port already open by ModemManager/getty — disable conflicting services or use `by-id`.
