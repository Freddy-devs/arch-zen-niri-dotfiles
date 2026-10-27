#!/usr/bin/env bash
# Construye la ISO arch-zen-niri sobre el perfil oficial "releng" de archiso.
# Uso (en Arch / WSL2 Arch, como root):  sudo ./build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# El trabajo va en un FS Linux: mkarchiso falla sobre /mnt/c (NTFS) en WSL
BUILD="${BUILD_DIR:-/var/tmp/arch-zen-niri}"
PROFILE="$BUILD/profile"
WORK="$BUILD/work"
OUT="$ROOT/out"
REPO="$BUILD/repo"
LIVE_USER="live"
LIVE_PASS="live"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "ejecuta como root: sudo ./build.sh"
[[ -f /etc/arch-release ]] || die "se necesita Arch Linux (o WSL2 con Arch)"

log "Dependencias de build"
pacman -Sy --needed --noconfirm archiso base-devel git openssl rsync sassc gtk4 gtk4-layer-shell
# cargo para las apps propias en Rust (rustup también sirve si ya está instalado)
command -v cargo >/dev/null || pacman -S --needed --noconfirm rust

# Los archivos pudieron editarse en Windows: quitar CRLF de todo lo de texto.
find "$ROOT/profile" "$ROOT/dotfiles" "$ROOT/system" "$ROOT/packages" "$ROOT/aur" "$ROOT/apps" \
    -type f ! -name '*.png' ! -name '*.jpg' ! -name '*.face' -exec sed -i 's/\r$//' {} +

rm -rf "$BUILD"
mkdir -p "$BUILD" "$OUT"

log "Repo local [custom]: yay, tema TokyoNight, Nordzy, Qogir, zen-calendar"
bash "$ROOT/aur/build-local-repo.sh" "$REPO"

log "Copiando perfil releng oficial"
cp -a /usr/share/archiso/configs/releng "$PROFILE"

# releng: sin autologin root en tty1 y sin red systemd-networkd/iwd (usamos NetworkManager)
rm -f "$PROFILE/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf"
find "$PROFILE/airootfs/etc/systemd/system" -type l \
    \( -name 'systemd-networkd*' -o -name 'iwd.service' -o -name 'dbus-org.freedesktop.network1.service' \) -delete
# sin sus .network, networkd no toma las interfaces aunque se active por D-Bus (chocaba con NetworkManager)
rm -rf "$PROFILE/airootfs/etc/systemd/network" "$PROFILE/airootfs/etc/systemd/networkd.conf.d"
# seguridad: releng trae SSH activo, cloud-init (lee configuración desde la red) y lector de voz
rm -f  "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/sshd.service" \
       "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/livecd-talk.service"
rm -rf "$PROFILE/airootfs/etc/systemd/system/cloud-init.target.wants"

log "Aplicando overlay propio"
rsync -a "$ROOT/profile/" "$PROFILE/"
A="$PROFILE/airootfs"

# Kernel linux-zen en lugar de linux
# archiso < 91 traía su propio linux.preset; desde 91 se usa el preset del paquete del kernel
if [[ -f "$A/etc/mkinitcpio.d/linux.preset" ]]; then
    mv "$A/etc/mkinitcpio.d/linux.preset" "$A/etc/mkinitcpio.d/linux-zen.preset"
    sed -i -E -e 's#vmlinuz-linux([^-a-z]|$)#vmlinuz-linux-zen\1#g' \
              -e 's#initramfs-linux\.img#initramfs-linux-zen.img#g' \
              -e 's#initramfs-linux-fallback\.img#initramfs-linux-zen-fallback.img#g' \
        "$A/etc/mkinitcpio.d/linux-zen.preset"
fi
# ERE: en BRE la alternativa \([^-]\|$\) no sustituía y las entradas apuntaban a vmlinuz-linux
grep -rlE 'vmlinuz-linux|initramfs-linux' "$PROFILE/grub" "$PROFILE/syslinux" "$PROFILE/efiboot" 2>/dev/null \
    | xargs -r sed -i -E -e 's#vmlinuz-linux([^-a-z]|$)#vmlinuz-linux-zen\1#g' \
                         -e 's#initramfs-linux\.img#initramfs-linux-zen.img#g'
# Abortar si alguna entrada de arranque sigue apuntando al kernel "linux"
if grep -rqE 'vmlinuz-linux([^-]|$)|initramfs-linux\.img' "$PROFILE/grub" "$PROFILE/syslinux" "$PROFILE/efiboot"; then
    die "quedaron entradas de arranque con el kernel 'linux' en lugar de 'linux-zen'"
