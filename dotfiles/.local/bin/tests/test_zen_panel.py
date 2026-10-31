"""Pruebas de zen_panel sin pantalla: pidfile, constructor que falla, SIGUSR1 y segunda invocación.

Usa Gio.Application (no necesita pantalla ni D-Bus con NON_UNIQUE) con un panel de mentira.
  python3 -m unittest discover -s dotfiles/.local/bin/tests     (o pytest, si está instalado)
"""
import os
import signal
import subprocess
import sys
import tempfile
import unittest

BIN = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
sys.path.insert(0, BIN)
import zen_panel  # noqa: E402

import gi  # noqa: E402

gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME = "zen-prueba"


class FakePanel:
    """Panel de mentira: cuenta show()/toggle(); toggle() cierra como los de verdad (app.quit)."""

    def __init__(self, app, log):
        self.app, self.log = app, log
        log.append(("pidfile al armar", os.path.exists(zen_panel.pidfile_path(NAME))))

    def show(self):
        self.log.append("show")

    def toggle(self):
        self.log.append("toggle")
        self.app.quit()


class PanelTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old_runtime = os.environ.get("XDG_RUNTIME_DIR")
        os.environ["XDG_RUNTIME_DIR"] = self.tmp.name
        self.log = []

    def tearDown(self):
        if self.old_runtime is None:
            os.environ.pop("XDG_RUNTIME_DIR", None)
        else:
            os.environ["XDG_RUNTIME_DIR"] = self.old_runtime
        self.tmp.cleanup()

    def run_app(self, factory, after_start=None):
        """Corre la app hasta que salga; tope de 5 s por si el panel se queda vivo (falla la prueba)."""
        app = Gio.Application(application_id="pe.zen.Prueba", flags=Gio.ApplicationFlags.NON_UNIQUE)
        zen_panel.attach(app, NAME, factory)
        timed_out = []

        def guard():
            timed_out.append(True)
            app.quit()
            return False
        guard_id = GLib.timeout_add_seconds(5, guard)
        if after_start:
            GLib.idle_add(lambda: after_start(app) and False)
        app.run(None)
        if not timed_out:
            GLib.source_remove(guard_id)
        self.assertFalse(timed_out, "el proceso seguía vivo: no salió")
        return app

    def pidfile(self):
        return zen_panel.pidfile_path(NAME)

    def test_pidfile_written_first_and_removed_on_exit(self):
        seen = []

        def factory(app):
            with open(self.pidfile()) as f:
                seen.append(f.read())
            return FakePanel(app, self.log)
        self.run_app(factory, after_start=lambda app: app.quit())
        self.assertEqual(seen, [str(os.getpid())])
        self.assertFalse(os.path.exists(self.pidfile()))

    def test_failing_constructor_quits_and_removes_pidfile(self):
        def factory(app):
            raise RuntimeError("servicio caído (a propósito, en la prueba)")
        # el traceback va a stderr como en los paneles; aquí se silencia
        with open(os.devnull, "w") as null:
            old, sys.stderr = sys.stderr, null
            try:
                self.run_app(factory)
            finally:
                sys.stderr = old
        self.assertFalse(os.path.exists(self.pidfile()))

    def test_sigusr1_toggles(self):
        self.run_app(lambda app: FakePanel(app, self.log),
                     after_start=lambda app: os.kill(os.getpid(), signal.SIGUSR1))
        self.assertEqual(self.log, [("pidfile al armar", True), "show", "toggle"])
        self.assertFalse(os.path.exists(self.pidfile()))

    def test_sigusr1_while_building_closes_after(self):
        # zen-toggle puede mandar SIGUSR1 mientras el panel se arma: no lo mata, lo cierra al terminar
        def factory(app):
            os.kill(os.getpid(), signal.SIGUSR1)
            return FakePanel(app, self.log)
        self.run_app(factory)
        self.assertEqual(self.log, [("pidfile al armar", True), "show", "toggle"])
        self.assertFalse(os.path.exists(self.pidfile()))

    def test_second_activation_toggles(self):
        self.run_app(lambda app: FakePanel(app, self.log), after_start=lambda app: app.activate())
        self.assertEqual(self.log, [("pidfile al armar", True), "show", "toggle"])


class PreloadTest(unittest.TestCase):
    def test_reexec_adds_layer_shell(self):
        # el re-exec repite sys.argv: hace falta un script de verdad (con -c se perdería el código)
        env = {k: v for k, v in os.environ.items() if k not in ("LD_PRELOAD", "GSK_RENDERER")}
        with tempfile.NamedTemporaryFile("w", suffix=".py") as script:
            script.write("import os, sys\nsys.path.insert(0, %r)\nimport zen_panel\n"
                         "zen_panel.preload_layer_shell()\n"
                         "print(os.environ['LD_PRELOAD'], os.environ['GSK_RENDERER'])\n" % BIN)
            script.flush()
            out = subprocess.run([sys.executable, script.name], env=env, capture_output=True, text=True,
                                 timeout=20).stdout.split()
        self.assertEqual(out, [zen_panel.LAYER_LIB, "cairo"])

if __name__ == "__main__":
    unittest.main()
