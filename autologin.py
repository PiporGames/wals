#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import json
import socket
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEFAULT_CONFIG = {
    "target_ip": "192.168.1.100",
    "target_mac": "AA:BB:CC:DD:EE:FF",
    "wait_for_controller": False,
    "controller_name": "Wireless Controller",
    "rdp_username": "usuario",
    "rdp_password": "",
    "rdp_domain": "",
    "rdp_extra_args": ["/cert:ignore", "+clipboard", "/w:1920", "/h:1080", "/sound", "/log-level:INFO"],
    "rdp_enable_session_transfer": True,
    "rdp_transfer_delay_seconds": 2,
    "rdp_transfer_timeout_seconds": 60,
    "rdp_progress_interval_seconds": 5,
    "remote_steam_command": "steam://open/bigpicture",
    "launch_local_steam_after_rdp": False,
    "steam_command": ["steam"],
    "max_retry_attempts": 5,
    "wol_timeout_seconds": 90,
    "online_check_port": 3389,
    "online_check_interval_seconds": 3,
    "controller_poll_seconds": 5,
    "log_file": "autologin.log"
}


config = None
config_path = None


def load_config(path):
    cfg_path = Path(path).expanduser().resolve()
    if not cfg_path.exists():
        cfg_path.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n", encoding="utf-8")
        print(f"Configuración creada en {cfg_path}. Edita el archivo y vuelve a ejecutar.")
        sys.exit(1)

    with cfg_path.open("r", encoding="utf-8") as f:
        loaded = json.load(f)

    merged = DEFAULT_CONFIG.copy()
    merged.update(loaded)
    return merged, cfg_path


def log(message):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] AUTOLOGIN: {message}"
    print(line, flush=True)

    log_file = Path(config.get("log_file", "autologin.log"))
    if not log_file.is_absolute():
        log_file = config_path.parent / log_file
    try:
        with log_file.open("a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def redact_command(command):
    redacted = []
    for part in command:
        if part.startswith("/p:"):
            redacted.append("/p:********")
        else:
            redacted.append(part)
    return " ".join(redacted)


def log_process_output(name, stdout, stderr):
    for line in (stdout or "").splitlines():
        if line.strip():
            log(f"{name} stdout: {line.strip()}")
    for line in (stderr or "").splitlines():
        if line.strip():
            log(f"{name} stderr: {line.strip()}")


def log_file_output(name, path):
    try:
        content = Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        log(f"No se pudo leer log temporal de {name}: {exc}")
        return

    for line in content.splitlines():
        if line.strip():
            log(f"{name}: {line.strip()}")


def retry_operation(name, operation, attempts=None, delay_seconds=3):
    max_attempts = int(attempts or config.get("max_retry_attempts", 5))
    for attempt in range(1, max_attempts + 1):
        log(f"{name}: intento {attempt}/{max_attempts}")
        try:
            if operation():
                log(f"{name}: completado")
                return True
        except Exception as exc:
            log(f"{name}: error inesperado: {exc}")

        if attempt < max_attempts:
            log(f"{name}: reintentando en {delay_seconds}s")
            time.sleep(delay_seconds)

    log(f"{name}: falló tras {max_attempts} intentos")
    return False


def run(command, timeout=20):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return None
    except subprocess.TimeoutExpired as exc:
        log(f"Timeout ejecutando: {' '.join(command)}")
        return exc


def check_command(name):
    result = run(["/usr/bin/env", "sh", "-c", f"command -v {name}"], timeout=5)
    return result is not None and getattr(result, "returncode", 1) == 0


def check_dependencies(require_controller=True):
    missing = []
    required_commands = ["xfreerdp", "xvfb-run"]
    if require_controller:
        required_commands.append("bluetoothctl")

    for command in required_commands:
        if not check_command(command):
            missing.append(command)

    if missing:
        log(f"Faltan dependencias: {', '.join(missing)}")
        log("Ejecuta install_autologon.sh para instalarlas.")
        return False
    return True


def enable_bluetooth():
    log("Activando Bluetooth")
    result = run(["bluetoothctl", "power", "on"], timeout=10)
    if result is None or result.returncode != 0:
        stderr = "" if result is None else result.stderr.strip()
        log(f"No se pudo activar Bluetooth: {stderr}")
        return False
    return True


def bluetooth_devices():
    result = run(["bluetoothctl", "devices"], timeout=10)
    if result is None or result.returncode != 0:
        return []

    devices = []
    for line in result.stdout.splitlines():
        parts = line.split(maxsplit=2)
        if len(parts) == 3 and parts[0] == "Device":
            devices.append((parts[1], parts[2]))
    return devices


def is_device_paired_and_connected(mac):
    result = run(["bluetoothctl", "info", mac], timeout=10)
    return (
        result is not None
        and result.returncode == 0
        and "Paired: yes" in result.stdout
        and "Connected: yes" in result.stdout
    )


def connected_controller_mac():
    target = config.get("controller_name", "").lower()
    if not target:
        return None

    for mac, name in bluetooth_devices():
        if target in name.lower() and is_device_paired_and_connected(mac):
            return mac
    return None


def wait_for_controller():
    poll = config["controller_poll_seconds"]

    log(f"Esperando mando Bluetooth emparejado y conectado: {config['controller_name']}")

    while True:
        mac = connected_controller_mac()
        if mac:
            log(f"Mando emparejado y conectado por Bluetooth: {mac}")
            return True

        time.sleep(poll)


def wait_until_controller_removed():
    log("Proceso completado. Esperando desconexión del mando para rearmar.")
    while connected_controller_mac():
        time.sleep(config["controller_poll_seconds"])


def send_magic_packet(mac):
    clean_mac = mac.replace(":", "").replace("-", "")
    if len(clean_mac) != 12:
        raise ValueError("MAC inválida para Wake-on-LAN")

    packet = b"\xff" * 6 + struct.pack("!6B", *bytes.fromhex(clean_mac)) * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(packet, ("255.255.255.255", 9))


def is_online():
    log(f"Comprobando conectividad {config['target_ip']}:{config['online_check_port']}")
    try:
        with socket.create_connection(
            (config["target_ip"], int(config["online_check_port"])),
            timeout=3,
        ):
            return True
    except OSError:
        return False


def wake_and_wait():
    if is_online():
        log(f"Equipo online: {config['target_ip']}:{config['online_check_port']}")
        return True

    log(f"Equipo offline. Enviando WOL a {config['target_mac']}")
    send_magic_packet(config["target_mac"])

    deadline = time.monotonic() + int(config["wol_timeout_seconds"])
    while time.monotonic() < deadline:
        if is_online():
            log("Equipo online tras WOL")
            return True
        remaining = int(deadline - time.monotonic())
        log(f"Esperando a que el equipo esté online. Restan ~{remaining}s")
        time.sleep(config["online_check_interval_seconds"])

    log("Timeout esperando a que el equipo esté online")
    return False


def start_rdp():
    username = config.get("rdp_username", "")
    domain = config.get("rdp_domain", "")
    password = config.get("rdp_password", "")

    command = [
        "xvfb-run",
        "--server-args=-screen 0 1920x1080x24",
        "xfreerdp",
        f"/v:{config['target_ip']}",
    ]
    if username:
        command.append(f"/u:{username}")
    if domain:
        command.append(f"/d:{domain}")
    if password:
        command.append(f"/p:{password}")
    else:
        log("Sin rdp_password; FreeRDP pedirá credenciales si hay sesión gráfica.")

    command.extend(config.get("rdp_extra_args", []))

    log("Iniciando RDP headless con xvfb-run")
    log(f"Comando RDP: {redact_command(command)}")
    output_path = None
    try:
        with tempfile.NamedTemporaryFile(prefix="autologin_xfreerdp_", suffix=".log", delete=False) as output:
            output_path = output.name
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, text=True)
        timeout = int(config.get("rdp_transfer_timeout_seconds", 60))
        progress_interval = int(config.get("rdp_progress_interval_seconds", 5))
        deadline = time.monotonic() + timeout

        while process.poll() is None:
            remaining = int(deadline - time.monotonic())
            if remaining <= 0:
                log(f"RDP no finalizó en {timeout}s; probablemente la transferencia remota no se ejecutó o tscon falló")
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    log("RDP no respondió a terminate; forzando kill")
                    process.kill()
                    process.wait(timeout=5)
                log_file_output("xfreerdp", output_path)
                return False

            log(f"RDP activo; esperando cierre automático tras transferencia. Timeout en ~{remaining}s")
            time.sleep(min(progress_interval, max(1, remaining)))

        process.wait(timeout=5)
        log_file_output("xfreerdp", output_path)
        result_code = process.returncode
        log(f"RDP finalizado con código {result_code}; se considera transferencia completada")
        return True
    except FileNotFoundError:
        log("xfreerdp no está instalado")
        return False
    except subprocess.TimeoutExpired as exc:
        log(f"Timeout recogiendo salida de xfreerdp: {exc}")
        return False
    finally:
        if output_path:
            try:
                Path(output_path).unlink()
            except OSError:
                pass


