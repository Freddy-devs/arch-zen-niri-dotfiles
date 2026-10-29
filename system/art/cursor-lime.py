#!/usr/bin/env python3
"""Genera el tema de cursor Qogir-lime-cursors: el Qogir blanco pintado de verde limón brillante.

Lee los Xcursor de /usr/share/icons/Qogir-white-cursors y tiñe solo los píxeles grises
(relleno blanco, sombras y borde oscuro), así el giro azul de "cargando" y el rojo de
"no permitido" conservan su color. Añade el tamaño 28 (escalado desde el 32). Los enlaces entre cursores se copian tal cual.
Uso: cursor-lime.py [destino] [--preview archivo.png]
"""
import os
import struct
import sys
import zlib

ORIGEN = "/usr/share/icons/Qogir-white-cursors"
LIMA = (0xC4, 0xFF, 0x1F)          # verde limón brillante
EXTRA = {28: 32}                   # tamaños nuevos: 28 se escala desde el de 32 (el escritorio usa 28)
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


def escalar(im, nominal, base):
    """Copia de una imagen a otro tamaño nominal, promediando por área (nítido al reducir)."""
    f = nominal / base
    w, h = max(1, round(im["w"] * f)), max(1, round(im["h"] * f))
    sw, sh, src = im["w"], im["h"], im["px"]
    px = []
    for y in range(h):
        y0, y1 = y / f, min(sh, (y + 1) / f)
        for x in range(w):
            x0, x1 = x / f, min(sw, (x + 1) / f)
            acc, area = [0.0] * 4, 0.0
            for sy in range(int(y0), min(sh, int(y1) + 1)):
                cy = min(y1, sy + 1) - max(y0, sy)
                if cy <= 0:
                    continue
                for sx in range(int(x0), min(sw, int(x1) + 1)):
                    cx = min(x1, sx + 1) - max(x0, sx)
                    if cx <= 0:
                        continue
                    p, k = src[sy * sw + sx], cx * cy
                    area += k
                    for i, sh_ in enumerate((24, 16, 8, 0)):
                        acc[i] += ((p >> sh_) & 255) * k
            c = [min(255, round(v / area)) for v in acc] if area else [0, 0, 0, 0]
            px.append((c[0] << 24) | (c[1] << 16) | (c[2] << 8) | c[3])
    return {"size": nominal, "w": w, "h": h, "xh": min(w - 1, round(im["xh"] * f)),
            "yh": min(h - 1, round(im["yh"] * f)), "delay": im["delay"], "px": px}


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
        for nominal, base in EXTRA.items():
            imgs += [escalar(im, nominal, base) for im in imgs if im["size"] == base]
        imgs.sort(key=lambda i: i["size"])
        escribir(dst, imgs)
        if nombre in ("default", "pointer", "text", "progress", "not-allowed"):
            vista.append(next(i for i in imgs if i["size"] == 28))
    if "--preview" in sys.argv:
        png(sys.argv[sys.argv.index("--preview") + 1], vista)
    print(f"Tema creado en {destino}")


if __name__ == "__main__":
    main()
