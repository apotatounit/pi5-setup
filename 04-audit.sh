#!/usr/bin/env bash
# 04-audit.sh — Read-only audit. Exits non-zero if any invariant missing.
set -uo pipefail

pass=0; fail=0
ck() { local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '\033[32m PASS\033[0m  %s\n' "$label"; pass=$((pass+1))
  else
    printf '\033[31m FAIL\033[0m  %s\n' "$label"; fail=$((fail+1))
  fi
}
section() { printf '\n\033[36m== %s ==\033[0m\n' "$*"; }

section "system"
printf "host         %s\n" "$(hostname)"
printf "kernel       %s\n" "$(uname -r)"
printf "os           %s\n" "$(. /etc/os-release; echo "$PRETTY_NAME")"
printf "arch         %s\n" "$(dpkg --print-architecture)"
printf "uptime       %s\n" "$(uptime -p)"

section "hardware"
grep -E 'Model|Revision|Serial' /proc/cpuinfo | sed 's/^/  /'
printf "mem          %s\n" "$(awk '/MemTotal/ {printf "%.2f GiB\n",$2/1024/1024}' /proc/meminfo)"
printf "root fs      %s\n" "$(df -h / | awk 'NR==2{printf "%s used of %s (%s)\n",$3,$2,$5}')"
printf "throttled    %s\n" "$(vcgencmd get_throttled 2>/dev/null || echo 'n/a')"
printf "temp         %s\n" "$(vcgencmd measure_temp 2>/dev/null || echo 'n/a')"

section "network"
ip -4 -o addr | awk '{print "  "$2,$4}'
printf "default gw   %s\n" "$(ip route | awk '/default/ {print $3; exit}')"
printf "dns          %s\n" "$(awk '/nameserver/ {print $2}' /etc/resolv.conf | paste -sd, -)"

section "security"
ck "sshd: PasswordAuthentication no"  bash -c "sudo sshd -T | grep -qi '^passwordauthentication no'"
ck "sshd: PermitRootLogin no"         bash -c "sudo sshd -T | grep -qi '^permitrootlogin no'"
ck "ufw active"                       bash -c "sudo ufw status | grep -q 'Status: active'"
ck "ufw: 22/tcp allowed"              bash -c "sudo ufw status | grep -qE '22/tcp.*ALLOW'"
ck "fail2ban running"                 systemctl is-active --quiet fail2ban
ck "unattended-upgrades enabled"      systemctl is-active --quiet unattended-upgrades

section "dev env"
ck "git"                              command -v git
ck "pyenv"                            bash -lc 'command -v pyenv'
ck "uv"                               bash -lc 'command -v uv'
ck "docker"                           command -v docker
ck "docker running"                   systemctl is-active --quiet docker
ck "user in docker group"             bash -c "id -nG | tr ' ' '\n' | grep -qx docker"
ck "docker compose plugin"            docker compose version

section "summary"
printf "%d passed, %d failed\n" "$pass" "$fail"
exit "$fail"
