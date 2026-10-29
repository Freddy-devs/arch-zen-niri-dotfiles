# arch-zen-niri

Un solo script, `install.sh`, convierte un Arch Linux recién instalado (con `archinstall`) en un
escritorio **mínimo** con **linux-zen**, **niri** (Wayland) y **SDDM** (tema Dark Pirate). Estética
Nord con sensación bspwm. Trae solo lo necesario para ir rápido y gastar pocos recursos;
navegador, oficina, bases de datos y lenguajes los instala cada usuario con `zen-apps`.

## Qué trae
| Área | Elección | Origen |
|---|---|---|
| Kernel | `linux-zen` (+ `linux-lts` de respaldo en el sistema instalado) | extra |
| Compositor | `niri` + `xwayland-satellite` (apps X11 automáticas) | extra |
| Login | `sddm` con el tema propio **Dark Pirate** (QML Qt6; X11 solo en la pantalla de login) | extra |
| Barra / menú / notif. | `waybar` (barra de vidrio translúcido con borde y esquinas redondeadas, con una isla redondeada por grupo: CPU · RAM · disco a la izquierda, escritorios Pac-Man al centro, hora a la derecha antes del idioma y del botón de apagado; clic en la hora = calendario), `rofi` (lanzador, energía, portapapeles), `mako` (por D-Bus, a pedido), `swaylock`, `swayidle` | extra |
| Calendario | `zen-calendar` (Python, apps/zen-calendar): feriados del Perú, agenda y alarmas (GTK4 + `gtk4-layer-shell`) | repo local |
| Tema | GTK **Colloid-Dark-Nord** (GTK2/3/4) · iconos **Nordzy-dark** (Nord) · cursor **Qogir-white-cursors** · Qt (qt6ct, Fusion) con la misma paleta | fuentes de sus autores → repo local |
| Terminal | alacritty + zsh: prompt de bspwm, historial de 100 000 comandos, sugerencias, completado de ~1000 programas, `pkgfile`, banner pixel-art, fastfetch | extra |
| Fuentes | **Inter** (interfaz), JetBrainsMono Nerd (terminal), Symbols Nerd (iconos) | extra |
| Paneles | Bluetooth `zen-bluetooth` (panel bajo la barra, con el mouse; clic derecho abre `bluetui`), sonido `zen-audio` (panel con volumen, micrófono, dispositivos y apps), brillo `zen-brightness` (laptop + monitor externo por DDC/CI con `ddcutil`; en el monitor activa DDC/CI en su menú), red `zen-network` (panel con la conexión actual y las redes Wi-Fi: buscar, conectar con contraseña en la misma fila, olvidar; Super+N; clic derecho abre `nmtui` para lo avanzado) | extra |
| Opcional | `zen-apps`: Brave Origin, WPS, Claude Code, herdr, PHP, MariaDB, PostgreSQL, Podman, Node, Go, Rust, gh, huella, GUIs | a pedido |
| Estabilidad | btrfs + snapper + snap-pac + grub-btrfs (sin demonio: una unidad .path de systemd), sin repos testing, aviso de noticias Arch | extra |
| Seguridad | cortafuegos nftables (entrada cerrada), sin SSH, DNS cifrado, kernel endurecido | extra |

## Seguridad ("caja fuerte")
- **Disco sin cifrar** (a propósito): sin contraseña al encender y los datos se leen desde cualquier
  USB live si algún día hay que recuperarlos.
- **Cortafuegos** (`/etc/nftables.conf`): entrada bloqueada por defecto, sin puertos abiertos y sin
  responder a ping. La salida es libre. Ver: `sudo nft list ruleset` · bloqueos: `journalctl -k -g zen-fw`.
- **Sin SSH**, sin avahi/cups. MariaDB (si la instalas con `zen-apps`) solo en localhost.
- **Acceso remoto solo por túnel**: WireGuard (`wireguard-tools`) que inicia la laptop hacia tu
  servidor; nunca se abre un puerto de entrada.
