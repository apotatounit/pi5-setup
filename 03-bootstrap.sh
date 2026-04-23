#!/usr/bin/env bash
# 03-bootstrap.sh — Idempotent Pi-side setup. Safe to re-run.
set -euo pipefail

log()  { printf '\033[36m[bootstrap]\033[0m %s\n' "$*"; }
skip() { printf '\033[33m[skip]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[ok]\033[0m %s\n' "$*"; }

[[ "$(id -u)" -ne 0 ]] || { echo "run as login user, not root"; exit 1; }
. /etc/os-release
[[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]] || { echo "not Debian-family"; exit 1; }

USER_NAME="$(id -un)"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"

# 1. apt base
log "apt update + base packages"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq upgrade
BASE_PKGS=(
  build-essential git curl wget ca-certificates gnupg lsb-release
  vim tmux htop jq rsync unzip zstd pv
  ufw fail2ban unattended-upgrades
  make libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev
  libffi-dev liblzma-dev
)
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install "${BASE_PKGS[@]}"
ok "base packages"

# 2. ssh daemon lockdown
log "hardening sshd"
SSHD_DROPIN=/etc/ssh/sshd_config.d/10-hardening.conf
sudo tee "$SSHD_DROPIN" >/dev/null <<'EOF'
Protocol 2
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 20
AllowAgentForwarding no
EOF
sudo chmod 644 "$SSHD_DROPIN"
sudo sshd -t && sudo systemctl reload ssh
ok "sshd hardened"

# 3. ufw
log "ufw"
if ! sudo ufw status | grep -q "Status: active"; then
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow 22/tcp comment 'ssh'
  sudo ufw --force enable
else
  sudo ufw allow 22/tcp >/dev/null || true
fi
ok "ufw active"

# 4. fail2ban
log "fail2ban"
sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null <<'EOF'
[sshd]
enabled = true
port    = ssh
backend = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
sudo systemctl enable --now fail2ban >/dev/null
sudo systemctl restart fail2ban
ok "fail2ban running"

# 5. unattended-upgrades
log "unattended-upgrades"
echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | sudo debconf-set-selections
sudo dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null
ok "auto-updates"

# 6. pyenv + uv + pipx
PYENV_ROOT="$HOME_DIR/.pyenv"
if [[ ! -d "$PYENV_ROOT" ]]; then
  log "installing pyenv"
  git clone --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
else
  skip "pyenv present"
fi

PROFILE="$HOME_DIR/.bashrc"
if ! grep -q 'PYENV_ROOT' "$PROFILE"; then
  cat >> "$PROFILE" <<'EOF'

# >>> pyenv >>>
export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
# <<< pyenv <<<

export PATH="$HOME/.local/bin:$PATH"
EOF
fi

export PYENV_ROOT="$HOME_DIR/.pyenv"
export PATH="$PYENV_ROOT/bin:$HOME_DIR/.local/bin:$PATH"

if ! command -v uv >/dev/null; then
  log "installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
else
  skip "uv present"
fi

if ! command -v pipx >/dev/null; then
  log "installing pipx"
  sudo apt-get -y -qq install pipx
  pipx ensurepath >/dev/null || true
fi
ok "python toolchain"

# 7. Docker
if ! command -v docker >/dev/null; then
  log "installing Docker CE"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get -y -qq install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  skip "docker present"
fi

if ! id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx docker; then
  sudo usermod -aG docker "$USER_NAME"
  log "added $USER_NAME to docker group (log out/in to take effect)"
fi
sudo systemctl enable --now docker >/dev/null
ok "docker ready"

STAMP="$HOME_DIR/.pi5-bootstrap.stamp"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STAMP"
ok "bootstrap complete — $STAMP"
echo
echo "Log out/in (or: exec \$SHELL -l) so docker group and pyenv load. Then ./04-audit.sh"
