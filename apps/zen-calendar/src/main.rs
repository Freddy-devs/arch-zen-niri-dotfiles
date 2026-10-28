// zen-calendar — calendario de la barra: reloj, mes con feriados del Perú, agenda y alarmas.
//
// Una sola instancia (GtkApplication):
//   zen-calendar --daemon          se lanza al iniciar niri; vigila las alarmas sin mostrar nada
//
// Solo queda en memoria mientras haya tareas pendientes: sin pendientes, sale al cerrar el panel
// (y "--daemon" termina al instante).
//   zen-calendar                   abre/cierra el panel en la pantalla enfocada (clic en el reloj)
//   zen-calendar --day AAAA-MM-DD  abre el panel en ese día
//
// Avisos de una tarea con hora H (sin hora = 09:00): 30 y 5 min antes una vez; desde H se repite
// cada 5 min hasta marcarla hecha. Clic en el aviso: abre el día · clic central: hecha / posponer.

mod holidays;
mod tasks;

use chrono::{Datelike, Duration, Local, NaiveDate, NaiveDateTime, Timelike};
use gtk::prelude::*;
use gtk::{gdk, gio, glib};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use holidays::{Calendar, Kind};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::path::PathBuf;
use std::rc::Rc;
use tasks::{Alert, Store, Task, ALLDAY, REMIND_EVERY, SNOOZE_MIN};

const APP_ID: &str = "pe.zen.Calendar";
const CHECK_EVERY: u32 = 30;
const SOUND_ALARM: &str = "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga";
const SOUND_PRE: &str = "/usr/share/sounds/freedesktop/stereo/message.oga";

const MONTHS: [&str; 12] =
    ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "setiembre", "octubre", "noviembre", "diciembre"];
const DAYS: [&str; 7] = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
const DAYS_SHORT: [&str; 7] = ["lu", "ma", "mi", "ju", "vi", "sá", "do"];

const CSS: &str = include_str!("style.css");

fn capitalize(s: &str) -> String {
    let mut c = s.chars();
    c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
}

fn long_date(d: NaiveDate) -> String {
    format!("{} {} de {}", DAYS[d.weekday().num_days_from_monday() as usize], d.day(), MONTHS[d.month0() as usize])
}

fn hour12(h: u32) -> u32 {
    if h.is_multiple_of(12) { 12 } else { h % 12 }
}

fn fmt_time(hhmm: &str) -> String {
    let (h, m) = hhmm.split_once(':').unwrap_or(("0", "0"));
    let h: u32 = h.parse().unwrap_or(0);
    format!("{}:{} {}", hour12(h), m, if h >= 12 { "pm" } else { "am" })
}

fn relative_days(d: NaiveDate, today: NaiveDate) -> String {
    match (d - today).num_days() {
        0 => "hoy".into(),
        1 => "mañana".into(),
        -1 => "ayer".into(),
        n if n > 0 => format!("en {n} días"),
        n => format!("hace {} días", -n),
    }
}

fn label(text: &str, css: &str) -> gtk::Label {
    let l = gtk::Label::builder().label(text).xalign(0.0).build();
    for c in css.split_whitespace() {
        l.add_css_class(c);
    }
    l
}

fn hbox(spacing: i32, css: &str) -> gtk::Box {
    let b = gtk::Box::new(gtk::Orientation::Horizontal, spacing);
    for c in css.split_whitespace() {
        b.add_css_class(c);
    }
    b
}

fn vbox(css: &str) -> gtk::Box {
    let b = gtk::Box::new(gtk::Orientation::Vertical, 0);
    for c in css.split_whitespace() {
        b.add_css_class(c);
    }
    b
}

fn clear(b: &gtk::Box) {
    while let Some(child) = b.first_child() {
        b.remove(&child);
    }
}

fn now_min() -> NaiveDateTime {
    let n = Local::now().naive_local();
    n.with_second(0).and_then(|n| n.with_nanosecond(0)).unwrap_or(n)
}

fn stamp(dt: NaiveDateTime) -> String {
    dt.format("%Y-%m-%d %H:%M").to_string()
}

