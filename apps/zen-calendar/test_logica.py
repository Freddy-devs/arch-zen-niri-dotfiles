"""Pruebas de feriados y avisos (las corre check() del PKGBUILD): python -m unittest -v test_logica"""
import json
import unittest
from datetime import date, datetime

import feriados
import tareas


class Feriados(unittest.TestCase):
    def test_semana_santa(self):
        self.assertEqual(feriados.easter(2026), date(2026, 4, 5))
        self.assertEqual(feriados.easter(2027), date(2027, 3, 28))
        ev = feriados.year_events(2026)
        self.assertEqual(sum(k == "feriado" for v in ev.values() for _, k in v), 16)
        self.assertIn("Jueves Santo", [n for n, _ in ev[date(2026, 4, 2)]])

    def test_dia_madre_padre(self):
        self.assertEqual(feriados.nth_weekday(2026, 5, 6, 2), date(2026, 5, 10))
        self.assertEqual(feriados.nth_weekday(2026, 6, 6, 3), date(2026, 6, 21))


class Avisos(unittest.TestCase):
    def test_avisos(self):
        task = json.loads
        at = lambda h, m: datetime(2026, 10, 27, h, m)
        now, ep = at(13, 40), 1_000_000
        self.assertEqual(tareas.due_alert(task('{"id":1,"date":"2026-10-27","time":"14:00"}'), now, ep)[:2], ("pre", 30))
        self.assertIsNone(tareas.due_alert(task('{"id":1,"date":"2026-10-27","time":"14:00","pre_done":[30]}'), now, ep))
        # 30, 10 y 5 min antes: a las 13:52 de una tarea de las 14:00 toca el de 10
        self.assertEqual(tareas.due_alert(task('{"id":1,"date":"2026-10-27","time":"14:00","pre_done":[30]}'), at(13, 52), ep)[:2], ("pre", 10))
        self.assertEqual(tareas.due_alert(task('{"id":1,"date":"2026-10-27","time":"14:00","pre_done":[30,10]}'), at(13, 56), ep)[:2], ("pre", 5))
        self.assertEqual(tareas.due_alert(task('{"id":1,"date":"2026-10-27","time":"13:00"}'), now, ep)[0], "due")
        self.assertIsNone(tareas.due_alert(task('{"id":1,"date":"2026-10-27","time":"13:00","last_alert":999990}'), now, ep))
        self.assertIsNone(tareas.due_alert(task('{"id":1,"date":"2026-10-27","time":"13:00","done":true}'), now, ep))
        # sin hora: aviso a las 09:00
        self.assertEqual(tareas.due(task('{"id":1,"date":"2026-10-27","time":""}')), at(9, 0))


if __name__ == "__main__":
    unittest.main()
