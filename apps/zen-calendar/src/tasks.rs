// Tareas en ~/.local/share/tasks/tasks.json (mismo formato que el script Tasks de bspwm).
// Los campos desconocidos se conservan tal cual al reescribir el archivo.

use chrono::{Duration, NaiveDate, NaiveDateTime, NaiveTime};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::fs::{self, File};
use std::io::Write;
use std::path::PathBuf;

pub const ALLDAY: &str = "09:00"; // hora de aviso de las tareas sin hora
pub const REMIND_EVERY: i64 = 300; // segundos entre avisos de una tarea vencida
pub const SNOOZE_MIN: i64 = 15;
pub const PRE_ALERTS: [i64; 3] = [30, 10, 5]; // minutos antes de la hora

#[derive(Serialize, Deserialize, Clone)]
pub struct Task {
    pub id: i64,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub date: String,
    #[serde(default)]
    pub time: String,
    #[serde(default)]
    pub done: bool,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl Task {
    pub fn day(&self) -> Option<NaiveDate> {
        self.date.parse().ok()
    }

    pub fn due(&self) -> Option<NaiveDateTime> {
        let t = if self.time.is_empty() { ALLDAY } else { &self.time };
        Some(self.day()?.and_time(NaiveTime::parse_from_str(t, "%H:%M").ok()?))
    }

    pub fn str_field(&self, k: &str) -> Option<&str> {
        self.extra.get(k).and_then(Value::as_str)
    }

    pub fn last_alert(&self) -> i64 {
        self.extra.get("last_alert").and_then(Value::as_i64).unwrap_or(0)
    }

    pub fn pre_done(&self) -> Vec<i64> {
        self.extra.get("pre_done").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_i64).collect()).unwrap_or_default()
    }
}

pub enum Alert {
    Pre(i64), // minutos antes
    Due,
}

/// Qué aviso toca ahora para la tarea, si alguno. `hit` devuelve todas las etapas alcanzadas.
pub fn due_alert(t: &Task, now: NaiveDateTime, epoch: i64) -> Option<(Alert, Vec<i64>)> {
    if t.done {
        return None;
    }
    let due = t.due()?;
    if due > now {
        let sent = t.pre_done();
        let hit: Vec<i64> = PRE_ALERTS.iter().copied().filter(|m| !sent.contains(m) && now + Duration::minutes(*m) >= due).collect();
        let first = *hit.iter().min()?;
        return Some((Alert::Pre(first), hit));
    }
    let snooze = t.str_field("snooze_until").unwrap_or("");
    if snooze <= now.format("%Y-%m-%d %H:%M").to_string().as_str() && t.last_alert() + REMIND_EVERY <= epoch {
        return Some((Alert::Due, Vec::new()));
    }
    None
}

pub struct Store {
    dir: PathBuf,
}

impl Store {
    pub fn new() -> Self {
        let base = std::env::var_os("XDG_DATA_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".local/share"));
        Store { dir: base.join("tasks") }
    }

    fn db(&self) -> PathBuf {
        self.dir.join("tasks.json")
    }

    pub fn load(&self) -> Vec<Task> {
        fs::read_to_string(self.db()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
    }

    /// Lee, modifica y escribe de forma atómica con el mismo lock que el script Tasks.
    pub fn update<R>(&self, f: impl FnOnce(&mut Vec<Task>) -> R) -> R {
        let _ = fs::create_dir_all(&self.dir);
        let lock = File::create(self.dir.join("tasks.json.lock")).ok();
        if let Some(l) = &lock {
            let _ = l.lock();
        }
        let mut data = self.load();
        let r = f(&mut data);
        let tmp = self.dir.join(format!(".tasks.{}", std::process::id()));
        let ok = File::create(&tmp)
            .and_then(|mut file| {
                file.write_all(serde_json::to_string_pretty(&data).unwrap_or_else(|_| "[]".into()).as_bytes())?;
                file.sync_all()
            })
            .is_ok();
        if ok {
            let _ = fs::rename(&tmp, self.db());
        } else {
            let _ = fs::remove_file(&tmp);
        }
        r
    }
}

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn avisos() {
        let task = |json: &str| -> Task { serde_json::from_str(json).unwrap() };
        let now = NaiveDate::from_ymd_opt(2026, 10, 27).unwrap().and_hms_opt(13, 40, 0).unwrap();
        let ep = 1_000_000;
        assert!(matches!(due_alert(&task(r#"{"id":1,"date":"2026-10-27","time":"14:00"}"#), now, ep), Some((Alert::Pre(30), _))));
        assert!(due_alert(&task(r#"{"id":1,"date":"2026-10-27","time":"14:00","pre_done":[30]}"#), now, ep).is_none());
        // 30, 10 y 5 min antes: a las 13:52 de una tarea de las 14:00 toca el de 10
        let at = |h, m| NaiveDate::from_ymd_opt(2026, 10, 27).unwrap().and_hms_opt(h, m, 0).unwrap();
        assert!(matches!(due_alert(&task(r#"{"id":1,"date":"2026-10-27","time":"14:00","pre_done":[30]}"#), at(13, 52), ep), Some((Alert::Pre(10), _))));
        assert!(matches!(due_alert(&task(r#"{"id":1,"date":"2026-10-27","time":"14:00","pre_done":[30,10]}"#), at(13, 56), ep), Some((Alert::Pre(5), _))));
        assert!(matches!(due_alert(&task(r#"{"id":1,"date":"2026-10-27","time":"13:00"}"#), now, ep), Some((Alert::Due, _))));
        assert!(due_alert(&task(r#"{"id":1,"date":"2026-10-27","time":"13:00","last_alert":999990}"#), now, ep).is_none());
        assert!(due_alert(&task(r#"{"id":1,"date":"2026-10-27","time":"13:00","done":true}"#), now, ep).is_none());
        // los campos desconocidos sobreviven
        let t = task(r#"{"id":1,"date":"2026-10-27","time":"","created":"x","otro":5}"#);
        assert!(serde_json::to_string(&t).unwrap().contains("\"otro\":5"));
    }
}
