#!/usr/bin/env bash
# install.sh — convierte un Arch recién instalado (archinstall o a mano) en arch-zen-niri:
#   niri (Wayland) + SDDM Dark Pirate + tema TokyoNight + dotfiles, seguridad "caja fuerte",
#   snapper + grub-btrfs, ajustes de hardware y rendimiento.
#
#   git clone https://github.com/Freddy-devs/arch-zen-niri-iso.git
#   cd arch-zen-niri-iso && ./install.sh
#
# Robusto: cada paso queda registrado; si algo falla (corte de red, de luz…), vuelve a ejecutarlo y
# continúa desde el paso que falló. Se puede repetir sin romper nada. Ver ./install.sh --help
set -Eeuo pipefail

VERSION=2.0
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
S="$ROOT/system"
STATE_DIR=/var/lib/zen-postinstall
LOG=/var/log/zen-postinstall.log
MIN_FREE_GB=8
MIN_BAT=40        # % mínimo de batería si no hay cargador
DOWNLOAD_TRIES=3
PREBUILT_URL=https://github.com/Freddy-devs/arch-zen-niri-iso/releases/download/paquetes
STEP_NAMES=(clock pacman packages aur files dotfiles users boot snapper services hardware dns snapshot)

c_b=$'\033[1;34m'; c_g=$'\033[1;32m'; c_r=$'\033[1;31m'; c_y=$'\033[1;33m'; c_0=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$c_b" "$c_0" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$c_g" "$c_0" "$*"; }
WARNS=()
warn() { printf '%s!!%s %s\n' "$c_y" "$c_0" "$*"; WARNS+=("$*"); }
die()  { printf '%sERROR:%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
arch-zen-niri post-instalación v$VERSION

Uso: ./install.sh [opciones]      (con tu usuario normal; pide sudo)

  -y, --yes             sin preguntas (teclado detectado, reinicio no automático)
  -k, --keyboard XKB    teclado del escritorio: latam, es, us (por defecto: el de la consola)
      --no-aur          no compilar yay, tema, cursor ni zen-calendar
      --no-hw           no aplicar ajustes de hardware (zen-hwsetup --auto)
      --no-hardening    no cambiar parámetros del kernel (lockdown, AppArmor…)
      --no-reboot       no ofrecer reiniciar al final
      --ignore-battery  no exigir cargador ni batería mínima (si la batería da lecturas raras)
      --redo            repetir todos los pasos aunque ya estén hechos
      --redo PASO[,PASO] repetir solo esos pasos (p. ej. --redo aur o --redo dotfiles,boot)
      --status          mostrar qué pasos están hechos y salir
  -h, --help            esta ayuda

Pasos: ${STEP_NAMES[*]}
Registro: $LOG
EOF
}

# ---------- opciones ----------
YES=0; XKB=""; DO_AUR=1; DO_HW=1; DO_HARDEN=1; DO_REBOOT=1; REDO=0; REDO_STEPS=""; STATUS=0; IGNORE_BAT=0
ARGS=("$@")
is_step() { [[ " ${STEP_NAMES[*]} " == *" $1 "* ]]; }
while (( $# )); do
    case $1 in
        -y|--yes) YES=1 ;;
        -k|--keyboard) XKB=${2:?falta el teclado}; shift ;;
        --keyboard=*) XKB=${1#*=} ;;
        --no-aur) DO_AUR=0 ;;
        --no-hw) DO_HW=0 ;;
        --no-hardening) DO_HARDEN=0 ;;
        --no-reboot) DO_REBOOT=0 ;;
        --ignore-battery) IGNORE_BAT=1 ;;
        --redo=*) REDO_STEPS=${1#*=} ;;
        # --redo solo = todos los pasos; --redo aur,boot = solo esos
        --redo) if [[ -n ${2:-} && $2 != -* ]]; then REDO_STEPS=$2; shift; else REDO=1; fi ;;
        --status) STATUS=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Opción desconocida: $1 (usa --help)" ;;
    esac
    shift
