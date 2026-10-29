"""Feriados nacionales del Perú, calculados para cualquier año, más los días no laborables
que el usuario agregue en ~/.config/zen-calendar/feriados.json."""
import json
from datetime import date, timedelta

# tipos: "feriado", "nolaborable", "fecha" (celebración: se trabaja); el nombre es también su clase CSS
TITLE = {"feriado": "FERIADO", "nolaborable": "DÍA NO LABORABLE", "fecha": "CELEBRACIÓN"}

# (mes, día, nombre, feriado desde el año)
FIXED = (
    (1, 1, "Año Nuevo", 0),
    (5, 1, "Día del Trabajo", 0),
    (6, 7, "Batalla de Arica y Día de la Bandera", 2022),
    (6, 29, "San Pedro y San Pablo", 0),
    (7, 23, "Día de la Fuerza Aérea del Perú", 2023),
    (7, 28, "Fiestas Patrias · Independencia", 0),
    (7, 29, "Fiestas Patrias · Gran Parada Militar", 0),
    (8, 6, "Batalla de Junín", 2022),
    (8, 30, "Santa Rosa de Lima", 0),
    (10, 8, "Combate de Angamos", 0),
    (11, 1, "Día de Todos los Santos", 0),
    (12, 8, "Inmaculada Concepción", 0),
    (12, 9, "Batalla de Ayacucho", 2022),
    (12, 25, "Navidad", 0),
)


def easter(y):
    a = y % 19
    b, c = divmod(y, 100)
    d, e = divmod(b, 4)
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = divmod(c, 4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    n = h + l - 7 * m + 114
    return date(y, n // 31, n % 31 + 1)


def nth_weekday(y, month, wd, n):
    """n-ésimo día de la semana `wd` (0 = lunes … 6 = domingo) del mes."""
    first = date(y, month, 1)
    return first + timedelta(days=(wd - first.weekday()) % 7 + 7 * (n - 1))


def year_events(y):
    ev = {}

    def add(d, name, kind):
        ev.setdefault(d, []).append((name, kind))

    for m, d, name, since in FIXED:
        if y >= since:
            add(date(y, m, d), name, "feriado")
    sunday = easter(y)
    add(sunday - timedelta(days=3), "Jueves Santo", "feriado")
    add(sunday - timedelta(days=2), "Viernes Santo", "feriado")
    add(sunday, "Domingo de Resurrección", "fecha")
    add(nth_weekday(y, 5, 6, 2), "Día de la Madre", "fecha")
    add(nth_weekday(y, 6, 6, 3), "Día del Padre", "fecha")
    add(date(y, 6, 24), "Inti Raymi · Día del Campesino", "fecha")
    add(date(y, 10, 31), "Día de la Canción Criolla", "fecha")
    add(date(y, 12, 24), "Nochebuena", "fecha")
    add(date(y, 12, 31), "Fin de año", "fecha")
    return ev


def load_extra(path):
    """[{"date": "2026-12-24", "name": "Día no laborable", "kind": "nolaborable|feriado|fecha"}]"""
    ev = {}
    try:
        with open(path, encoding="utf-8") as f:
            items = json.load(f)
    except (OSError, ValueError):
        return ev
    if not isinstance(items, list):
        return ev
    for it in items:
        if not isinstance(it, dict):
            continue
        try:
            d = date.fromisoformat(it.get("date"))
        except (TypeError, ValueError):
            continue
        name = it.get("name") if isinstance(it.get("name"), str) else "Día no laborable"
        kind = it.get("kind") if it.get("kind") in ("feriado", "fecha") else "nolaborable"
        ev.setdefault(d, []).append((name, kind))
    return ev


class Calendar:
    """Caché por año + extras del usuario."""

    def __init__(self):
        self.years = {}
        self.extra = {}

    def on(self, d):
        if d.year not in self.years:
            self.years[d.year] = year_events(d.year)
        return self.years[d.year].get(d, []) + self.extra.get(d, [])

    def upcoming(self, start, n):
        """Próximos feriados y días no laborables desde `start` (inclusive)."""
        out = []
        d, end = start, start + timedelta(days=400)
        while d <= end and len(out) < n:
            for name, kind in self.on(d):
                if kind != "fecha" and len(out) < n:
                    out.append((d, name, kind))
            d += timedelta(days=1)
        return out