- **Túneles con otros PCs de la red local** (`zen-traspaso` + panel `zen-tuneles` en la barra, Super+Shift+N,
  a pedido): cada PC se agrega una vez pegando su código público («Copiar mi código» en el otro) y luego
  se conecta o apaga con un interruptor; conectado, SSH en una terminal o `rsync` a `~/Recibido/`. Los
  dos PCs encienden su lado. Encendido abre solo UDP 51820 desde la LAN y SSH dentro del túnel (solo
  llave, solo los PCs conectados); «Apagar todo» (`sudo zen-traspaso apagar`) lo cierra. Nada queda al arrancar.
- **Red privada**: MAC aleatoria por red Wi-Fi, IPv6 temporal, no envía el nombre del equipo al router.
- **DNS cifrado obligatorio** (DNS-over-TLS a Quad9, respaldo Cloudflare) con systemd-resolved. NetworkManager no
  pasa el DNS del router (`dns=none` + `systemd-resolved=false`): ninguna consulta sale al DNS del
  proveedor. Comprobar: `resolvectl status` (la interfaz debe salir sin «DNS Servers»).
- **Kernel endurecido** (`/etc/sysctl.d/90-zen-hardening.conf`), `sudo` con registro y 5 min de
  validez, bloqueo de 10 min tras 5 contraseñas fallidas.
- **AppArmor** activo y **kernel lockdown=integrity**: no se cargan módulos sin firmar ni se accede
  a `/dev/mem`. Endurecimiento de memoria sin costo perceptible (`slab_nomerge`,
  `page_alloc.shuffle`, `randomize_kstack_offset`, `vsyscall=none`, `debugfs=off`).
  Si instalas el driver NVIDIA propietario (DKMS, sin firmar), `zen-hwsetup` quita el lockdown
  y `install.sh` ya no lo vuelve a poner.
  La hibernación no está disponible con lockdown (la suspensión sí).
- Sin volcados de memoria en disco; protocolos de red raros y sistemas de archivos antiguos bloqueados.
- `zen-hwcheck` incluye secciones de seguridad y rendimiento que comprueban todo lo anterior.

## Rendimiento
- **Nada corre en segundo plano sin motivo.** Residentes: niri, waybar, swaybg, swayidle, el agente
  polkit y el historial del portapapeles. mako arranca por D-Bus con la primera notificación; el
  calendario (Python) solo queda en memoria si hay tareas pendientes; Bluetooth, audio y red se
  abren en terminal y se cierran al salir. Los servicios que instala `zen-apps` quedan apagados.
- SDDM solo durante el login; grub-btrfs sin demonio (systemd vigila `/.snapshots`).
- **zram** (zstd, hasta la mitad de la RAM / 8 GB) en vez de zswap; `systemd-oomd` evita que el
  equipo se congele cuando falta memoria.
- Red con **TCP BBR + fq**, colas amplias y TCP Fast Open; límites de archivos abiertos 65 536 / 524 288
  e inotify ampliado (IDEs, node, go, rust, podman).
- Escritura a disco en bloques chicos (el escritorio no se traba al copiar), journal acotado a 256 MB,
  btrfs con `noatime` + `zstd`, sin watchdog.

## Aplicaciones opcionales: `zen-apps`
```sh
zen-apps                 # menú: Tab marca varias, Enter instala
zen-apps brave wps       # directo por nombre
zen-apps --list          # todo lo disponible
```
| id | Qué instala |
|---|---|
| `brave` · `wps` | Navegador Brave Origin · WPS Office en español (AUR con `yay`) |
| `claude` · `herdr` | Claude Code · herdr (instaladores oficiales, en `~/.local/bin`) |
| `php` · `mariadb` · `postgresql` | PHP + php-fpm + Composer · MariaDB solo en localhost · PostgreSQL (inicializados, apagados) |
| `podman` · `node` · `go` · `rust` · `gh` | Podman sin root (`alias docker=podman`) · Node.js · Go · Rust (rustup) · GitHub CLI |
| `huella` · `gui` | fprintd · pavucontrol, blueman, nwg-look |

