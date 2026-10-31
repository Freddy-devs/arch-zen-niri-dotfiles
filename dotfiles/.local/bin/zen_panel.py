"""zen_panel — lo común de los paneles de la barra (zen-audio, zen-network, zen-ram…).

GTK4 + gtk4-layer-shell: re-exec con la biblioteca precargada, ventana de capa, CSS y el ciclo de
vida (pidfile, SIGUSR1 de zen-toggle, segunda invocación, constructor que falla).
No importa Gtk al cargarse: zen-media --waybar lo usa sin abrir ventanas y sin gastar esa RAM.
"""
import os
import signal
import sys
import traceback

LAYER_LIB = "/usr/lib/libgtk4-layer-shell.so"
# márgenes de cada borde anclado si el panel no pide otros (pegado a la barra, a 12 px del lado)
MARGINS = {"TOP": 8, "RIGHT": 12, "LEFT": 12}


def preload_layer_shell():
    """Re-ejecuta el script con gtk4-layer-shell en LD_PRELOAD; llamar antes de importar Gtk."""
    # dibujo por CPU (cairo): para un panel chico basta y usa la mitad de RAM que el renderizador GL
    os.environ.setdefault("GSK_RENDERER", "cairo")
    # gtk4-layer-shell debe cargarse antes que libwayland; en Python solo se logra con LD_PRELOAD
    if LAYER_LIB not in os.environ.get("LD_PRELOAD", ""):
        os.environ["LD_PRELOAD"] = ":".join(filter(None, [LAYER_LIB, os.environ.get("LD_PRELOAD")]))
        os.execv(sys.executable, [sys.executable] + sys.argv)


# ---------- pidfile: zen-toggle y zen-close lo usan para encontrar el panel abierto ----------
def pidfile_path(name):
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), name + ".pid")


def write_pidfile(name):
    with open(pidfile_path(name), "w") as f:
        f.write(str(os.getpid()))


def remove_pidfile(name):
    try:
        os.unlink(pidfile_path(name))
    except FileNotFoundError:
        pass


# ---------- ventana ----------
def load_css(css):
    from gi.repository import Gdk, Gtk
    provider = Gtk.CssProvider()
    provider.load_from_string(css)
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider,
                                              Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def layer_window(app, namespace, css_class, layer="TOP", anchors=("TOP", "RIGHT"), margins=None,
                 on_escape=None):
    """Ventana de capa lista para set_child(). anchors/margins por nombre de borde ("TOP", "LEFT"…).

    Teclado EXCLUSIVE mientras esté abierta: con focus-follows-mouse de niri, lo escrito se iba a la
    ventana bajo el puntero. on_escape: lo que hace Esc (sin él, el panel pone su propio controlador).
    """
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Gdk", "4.0")
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gdk, Gtk, Gtk4LayerShell as Layer

    win = Gtk.ApplicationWindow(application=app)
    win.add_css_class(css_class)
    Layer.init_for_window(win)
    Layer.set_namespace(win, namespace)
    Layer.set_layer(win, getattr(Layer.Layer, layer))
    for edge in anchors:
        Layer.set_anchor(win, getattr(Layer.Edge, edge), True)
    if margins is None:
        margins = {e: MARGINS[e] for e in anchors if e in MARGINS}
    for edge, px in margins.items():
        Layer.set_margin(win, getattr(Layer.Edge, edge), px)
    Layer.set_keyboard_mode(win, Layer.KeyboardMode.EXCLUSIVE)

    if on_escape:
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", lambda c, k, *a: k == Gdk.KEY_Escape and on_escape())
        win.add_controller(keys)
    return win


# ---------- ciclo de vida ----------
def attach(app, name, factory):
    """Conecta a `app` (Gtk.Application o, en pruebas, Gio.Application) el ciclo de vida del panel.

    factory(app) arma el panel; debe tener show() y toggle(). La primera activación lo arma y lo
    muestra; las siguientes (otra llamada al script) y SIGUSR1 lo abren o cierran.
    """
    import gi
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import GLib, GLibUnix

    state = {}

    def on_usr1():
        # mientras se arma, o si el constructor falló, el aviso de cerrar se cumple saliendo
        state["panel"].toggle() if "panel" in state else app.quit()
        return True

    def activate(a):
        if "panel" in state:          # otra llamada al script: abrir/cerrar
            state["panel"].toggle()
            return
        a.hold()
        # pidfile y su limpieza lo primero: mientras se arma el panel, Super+C y zen-toggle ya lo
        # encuentran, y si algo falla después no queda un proceso invisible que no encuentren
        write_pidfile(name)
        a.connect("shutdown", lambda *_: remove_pidfile(name))
        # zen-toggle manda SIGUSR1 para cerrarlo; Esc o Super+C también
        sig = GLibUnix.signal_add(GLib.PRIORITY_HIGH, signal.SIGUSR1, on_usr1)
        a.connect("shutdown", lambda *_: GLib.source_remove(sig))
        try:
            state["panel"] = factory(a)
            state["panel"].show()
        except Exception:
            # servicio caído, sin pantalla…: sin esto quedaba vivo por el hold(), invisible
            traceback.print_exc()
            state.pop("panel", None)
            a.quit()

    app.connect("activate", activate)
    return state


def run(app_id, name, factory):
    """main() de un panel: Gtk.Application `app_id`, pidfile `name`.pid y el panel de factory(app)."""
    import gi
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gtk
    app = Gtk.Application(application_id=app_id)
    attach(app, name, factory)
    return app.run(None)