fn play(sound: &str) {
    if std::path::Path::new(sound).exists() {
        let _ = std::process::Command::new("pw-play")
            .arg(sound)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    }
}

type TaskAction = fn(&Rc<App>, i64);

struct DayCell {
    button: gtk::Button,
    num: gtk::Label,
    dot_event: gtk::Label,
    dot_task: gtk::Label,
    day: Cell<NaiveDate>,
}

struct Ui {
    win: gtk::ApplicationWindow,
    time: gtk::Label,
    ampm: gtk::Label,
    date: gtk::Label,
    month: gtk::Label,
    year: gtk::Label,
    cells: Vec<DayCell>,
    day_title: gtk::Label,
    day_sub: gtk::Label,
    events: gtk::Box,
    tasks: gtk::Box,
    upcoming: gtk::Box,
    entry_title: gtk::Entry,
    entry_time: gtk::Entry,
}

struct App {
    app: gtk::Application,
    store: Store,
    cal: RefCell<Calendar>,
    extra_path: PathBuf,
    ui: RefCell<Option<Rc<Ui>>>,
    today: Cell<NaiveDate>,
    view: Cell<NaiveDate>,
    selected: Cell<NaiveDate>,
    was_active: Cell<bool>,
    hold: RefCell<Option<gio::ApplicationHoldGuard>>,
    notif: RefCell<Option<gio::DBusProxy>>,
    notif_by_task: RefCell<HashMap<i64, u32>>,
    task_by_notif: RefCell<HashMap<u32, i64>>,
}

impl App {
    fn ui(&self) -> Option<Rc<Ui>> {
        self.ui.borrow().clone()
    }

    fn visible(&self) -> bool {
        self.ui().is_some_and(|u| u.win.is_visible())
    }

    // ---------- ventana