Al final muestra el comando para encender lo que lo necesite (por ejemplo `sudo systemctl start mariadb`).
MySQL no está en los repos oficiales de Arch; **MariaDB** es el reemplazo oficial y compatible.

## Mirrors
`system/pacman.d/mirrorlist`: Brasil (ufscar, c3sl/ufpr, unicamp) → Chile (anquan) → EE.UU.
(logal.dev) → CDN oficial. Todos 100 % sincronizados según archlinux.org/mirrors/status.
`reflector.timer` los renueva cada semana (BR, CL, US, HTTPS, ≤12 h de retraso).

## Instalar: ISO oficial + archinstall + `install.sh`

1. Descarga la ISO oficial de <https://archlinux.org/download/> y grábala con Ventoy o Rufus (modo DD).
2. Arranca el USB. Si usas Wi-Fi: `iwctl` → `station wlan0 connect "TuRed"` → `exit`.
3. Ejecuta `archinstall` y elige en sus menús:

   | Opción de archinstall | Elegir |
   |---|---|
   | Disk configuration | *Use a best-effort default partition layout* → tu disco → **btrfs** → **sí** a subvolúmenes por defecto → compresión **sí** |
   | Disk encryption | **No encryption** (sin cifrar: sin contraseña al encender y datos recuperables desde un USB live) |
   | Bootloader | **Grub** (necesario para los snapshots en el menú de arranque) |
   | Swap | **sí** (zram) |
   | Hostname / Root password / User account | los tuyos; el usuario como **superusuario (sudo)** |
   | Profile | **Minimal** (el escritorio lo pone `install.sh`) |
   | Audio | **pipewire** |
   | Kernels | **linux-zen** y **linux-lts** (puedes quitar `linux`) |
   | Network configuration | **NetworkManager** |
   | Timezone / Locales | America/Lima · es_PE.UTF-8 · teclado `la-latin1` |

   Luego *Install*. Al terminar, sin entrar al chroot: `reboot` y retira el USB.
4. Entra con tu usuario (pantalla de texto), conéctate (`nmtui`) y ejecuta:
   ```bash
   sudo pacman -S --needed git
   git clone https://github.com/Freddy-devs/arch-zen-niri-dotfiles.git
   cd arch-zen-niri-dotfiles && ./install.sh
   ```
   Instala niri, SDDM Dark Pirate, tema, dotfiles, seguridad, snapper y ajustes de hardware.
   Pregunta solo el teclado y una confirmación. Reinicia al final.

### Qué lo hace robusto
- **Continúa donde quedó**: cada paso se marca en `/var/lib/zen-postinstall/`. Si se corta la red o la
  luz, vuelve a ejecutar `./install.sh` y sigue desde el paso que falló (`--status` muestra el avance).
- **Reintenta** las descargas de pacman, del AUR y de las fuentes; espera a que vuelva internet.
- **Comprueba antes de empezar**: que sea Arch instalado (no la ISO), usuario normal con sudo, internet,
  espacio libre (8 GB), batería (sin cargador exige 40 %; `--ignore-battery` si la batería marca mal) y candados viejos de pacman.
- **Nunca deja el equipo sin arrancar**: añade parámetros del kernel sin quitar los de archinstall
  y, si `grub-mkconfig` falla, restaura la configuración original.
- **Se adapta**: GRUB o systemd-boot, btrfs o ext4 (sin btrfs omite snapper), equipo físico o VM,
  NVIDIA detectada; pulseaudio/iptables en conflicto se reemplazan solos; paquetes que ya no existan
  o del AUR que fallen se avisan al final en vez de abortar todo.
