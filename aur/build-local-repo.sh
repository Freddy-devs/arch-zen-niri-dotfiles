#!/usr/bin/env bash
# Compila paquetes del AUR (binarios oficiales reempaquetados) y crea el repo local [custom].
# Uso: build-local-repo.sh <directorio-repo>
set -euo pipefail

REPO="${1:?falta directorio del repo}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mapfile -t PKGS < <(cat "$HERE/../packages/custom.txt" "$HERE/../packages/custom-install.txt" | grep -vE '^\s*(#|$)')

# makepkg no corre como root: usar el usuario que llamó a sudo o uno temporal
BUILDER="${SUDO_USER:-}"
if [[ -z "$BUILDER" || "$BUILDER" == root ]]; then
    BUILDER=zenbuilder
    id "$BUILDER" &>/dev/null || useradd -r -m -d /var/lib/zenbuilder "$BUILDER"
fi

SRC="$(mktemp -d /var/tmp/zen-aur.XXXXXX)"
chown "$BUILDER:" "$SRC"
mkdir -p "$REPO"

# Binarios ya compilados: sin paquetes -debug (evita los avisos de gdb-add-index y acelera)
CONF="$SRC/makepkg.conf"
cat > "$CONF" <<'EOF'
source /etc/makepkg.conf
OPTIONS=($(printf '%s\n' "${OPTIONS[@]}" | grep -vxE '!?debug') '!debug')
EOF
chmod 644 "$CONF"

for pkg in "${PKGS[@]}"; do
    echo "--> $pkg"
    runuser -u "$BUILDER" -- git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "$SRC/$pkg"
    # Son paquetes -bin: no necesitan dependencias instaladas para empaquetar
    (cd "$SRC/$pkg" && runuser -u "$BUILDER" -- makepkg --config "$CONF" --nodeps --noconfirm --cleanbuild)
    find "$SRC/$pkg" -maxdepth 1 -name '*.pkg.tar.zst' ! -name '*-debug-*' -exec cp {} "$REPO/" \;
done

repo-add "$REPO/custom.db.tar.gz" "$REPO"/*.pkg.tar.zst
rm -rf "$SRC"