done
[[ -z $XKB || $XKB =~ ^(latam|es|us)$ ]] || die "Teclado inválido '$XKB': usa latam, es o us"
REDO_STEPS=${REDO_STEPS//,/ }
for s in $REDO_STEPS; do is_step "$s" || die "Paso desconocido '$s'. Pasos: ${STEP_NAMES[*]}"; done
# ¿se pidió repetir este paso? (--redo o --redo PASO)
redo_step() { (( REDO )) || [[ " $REDO_STEPS " == *" $1 "* ]]; }

ask() { local v; (( YES )) && { printf '%s' "$2"; return; }; read -rp "$1 [$2]: " v; printf '%s' "${v:-$2}"; }
yes_no() { [[ $(ask "$1 (s/n)" "${2:-s}") =~ ^[sSyY] ]]; }

# ---------- comprobaciones previas ----------
[[ -f /etc/arch-release ]] || die "Esto no es Arch Linux."
[[ -d /run/archiso ]] && die "Estás en la ISO live. Instala primero con archinstall, reinicia y ejecuta esto en el sistema instalado."
for d in dotfiles system packages aur/local; do
    [[ -d $ROOT/$d ]] || die "Falta la carpeta '$d' junto a install.sh. Clona el repositorio completo."
done
if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null || die "Falta sudo. Como root: pacman -S sudo y agrega tu usuario al grupo wheel."
    exec sudo bash "$0" "${ARGS[@]}"
fi
[[ -n ${SUDO_USER:-} && $SUDO_USER != root ]] || die "Ejecútalo con tu usuario normal (no como root): ./install.sh"
USR=$SUDO_USER
HOME_USR=$(getent passwd "$USR" | cut -d: -f6)
[[ -d $HOME_USR ]] || die "No existe el directorio personal de $USR"
id -nG "$USR" | grep -qw wheel || warn "$USR no está en el grupo wheel: agrégalo para usar sudo (usermod -aG wheel $USR)"

mkdir -p "$STATE_DIR"
if (( STATUS )); then
    echo "Pasos hechos (en $STATE_DIR):"; ls -1 "$STATE_DIR" 2>/dev/null | sed 's/^/  ✓ /' || true; exit 0
fi

# sin cargador y con poca batería se corta a mitad (ya pasó con el build de la ISO)
check_power() {
    local p ac=0 mains=0 bat="" cap
    for p in /sys/class/power_supply/*; do
        [[ -r $p/type ]] || continue
        case $(<"$p/type") in
            # basta una entrada de corriente conectada (algunos equipos tienen varias)
            Mains|USB) mains=1; [[ $(cat "$p/online" 2>/dev/null) == 1 ]] && ac=1 ;;
            Battery) [[ -n $bat ]] || bat=$p ;;
        esac
    done
    [[ -n $bat ]] || return 0
    (( ac || ! mains )) && return 0
    cap=$(cat "$bat/capacity" 2>/dev/null || true)
    if [[ ! $cap =~ ^[0-9]+$ ]]; then
        warn "No se pudo leer la batería: conecta el cargador por si acaso."; return 0
    fi
    if (( IGNORE_BAT )); then warn "Sin cargador (batería $cap %), se continúa por --ignore-battery."; return 0; fi
    (( cap >= MIN_BAT )) || die "Sin cargador y batería al $cap %. Conecta el cargador (mínimo $MIN_BAT % sin él).
Si el cargador está conectado y la batería marca mal: ./install.sh --ignore-battery"
    warn "Sin cargador (batería $cap %). Mejor conéctalo."
}
check_power

free_gb=$(( $(df --output=avail -k / | tail -1) / 1024 / 1024 ))
(( free_gb >= MIN_FREE_GB )) || die "Poco espacio en /: ${free_gb} GB libres (mínimo $MIN_FREE_GB GB)."

wait_net() {
    local i
    for i in 1 2 3 4 5 6; do
        curl -fsS --max-time 8 -o /dev/null https://archlinux.org && return 0
        (( i == 1 )) && warn "Sin internet; reintentando… (conéctate con: nmtui)"
        sleep 5
    done
    die "Sin internet. Conéctate (nmtui) y vuelve a ejecutar ./install.sh: continúa donde quedó."
}
wait_net

# pacman ocupado por otra terminal, o candado huérfano de un corte anterior
if [[ -e /var/lib/pacman/db.lck ]]; then
    if pgrep -x pacman >/dev/null || pgrep -x yay >/dev/null; then
        die "pacman se está ejecutando en otra terminal. Espera a que termine y reintenta."
    fi
    warn "Se quitó un candado viejo de pacman (/var/lib/pacman/db.lck)"
    rm -f /var/lib/pacman/db.lck
fi

# ---------- entorno detectado ----------
if [[ -f /boot/grub/grub.cfg ]]; then BOOTLOADER=grub
elif bootctl is-installed >/dev/null 2>&1; then BOOTLOADER=systemd-boot
else BOOTLOADER=other; fi
ROOTFS=$(findmnt -no FSTYPE /)
VIRT=$(systemd-detect-virt 2>/dev/null || true)
if [[ -z $XKB ]]; then
    case $(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf 2>/dev/null) in
        es) XKB=es ;; us) XKB=us ;; *) XKB=latam ;;
    esac
    (( YES )) || XKB=$(ask "Teclado del escritorio (latam, es, us)" "$XKB")
    [[ $XKB =~ ^(latam|es|us)$ ]] || die "Teclado inválido"
fi

clear 2>/dev/null || true
cat <<EOF
  ┌──────────────────────────────────────────────┐
  │   arch-zen-niri · post-instalación v$VERSION      │
  │   niri · SDDM · TokyoNight · caja fuerte     │
  └──────────────────────────────────────────────┘
  Usuario:    $USR
  Cargador:   $BOOTLOADER
  Raíz:       $ROOTFS$( [[ $(lsblk -no TYPE "$(findmnt -no SOURCE / | sed 's/\[.*//')" 2>/dev/null) == crypt ]] && echo ' (cifrada)')
  Equipo:     ${VIRT/none/físico}
  Teclado:    $XKB
  Libre en /: ${free_gb} GB
EOF
[[ $BOOTLOADER == grub ]] || warn "Sin GRUB: no habrá snapshots en el menú de arranque (grub-btrfs)."
[[ $ROOTFS == btrfs ]]    || warn "La raíz no es btrfs ($ROOTFS): se omite snapper."
(( REDO )) && rm -f "$STATE_DIR"/*
for s in $REDO_STEPS; do rm -f "$STATE_DIR/$s"; done
done_steps=$(ls -1 "$STATE_DIR" 2>/dev/null | wc -l)
(( done_steps )) && echo "  Pasos ya hechos en una ejecución anterior: $done_steps (se saltan; --redo PASO para repetir uno)"
echo
yes_no "¿Instalar y configurar todo?" s || die "Cancelado"

touch "$LOG"; chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "----- $(date '+%F %T') install.sh v$VERSION ${ARGS[*]:-} -----" >> "$LOG"

CUR_STEP=""
on_err() {
    local rc=$? line=$1
    printf '\n%sFALLÓ%s el paso «%s» (línea %s, código %s).\n' "$c_r" "$c_0" "$CUR_STEP" "$line" "$rc"
    printf 'Registro: %s\nCorrige el problema (p. ej. la red) y vuelve a ejecutar ./install.sh: continúa desde ese paso.\n' "$LOG"
}
trap 'on_err $LINENO' ERR

# ejecutar un paso una sola vez (marca en $STATE_DIR). Un paso que termina con partes pendientes
# (STEP_PENDING=1) no se marca: la próxima ejecución lo reintenta sin repetir los demás.
run() {
    local name=$1
    if [[ -e $STATE_DIR/$name ]]; then ok "$name (ya hecho)"; return; fi
    CUR_STEP=$name; STEP_PENDING=0
    log "$2"
    "step_$name"
    (( STEP_PENDING )) || date '+%F %T' > "$STATE_DIR/$name"
}

# pacman con reintentos (mirror caído, red inestable). --ask 4: aceptar quitar paquetes en
# conflicto (p. ej. pulseaudio → pipewire-pulse, iptables → iptables-nft)
pac() {
    local i
    for (( i = 1; i <= DOWNLOAD_TRIES; i++ )); do
        pacman --noconfirm --ask 4 "$@" && return 0
        (( i < DOWNLOAD_TRIES )) || break
        warn "pacman falló (intento $i/$DOWNLOAD_TRIES); reintentando en 10 s…"
        sleep 10; wait_net
        pacman -Syy --noconfirm >/dev/null 2>&1 || true
    done
    return 1
}

pkglist() { cat "$@" | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v '^$'; }

# ================================================================ pasos
step_clock() {
    # reloj mal = firmas de paquetes "inválidas"
    timedatectl set-ntp true || true
    systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
    ok "Hora: $(date '+%F %T %Z')"
}

step_pacman() {
    sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    grep -q '^Color' /etc/pacman.conf || sed -i 's/^#Color/Color\nILoveCandy/' /etc/pacman.conf
    sed -i '/^#\[multilib\]/{N;s/#//g}' /etc/pacman.conf
    # mirrors propios; si no responden se vuelve a los que dejó archinstall
    [[ -f /etc/pacman.d/mirrorlist.archinstall ]] || cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.archinstall
    install -m644 "$S/pacman.d/mirrorlist" /etc/pacman.d/mirrorlist
    if ! pacman -Syy --noconfirm; then
        warn "Los mirrors propios no responden: se usan los de archinstall"
        cp /etc/pacman.d/mirrorlist.archinstall /etc/pacman.d/mirrorlist
        pacman -Syy --noconfirm
    fi
    # llavero al día antes de todo lo demás (evita errores de firma en sistemas de ISO vieja)
    pac -S --needed archlinux-keyring
}

step_packages() {
    local -a pkgs
    mapfile -t pkgs < <(pkglist "$ROOT/packages/install-base.txt" "$ROOT/packages/desktop.txt")
    [[ $BOOTLOADER == grub ]] || mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vxE 'grub|grub-btrfs')
    [[ $ROOTFS == btrfs ]]    || mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vxE 'snapper|snap-pac|grub-btrfs|btrfs-progs')
    # paquetes que ya no existen en los repos: avisar en vez de abortar toda la instalación
    local -a missing=() avail=()
    local p
    for p in "${pkgs[@]}"; do
        if pacman -Si "$p" &>/dev/null || pacman -Sg "$p" &>/dev/null; then avail+=("$p"); else missing+=("$p"); fi
    done
    (( ${#missing[@]} )) && warn "No están en los repos (se omiten): ${missing[*]}"
    pac -Syu --needed "${avail[@]}"
    ok "${#avail[@]} paquetes instalados o al día"
    # satty ya no se usa (las capturas son con flameshot): se quita si quedó de una instalación
    # anterior. grim y slurp se quedan: xdg-desktop-portal-wlr los usa para capturar.
    if pacman -Qq satty &>/dev/null; then
        pacman -Rns --noconfirm satty && ok "Quitado: satty"
    fi
    return 0
}

step_aur() {
    (( DO_AUR )) || { warn "--no-aur: sin yay, tema TokyoNight, cursor ni zen-calendar"; return 0; }
    local -a all pkgs=() makedeps=() failed=()
    local p src conf
    mapfile -t all < <(pkglist "$ROOT/packages/custom.txt")
    # primero los ya compilados por GitHub Actions (Release "paquetes"); solo se compila lo que falte
    for p in "${all[@]}"; do
        if pacman -Qq "$p" &>/dev/null && ! redo_step aur; then ok "$p ya instalado"; continue; fi
        if fetch_prebuilt "$p"; then ok "$p instalado (ya compilado)"; else pkgs+=("$p"); fi
    done
    (( ${#pkgs[@]} )) || return 0
    # herramientas de compilación solo durante el build (se quitan después si no estaban)
    for p in rust sassc; do pacman -Qq "$p" &>/dev/null || makedeps+=("$p"); done
    (( ${#makedeps[@]} )) && pac -S --needed --asdeps "${makedeps[@]}"

    src=$(mktemp -d /var/tmp/zen-aur.XXXXXX)
    chown "$USR:" "$src"
    conf="$src/makepkg.conf"
    # binarios ya compilados: sin paquetes -debug (más rápido, sin avisos de gdb-add-index)
    cat > "$conf" <<'EOF'
source /etc/makepkg.conf
OPTIONS=($(printf '%s\n' "${OPTIONS[@]}" | grep -vxE '!?debug') '!debug')
EOF
    chmod 644 "$conf"

    for p in "${pkgs[@]}"; do
        echo "--> $p"
        if ! build_pkg "$p" "$src" "$conf"; then failed+=("$p"); warn "No se pudo compilar $p"; fi
    done
    rm -rf "$src"
    (( ${#makedeps[@]} )) && { pacman -Rns --noconfirm "${makedeps[@]}" || true; }
    if (( ${#failed[@]} )); then
        STEP_PENDING=1
        warn "Paquetes propios que fallaron: ${failed[*]}. Vuelve a ejecutar ./install.sh: reintenta solo esos."
    fi
    return 0
}

fetch_prebuilt() {   # $1 paquete con PKGBUILD propio: descarga la versión exacta del PKGBUILD
    local p=$1 name file sums tmp
    [[ -f $ROOT/aur/local/$p/PKGBUILD ]] || return 1
    name=$(source "$ROOT/aur/local/$p/PKGBUILD" && echo "$pkgname-$pkgver-$pkgrel-${arch[0]}") || return 1
    file="$name.pkg.tar.zst"
    tmp=$(mktemp -d /var/tmp/zen-pkg.XXXXXX)
    # si cambió el PKGBUILD o el código y Actions aún no publicó esa versión, no está: se compila
    if curl -fsSL --retry "$DOWNLOAD_TRIES" --max-time 300 -o "$tmp/$file" "$PREBUILT_URL/$file" \
        && sums=$(curl -fsSL --retry "$DOWNLOAD_TRIES" --max-time 30 "$PREBUILT_URL/SHA256SUMS") \
        && grep -F "  $file" <<<"$sums" | (cd "$tmp" && sha256sum -c --quiet -) \
        && pac -U --needed "$tmp/$file"; then
        rm -rf "$tmp"; return 0
    fi
    rm -rf "$tmp"; return 1
}

build_pkg() {   # $1 paquete, $2 carpeta de trabajo, $3 makepkg.conf
    local p=$1 dir=$2/$1 i
    rm -rf "$dir"
    if [[ -f $ROOT/aur/local/$p/PKGBUILD ]]; then
        cp -r "$ROOT/aur/local/$p" "$dir"
        # apps propias (Rust): el código va junto al PKGBUILD
        [[ -d $ROOT/apps/$p ]] && cp -r "$ROOT/apps/$p" "$dir/src-app"
        chown -R "$USR:" "$dir"
    else
        for (( i = 1; i <= DOWNLOAD_TRIES; i++ )); do
            runuser -u "$USR" -- git clone -q --depth 1 "https://aur.archlinux.org/$p.git" "$dir" && break
            rm -rf "$dir"; sleep 5
        done
        [[ -f $dir/PKGBUILD ]] || return 1
    fi
    # las descargas de fuentes también se reintentan
    for (( i = 1; i <= DOWNLOAD_TRIES; i++ )); do
        (cd "$dir" && runuser -u "$USR" -- makepkg --config "$3" --nodeps --noconfirm --cleanbuild) && break
        (( i < DOWNLOAD_TRIES )) || return 1
        sleep 5
    done
    local -a built
    mapfile -t built < <(find "$dir" -maxdepth 1 -name '*.pkg.tar.zst' ! -name '*-debug-*')
    (( ${#built[@]} )) || return 1
    pac -U --needed "${built[@]}"
}

step_files() {
    install -d /etc/sddm.conf.d /usr/share/sddm/themes /etc/pacman.d/hooks /etc/xdg/reflector \
               /usr/share/backgrounds/zen-niri /usr/local/bin /etc/skel
    install -m644 "$S/sddm/10-zen.conf" /etc/sddm.conf.d/
    cp -r "$S"/sddm/themes/* /usr/share/sddm/themes/
    install -Dm644 "$S/sddm/default.face" /var/lib/AccountsService/icons/default.face
    install -m644 "$S"/pacman.d/hooks/*.hook /etc/pacman.d/hooks/
    install -m644 "$S/reflector.conf" /etc/xdg/reflector/reflector.conf
    install -m755 "$S"/bin/* /usr/local/bin/
    install -m644 "$S/wallpaper.jpg" /usr/share/backgrounds/zen-niri/wallpaper.jpg
    install -Dm755 "$S/environment/90-zen-vm-render" /usr/lib/systemd/user-environment-generators/90-zen-vm-render
    # seguridad: cortafuegos, sysctl, privacidad de red, DNS cifrado
    install -Dm644 "$S/security/nftables.conf"          /etc/nftables.conf
    install -Dm644 "$S/security/90-zen-hardening.conf"  /etc/sysctl.d/90-zen-hardening.conf
    install -Dm644 "$S/security/20-zen-privacy.conf"    /etc/NetworkManager/conf.d/20-zen-privacy.conf
    install -Dm644 "$S/security/zen-dns.conf"           /etc/systemd/resolved.conf.d/zen-dns.conf
    install -Dm644 "$S/security/zen-coredump.conf"      /etc/systemd/coredump.conf.d/zen-coredump.conf
    install -Dm644 "$S/security/zen-blacklist.conf"     /etc/modprobe.d/zen-blacklist.conf
    if [[ $BOOTLOADER == grub && $ROOTFS == btrfs ]]; then
        install -Dm644 "$S/systemd/zen-grub-snapshots.path"    /etc/systemd/system/zen-grub-snapshots.path
        install -Dm644 "$S/systemd/zen-grub-snapshots.service" /etc/systemd/system/zen-grub-snapshots.service
    fi
    # rendimiento: zram, sysctl de memoria/red, límites de archivos, journal acotado
    install -Dm644 "$S/perf/zram-generator.conf"        /etc/systemd/zram-generator.conf
    install -Dm644 "$S/perf/80-zen-performance.conf"    /etc/sysctl.d/80-zen-performance.conf
    install -Dm644 "$S/perf/zen-limits.conf"            /etc/systemd/system.conf.d/zen-limits.conf
    install -Dm644 "$S/perf/zen-limits.conf"            /etc/systemd/user.conf.d/zen-limits.conf
    install -Dm644 "$S/perf/zen-journald.conf"          /etc/systemd/journald.conf.d/zen-journald.conf
    echo tcp_bbr | install -Dm644 /dev/stdin /etc/modules-load.d/zen-bbr.conf
    # teclado del login (SDDM usa X11)
    install -Dm644 /dev/stdin /etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$XKB"
EndSection
EOF
    ok "Configuración copiada"
}

step_dotfiles() {
    # Windows/editores pueden dejar CRLF si se copió el repo a mano
    find "$ROOT/dotfiles" -type f -exec grep -lI $'\r' {} + 2>/dev/null | xargs -r sed -i 's/\r$//' || true
    # niri: el teclado elegido va primero (por defecto) y el inglés de segundo para alternar
    local layouts="$XKB,us"
    [[ $XKB == us ]] && layouts="us,latam"
    cp -rT "$ROOT/dotfiles" /etc/skel
    sed -i -E "s/^( *)layout \"[a-z,]+\"/\1layout \"$layouts\"/" /etc/skel/.config/niri/config.kdl
    # en la carpeta personal se copia como el usuario (sin chown de todo el home: no toca podman ni
    # nada más). Solo cambia lo distinto; lo que el usuario ya tenía queda como archivo.~1~
    local src rel dst tmp n=0
    tmp=$(mktemp -d); chmod 755 "$tmp"
    cp -rT "$ROOT/dotfiles" "$tmp"
    sed -i -E "s/^( *)layout \"[a-z,]+\"/\1layout \"$layouts\"/" "$tmp/.config/niri/config.kdl"
    while IFS= read -r -d '' src; do
        rel=${src#"$tmp/"}; dst=$HOME_USR/$rel
        cmp -s "$src" "$dst" && continue
        runuser -u "$USR" -- mkdir -p "$(dirname "$dst")"
        runuser -u "$USR" -- cp --backup=numbered --preserve=mode "$src" "$dst"
        n=$((n + 1))
    done < <(find "$tmp" -type f -print0)
    rm -rf "$tmp"
    rm -f "$HOME_USR/.config/zen-niri-first-login.done"
    ok "Dotfiles: $n archivos actualizados en $HOME_USR y /etc/skel (usuarios nuevos)"
}

step_users() {
    chsh -s /usr/bin/zsh "$USR" >/dev/null
    chsh -s /usr/bin/zsh root >/dev/null
    grep -q "^$USR:" /etc/subuid || usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USR"
    # sudo: contraseña cada 5 min y registro de lo que se ejecuta; se valida antes de dejarlo
    local tmp; tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
Defaults timestamp_timeout=5
Defaults use_pty
Defaults logfile="/var/log/sudo.log"
EOF
    if visudo -cqf "$tmp"; then install -m440 "$tmp" /etc/sudoers.d/20-zen-hardening
    else warn "sudoers de endurecimiento inválido: no se aplicó"; fi
    rm -f "$tmp"
    # bloqueo tras 5 contraseñas fallidas durante 10 minutos (login, sudo, swaylock)
    sed -i 's/^#\? *deny = .*/deny = 5/; s/^#\? *unlock_time = .*/unlock_time = 600/' /etc/security/faillock.conf
    ok "zsh, sudo endurecido, bloqueo por fallos"
}

# kernel: AppArmor + lockdown=integrity, memoria endurecida sin costo perceptible, sin watchdog,
# sin zswap (se usa zram). Se AÑADEN a lo que dejó archinstall, nunca se quitan.
KCMD="nowatchdog zswap.enabled=0"
KCMD_HARD="lsm=landlock,lockdown,yama,integrity,apparmor,bpf slab_nomerge page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off"
add_params() {   # $1 línea de parámetros → imprime la línea con los que falten
    local line=$1 p all=$KCMD
    (( DO_HARDEN )) && all+=" $KCMD_HARD"
    # lockdown impide cargar módulos DKMS sin firmar (driver NVIDIA de zen-hwsetup): no se pone si hay DKMS
    (( DO_HARDEN )) && ! pacman -Qq dkms &>/dev/null && all+=" lockdown=integrity"
    for p in $all; do [[ " $line " == *" ${p%%=*}="* || " $line " == *" $p "* ]] || line+=" $p"; done
    printf '%s' "${line# }"
}

step_boot() {
    local cur e esp
    case $BOOTLOADER in
    grub)
        [[ -e /etc/default/grub.archinstall ]] || cp /etc/default/grub /etc/default/grub.archinstall
        cur=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' /etc/default/grub)
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$(add_params "$cur")\"|" /etc/default/grub
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
        sed -i '/^#\?GRUB_TOP_LEVEL=/d' /etc/default/grub
        [[ -f /boot/vmlinuz-linux-zen ]] && echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-zen"' >> /etc/default/grub
        if ! grub-mkconfig -o /boot/grub/grub.cfg.new; then
            # nunca dejar el equipo sin arranque: restaurar y avisar
            cp /etc/default/grub.archinstall /etc/default/grub
            rm -f /boot/grub/grub.cfg.new
            warn "grub-mkconfig falló: se restauró la configuración de archinstall"
            return 0
        fi
        mv /boot/grub/grub.cfg.new /boot/grub/grub.cfg
        ok "GRUB: linux-zen por defecto, parámetros añadidos"
        ;;
    systemd-boot)
        esp=$(bootctl --print-esp-path 2>/dev/null || echo /boot)
        for e in "$esp"/loader/entries/*.conf; do
            [[ -f $e ]] || continue
            [[ -e $e.archinstall ]] || cp "$e" "$e.archinstall"
            cur=$(sed -n 's/^options[[:space:]]\+//p' "$e")
            sed -i "s|^options[[:space:]].*|options $(add_params "$cur")|" "$e"
        done
        # entrada para linux-zen si archinstall no la creó (se copia la de otro kernel)
        if [[ -f /boot/vmlinuz-linux-zen ]] && ! grep -lq 'vmlinuz-linux-zen' "$esp"/loader/entries/*.conf 2>/dev/null; then
            e=$(ls "$esp"/loader/entries/*.conf 2>/dev/null | grep -v fallback | head -1 || true)
            if [[ -n $e ]]; then
                sed -e 's/vmlinuz-linux[a-z-]*/vmlinuz-linux-zen/; s/initramfs-linux[a-z-]*\.img/initramfs-linux-zen.img/' \
                    -e 's/^title.*/title   Arch Linux (linux-zen)/' "$e" > "$esp/loader/entries/zen-niri-linux-zen.conf"
                ok "Entrada de arranque para linux-zen creada"
            fi
        fi
        ok "systemd-boot: parámetros añadidos"
        ;;
    *) warn "Cargador no reconocido: añade a mano estos parámetros del kernel: $(add_params '')" ;;
    esac
}