- Lo que ya tenías en tu carpeta personal queda respaldado como `archivo.~1~` (solo si cambia).
- **Rápido**: el tema, el cursor y zen-calendar se descargan ya compilados del Release
  [`paquetes`](https://github.com/Freddy-devs/arch-zen-niri-dotfiles/releases/tag/paquetes)
  (los genera GitHub Actions cada vez que cambian `aur/local/` o `apps/`, con `SHA256SUMS`).
  Solo si falta la versión exacta del PKGBUILD se compilan en el equipo.
- Si un paquete propio (yay, tema, calendario) no compila, el resto sigue; al volver a ejecutar
  `./install.sh` se reintenta solo eso.
  Registro completo: `/var/log/zen-postinstall.log`.

### Opciones
```sh
./install.sh --help            # todas las opciones
./install.sh -y -k latam       # sin preguntas, teclado latinoamericano
./install.sh --status          # qué pasos ya están hechos
./install.sh --redo dotfiles   # repetir solo un paso (p. ej. tras git pull); varios: --redo dotfiles,files
./install.sh --redo            # repetir todos los pasos
./install.sh --ignore-battery  # no exigir cargador (si la batería da lecturas raras)
./install.sh --no-aur          # sin compilar yay, tema, cursor ni zen-calendar
./install.sh --no-hw           # sin ajustes de hardware (zen-hwsetup --auto)
./install.sh --no-hardening    # sin lockdown/AppArmor en los parámetros del kernel
```

## Primer inicio
Entras por SDDM a niri y una bienvenida sugiere `zen-apps` (no instala nada sola).

## Atajos (Super = tecla Windows)
| Atajo | Acción | | Atajo | Acción |
|---|---|---|---|---|
| `Super+Enter` | terminal | | `Super+1..9`, `Super+0` | ir a escritorio (0 = 10) |
| `Super+Space` / `Super+D` | lanzador | | `Super+Shift+1..0` | enviar ventana |
| `Super+B` | Lanzador de apps (rofi) | | `Super+H/J/K/L` | foco |
| `Super+E` | archivos (Thunar) | | `Super+Shift+H/J/K/L` | mover |
| `Super+W` | cerrar | | `Super+R` | ancho 1/3 · 1/2 · 2/3 · 1 |
| `Super+T` | flotante | | `Super+F` / `Super+Shift+F` | maximizar / pantalla completa |
| `Super+O` | vista general | | `Super+,` / `Super+.` | apilar / separar en columna |
| `Super+V` | portapapeles | | `Print` | captura: elegir área + anotar (flameshot) |
| `Shift+Print` | área de la pantalla actual + anotar | | `Ctrl+Print` | captura de la pantalla actual, directo |
| `Super+Alt+L` | bloquear | | `Super+Alt+Q` | salir de niri |
| `Super+F1` | ver todos los atajos | | `Super+Tab` | escritorio anterior |
| `Super+A` | calendario y tareas | | `Super+-` / `Super++` | columna más angosta / ancha |
| `Super+Alt+Space` | teclado latam ⇄ inglés | | | |

## Capturas: flameshot
`zen-captura` (atajos `Print`, `Shift+Print`, `Ctrl+Print`): elegir área + anotar · un área de la
pantalla actual + anotar · la pantalla actual entera, directo. Las capturas van a
`~/Imágenes/Capturas` y al portapapeles. En Wayland flameshot no sabe dónde está el cursor y
pregunta la pantalla; `zen-captura` le pasa la pantalla enfocada de niri (calibra la numeración
de flameshot una vez por sesión comparando tamaños, en caché en `$XDG_RUNTIME_DIR`). En Wayland flameshot captura por el portal; el de
gnome en niri solo sirve con una pantalla, así que `~/.config/xdg-desktop-portal/niri-portals.conf`
manda la captura a `xdg-desktop-portal-wlr` (funciona con varios monitores; usa `grim` por dentro,
por eso grim y slurp quedan instalados como dependencias). Compartir pantalla sigue con gnome.

## Barra y calendario
La barra: CPU · RAM · disco | escritorios de cada pantalla |
bluetooth · red + batería · volumen · brillo · actualizaciones · bandeja · hora · teclado · energía.
Teclado: latam por defecto e inglés (us) de segundo; clic en el idioma o `Super+Alt+Space` para alternar.
Con dos pantallas sale en ambas, y cada una muestra sus escritorios.

Clic en la hora (o `Super+A`) abre el calendario en la pantalla enfocada; se cierra con `Esc` o al
hacer clic fuera. Izquierda: reloj y mes (rueda del mouse = cambiar mes; rojo = feriado, naranja = día
no laborable, morado = celebración, amarillo = tiene tareas). Derecha: el día elegido, su agenda,
alta rápida de tareas/alarmas (hora `15:30`, `3pm` o vacía = todo el día) y los próximos feriados.

- Feriados nacionales del Perú calculados para cualquier año (Semana Santa incluida).
- Días no laborables que decrete el gobierno: `~/.config/zen-calendar/feriados.json`
  `[{"date": "2026-12-24", "name": "Día no laborable"}]`
- Tareas en `~/.local/share/tasks/tasks.json` (mismo formato que el script `Tasks` de bspwm).
- Avisos 30 y 5 min antes; a la hora suena y se repite cada 5 min hasta marcarla. Clic en el aviso:
  abre el día · clic central: marcar hecha / posponer 15 min.

## Terminal
- Al abrir alacritty sale un banner pixel-art al azar (`zen-banner`; `zen-banner --list` los lista; se agregan en `~/.local/share/zen-banners`).
- **Recuerda** todo lo que escribes (`~/.config/zsh/zhistory`, compartido entre terminales).
  Mientras escribes sugiere en gris lo que ya usaste o lo que existe (`→` acepta);
  `↑`/`↓` buscan en el historial lo ya escrito; `Ctrl+R` búsqueda difusa con fzf.
- `Tab` completa comandos, opciones y argumentos de todo lo instalado (zsh-completions);
  un comando que no existe dice qué paquete lo trae (pkgfile).
- `z <fragmento>` salta a carpetas visitadas · `neofetch` = fastfetch con el diseño Nord.

**bspwm vs niri:** niri no divide en árbol BSP; cada escritorio es una tira horizontal de columnas
que se desplaza. `Super+R` y `Super+,` dan el equivalente práctico a las divisiones de bspwm.

## Si una actualización rompe algo
En GRUB entra a *Arch Linux snapshots* y arranca el snapshot previo (creado por snap-pac),
o elige el kernel `linux-lts`. Luego `snapper rollback` si quieres quedarte en él.
Ojo: los snapshots no guardan el kernel (está en `/boot`, fuera de btrfs). Un snapshot de ANTES de
una actualización del kernel puede arrancar sin Wi-Fi o GPU; en ese caso usa `linux-lts` o el más reciente.
Antes de actualizar, `news` muestra las noticias de archlinux.org (también aparecen en cada `pacman -Syu`).
Sin falsas alarmas: los avisos "Update to paquete ≥ versión" se omiten si ya tienes esa versión (o no tienes
el paquete), y en `pacman` cada noticia sale una sola vez (`/var/lib/arch-news/seen`). `arch-news 30 --all` muestra todo.

## Estructura
```
install.sh     post-instalación: todo el sistema en pasos reanudables
packages/      install-base.txt (base) · desktop.txt (escritorio) · custom.txt (se compilan: yay, tema, zen-calendar)
aur/local/     PKGBUILD propios: tema Nord, cursor Qogir, zen-calendar
apps/          zen-calendar (Python)
system/        sddm (tema Dark Pirate), seguridad, rendimiento, mirrors, hooks, reflector,
               scripts (zen-apps, zen-hwsetup, zen-hwcheck, zen-power…), wallpaper
dotfiles/      ~ y /etc/skel: niri, waybar, rofi, mako, alacritty, swaylock, gtk, zsh
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
  sensores, batería, GPU, firmware). Úsalo tras instalar para comprobar
  que todo funciona en la laptop. Guarda un informe en `~/zen-hwcheck-*.txt`.
- **`zen-hwsetup`** — ajustes: thermald, perfiles de energía (botón en waybar), ahorro de Wi-Fi,
  GPU NVIDIA en reposo, límite de carga de batería y registro de huella para `sudo`.
  `install.sh` ya aplica los ajustes seguros (`zen-hwsetup --auto`).
- En VirtualBox habilita *VMSVGA + aceleración 3D*; en QEMU usa `-vga virtio`.
