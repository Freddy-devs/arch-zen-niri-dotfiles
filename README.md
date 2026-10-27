# arch-zen-niri

ISO live + instalador de Arch Linux con **linux-zen**, **niri** (Wayland), **greetd + ReGreet**,
Brave, Podman, PHP, MariaDB, PostgreSQL, herdr y Claude Code. Estética Catppuccin Mocha con
sensación bspwm.

## Qué trae
| Área | Elección | Origen |
|---|---|---|
| Kernel | `linux-zen` (+ `linux-lts` de respaldo en el sistema instalado) | extra |
| Compositor | `niri` + `xwayland-satellite` (apps X11 automáticas) | extra |
| Login | `greetd` + `greetd-regreet` dentro de un niri mínimo | extra |
| Barra / menú / notif. | `waybar`, `rofi` (lanzador, energía, portapapeles), `mako`, `swaylock`, `swayidle` | extra |
| Fuentes | **Inter** (interfaz), JetBrainsMono Nerd (terminal), Symbols Nerd (iconos) | extra |
| Navegador | `brave-bin` (binario oficial de Brave, empaquetado del AUR en repo local) | AUR → repo local |
| Oficina | `wps-office` + interfaz en español + `ttf-wps-fonts` (solo en el sistema instalado; corre vía XWayland) | AUR → repo local |
| Contenedores | `podman`, `buildah`, `podman-compose` (rootless; `alias docker=podman`) | extra |
| Web/BD | `php`, `php-fpm`, `composer`, `mariadb`, `postgresql` | extra |
| IA | Claude Code (instalador nativo oficial), herdr (instalador oficial) | se instalan en el primer login |
| Estabilidad | btrfs + snapper + snap-pac + grub-btrfs, sin repos testing, aviso de noticias Arch | extra |
| Seguridad | disco cifrado LUKS2, cortafuegos nftables (entrada cerrada), sin SSH, DNS cifrado, kernel endurecido | extra |

## Seguridad ("caja fuerte")
- **Disco cifrado (LUKS2 + argon2id)**: todo menos los kernels (`/boot`). Contraseña al encender;
  si se olvida, los datos no se recuperan.
- **Cortafuegos** (`/etc/nftables.conf`): entrada bloqueada por defecto, sin puertos abiertos y sin
  responder a ping. La salida es libre. Ver: `sudo nft list ruleset` · bloqueos: `journalctl -k -g zen-fw`.
- **Sin SSH** (enmascarado también en la ISO live), sin avahi/cups. MariaDB y PostgreSQL solo en localhost.
- **Acceso remoto solo por túnel**: WireGuard (`wireguard-tools`) que inicia la laptop hacia tu
  servidor; nunca se abre un puerto de entrada.
- **Red privada**: MAC aleatoria por red Wi-Fi, IPv6 temporal, no envía el nombre del equipo al router.
- **DNS cifrado** (DNS-over-TLS a Quad9, respaldo Cloudflare) con systemd-resolved.
- **Kernel endurecido** (`/etc/sysctl.d/90-zen-hardening.conf`), `sudo` con registro y 5 min de
  validez, bloqueo de 10 min tras 5 contraseñas fallidas.
- `zen-hwcheck` incluye una sección de seguridad que comprueba todo lo anterior.

MySQL no está en los repos oficiales de Arch; **MariaDB** es el reemplazo oficial y compatible
(cliente `mysql`, `pdo_mysql`, `mysqli`).

## Mirrors
`system/pacman.d/mirrorlist`: Brasil (ufscar, c3sl/ufpr, unicamp) → Chile (anquan) → EE.UU.
(logal.dev) → CDN oficial. Todos 100 % sincronizados según archlinux.org/mirrors/status.
`reflector.timer` los renueva cada semana (BR, CL, US, HTTPS, ≤12 h de retraso).

## Construir la ISO (desde Windows)
1. PowerShell como admin: `wsl --install archlinux`
2. Dentro de Arch (WSL):
   ```sh
   pacman -Syu
   cd /mnt/c/Users/Freddy/iso-linux-zen/arch-linux
   bash build.sh        # como root
   ```
   El trabajo pesado va a `/var/tmp/arch-zen-niri` (disco Linux; cambiar con `BUILD_DIR=...`)
   y la ISO final se escribe en `out/` de esta carpeta, visible desde Windows.
   > Si WSL falla al montar/crear la imagen, usa una VM con Arch y el mismo comando.
3. Resultado: `out/arch-zen-niri-AAAA.MM.DD-x86_64.iso`

Graba con Ventoy, Rufus (modo DD) o `dd`.