step_snapper() {
    [[ $ROOTFS == btrfs ]] || return 0
    if [[ ! -f /etc/snapper/configs/root ]]; then
        if mountpoint -q /.snapshots; then
            # subvolumen @.snapshots de archinstall ya montado: usar la plantilla directamente
            install -Dm644 /usr/share/snapper/config-templates/default /etc/snapper/configs/root
            sed -i 's/^SUBVOLUME=.*/SUBVOLUME="\/"/' /etc/snapper/configs/root
            if [[ -f /etc/conf.d/snapper ]]; then
                sed -i 's/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS="root"/' /etc/conf.d/snapper
            else
                install -Dm644 /dev/stdin /etc/conf.d/snapper <<< 'SNAPPER_CONFIGS="root"'
            fi
        else
            # create-config falla si /.snapshots existe como carpeta vacía
            [[ -d /.snapshots ]] && rmdir /.snapshots 2>/dev/null || true
            snapper --no-dbus -c root create-config /
        fi
    fi
    sed -i -e "s/^ALLOW_GROUPS=.*/ALLOW_GROUPS=\"wheel\"/" \
           -e 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' \
           -e 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' \
           -e 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' \
           -e 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="1"/' \
           -e 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' \
           -e 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/' \
        /etc/snapper/configs/root
    chmod 750 /.snapshots
    chown :wheel /.snapshots
    ok "Snapper: horas 5 · días 7 · semanas 2 · meses 1"
}