def start_steam():
    command = config.get("steam_command", ["steam"])
    if not command:
        log("steam_command vacío; no se lanza nada")
        return

    log(f"Lanzando comando local: {' '.join(command)}")
    try:
        subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        log(f"Comando no encontrado: {command[0]}")
    except OSError as exc:
        log(f"No se pudo lanzar Steam: {exc}")


def run_flow_once():
    if not retry_operation("WOL/conectividad", wake_and_wait):
        return
    retry_operation("RDP/transferencia", start_rdp)
    if config.get("launch_local_steam_after_rdp", False):
        start_steam()


def parse_args():
    parser = argparse.ArgumentParser(
        description="Autologin seguro: DS4 -> WOL -> RDP estándar -> Steam"
    )
    parser.add_argument(
        "--config",
        default=str(Path(__file__).with_name("autologin_config.json")),
        help="Ruta del archivo JSON de configuración",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Ejecuta el flujo una vez sin esperar desconexión/rearme",
    )
    return parser.parse_args()


def should_wait_for_controller():
    return bool(config.get("wait_for_controller", False) and config.get("controller_name", ""))


def main():
    global config, config_path
    args = parse_args()
    config, config_path = load_config(args.config)
    wait_controller = should_wait_for_controller()

    log("=== Iniciando autologin ===")
    if not check_dependencies(require_controller=wait_controller):
        sys.exit(2)
    if wait_controller and not enable_bluetooth():
        sys.exit(2)

    while True:
        if wait_controller:
            wait_for_controller()
        else:
            log("Espera de mando desactivada; ejecutando flujo directamente")

        run_flow_once()
        if args.once or not wait_controller:
            break

        wait_until_controller_removed()

    log("=== autologin finalizado ===")


if __name__ == "__main__":
    main()
