#!/usr/bin/env bash
# install.sh — convierte un Arch recién instalado con archinstall en arch-zen-niri:
#   niri (Wayland) + SDDM Dark Pirate + tema TokyoNight + dotfiles, seguridad "caja fuerte",
#   snapper + grub-btrfs, ajustes de hardware y rendimiento.
#
# Uso (en el sistema ya instalado, con tu usuario normal y con internet):
#   git clone https://github.com/Freddy-devs/arch-zen-niri-iso.git
#   cd arch-zen-niri-iso && ./install.sh
# En archinstall elige: btrfs (subvolúmenes por defecto) + cifrado, GRUB, perfil Minimal,
# audio pipewire, kernels linux-zen y linux-lts, red NetworkManager. Ver README.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$ROOT/system"
LOG=/var/log/zen-postinstall.log

c_b=$'\033[1;34m'; c_r=$'\033[1;31m'; c_y=$'\033[1;33m'; c_0=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$c_b" "$c_0" "$*"; }
warn() { printf '%s!!%s %s\n' "$c_y" "$c_0" "$*"; }
die()  { printf '%sERROR:%s %s\n' "$c_r" "$c_0" "$*" >&2; exit 1; }
ask()  { local v; read -rp "$1 [$2]: " v; printf '%s' "${v:-$2}"; }

# ---------- comprobaciones ----------
[[ -f /etc/arch-release ]] || die "Esto no es Arch Linux."
[[ -d /run/archiso ]] && die "Estás en la ISO live. Primero instala con archinstall, reinicia y ejecuta esto en el sistema instalado."
[[ $EUID -ne 0 ]] || [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]] \
    || die "Ejecútalo con tu usuario normal (no como root): ./install.sh"
[[ $EUID -eq 0 ]] || exec sudo bash "$0" "$@"
USR=$SUDO_USER
HOME_USR=$(getent passwd "$USR" | cut -d: -f6)
curl -fsS --max-time 8 -o /dev/null https://archlinux.org || die "Sin internet. Conéctate (nmtui) y reintenta."

if [[ -f /boot/grub/grub.cfg ]]; then BOOTLOADER=grub
elif bootctl is-installed >/dev/null 2>&1; then BOOTLOADER=systemd-boot
else BOOTLOADER=other; fi
ROOTFS=$(findmnt -no FSTYPE /)

# teclado: el que se eligió en archinstall (vconsole) → XKB del escritorio
case $(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf 2>/dev/null) in
    es) XKB_DEF=es ;; us) XKB_DEF=us ;; *) XKB_DEF=latam ;;
esac

clear 2>/dev/null || true
cat <<EOF
  ┌──────────────────────────────────────────────┐
  │   arch-zen-niri · post-instalación           │
  │   niri · SDDM · TokyoNight · caja fuerte     │
  └──────────────────────────────────────────────┘
  Usuario:          $USR
  Cargador:         $BOOTLOADER
  Sistema de arch.: $ROOTFS
EOF
[[ $BOOTLOADER == grub ]] || warn "Sin GRUB: no habrá snapshots en el menú de arranque (grub-btrfs)."
[[ $ROOTFS == btrfs ]] || warn "La raíz no es btrfs: se omite snapper (sin snapshots)."
XKB=$(ask "Teclado del escritorio (latam, es, us)" "$XKB_DEF")
[[ $XKB =~ ^(latam|es|us)$ ]] || die "Teclado inválido"
[[ $(ask "¿Instalar y configurar todo? (s/n)" "s") =~ ^[sSyY] ]] || die "Cancelado"

: > "$LOG"; chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1

# ---------- pacman ----------
log "pacman: descargas paralelas, color, multilib, mirrors"
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
grep -q '^Color' /etc/pacman.conf || sed -i 's/^#Color/Color\nILoveCandy/' /etc/pacman.conf
sed -i '/^#\[multilib\]/{N;s/#//g}' /etc/pacman.conf
install -m644 "$S/pacman.d/mirrorlist" /etc/pacman.d/mirrorlist

