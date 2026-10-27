// Feriados nacionales del Perú, calculados para cualquier año, más los días no laborables
// que el usuario agregue en ~/.config/zen-calendar/feriados.json.

use chrono::{Datelike, Duration, NaiveDate, Weekday};
use std::collections::HashMap;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Feriado,
    NoLaborable,
    Fecha, // celebración: se trabaja
}

impl Kind {
    pub fn css(self) -> &'static str {
        match self {
            Kind::Feriado => "feriado",
            Kind::NoLaborable => "nolaborable",
            Kind::Fecha => "fecha",
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Kind::Feriado => "FERIADO",
            Kind::NoLaborable => "DÍA NO LABORABLE",
            Kind::Fecha => "CELEBRACIÓN",
        }
    }
}

pub type Events = HashMap<NaiveDate, Vec<(String, Kind)>>;

// (mes, día, nombre, feriado desde el año)
const FIXED: &[(u32, u32, &str, i32)] = &[
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
];

fn easter(y: i32) -> NaiveDate {
    let a = y % 19;
    let (b, c) = (y / 100, y % 100);
    let (d, e) = (b / 4, b % 4);
    let f = (b + 8) / 25;
    let g = (b - f + 1) / 3;
    let h = (19 * a + b - d - g + 15) % 30;
    let (i, k) = (c / 4, c % 4);
    let l = (32 + 2 * e + 2 * i - h - k) % 7;
    let m = (a + 11 * h + 22 * l) / 451;
    let n = h + l - 7 * m + 114;
    NaiveDate::from_ymd_opt(y, (n / 31) as u32, (n % 31 + 1) as u32).unwrap()
}

fn nth_weekday(y: i32, month: u32, wd: Weekday, n: u8) -> NaiveDate {
    NaiveDate::from_weekday_of_month_opt(y, month, wd, n).unwrap()
}

fn ymd(y: i32, m: u32, d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).unwrap()
}

pub fn year_events(y: i32) -> Events {
    let mut ev: Events = HashMap::new();
    let mut add = |d: NaiveDate, name: &str, kind: Kind| ev.entry(d).or_default().push((name.to_string(), kind));
    for &(m, d, name, since) in FIXED {
        if y >= since {
            add(ymd(y, m, d), name, Kind::Feriado);
        }
    }
    let sunday = easter(y);
    add(sunday - Duration::days(3), "Jueves Santo", Kind::Feriado);
    add(sunday - Duration::days(2), "Viernes Santo", Kind::Feriado);
    add(sunday, "Domingo de Resurrección", Kind::Fecha);
    add(nth_weekday(y, 5, Weekday::Sun, 2), "Día de la Madre", Kind::Fecha);
    add(nth_weekday(y, 6, Weekday::Sun, 3), "Día del Padre", Kind::Fecha);
    add(ymd(y, 6, 24), "Inti Raymi · Día del Campesino", Kind::Fecha);
    add(ymd(y, 10, 31), "Día de la Canción Criolla", Kind::Fecha);
    add(ymd(y, 12, 24), "Nochebuena", Kind::Fecha);
    add(ymd(y, 12, 31), "Fin de año", Kind::Fecha);
    ev
}

/// [{"date": "2026-12-24", "name": "Día no laborable", "kind": "nolaborable|feriado|fecha"}]
pub fn load_extra(path: &std::path::Path) -> Events {
    let mut ev: Events = HashMap::new();
    let Ok(text) = std::fs::read_to_string(path) else { return ev };
    let Ok(serde_json::Value::Array(items)) = serde_json::from_str(&text) else { return ev };
    for it in items {
        let Some(d) = it.get("date").and_then(|v| v.as_str()).and_then(|s| s.parse().ok()) else { continue };
        let name = it.get("name").and_then(|v| v.as_str()).unwrap_or("Día no laborable");
        let kind = match it.get("kind").and_then(|v| v.as_str()) {
            Some("feriado") => Kind::Feriado,
            Some("fecha") => Kind::Fecha,
            _ => Kind::NoLaborable,
        };
        ev.entry(d).or_default().push((name.to_string(), kind));
    }
    ev
}

/// Caché por año + extras del usuario.
#[derive(Default)]
pub struct Calendar {
    years: HashMap<i32, Events>,
    pub extra: Events,
}

impl Calendar {
    pub fn on(&mut self, d: NaiveDate) -> Vec<(String, Kind)> {
        let mut v = self.years.entry(d.year()).or_insert_with(|| year_events(d.year())).get(&d).cloned().unwrap_or_default();
        v.extend(self.extra.get(&d).cloned().unwrap_or_default());
        v
    }

    /// Próximos feriados y días no laborables desde `from` (inclusive).
    pub fn upcoming(&mut self, from: NaiveDate, n: usize) -> Vec<(NaiveDate, String, Kind)> {
        let mut out = Vec::new();
        let mut d = from;
        let end = from + Duration::days(400);
        while d <= end && out.len() < n {
            for (name, kind) in self.on(d) {
                if kind != Kind::Fecha && out.len() < n {
                    out.push((d, name, kind));
                }
            }
            d += Duration::days(1);
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn semana_santa() {
        assert_eq!(easter(2026), ymd(2026, 4, 5));
        assert_eq!(easter(2027), ymd(2027, 3, 28));
        let ev = year_events(2026);
        assert_eq!(ev.values().flatten().filter(|(_, k)| *k == Kind::Feriado).count(), 16);
        assert!(ev[&ymd(2026, 4, 2)].iter().any(|(n, _)| n == "Jueves Santo"));
    }
}
