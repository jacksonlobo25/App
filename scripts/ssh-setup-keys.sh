#!/usr/bin/env bash
set -euo pipefail

DEV_USER="${DEV_USERNAME:-dev}"
HOME_DIR="/home/${DEV_USER}"
SRC="/etc/ssh/authorized_keys.list"
DST_DIR="${HOME_DIR}/.ssh"
DST="${DST_DIR}/authorized_keys"

install -d -m 700 -o "${DEV_USER}" -g "${DEV_USER}" "${DST_DIR}"

if [[ -f "${SRC}" ]]; then
  sed -e 's/\r$//' "${SRC}" | awk 'NF && $1 !~ /^#/' > "${DST}"
  chown "${DEV_USER}:${DEV_USER}" "${DST}"
  chmod 600 "${DST}"
  echo "[ssh-setup-keys] authorized_keys installed for ${DEV_USER}"
else
  echo "[ssh-setup-keys] WARNING: ${SRC} not found; no keys installed"
fi