# ---------- paquetes ----------
log "Instalando paquetes"
mapfile -t PKGS < <(cat "$ROOT/packages/install-base.txt" "$ROOT/packages/desktop.txt" | grep -vE '^\s*(#|$)')
[[ $BOOTLOADER == grub ]] || mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | grep -vxE 'grub|grub-btrfs')
[[ $ROOTFS == btrfs ]]     || mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | grep -vxE 'snapper|snap-pac|grub-btrfs')
pacman -Syu --needed --noconfirm "${PKGS[@]}"

log "Paquetes propios (yay, tema TokyoNight, Nordzy, Qogir, zen-calendar)"
# herramientas de compilación solo durante el build (se quitan si no estaban)
MAKEDEPS=()
for p in rust sassc; do pacman -Qq "$p" &>/dev/null || MAKEDEPS+=("$p"); done
(( ${#MAKEDEPS[@]} )) && pacman -S --needed --noconfirm --asdeps "${MAKEDEPS[@]}"
REPO=$(mktemp -d /var/tmp/zen-repo.XXXXXX)
bash "$ROOT/aur/build-local-repo.sh" "$REPO"
pacman -U --needed --noconfirm "$REPO"/*.pkg.tar.zst
rm -rf "$REPO"
(( ${#MAKEDEPS[@]} )) && pacman -Rns --noconfirm "${MAKEDEPS[@]}" || true

# ---------- archivos del sistema ----------
log "Copiando configuración del sistema"
install -d /etc/sddm.conf.d /usr/share/sddm/themes /etc/pacman.d/hooks /etc/xdg/reflector \
           /usr/share/backgrounds/zen-niri /usr/local/bin /etc/skel
install -m644 "$S/sddm/10-zen.conf" /etc/sddm.conf.d/
cp -r "$S"/sddm/themes/* /usr/share/sddm/themes/
install -Dm644 "$S/sddm/default.face" /var/lib/AccountsService/icons/default.face
install -m644 "$S"/pacman.d/hooks/*.hook /etc/pacman.d/hooks/
install -m644 "$S/reflector.conf" /etc/xdg/reflector/reflector.conf
install -m755 "$S"/bin/arch-news "$S"/bin/zen-first-login "$S"/bin/zen-power "$S"/bin/zen-apps \
               "$S"/bin/zen-hwcheck "$S"/bin/zen-hwsetup /usr/local/bin/
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

# ---------- dotfiles ----------
log "Dotfiles → /etc/skel y $HOME_USR (los archivos que ya existían quedan como *.~N~)"
cp -rT "$ROOT/dotfiles" /etc/skel
cp -rT --backup=numbered "$ROOT/dotfiles" "$HOME_USR"
for f in /etc/skel/.config/niri/config.kdl "$HOME_USR/.config/niri/config.kdl"; do
    sed -i "s/layout \"latam\"/layout \"$XKB\"/" "$f"
done
rm -f "$HOME_USR/.config/zen-niri-first-login.done"
chown -R "$USR:" "$HOME_USR"

# ---------- usuarios ----------
log "Shell zsh, sudo y bloqueo por contraseñas fallidas"
chsh -s /usr/bin/zsh "$USR"
chsh -s /usr/bin/zsh root
grep -q "^$USR:" /etc/subuid || usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USR"
# sudo: contraseña cada 5 min y registro de lo que se ejecuta
install -m440 /dev/stdin /etc/sudoers.d/20-zen-hardening <<'EOF'
Defaults timestamp_timeout=5
Defaults use_pty
Defaults logfile="/var/log/sudo.log"
EOF
visudo -cq || die "sudoers inválido"
# bloqueo tras 5 contraseñas fallidas durante 10 minutos (login, sudo, swaylock)
sed -i 's/^#\? *deny = .*/deny = 5/; s/^#\? *unlock_time = .*/unlock_time = 600/' /etc/security/faillock.conf

# ---------- arranque ----------
# kernel: AppArmor + lockdown=integrity, endurecimiento de memoria sin costo perceptible,
# sin watchdog y sin zswap (se usa zram). Se AÑADEN a lo que dejó archinstall (cifrado incluido).
KCMD="nowatchdog zswap.enabled=0 lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
KCMD+=" lockdown=integrity slab_nomerge page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off"
add_params() {   # $1 = línea actual de parámetros → imprime la línea con los que falten
    local line=$1 p
    for p in $KCMD; do [[ " $line " == *" ${p%%=*}="* || " $line " == *" $p "* ]] || line+=" $p"; done
    printf '%s' "${line# }"
}
case $BOOTLOADER in
grub)
    log "GRUB: parámetros del kernel, linux-zen por defecto, 3 s de espera"
    cur=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/p' /etc/default/grub)
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$(add_params "$cur")\"|" /etc/default/grub
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
    sed -i '/^#\?GRUB_TOP_LEVEL=/d' /etc/default/grub
    echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-zen"' >> /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    ;;
systemd-boot)
    log "systemd-boot: parámetros del kernel en las entradas"
    ESP=$(bootctl --print-esp-path 2>/dev/null || echo /boot)
    for e in "$ESP"/loader/entries/*.conf; do
        [[ -f $e ]] || continue
        cur=$(sed -n 's/^options[[:space:]]\+//p' "$e")
        sed -i "s|^options[[:space:]].*|options $(add_params "$cur")|" "$e"
    done
    warn "Si instalaste linux-zen recién ahora, archinstall no creó su entrada: revisa $ESP/loader/entries."
    ;;
*) warn "Cargador no reconocido: añade a mano estos parámetros del kernel: $KCMD" ;;
esac

# ---------- snapper ----------
if [[ $ROOTFS == btrfs ]]; then
    log "Snapper (config root, límites moderados)"
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
fi

# ---------- servicios ----------
log "Servicios"
# --force: reemplaza otro gestor de login si archinstall dejó uno
systemctl enable --force sddm
systemctl enable NetworkManager bluetooth systemd-timesyncd fstrim.timer pkgfile-update.timer \
    systemd-oomd apparmor nftables systemd-resolved reflector.timer paccache.timer
if [[ $ROOTFS == btrfs ]]; then
    systemctl enable snapper-timeline.timer snapper-cleanup.timer
    [[ $BOOTLOADER == grub ]] && systemctl enable zen-grub-snapshots.path
fi
# red: NetworkManager en exclusiva (iwd/systemd-networkd chocan con él)
for u in iwd systemd-networkd systemd-networkd.socket; do
    systemctl is-enabled -q "$u" 2>/dev/null && systemctl disable "$u"
done
# Seguridad "caja fuerte": sin SSH ni servicios escuchando en la red
systemctl mask sshd.service sshd.socket sshd@.service avahi-daemon.service avahi-daemon.socket \
    cups.service cups.socket 2>/dev/null || true
pkgfile -u >/dev/null 2>&1 || true

log "Hardware: térmico, perfiles de energía, ahorro de Wi-Fi y GPU NVIDIA en reposo"
/usr/local/bin/zen-hwsetup --auto || warn "zen-hwsetup terminó con avisos (revísalo luego con: zen-hwsetup)"

# DNS cifrado: resolv.conf → systemd-resolved (al final, para no cortar las descargas)
systemctl start systemd-resolved
ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

if [[ $ROOTFS == btrfs ]]; then
    log "Snapshot inicial"
    snapper --no-dbus -c root create -d "arch-zen-niri recién instalado" || warn "No se pudo crear el snapshot inicial"
fi

echo
log "Listo. Registro: $LOG"
log "Reinicia: entrarás por SDDM (Dark Pirate) a niri. En el primer inicio verás la bienvenida (zen-apps)."
read -rp "¿Reiniciar ahora? [S/n] " r || r=n
[[ ${r,,} == n* ]] || systemctl reboot
