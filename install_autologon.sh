#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/autologin.py"
CONFIG_FILE="$SCRIPT_DIR/autologin_config.json"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/autologin.service"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-}"

ask_yes_no() {
  local question="$1"
  local answer=""

  while true; do
    read -r -p "$question [s/N]: " answer
    case "${answer,,}" in
      s|si|sí|y|yes)
        return 0
        ;;
      ""|n|no)
        return 1
        ;;
      *)
        printf 'Responde s o n.\n'
        ;;
    esac
  done
}

get_desktop_dir() {
  if [[ -n "$DESKTOP_DIR" && -d "$DESKTOP_DIR" ]]; then
    printf '%s\n' "$DESKTOP_DIR"
    return
  fi

  if command -v xdg-user-dir >/dev/null 2>&1; then
    local detected=""
    detected="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    if [[ -n "$detected" && -d "$detected" ]]; then
      printf '%s\n' "$detected"
      return
    fi
  fi

  if [[ -d "$HOME/Escritorio" ]]; then
    printf '%s\n' "$HOME/Escritorio"
  else
    printf '%s\n' "$HOME/Desktop"
  fi
}

if [[ ! -f "$PYTHON_SCRIPT" ]]; then
  printf 'No se encontró %s\n' "$PYTHON_SCRIPT" >&2
  exit 1
fi

printf 'Instalando dependencias del sistema...\n'
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y bluez bluetooth freerdp2-x11 xvfb
else
  printf 'apt-get no disponible. Instala manualmente: bluez bluetooth freerdp2-x11 xvfb\n' >&2
fi

chmod +x "$PYTHON_SCRIPT"

if [[ ! -f "$CONFIG_FILE" ]]; then
  "$PYTHON_SCRIPT" --config "$CONFIG_FILE" || true
fi

if ask_yes_no '¿Crear servicio para iniciar autologin al iniciar sesión?'; then
  mkdir -p "$SERVICE_DIR"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Autologin seguro por mando DS4
After=graphical-session.target bluetooth.service
Wants=bluetooth.service

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/python3 $PYTHON_SCRIPT --config $CONFIG_FILE
Restart=on-failure
RestartSec=5
Environment=DISPLAY=:0
Environment=XAUTHORITY=$HOME/.Xauthority

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable autologin.service

  if command -v loginctl >/dev/null 2>&1; then
    sudo loginctl disable-linger "$USER" || true
  fi

  printf '\nServicio instalado: %s\n' "$SERVICE_FILE"
  printf 'El servicio arrancará automáticamente al iniciar sesión el usuario %s.\n' "$USER"
  printf 'Para arrancarlo en esta sesión: systemctl --user start autologin.service\n'
  printf 'Para ver logs: journalctl --user -u autologin.service -f\n'
else
  printf '\nServicio no creado.\n'
fi

if ask_yes_no '¿Crear acceso directo en el escritorio para ejecutar autologin manualmente?'; then
  DESKTOP_TARGET_DIR="$(get_desktop_dir)"
  mkdir -p "$DESKTOP_TARGET_DIR"
  SHORTCUT_FILE="$DESKTOP_TARGET_DIR/Autologon.desktop"

  cat > "$SHORTCUT_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Autologon
Comment=Ejecutar flujo autologin manualmente
Exec=/usr/bin/python3 $PYTHON_SCRIPT --config $CONFIG_FILE --once
Path=$SCRIPT_DIR
Terminal=false
Categories=Utility;
EOF

  chmod +x "$SHORTCUT_FILE"
  printf '\nAcceso directo creado: %s\n' "$SHORTCUT_FILE"
else
  printf '\nAcceso directo no creado.\n'
fi

printf 'Edita la configuración: %s\n' "$CONFIG_FILE"
printf '\nConfigura la contraseña únicamente en rdp_password dentro de autologin_config.json.\n'