    fn build(self: &Rc<Self>) -> Rc<Ui> {
        let win = gtk::ApplicationWindow::builder().application(&self.app).title("Calendario").build();
        win.add_css_class("zen-cal");
        win.init_layer_shell();
        win.set_namespace(Some("zen-calendar"));
        win.set_layer(Layer::Overlay);
        win.set_anchor(Edge::Top, true);
        win.set_anchor(Edge::Right, true);
        win.set_margin(Edge::Top, 4);
        win.set_margin(Edge::Right, 4);
        win.set_keyboard_mode(KeyboardMode::OnDemand);

        let keys = gtk::EventControllerKey::new();
        let me = self.clone();
        keys.connect_key_pressed(move |_, key, _, _| {
            if key == gdk::Key::Escape {
                me.hide();
                glib::Propagation::Stop
            } else {
                glib::Propagation::Proceed
            }
        });
        win.add_controller(keys);
        // se cierra al hacer clic fuera (pierde el foco), igual que un menú
        let me = self.clone();
        win.connect_is_active_notify(move |w| {
            if w.is_active() {
                me.was_active.set(true);
            } else if me.was_active.get() && w.is_visible() {
                me.hide();
            }
        });
        let me = self.clone();
        win.connect_close_request(move |_| {
            me.hide();
            glib::Propagation::Stop
        });

        // ---- columna izquierda: reloj + mes
        let left = vbox("col-left");
        let hero = hbox(0, "");
        let time = label("", "hero-time");
        let ampm = label("", "hero-ampm");
        ampm.set_valign(gtk::Align::End);
        hero.append(&time);
        hero.append(&ampm);
        left.append(&hero);
        let date = label("", "hero-date");
        left.append(&date);

        let head = hbox(4, "");
        let month = label("", "month-title");
        let year = label("", "month-year");
        year.set_hexpand(true);
        head.append(&month);
        head.append(&year);
        // los iconos van como escapes: pegados como carácter se pierden con facilidad al editar
        for (text, css, step, tip) in [
            ("\u{f0141}", "nav", -1, "Mes anterior"),
            ("Hoy", "nav today", 0, "Volver a hoy"),
            ("\u{f0142}", "nav", 1, "Mes siguiente"),
        ] {
            let b = gtk::Button::with_label(text);
            b.set_tooltip_text(Some(tip));
            for c in css.split_whitespace() {
                b.add_css_class(c);
            }
            let me = self.clone();
            b.connect_clicked(move |_| me.nav(step));
            head.append(&b);
        }
        left.append(&head);

        let grid = gtk::Grid::builder().column_homogeneous(true).build();
        for (i, name) in DAYS_SHORT.iter().enumerate() {
            let l = label(name, if i == 6 { "weekday sunday" } else { "weekday" });
            l.set_xalign(0.5);
            grid.attach(&l, i as i32, 0, 1, 1);
        }
        let mut cells = Vec::with_capacity(42);
        for n in 0..42 {
            let button = gtk::Button::new();
            button.add_css_class("day");
            let inner = vbox("");
            inner.set_valign(gtk::Align::Center);
            let num = label("", "num");
            num.set_xalign(0.5);
            let dots = hbox(0, "");
            dots.set_halign(gtk::Align::Center);
            let dot_event = label("●", "dot");
            let dot_task = label("●", "dot task");
            dots.append(&dot_event);
            dots.append(&dot_task);
            inner.append(&num);
            inner.append(&dots);
            button.set_child(Some(&inner));
            let me = self.clone();
            button.connect_clicked(move |_| me.pick(n));
            grid.attach(&button, n as i32 % 7, n as i32 / 7 + 1, 1, 1);
            cells.push(DayCell { button, num, dot_event, dot_task, day: Cell::new(self.today.get()) });
        }
        let scroll = gtk::EventControllerScroll::new(gtk::EventControllerScrollFlags::VERTICAL);
        let me = self.clone();
        scroll.connect_scroll(move |_, _, dy| {
            me.nav(if dy > 0.0 { 1 } else { -1 });
            glib::Propagation::Stop
        });
        grid.add_controller(scroll);
        left.append(&grid);

        let legend = hbox(4, "legend");
        for (css, text) in [("feriado", "feriado"), ("nolaborable", "no laborable"), ("fecha", "celebración"), ("task", "tarea")] {
            legend.append(&label("●", &format!("dot {css}")));
            legend.append(&label(&format!("{text}   "), ""));
        }
        left.append(&legend);

        // ---- columna derecha: día elegido, agenda, alta rápida, próximos feriados
        let right = vbox("col-right");
        right.set_size_request(300, -1);
        let day_title = label("", "day-title");
        let day_sub = label("", "day-sub");
        right.append(&day_title);
        right.append(&day_sub);
        let events = vbox("");
        right.append(&events);
        right.append(&label("AGENDA", "section"));
        let tasks = vbox("");
        let sw = gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .propagate_natural_height(true)
            .max_content_height(230)
            .child(&tasks)
            .build();
        right.append(&sw);

        let add = hbox(6, "add-row");
        let entry_title = gtk::Entry::builder().placeholder_text("Nueva tarea o alarma…").hexpand(true).build();
        let entry_time = gtk::Entry::builder().placeholder_text("hora").width_chars(7).max_width_chars(7).build();
        entry_time.set_tooltip_text(Some("15:30 · 3pm · vacío = todo el día (aviso 9:00 am)"));
        let add_btn = gtk::Button::with_label("Agregar");
        add_btn.add_css_class("add");
        for e in [&entry_title, &entry_time] {
            let me = self.clone();
            e.connect_activate(move |_| me.add_task());
        }
        let me = self.clone();
        add_btn.connect_clicked(move |_| me.add_task());
        add.append(&entry_title);
        add.append(&entry_time);
        add.append(&add_btn);
        right.append(&add);
        right.append(&label("PRÓXIMOS FERIADOS", "section"));
        let upcoming = vbox("");
        right.append(&upcoming);

        let panel = hbox(0, "panel");
        panel.append(&left);
        panel.append(&right);
        win.set_child(Some(&panel));

        let ui = Rc::new(Ui {
            win, time, ampm, date, month, year, cells, day_title, day_sub, events, tasks, upcoming, entry_title, entry_time,
        });
        *self.ui.borrow_mut() = Some(ui.clone());
        ui
    }

