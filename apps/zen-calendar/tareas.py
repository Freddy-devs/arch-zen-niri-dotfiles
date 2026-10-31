"""Tareas en ~/.local/share/tasks/tasks.json (mismo formato que el script Tasks de bspwm).
Los campos desconocidos se conservan tal cual al reescribir el archivo."""
import fcntl
import json
import os
import shutil
from datetime import date, datetime, timedelta

ALLDAY = "09:00"          # hora de aviso de las tareas sin hora
REMIND_EVERY = 300        # segundos entre avisos de una tarea vencida
SNOOZE_MIN = 15
PRE_ALERTS = (30, 10, 5)  # minutos antes de la hora


def _int(v):
    return v if isinstance(v, int) and not isinstance(v, bool) else None


def day(t):
    try:
        return date.fromisoformat(t.get("date") or "")
    except (TypeError, ValueError):
        return None


def due(t):
    d = day(t)
    if d is None:
        return None
    try:
        hm = datetime.strptime(t.get("time") or ALLDAY, "%H:%M")
    except (TypeError, ValueError):
        return None
    return datetime.combine(d, hm.time())


def str_field(t, k):
    v = t.get(k)
    return v if isinstance(v, str) else None


def last_alert(t):
    return _int(t.get("last_alert")) or 0


def pre_done(t):
    v = t.get("pre_done")
    return [m for m in v if _int(m) is not None] if isinstance(v, list) else []


def due_alert(t, now, epoch):
    """Qué aviso toca ahora para la tarea, si alguno: ("pre", minutos, etapas alcanzadas) o ("due", None, [])."""
    if t.get("done"):
        return None
    d = due(t)
    if d is None:
        return None
    if d > now:
        sent = pre_done(t)
        hit = [m for m in PRE_ALERTS if m not in sent and now + timedelta(minutes=m) >= d]
        return ("pre", min(hit), hit) if hit else None
    snooze = str_field(t, "snooze_until") or ""
    last = last_alert(t)
    if last > epoch:   # el reloj retrocedió (o se corrigió la hora): si no, callaría la tarea hasta alcanzarlo
        last = 0
    if snooze <= now.strftime("%Y-%m-%d %H:%M") and last + REMIND_EVERY <= epoch:
        return ("due", None, [])
    return None


class Corrupt(Exception):
    """tasks.json existe pero no se puede leer o no es una lista: no se escribe encima."""


class Store:
    def __init__(self):
        base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        self.dir = os.path.join(base, "tasks")
        self.db = os.path.join(self.dir, "tasks.json")
        self.error = None    # texto del problema si el último load() halló el archivo dañado
        self.backup = None   # copia tasks.json.bad-<fecha> del archivo dañado

    def read(self):
        """Lista de tareas; [] si el archivo no existe. Si existe y está dañado lanza Corrupt."""
        try:
            with open(self.db, encoding="utf-8") as f:
                data = json.load(f)
        except FileNotFoundError:
            return []
        except (OSError, ValueError) as e:
            raise Corrupt(str(e)) from e
        if not isinstance(data, list):
            raise Corrupt("no es una lista de tareas")
        return [t for t in data if isinstance(t, dict)]

    def load(self):
        """Como read() pero sin lanzar: con el archivo dañado devuelve [] y deja el motivo en self.error."""
        try:
            data = self.read()
        except Corrupt as e:
            self.error = str(e)
            self.save_bad()
            return []
        self.error = None
        return data

    def save_bad(self):
        """Copia el archivo dañado una sola vez por versión (la fecha es la de su última modificación)."""
        try:
            stamp = datetime.fromtimestamp(os.stat(self.db).st_mtime).strftime("%Y%m%d-%H%M%S")
            bad = f"{self.db}.bad-{stamp}"
            if not os.path.exists(bad):
                shutil.copy2(self.db, bad)
            self.backup = bad
        except OSError:
            self.backup = None

    def update(self, f):
        """Lee, modifica y escribe de forma atómica con el mismo lock que el script Tasks.
        Con el archivo dañado lanza Corrupt sin tocar nada: un JSON a medias (apagón) no debe
        convertirse en una lista vacía escrita encima de todas las tareas."""
        os.makedirs(self.dir, exist_ok=True)
        with open(os.path.join(self.dir, "tasks.json.lock"), "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                data = self.read()
            except Corrupt as e:
                self.error = str(e)
                self.save_bad()
                raise
            self.error = None
            r = f(data)
            tmp = os.path.join(self.dir, f".tasks.{os.getpid()}")
            try:
                with open(tmp, "w", encoding="utf-8") as out:
                    json.dump(data, out, indent=2, ensure_ascii=False)
                    out.flush()
                    os.fsync(out.fileno())
                os.replace(tmp, self.db)
            except OSError:
                try:
                    os.remove(tmp)
                except OSError:
                    pass
        return r
