#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/autologin.service"

if systemctl --user list-unit-files autologin.service >/dev/null 2>&1; then
  systemctl --user stop autologin.service >/dev/null 2>&1 || true
  systemctl --user disable autologin.service >/dev/null 2>&1 || true
fi

if [[ -f "$SERVICE_FILE" ]]; then
  rm -f "$SERVICE_FILE"
fi

systemctl --user daemon-reload
systemctl --user reset-failed autologin.service >/dev/null 2>&1 || true

printf 'Servicio autologin desinstalado.\n'