## Usar
- La ISO arranca directo en niri como usuario `live` (contraseña `live`).
- Instalar: abre una terminal (`Super+Enter`) y ejecuta `zen-install`.
  Pide disco, usuario, contraseñas, zona horaria (por defecto America/Lima), idioma y teclado.
  Soporta UEFI y BIOS. **Necesita internet.**
- Primer inicio del sistema instalado: se abre una terminal que instala **Claude Code** y **herdr**
  en `~/.local/bin` (ambos se auto-actualizan).
- Bases de datos: inicializadas pero apagadas. `sudo systemctl enable --now mariadb postgresql`.

## Atajos (Super = tecla Windows)
| Atajo | Acción | | Atajo | Acción |
|---|---|---|---|---|
| `Super+Enter` | terminal | | `Super+1..9` | ir a escritorio |
| `Super+Space` / `Super+D` | lanzador | | `Super+Shift+1..9` | enviar ventana |
| `Super+B` | Brave | | `Super+H/J/K/L` | foco |
| `Super+E` | archivos (Thunar) | | `Super+Shift+H/J/K/L` | mover |
| `Super+W` | cerrar | | `Super+R` | ancho 1/3 · 1/2 · 2/3 · 1 |
| `Super+T` | flotante | | `Super+F` / `Super+Shift+F` | maximizar / pantalla completa |
| `Super+O` | vista general | | `Super+,` / `Super+.` | apilar / separar en columna |
| `Super+V` | portapapeles | | `Print` / `Shift+Print` | captura / captura + anotar |
| `Super+Alt+L` | bloquear | | `Super+Alt+Q` | salir de niri |
| `Super+Shift+/` | ver todos los atajos | | `Super+Tab` | escritorio anterior |

**bspwm vs niri:** niri no divide en árbol BSP; cada escritorio es una tira horizontal de columnas
que se desplaza. `Super+R` y `Super+,` dan el equivalente práctico a las divisiones de bspwm.

## Si una actualización rompe algo
En GRUB entra a *Arch Linux snapshots* y arranca el snapshot previo (creado por snap-pac),
o elige el kernel `linux-lts`. Luego `snapper rollback` si quieres quedarte en él.
Antes de actualizar, `news` muestra las noticias de archlinux.org (también aparecen en cada `pacman -Syu`).

## Estructura
```
build.sh                  construye la ISO (releng oficial + overlay)
aur/build-local-repo.sh   compila brave-bin, yay-bin → repo [custom]
packages/                 desktop.txt (común) · install-base.txt · custom.txt (AUR, ISO+sistema) · custom-install.txt (AUR, solo sistema)
profile/pacman.conf.in    pacman.conf de build
system/                   greetd, mirrors, hooks, reflector, scripts (zen-install…), wallpaper
dotfiles/                 /etc/skel: niri, waybar, rofi, mako, alacritty, swaylock, gtk, zsh
```

## Notas
- GPU NVIDIA MX150 (Pascal): por defecto queda en ahorro y todo va en la Intel UHD 620.
  `nvidia-open` y el driver actual de Arch **no** soportan Pascal; si la necesitas,
  `zen-hwsetup` → opción GPU instala `nvidia-580xx` (AUR) y luego se usa con `prime-run <app>`.

## Hardware (ASUS VivoBook X510UNO)
| Componente | Chip | Driver |
|---|---|---|
| Wi-Fi | Intel AC 8265 | `iwlwifi` + linux-firmware-intel |
| Bluetooth | Intel 8087:0a2b | `btusb` |
| Touchpad | ELAN1300 (I²C, Precision) | `i2c_hid_acpi` + `hid_multitouch` |
| Audio | Conexant CX8200 | `snd_hda_intel` (+ sof-firmware) |
| Cámara | UVC 13d3:5a07 | `uvcvideo` |
| Huella | ELAN7001 (SPI) | `fprintd` (libfprint elanspi; probar con `zen-hwcheck`) |
| Teclas Fn | ASUS ATK | `asus-nb-wmi`, `asus-wireless` |

- **`zen-hwcheck`** — diagnóstico completo (Wi-Fi, Bluetooth, touchpad, audio, cámara, huella,
  sensores, batería, GPU, firmware). Úsalo **en la ISO live antes de instalar** para comprobar
  que todo funciona en la laptop sin tocar Windows. Guarda un informe en `~/zen-hwcheck-*.txt`.
- **`zen-hwsetup`** — ajustes: thermald, perfiles de energía (botón en waybar), ahorro de Wi-Fi,
  GPU NVIDIA en reposo, límite de carga de batería y registro de huella para `sudo`.
  El instalador ya aplica los ajustes seguros (`zen-hwsetup --auto`).
- En VirtualBox habilita *VMSVGA + aceleración 3D*; en QEMU usa `-vga virtio`.
