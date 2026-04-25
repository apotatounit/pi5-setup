#!/usr/bin/env bash
# SSH to Pi over NetworkManager hotspot (10.42.0.1). Pubkey-only — no password prompt.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/config.env"
KEY="${SSH_PUBKEY_PATH%.pub}"
exec ssh -o BatchMode=yes \
  -o PreferredAuthentications=publickey \
  -o PubkeyAuthentication=yes \
  -o IdentitiesOnly=yes \
  -i "$KEY" \
  "${PI_USER}@10.42.0.1"
