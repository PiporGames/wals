# Windows AutoLogin for Steam (WALS)

Windows AutoLogin for Steam (WALS) es una herramienta que permite poder arrancar, iniciar sesión y lanzar Steam en un PC con Windows desde un equipo Linux de forma automática y sin intervención del usuario.

Resuelve el típico problema de cualquier entusiasta de Steam Big Picture: Querer jugar desde el salón usando un mini-PC Linux/raspberry Pi por Steam Remote Play, pero tener que ir a encender el PC con Windows, iniciar sesión y lanzar Steam antes de poder jugar. Con WALS, todo esto se hace automáticamente a petición del usuario, bien porque el usuario lanza el programa, o bien cuando se detecte automaticamente que se ha conectado un mando Bluetooth al equipo Linux.

Esto es posible gracias a la combinación de Wake-on-LAN (WOL), Remote Desktop Protocol (RDP) y un pequeño hack que permite la transferencia de sesión de RDP a la consola (escritorio local) de Windows.

## Funcionamiento

El funcionamiento de WALS se puede resumir en los siguientes pasos:

  - Fase 1: El programa carga la configuración y espera a que se cumpla la condición de activación (por ejemplo, que se conecte un mando Bluetooth).

  - Fase 2: Se envía un paquete WOL al PC con Windows para encenderlo.

  - Fase 3: El programa comprueba periódicamente que el PC está disponible mediante el puerto RDP. Si no responde dentro del tiempo configurado, se considera que el intento ha fallado.

  - Fase 4: Cuando el PC está disponible, se inicia una conexión RDP sin interfaz gráfica mediante `xfreerdp` y `xvfb-run`, utilizando las credenciales definidas en la configuración.

  - Fase 5: La tarea programada de Windows detecta la conexión RDP autorizada, localiza la sesión activa y la transfiere a la consola física mediante `tscon`. De esta forma, la sesión pasa a verse en el monitor del PC y se desbloquea la pantalla de bloqueo, cerrandose la sesión RDP.

  - Fase 6: Una vez transferida la sesión, Windows inicia Steam. De forma opcional, Linux también puede ejecutar el comando definido en `steam_command` cuando finaliza la conexión RDP.

  - Fase 7: Si todo el proceso ha sido satisfactorio y el programa se ejecuta con `--once`, el proceso termina. En modo continuo, vuelve a esperar la desconexión del mando Bluetooth para poder iniciar un nuevo ciclo. En caso de error, se reintenta el proceso hasta el número máximo de intentos configurado.

## Requisitos

### Linux

- Python 3.9 o posterior.
- Soporte para Wake-on-LAN en la tarjeta de red.
- Soporte para Bluetooth.
- Debian/Ubuntu: `bluez`, `bluetooth`, `freerdp2-x11` y `xvfb`.

Instalación típica:

```bash
sudo apt-get update
sudo apt-get install -y bluez bluetooth freerdp2-x11 xvfb
```

### Windows

- Windows 10/11 **Pro** o superior. **Las ediciones Home no permiten RDP entrante.**
- Escritorio remoto habilitado y configurado para permitir conexiones.
- Usuario local con contraseña.
- Permisos de administrador para instalar la tarea programada.
- Wake-on-LAN habilitado en BIOS, sistema y tarjeta de red (Ethernet).
- Tener Steam instalado, configurado para Remote Play, y haber emparejado y probado a jugar remotamente desde el otro equipo para asegurarse de que funciona correctamente.

## Configuración

Edita `autologin_config-example.json` y sustituye los valores de ejemplo. Luego, renombre el archivo a `autologin_config.json`. Cada opción
se describe en su propia línea:

