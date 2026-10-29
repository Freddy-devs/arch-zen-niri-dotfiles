#!/usr/bin/env python3
"""Genera el tema de cursor Qogir-lime-cursors: el Qogir blanco pintado de verde limón.

Lee los Xcursor de /usr/share/icons/Qogir-white-cursors y tiñe solo los píxeles grises
(relleno blanco, sombras y borde oscuro), así el giro azul de "cargando" y el rojo de
"no permitido" conservan su color. Los enlaces entre cursores se copian tal cual.
Uso: cursor-lime.py [destino] [--preview archivo.png]
"""
import os
import struct
import sys
import zlib

ORIGEN = "/usr/share/icons/Qogir-white-cursors"
LIMA = (0xA3, 0xE6, 0x35)          # verde limón
NOMBRE = "Qogir-lime-cursors"
XCUR_IMG = 0xFFFD0002


def leer(path):
    d = open(path, "rb").read()
    assert d[:4] == b"Xcur", path
    _, _, ntoc = struct.unpack_from("<III", d, 4)
    imgs = []
    for i in range(ntoc):
        typ, sub, pos = struct.unpack_from("<III", d, 16 + i * 12)
        if typ != XCUR_IMG:
            continue
        _, _, _, _, w, h, xh, yh, delay = struct.unpack_from("<9I", d, pos)
        px = list(struct.unpack_from(f"<{w * h}I", d, pos + 36))
        imgs.append({"size": sub, "w": w, "h": h, "xh": xh, "yh": yh, "delay": delay, "px": px})
    return imgs


def escribir(path, imgs):
    toc, cuerpo = [], b""
    inicio = 16 + 12 * len(imgs)
    for im in imgs:
        toc.append(struct.pack("<III", XCUR_IMG, im["size"], inicio + len(cuerpo)))
        cuerpo += struct.pack("<9I", 36, XCUR_IMG, im["size"], 1, im["w"], im["h"], im["xh"], im["yh"], im["delay"])
        cuerpo += struct.pack(f"<{len(im['px'])}I", *im["px"])
    with open(path, "wb") as f:
        f.write(b"Xcur" + struct.pack("<III", 16, 0x10000, len(imgs)) + b"".join(toc) + cuerpo)


def tenir(p):
    """Multiplica los grises por el verde limón (ARGB premultiplicado: sirve tal cual)."""
    a, r, g, b = p >> 24, (p >> 16) & 255, (p >> 8) & 255, p & 255
    if a == 0 or max(r, g, b) - min(r, g, b) > 24:      # transparente o con color propio
        return p
    r, g, b = (c * l // 255 for c, l in zip((r, g, b), LIMA))
    return (a << 24) | (r << 16) | (g << 8) | b


def png(path, imgs):
    """Vista previa: la imagen más grande de cada cursor, una al lado de otra, sobre fondo oscuro."""
    w, h = sum(i["w"] for i in imgs), max(i["h"] for i in imgs)
    filas = []
    for y in range(h):
        fila = bytearray(b"\x00")
        for im in imgs:
            for x in range(im["w"]):
                p = im["px"][y * im["w"] + x] if y < im["h"] else 0
                a = p >> 24
                fondo = 0x2E
                for c in ((p >> 16) & 255, (p >> 8) & 255, p & 255):
                    fila.append(min(255, c + fondo * (255 - a) // 255))
        filas.append(bytes(fila))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(b"".join(filas))) + chunk(b"IEND", b""))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    destino = args[0] if args else os.path.expanduser(f"~/.local/share/icons/{NOMBRE}")
    os.makedirs(f"{destino}/cursors", exist_ok=True)
    with open(f"{destino}/index.theme", "w") as f:
        f.write(f"[Icon Theme]\nName=Qogir-lime Cursors\nComment=Qogir blanco en verde limón\n")
    vista = []
    for nombre in sorted(os.listdir(f"{ORIGEN}/cursors")):
        src, dst = f"{ORIGEN}/cursors/{nombre}", f"{destino}/cursors/{nombre}"
        if os.path.lexists(dst):
            os.remove(dst)
        if os.path.islink(src):
            os.symlink(os.readlink(src), dst)
            continue
        imgs = leer(src)
        for im in imgs:
            im["px"] = [tenir(p) for p in im["px"]]
        escribir(dst, imgs)
        if nombre in ("default", "pointer", "text", "progress", "not-allowed", "grabbing"):
            vista.append(max(imgs, key=lambda i: i["w"]))
    if "--preview" in sys.argv:
        png(sys.argv[sys.argv.index("--preview") + 1], vista)
    print(f"Tema creado en {destino}")


if __name__ == "__main__":
    main()