    fn focused_monitor() -> Option<gdk::Monitor> {
        let out = std::process::Command::new("niri").args(["msg", "-j", "focused-output"]).output().ok()?;
        let v: serde_json::Value = serde_json::from_slice(&out.stdout).ok()?;
        let name = v.get("name")?.as_str()?;
        let monitors = gdk::Display::default()?.monitors();
        (0..monitors.n_items())
            .filter_map(|i| monitors.item(i).and_downcast::<gdk::Monitor>())
            .find(|m| m.connector().as_deref() == Some(name))
    }

    fn show(self: &Rc<Self>, day: Option<NaiveDate>) {
        let ui = self.ui().unwrap_or_else(|| self.build());
        let today = Local::now().date_naive();
        self.today.set(today);
        let sel = day.unwrap_or(today);
        self.selected.set(sel);
        self.view.set(sel.with_day(1).unwrap());
        ui.win.set_monitor(Self::focused_monitor().as_ref());
        self.was_active.set(false);
        ui.entry_title.set_text("");
        ui.entry_time.set_text("");
        self.refresh();
        self.tick();
        ui.win.present();
    }

    fn hide(&self) {
        if let Some(ui) = self.ui() {
            ui.win.set_visible(false);
        }
        self.residency();
    }

    /// Residente solo con tareas pendientes (hay alarmas que vigilar); si no, sale con el panel cerrado.
    fn residency(&self) {
        if self.store.load().iter().any(|t| !t.done) {
            if self.hold.borrow().is_none() {
                *self.hold.borrow_mut() = Some(self.app.hold());
            }
        } else {
            self.hold.borrow_mut().take();
            if !self.visible() {
                self.app.quit();
            }
        }
    }

    fn toggle(self: &Rc<Self>) {
        if self.visible() { self.hide() } else { self.show(None) }
    }

    // ---------- datos -> widgets

    fn refresh(self: &Rc<Self>) {
        let Some(ui) = self.ui() else { return };
        let today = Local::now().date_naive();
        self.today.set(today);
        let tasks = self.store.load();
        self.cal.borrow_mut().extra = holidays::load_extra(&self.extra_path);
        let view = self.view.get();
        let selected = self.selected.get();

        ui.month.set_text(&capitalize(MONTHS[view.month0() as usize]));
        ui.year.set_text(&view.year().to_string());
        let start = view - Duration::days(view.weekday().num_days_from_monday() as i64);
        for (n, cell) in ui.cells.iter().enumerate() {
            let d = start + Duration::days(n as i64);
            cell.day.set(d);
            cell.num.set_text(&d.day().to_string());
            let evs = self.cal.borrow_mut().on(d);
            let kind = [Kind::Feriado, Kind::NoLaborable, Kind::Fecha].into_iter().find(|k| evs.iter().any(|(_, e)| e == k));
            let mut classes = vec!["day"];
            if d.month() != view.month() {
                classes.push("outside");
            }
            match d.weekday().num_days_from_monday() {
                5 => classes.push("weekend"),
                6 => classes.push("sunday"),
                _ => {}
            }
            if let Some(k @ (Kind::Feriado | Kind::NoLaborable)) = kind {
                classes.push(k.css());
            }
            if d == selected {
                classes.push("selected");
            }
            if d == today {
                classes.push("today");
            }
            cell.button.set_css_classes(&classes);
            cell.dot_event.set_css_classes(&["dot", kind.unwrap_or(Kind::Fecha).css()]);
            cell.dot_event.set_visible(kind.is_some());
            let iso = d.to_string();
            cell.dot_task.set_visible(tasks.iter().any(|t| !t.done && t.date == iso));
            let tip = evs.iter().map(|(n, _)| n.as_str()).collect::<Vec<_>>().join("\n");
            cell.button.set_tooltip_text((!tip.is_empty()).then_some(tip.as_str()));
        }
        self.refresh_day(&ui, &tasks);
        self.refresh_upcoming(&ui);
    }