- `target_ip`: dirección IP del PC Windows.
- `target_mac`: dirección MAC utilizada para Wake-on-LAN.
- `wait_for_controller`: espera un mando Bluetooth antes de iniciar el flujo.
- `controller_name`: nombre Bluetooth del mando que se debe detectar.
- `rdp_username`: usuario para iniciar la sesión RDP. Si es una cuenta de Microsoft, es posible que deba usar el correo electrónico completo de su cuenta; si es un usuario local, use simplemente el nombre de usuario.
- `rdp_password`: contraseña utilizada para la autenticación RDP. Si es una cuenta de Microsoft, es posible que deba usar la contraseña de la cuenta; si es un usuario local, use simplemente la contraseña del usuario.
- `rdp_domain`: dominio Windows opcional para la autenticación RDP.
- `rdp_extra_args`: argumentos adicionales que se pasan a FreeRDP.
- `rdp_enable_session_transfer`: indicador de configuración para la transferencia de sesión RDP.
- `rdp_transfer_delay_seconds`: espera configurada antes de transferir la sesión RDP.
- `rdp_transfer_timeout_seconds`: tiempo máximo de espera para que termine la sesión RDP.
- `rdp_progress_interval_seconds`: intervalo entre mensajes de progreso del proceso RDP.
- `remote_steam_command`: comando URI de Steam previsto para ejecutarse en el equipo remoto.
- `launch_local_steam_after_rdp`: indica si se debe lanzar Steam localmente después de RDP.
- `steam_command`: comando y argumentos utilizados para iniciar Steam localmente.
- `max_retry_attempts`: número máximo de reintentos para las operaciones WOL y RDP.
- `wol_timeout_seconds`: tiempo máximo de espera para que el PC responda después de WOL.
- `online_check_port`: puerto usado para comprobar si el PC está disponible, normalmente `3389`.
- `online_check_interval_seconds`: intervalo entre comprobaciones de conectividad.
- `controller_poll_seconds`: intervalo entre comprobaciones del estado del mando Bluetooth.
- `log_file`: ruta del archivo de log local.

Configura la contraseña directamente en `rdp_password`.

Por favor, no publiques el archivo de configuración si contiene credenciales reales en los bugs de GitHub u otros foros, **ESPECIALMENTE** si es una cuenta de Microsoft.

## Instalación y ejecución

### Linux

Primero, asegúrese de que todos los requisitos de Linux estén cumplidos y que la configuración de `autologin_config.json` sea correcta.

Si desea ejecutar una sola vez:

```bash
python3 autologin.py --config autologin_config.json --once
```

Si desea dejarlo ejecutándose continuamente (por ejemplo, para que se active al detectar un mando Bluetooth):

```bash
python3 autologin.py --config autologin_config.json
```

Para que arranque automáticamente al iniciar sesión en Linux, instale el servicio systemd:

```bash
bash install_autologon.sh
```
### Windows

1. Primero, asegúrese de que todos los requisitos de Windows estén cumplidos.

2. Abra `transfer_rdp_session.ps1` y configura la linea `AllowedClientAddresses` con la IP del cliente Linux. Esto garantiza que solo el mini-PC Linux pueda saltarse la pantalla de bloqueo.

3. Después, ejecuta PowerShell como administrador y ejecuta el script de instalación:

```powershell
.\install_transfer_rdp_task.ps1
```

Recuerde no borrar la carpeta que contiene el script `transfer_rdp_session.ps1`, ya que la tarea programada depende de él.

## Seguridad y limitaciones

- ⚠⚠⚠ Asegúrese de que la red sea confiable y segura; el flujo de trabajo de WALS no está diseñado para redes públicas o inseguras, en especial el acceso remoto RDP. **NUNCA abra el puerto RDP a Internet.** Si desea arrancar remotamente desde fuera de su red local, use una VPN segura. Un mal uso de RDP puede permitir a un atacante tomar el control de su PC con Windows y acceder a todos sus datos de forma silenciosa. **Use WALS bajo su propio riesgo**.

- ⚠ La transferencia de sesión RDP a la consola física de Windows es un hack que se salta la pantalla de bloqueo. Esto significa que cualquier persona con acceso físico al PC tendrá acceso a todo tu PC. Actue con precaución y asegúrese de que el PC esté en un lugar seguro.

- Tanto los logs como el archivo de configuración contienen IPs, usuarios y detalles operativos; no deben publicarse en los issues de GitHub ni en foros públicos. Si necesita ayuda, proporcione solo la información estrictamente necesaria y anonimizada.

- ✅ Recomendación: Cree un usuario local de Windows dedicado para WALS, con permisos limitados, contraseña y solo con Steam y los programas que necesite. No use su cuenta principal de Windows ni una cuenta de Microsoft para este propósito.

## Estructura

```text
autologin.py                         Flujo principal Linux
autologin_config.json                Configuración de ejemplo
install_autologon.sh                 Instalador del servicio systemd
uninstall_autologin_service.sh       Desinstalador del servicio
transfer_rdp_session.ps1             Transferencia RDP a consola Windows
install_transfer_rdp_task.ps1        Instalador de tarea programada
uninstall_transfer_rdp_task.ps1      Desinstalador de tarea programada
```