enable() {   # habilitar sin abortar si un servicio no existe en este equipo
    local u
    for u in "$@"; do
        systemctl enable "$u" >/dev/null 2>&1 || warn "No se pudo habilitar $u"
    done
}

step_services() {
    local u
    # --force: reemplaza otro gestor de login si archinstall dejó uno (gdm, lightdm…)
    systemctl enable --force sddm >/dev/null
    enable NetworkManager bluetooth systemd-timesyncd fstrim.timer pkgfile-update.timer \
        systemd-oomd apparmor nftables systemd-resolved reflector.timer paccache.timer
    if [[ $ROOTFS == btrfs ]]; then
        enable snapper-timeline.timer snapper-cleanup.timer
        [[ $BOOTLOADER == grub ]] && enable zen-grub-snapshots.path
    fi
    # red: NetworkManager en exclusiva (iwd/systemd-networkd chocan con él)
    for u in iwd systemd-networkd systemd-networkd.socket dhcpcd; do
        systemctl is-enabled -q "$u" 2>/dev/null && { systemctl disable "$u" >/dev/null 2>&1 || true; }
    done
    # seguridad "caja fuerte": sin SSH ni servicios escuchando en la red
    systemctl mask sshd.service sshd.socket sshd@.service avahi-daemon.service avahi-daemon.socket \
        cups.service cups.socket >/dev/null 2>&1 || true
    pkgfile -u >/dev/null 2>&1 || true
    ok "Servicios habilitados (se activan al reiniciar)"
}