    fn refresh_day(self: &Rc<Self>, ui: &Ui, tasks: &[Task]) {
        let d = self.selected.get();
        let today = self.today.get();
        ui.day_title.set_text(&capitalize(&long_date(d)));
        let rel = relative_days(d, today);
        ui.day_sub.set_text(&if matches!(rel.as_str(), "hoy" | "mañana" | "ayer") {
            format!("{} · {}", capitalize(&rel), d.year())
        } else {
            format!("{} · {}", d.year(), rel)
        });

        clear(&ui.events);
        for (name, kind) in self.cal.borrow_mut().on(d) {
            let ev = vbox(&format!("event {}", kind.css()));
            ev.append(&label(kind.title(), "kind"));
            let n = label(&name, "name");
            n.set_wrap(true);
            ev.append(&n);
            ui.events.append(&ev);
        }

        clear(&ui.tasks);
        let iso = d.to_string();
        let mut rows: Vec<&Task> = tasks.iter().filter(|t| t.date == iso).collect();
        if d == today {
            // lo vencido de días anteriores también se ve hoy
            rows.extend(tasks.iter().filter(|t| !t.done && !t.date.is_empty() && t.date < iso));
        }
        rows.sort_by_key(|t| (t.done, t.date.clone(), if t.time.is_empty() { ALLDAY.to_string() } else { t.time.clone() }));
        if rows.is_empty() {
            ui.tasks.append(&label("Sin tareas · escribe una abajo", "empty"));
        }
        let now = Local::now().naive_local();
        for t in rows {
            ui.tasks.append(&self.task_row(t, now));
        }
    }

    fn task_row(self: &Rc<Self>, t: &Task, now: NaiveDateTime) -> gtk::Box {
        let today = self.today.get();
        let due = t.due();
        let state = if t.done {
            "done"
        } else if due.is_some_and(|d| d <= now) {
            "overdue"
        } else if due.is_some_and(|d| d.date() == today) {
            "today"
        } else {
            "later"
        };
        let row = hbox(6, &format!("task {state}"));
        let info = vbox("");
        info.set_hexpand(true);
        info.set_valign(gtk::Align::Center);
        let title = label(&t.title, "t-title");
        title.set_ellipsize(gtk::pango::EllipsizeMode::End);
        title.set_max_width_chars(28);
        info.append(&title);
        let mut when = if t.time.is_empty() { "todo el día".to_string() } else { fmt_time(&t.time) };
        if t.date != self.selected.get().to_string()
            && let Some(d) = t.day()
        {
            when = format!("{} · {when}", long_date(d));
        }
        let meta = if t.done {
            format!("hecha · {when}")
        } else if state == "overdue" {
            format!("vencida · {when}")
        } else if let Some(s) = t.str_field("snooze_until") {
            format!("{when} · pospuesta hasta {}", s.get(s.len().saturating_sub(5)..).unwrap_or(s))
        } else {
            when
        };
        info.append(&label(&meta, "t-meta"));
        row.append(&info);

        let id = t.id;
        let mut buttons: Vec<(&str, &str, &str, TaskAction)> = Vec::new();
        if t.done {
            buttons.push(("󰕌", "undo", "Volver a pendiente", App::undone));
        } else {
            buttons.push(("󰄬", "ok", "Marcar hecha", App::done));
        }
        buttons.push(("󰆴", "del", "Eliminar", App::delete));
        for (icon, css, tip, f) in buttons {
            let b = gtk::Button::with_label(icon);
            b.set_tooltip_text(Some(tip));
            b.set_valign(gtk::Align::Center);
            b.add_css_class("t-btn");
            b.add_css_class(css);
            let me = self.clone();
            b.connect_clicked(move |_| f(&me, id));
            row.append(&b);
        }
        row
    }