fi

# Lista de paquetes: releng (sin "linux" ni grml-zsh-config, que choca con nuestro /etc/skel/.zshrc)
# + escritorio + repo custom
{
    grep -vxE 'linux|grml-zsh-config' /usr/share/archiso/configs/releng/packages.x86_64
    grep -vE '^\s*(#|$)' "$ROOT/packages/desktop.txt"
    grep -vE '^\s*(#|$)' "$ROOT/packages/custom.txt"
    echo linux-zen
} | sort -u > "$PROFILE/packages.x86_64"

# pacman.conf de build: mirrors propios + repo local
sed -e "s|@MIRRORLIST@|$ROOT/system/pacman.d/mirrorlist|" \
    -e "s|@CUSTOM_REPO@|$REPO|" \
    "$ROOT/profile/pacman.conf.in" > "$PROFILE/pacman.conf"
rm -f "$PROFILE/pacman.conf.in"

# Identidad de la ISO
sed -i -e 's|^iso_name=.*|iso_name="arch-zen-niri"|' \
       -e 's|^iso_label=.*|iso_label="ZEN_NIRI_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"|' \
       -e 's|^iso_publisher=.*|iso_publisher="arch-zen-niri <https://archlinux.org>"|' \
       -e 's|^iso_application=.*|iso_application="Arch Linux zen + niri Live/Install"|' \
    "$PROFILE/profiledef.sh"
cat >> "$PROFILE/profiledef.sh" <<'EOF'
file_permissions+=(
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d/10-live"]="0:0:440"
  ["/usr/local/bin/zen-install"]="0:0:755"
  ["/usr/local/bin/zen-first-login"]="0:0:755"
  ["/usr/local/bin/arch-news"]="0:0:755"
  ["/usr/local/bin/zen-power"]="0:0:755"
  ["/usr/local/bin/zen-hwcheck"]="0:0:755"
  ["/usr/local/bin/zen-hwsetup"]="0:0:755"
  ["/usr/local/bin/zen-apps"]="0:0:755"
  ["/usr/lib/systemd/user-environment-generators/90-zen-vm-render"]="0:0:755"
)
EOF

log "Configuración del sistema (SDDM, pacman hooks, reflector, mirrors)"
mkdir -p "$A/etc/sddm.conf.d" "$A/usr/share/sddm/themes" "$A/etc/pacman.d/hooks" "$A/etc/xdg/reflector" \
         "$A/usr/share/zen-niri" "$A/usr/local/bin" "$A/opt/zen-niri/repo"