step_hardware() {
    (( DO_HW )) || { warn "--no-hw: sin ajustes de hardware"; return 0; }
    /usr/local/bin/zen-hwsetup --auto || warn "zen-hwsetup terminó con avisos (revísalo luego con: zen-hwsetup)"
    [[ -n $(lspci -d 10de: 2>/dev/null) ]] && echo "  NVIDIA detectada: driver propietario con  zen-hwsetup  → opción NVIDIA (después de reiniciar)"
    return 0
}

step_dns() {
    # DNS cifrado: resolv.conf → systemd-resolved (al final, para no cortar las descargas)
    systemctl start systemd-resolved
    ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    if ! curl -fsS --max-time 10 -o /dev/null https://archlinux.org; then
        warn "Con systemd-resolved no hay DNS todavía; se aplicará al reiniciar"
    fi
}

step_snapshot() {
    [[ $ROOTFS == btrfs ]] || return 0
    snapper --no-dbus -c root create -d "arch-zen-niri recién instalado" || warn "No se pudo crear el snapshot inicial"
}

run clock    "Reloj sincronizado"
run pacman   "pacman: descargas paralelas, color, multilib, mirrors, llavero"
run packages "Paquetes del sistema y escritorio"
run aur      "Paquetes propios: yay, tema TokyoNight, cursor Qogir, zen-calendar"
run files    "Configuración del sistema (SDDM, seguridad, rendimiento)"
run dotfiles "Dotfiles (niri, waybar, rofi, alacritty, zsh…)"
run users    "Shell zsh, sudo y bloqueo por contraseñas fallidas"
run boot     "Arranque: kernel linux-zen y parámetros"
run snapper  "Snapper"
run services "Servicios"
run hardware "Hardware: térmico, energía, Wi-Fi, GPU"
run dns      "DNS cifrado"
run snapshot "Snapshot inicial"
trap - ERR

echo
if (( ${#WARNS[@]} )); then
    printf '%sAvisos:%s\n' "$c_y" "$c_0"; printf '  - %s\n' "${WARNS[@]}"; echo
fi
log "Listo. Registro: $LOG"
log "Reinicia: entrarás por SDDM (Dark Pirate) a niri. En el primer inicio verás la bienvenida (zen-apps)."
(( DO_REBOOT )) || exit 0
(( YES )) && { echo "Reinicia cuando quieras:  reboot"; exit 0; }
read -rp "¿Reiniciar ahora? [S/n] " r || r=n
[[ ${r,,} == n* ]] || systemctl reboot