    fn refresh_upcoming(&self, ui: &Ui) {
        clear(&ui.upcoming);
        let today = self.today.get();
        for (d, name, kind) in self.cal.borrow_mut().upcoming(today, 4) {
            let row = hbox(8, "upcoming-row");
            row.append(&label(&format!("{:02} {}", d.day(), &MONTHS[d.month0() as usize][..3]), &format!("up-date {}", kind.css())));
            let n = label(&name, "up-name");
            n.set_hexpand(true);
            n.set_ellipsize(gtk::pango::EllipsizeMode::End);
            n.set_max_width_chars(24);
            row.append(&n);
            let w = label(&relative_days(d, today), "up-when");
            w.set_xalign(1.0);
            row.append(&w);
            ui.upcoming.append(&row);
        }
    }

    fn tick(self: &Rc<Self>) {
        let Some(ui) = self.ui() else { return };
        if !ui.win.is_visible() {
            return;
        }
        let now = Local::now();
        let h = now.hour();
        ui.time.set_text(&format!("{}:{:02}", hour12(h), now.minute()));
        ui.ampm.set_text(if h >= 12 { "pm" } else { "am" });
        ui.date.set_text(&format!("{} de {}", capitalize(&long_date(now.date_naive())), now.year()));
        if now.date_naive() != self.today.get() {
            self.refresh();
        }
    }

    // ---------- acciones

    fn nav(self: &Rc<Self>, step: i32) {
        if step == 0 {
            let today = Local::now().date_naive();
            self.selected.set(today);
            self.view.set(today.with_day(1).unwrap());
        } else {
            let v = self.view.get();
            let m = v.month0() as i32 + step;
            self.view.set(NaiveDate::from_ymd_opt(v.year() + m.div_euclid(12), m.rem_euclid(12) as u32 + 1, 1).unwrap());
        }
        self.refresh();
    }

    fn pick(self: &Rc<Self>, n: usize) {
        let Some(ui) = self.ui() else { return };
        let d = ui.cells[n].day.get();
        self.selected.set(d);
        if d.month() != self.view.get().month() || d.year() != self.view.get().year() {
            self.view.set(d.with_day(1).unwrap());
        }
        self.refresh();
        ui.entry_title.grab_focus();
    }

    fn add_task(self: &Rc<Self>) {
        let Some(ui) = self.ui() else { return };
        let title = ui.entry_title.text().trim().to_string();
        ui.entry_time.remove_css_class("error");
        let Some(time) = tasks::parse_time(&ui.entry_time.text()) else {
            ui.entry_time.add_css_class("error");
            ui.entry_time.grab_focus();
            return;
        };
        if title.is_empty() {
            ui.entry_title.grab_focus();
            return;
        }
        let date = self.selected.get().to_string();
        self.store.update(|data| {
            let id = data.iter().map(|t| t.id).max().unwrap_or(0) + 1;
            let mut extra = serde_json::Map::new();
            extra.insert("created".into(), stamp(now_min()).into());
            data.push(Task { id, title, date, time, done: false, extra });
        });
        ui.entry_title.set_text("");
        ui.entry_time.set_text("");
        ui.entry_title.grab_focus();
        self.refresh();
        self.check_alarms();
        self.residency();
    }

    fn edit(self: &Rc<Self>, id: i64, f: impl Fn(&mut Task)) {
        self.store.update(|data| data.iter_mut().filter(|t| t.id == id).for_each(&f));
        if self.visible() {
            self.refresh();
        }
        self.residency();
    }

    fn done(self: &Rc<Self>, id: i64) {
        let at = stamp(now_min());
        self.edit(id, |t| {
            t.done = true;
            t.extra.insert("done_at".into(), at.clone().into());
            t.extra.remove("snooze_until");
        });
        self.close_notification(id);
    }

    fn undone(self: &Rc<Self>, id: i64) {
        self.edit(id, |t| {
            t.done = false;
            for k in ["done_at", "last_alert", "pre_done", "snooze_until"] {
                t.extra.remove(k);
            }
        });
    }

    fn delete(self: &Rc<Self>, id: i64) {
        self.store.update(|data| data.retain(|t| t.id != id));
        self.close_notification(id);
        self.refresh();
        self.residency();
    }

    fn snooze(self: &Rc<Self>, id: i64) {
        let until = stamp(now_min() + Duration::minutes(SNOOZE_MIN));
        self.edit(id, |t| {
            t.extra.insert("snooze_until".into(), until.clone().into());
            t.extra.remove("last_alert");
        });
        self.close_notification(id);
    }