cp "$ROOT/system/sddm/10-zen.conf" "$A/etc/sddm.conf.d/"
cp -r "$ROOT/system/sddm/themes/"* "$A/usr/share/sddm/themes/"
install -Dm644 "$ROOT/system/sddm/default.face" "$A/var/lib/AccountsService/icons/default.face"
# Solo en la ISO live: entra directo a niri
cat > "$A/etc/sddm.conf.d/20-live.conf" <<EOF
[Autologin]
User=$LIVE_USER
Session=niri.desktop
EOF
cp "$ROOT/system/pacman.d/mirrorlist" "$A/etc/pacman.d/mirrorlist"
cp "$ROOT/system/pacman.d/hooks/"*.hook "$A/etc/pacman.d/hooks/"
cp "$ROOT/system/reflector.conf" "$A/etc/xdg/reflector/reflector.conf"
mkdir -p "$A/etc/tmpfiles.d"
cp "$ROOT"/system/bin/* "$A/usr/local/bin/"

# Material que el instalador copia al disco
rsync -a "$ROOT/system/" "$A/usr/share/zen-niri/system/"
cp "$ROOT/packages/install-base.txt" "$ROOT/packages/desktop.txt" "$A/usr/share/zen-niri/"
cp "$REPO"/*.pkg.tar.zst "$A/opt/zen-niri/repo/"

log "Wallpaper"
mkdir -p "$A/usr/share/backgrounds/zen-niri"
cp "$ROOT/system/wallpaper.jpg" "$A/usr/share/backgrounds/zen-niri/wallpaper.jpg"

log "Dotfiles -> /etc/skel y usuario live"
mkdir -p "$A/etc/skel" "$A/home/$LIVE_USER"
rsync -a "$ROOT/dotfiles/" "$A/etc/skel/"
rsync -a "$ROOT/dotfiles/" "$A/home/$LIVE_USER/"
# En live no se ejecuta el asistente de primer login
touch "$A/home/$LIVE_USER/.config/zen-niri-first-login.done"

log "Usuario live ($LIVE_USER / $LIVE_PASS)"
HASH="$(openssl passwd -6 "$LIVE_PASS")"
cat > "$A/etc/passwd" <<EOF
root:x:0:0:root:/root:/usr/bin/zsh
$LIVE_USER:x:1000:1000:Live:/home/$LIVE_USER:/usr/bin/zsh
EOF
cat > "$A/etc/shadow" <<EOF
root::14871::::::
$LIVE_USER:$HASH:14871::::::
EOF
cat > "$A/etc/group" <<EOF
root:x:0:root
wheel:x:10:$LIVE_USER
$LIVE_USER:x:1000:
EOF
cat > "$A/etc/gshadow" <<EOF
root:!*::root
wheel:!*::$LIVE_USER
$LIVE_USER:!*::
EOF
mkdir -p "$A/etc/sudoers.d"
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$A/etc/sudoers.d/10-live"
echo "Z /home/$LIVE_USER - $LIVE_USER $LIVE_USER -" > "$A/etc/tmpfiles.d/zen-live-home.conf"
printf '%s:100000:65536\n' "$LIVE_USER" | tee "$A/etc/subuid" > "$A/etc/subgid"

log "Servicios de la ISO live"
S="$A/etc/systemd/system"
mkdir -p "$S/multi-user.target.wants" "$S/bluetooth.target.wants"
ln -sf /usr/lib/systemd/system/sddm.service "$S/display-manager.service"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$S/multi-user.target.wants/NetworkManager.service"
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service "$S/dbus-org.freedesktop.nm-dispatcher.service"
ln -sf /usr/lib/systemd/system/bluetooth.service "$S/bluetooth.target.wants/bluetooth.service"
ln -sf /usr/lib/systemd/system/bluetooth.service "$S/dbus-org.bluez.service"

install -Dm755 "$ROOT/system/environment/90-zen-vm-render" \
    "$A/usr/lib/systemd/user-environment-generators/90-zen-vm-render"

log "Seguridad de la ISO live: cortafuegos, sysctl, sin SSH"
install -Dm644 "$ROOT/system/security/nftables.conf"         "$A/etc/nftables.conf"
install -Dm644 "$ROOT/system/security/90-zen-hardening.conf" "$A/etc/sysctl.d/90-zen-hardening.conf"
install -Dm644 "$ROOT/system/security/20-zen-privacy.conf"   "$A/etc/NetworkManager/conf.d/20-zen-privacy.conf"
ln -sf /usr/lib/systemd/system/nftables.service "$S/multi-user.target.wants/nftables.service"
for u in sshd.service sshd.socket sshd@.service; do ln -sf /dev/null "$S/$u"; done
# sin mDNS/LLMNR (puertos 5353/5355) y DNS cifrado, igual que el sistema instalado
install -Dm644 "$ROOT/system/security/zen-dns.conf" "$A/etc/systemd/resolved.conf.d/zen-dns.conf"
# systemd intenta abrir el DVD de arranque como imagen de disco y marca [FAILED] al iniciar
ln -sf /dev/null "$S/systemd-loop@.service"
# hora de Lima en la sesión live (releng trae UTC)
ln -sf /usr/share/zoneinfo/America/Lima "$A/etc/localtime"

log "Rendimiento de la ISO live: zram, sysctl, límites, sin volcados de memoria"
install -Dm644 "$ROOT/system/perf/zram-generator.conf"     "$A/etc/systemd/zram-generator.conf"
install -Dm644 "$ROOT/system/perf/80-zen-performance.conf" "$A/etc/sysctl.d/80-zen-performance.conf"
install -Dm644 "$ROOT/system/perf/zen-limits.conf"         "$A/etc/systemd/system.conf.d/zen-limits.conf"
install -Dm644 "$ROOT/system/perf/zen-limits.conf"         "$A/etc/systemd/user.conf.d/zen-limits.conf"
install -Dm644 "$ROOT/system/security/zen-coredump.conf"   "$A/etc/systemd/coredump.conf.d/zen-coredump.conf"
install -Dm644 "$ROOT/system/security/zen-blacklist.conf"  "$A/etc/modprobe.d/zen-blacklist.conf"
echo tcp_bbr | install -Dm644 /dev/stdin "$A/etc/modules-load.d/zen-bbr.conf"

log "mkarchiso"
mkarchiso -v -r -w "$WORK" -o "$OUT" "$PROFILE"

log "Listo:"
ls -lh "$OUT"/*.iso