    // ---------- alarmas

    fn check_alarms(self: &Rc<Self>) {
        let now = now_min();
        let epoch = Local::now().timestamp();
        // lectura sin lock primero: solo se escribe si de verdad hay algo que avisar
        if !self.store.load().iter().any(|t| tasks::due_alert(t, now, epoch).is_some()) {
            return;
        }
        let fire: Vec<(Task, Option<i64>)> = self.store.update(|data| {
            let mut fire = Vec::new();
            for t in data.iter_mut() {
                match tasks::due_alert(t, now, epoch) {
                    Some((Alert::Pre(first), hit)) => {
                        let mut sent = t.pre_done();
                        sent.extend(hit);
                        sent.sort_unstable();
                        sent.dedup();
                        t.extra.insert("pre_done".into(), sent.into());
                        fire.push((t.clone(), Some(first)));
                    }
                    Some((Alert::Due, _)) => {
                        t.extra.insert("last_alert".into(), epoch.into());
                        fire.push((t.clone(), None));
                    }
                    None => {}
                }
            }
            fire
        });
        for (t, pre) in &fire {
            self.alert(t, *pre, now);
        }
        if !fire.is_empty() && self.visible() {
            self.refresh();
        }
    }

    fn alert(&self, t: &Task, pre: Option<i64>, now: NaiveDateTime) {
        let Some(due) = t.due() else { return };
        let hour = if t.time.is_empty() { "todo el día".to_string() } else { fmt_time(&t.time) };
        let when = format!("{} · {hour}", long_date(due.date()));
        let title = glib::markup_escape_text(&t.title);
        let snooze = format!("Posponer {SNOOZE_MIN} min");
        let (summary, body, actions, sound) = match pre {
            Some(_) => (
                format!("En {} min", (due - now).num_minutes().max(1)),
                format!("<b>{title}</b>\n{when}"),
                vec!["default", "Abrir calendario", "done", "Marcar hecha"],
                SOUND_PRE,
            ),
            None => {
                let ago = match (now - due).num_minutes() {
                    l if l < 1 => "ahora".to_string(),
                    l if l < 60 => format!("hace {l} min"),
                    l if l < 1440 => format!("hace {} h", l / 60),
                    l => format!("hace {} d", l / 1440),
                };
                (
                    "Tarea pendiente".to_string(),
                    format!("<b>{title}</b>\n{when} · {ago}\n<small>se repite cada {} min hasta marcarla</small>", REMIND_EVERY / 60),
                    vec!["default", "Abrir calendario", "done", "Marcar hecha", "snooze", snooze.as_str()],
                    SOUND_ALARM,
                )
            }
        };
        self.notify(t.id, &summary, &body, &actions);
        play(sound);
    }

    fn setup_notifications(self: &Rc<Self>) {
        let proxy = gio::DBusProxy::for_bus_sync(
            gio::BusType::Session,
            gio::DBusProxyFlags::NONE,
            None,
            "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications",
            gio::Cancellable::NONE,
        );
        let Ok(proxy) = proxy else { return };
        let me = Rc::downgrade(self);
        proxy.connect_local("g-signal", false, move |args| {
            let me = me.upgrade()?;
            let signal: String = args[2].get().ok()?;
            let params: glib::Variant = args[3].get().ok()?;
            me.on_notif_signal(&signal, &params);
            None
        });
        *self.notif.borrow_mut() = Some(proxy);
    }

    fn notify(&self, id: i64, summary: &str, body: &str, actions: &[&str]) {
        let Some(proxy) = self.notif.borrow().clone() else { return };
        let replaces = self.notif_by_task.borrow().get(&id).copied().unwrap_or(0);
        let hints = glib::VariantDict::new(None);
        hints.insert_value("urgency", &2u8.to_variant());
        hints.insert_value("category", &"x-zen.alarm".to_variant());
        let actions: Vec<String> = actions.iter().map(|s| s.to_string()).collect();
        let params = (
            "Calendario",
            replaces,
            "x-office-calendar",
            summary,
            body,
            actions,
            hints.end(),
            0i32,
        )
            .to_variant();
        let Ok(res) = proxy.call_sync("Notify", Some(&params), gio::DBusCallFlags::NONE, 2000, gio::Cancellable::NONE) else {
            return;
        };
        if let Some((nid,)) = res.get::<(u32,)>() {
            self.notif_by_task.borrow_mut().insert(id, nid);
            self.task_by_notif.borrow_mut().insert(nid, id);
        }
    }

    fn close_notification(&self, id: i64) {
        let Some(nid) = self.notif_by_task.borrow_mut().remove(&id) else { return };
        self.task_by_notif.borrow_mut().remove(&nid);
        if let Some(proxy) = self.notif.borrow().clone() {
            let _ = proxy.call_sync("CloseNotification", Some(&(nid,).to_variant()), gio::DBusCallFlags::NONE, 2000, gio::Cancellable::NONE);
        }
    }

    fn on_notif_signal(self: &Rc<Self>, signal: &str, params: &glib::Variant) {
        let nid = params.child_value(0).get::<u32>().unwrap_or(0);
        let Some(id) = self.task_by_notif.borrow().get(&nid).copied() else { return };
        match signal {
            "NotificationClosed" => {
                self.task_by_notif.borrow_mut().remove(&nid);
                self.notif_by_task.borrow_mut().remove(&id);
            }
            "ActionInvoked" => match params.child_value(1).get::<String>().as_deref() {
                Some("done") => self.done(id),
                Some("snooze") => self.snooze(id),
                Some("default") => {
                    let day = self.store.load().into_iter().find(|t| t.id == id).and_then(|t| t.day());
                    self.show(day);
                }
                _ => {}
            },
            _ => {}
        }
    }
}

fn main() -> glib::ExitCode {
    let app = gtk::Application::new(Some(APP_ID), gio::ApplicationFlags::HANDLES_COMMAND_LINE);
    let today = Local::now().date_naive();
    let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| tasks::home().join(".config"));
    let me = Rc::new(App {
        app: app.clone(),
        store: Store::new(),
        cal: RefCell::new(Calendar::default()),
        extra_path: config.join("zen-calendar/feriados.json"),
        ui: RefCell::new(None),
        today: Cell::new(today),
        view: Cell::new(today.with_day(1).unwrap()),
        selected: Cell::new(today),
        was_active: Cell::new(false),
        hold: RefCell::new(None),
        notif: RefCell::new(None),
        notif_by_task: RefCell::new(HashMap::new()),
        task_by_notif: RefCell::new(HashMap::new()),
    });

    let m = me.clone();
    app.connect_startup(move |_| {
        let provider = gtk::CssProvider::new();
        provider.load_from_string(CSS);
        if let Some(display) = gdk::Display::default() {
            gtk::style_context_add_provider_for_display(&display, &provider, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
        m.setup_notifications();
        let a = m.clone();
        glib::timeout_add_seconds_local(CHECK_EVERY, move || {
            a.check_alarms();
            // las tareas pueden marcarse hechas desde otro lado (script Tasks)
            a.residency();
            glib::ControlFlow::Continue
        });
        let a = m.clone();
        glib::timeout_add_seconds_local(1, move || {
            a.tick();
            glib::ControlFlow::Continue
        });
        let a = m.clone();
        glib::idle_add_local_once(move || a.check_alarms());
    });

    let m = me.clone();
    app.connect_command_line(move |_, cmd| {
        let args: Vec<String> = cmd.arguments().iter().skip(1).map(|a| a.to_string_lossy().into_owned()).collect();
        if args.iter().any(|a| a == "--daemon") {
            m.residency();
            return glib::ExitCode::SUCCESS;
        }
        let day = args.iter().position(|a| a == "--day").and_then(|i| args.get(i + 1)).and_then(|s| s.parse().ok());
        match day {
            Some(d) => m.show(Some(d)),
            None => m.toggle(),
        }
        glib::ExitCode::SUCCESS
    });

    app.run()
}
