// Lógica pura, sin APIs del navegador: la usan background.js, popup.js, opciones.js y las pruebas.

export const MIN_MINUTOS = 0.5; // la alarma corre cada 30 s: menos no tendría efecto
export const MAX_MINUTOS = 7 * 24 * 60;
export const MAX_REGLAS = 500;
const MAX_PATRON = 300;
const MAX_URLS_VENTANA = 50;
const CADUCA_VENTANA_MS = 30 * 24 * 60 * 60 * 1000;

// Notificaciones en tiempo real: se siembran como reglas "nunca" y se pueden editar.
export const SIEMPRE_ACTIVOS = [
  "web.whatsapp.com",
  "teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft",
  "outlook.office.com", "outlook.office365.com", "outlook.live.com", "outlook.cloud.microsoft",
];

export function configInicial() {
  return {
    version: 2,
    activo: true,
    minutos: 30,
    respetarFijadas: false,
    reglas: SIEMPRE_ACTIVOS.map(patron => ({ patron, minutos: null })),
  };
}

// null = nunca dormir. Devuelve undefined si el valor no sirve.
export function normalizarMinutos(valor) {
  if (valor === null) return null;
  if (typeof valor === "string" && valor.trim() === "") return undefined;
  const n = Number(valor);
  if (!Number.isFinite(n) || n < MIN_MINUTOS || n > MAX_MINUTOS) return undefined;
  return Math.round(n * 100) / 100;
}

// "HTTPS://WWW.Ejemplo.com/a/b/?x=1#y" -> "ejemplo.com/a/b". Devuelve null si no es válido.
export function normalizarPatron(texto) {
  if (typeof texto !== "string") return null;
  let p = texto.trim();
  if (!p || p.length > MAX_PATRON) return null;
  p = p.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").split(/[?#]/)[0];
  const corte = p.indexOf("/");
  let host = corte < 0 ? p : p.slice(0, corte);
  let ruta = corte < 0 ? "" : p.slice(corte);
  if (!host) return null;

  // Se valida a mano: Chromium acepta hosts con espacios en new URL() y Node no.
  if (!/^[\p{L}\p{N}.*:\[\]_-]+$/u.test(host)) return null;
  if (host.includes("*")) {
    host = host.toLowerCase();
    if (/^\*+$/.test(host) && !ruta) return null;
  } else {
    try {
      const u = new URL("https://" + host);
      if (u.username || u.password || !u.hostname) return null;
      host = u.host;
    } catch {
      return null;
    }
  }
  host = host.replace(/^www\./, "");
  ruta = ruta.replace(/\*+/g, "*").replace(/\/+$/, "");
  return host + ruta;
}

// Comodines sin expresiones regulares: el tiempo no se dispara con patrones raros.
function encajaComodin(patron, texto) {
  let p = 0, t = 0, estrella = -1, marca = 0;
  while (t < texto.length) {
    if (p < patron.length && patron[p] === "*") {
      estrella = p++;
      marca = t;
    } else if (p < patron.length && patron[p] === texto[t]) {
      p++;
      t++;
    } else if (estrella >= 0) {
      p = estrella + 1;
      t = ++marca;
    } else {
      return false;
    }
  }
  while (p < patron.length && patron[p] === "*") p++;
  return p === patron.length;
}

function hostCoincide(patronHost, url) {
  const candidatos = [url.host, url.hostname];
  if (patronHost.includes("*")) {
    return candidatos.some(h => encajaComodin(patronHost, h) || encajaComodin(patronHost, h.replace(/^www\./, "")));
  }
  return candidatos.some(h => h === patronHost || h.endsWith("." + patronHost));
}

function rutaCoincide(patronRuta, ruta) {
  if (!patronRuta) return true;
  if (patronRuta.includes("*")) return encajaComodin(patronRuta, ruta) || encajaComodin(patronRuta + "/*", ruta);
  // "/foo" abarca "/foo" y "/foo/bar", pero no "/foobar"
  return ruta === patronRuta || ruta.startsWith(patronRuta + "/");
}

function aUrl(texto) {
  try {
    const u = new URL(texto);
    return u.protocol === "http:" || u.protocol === "https:" ? u : null;
  } catch {
    return null;
  }
}

export function coincide(patron, urlTexto) {
  const url = aUrl(urlTexto);
  if (!url) return false;
  const corte = patron.indexOf("/");
  const host = corte < 0 ? patron : patron.slice(0, corte);
  const ruta = corte < 0 ? "" : patron.slice(corte);
  return hostCoincide(host, url) && rutaCoincide(ruta, url.pathname);
}

// Con comodines cuenta menos: "github.com/a/b" gana a "github.com/*/b" y este a "github.com".
function especificidad(patron) {
  const corte = patron.indexOf("/");
  const host = corte < 0 ? patron : patron.slice(0, corte);
  const ruta = corte < 0 ? "" : patron.slice(corte);
  const peso = s => s.replace(/\*/g, "").length;
  return (ruta ? 100000 : 0) + peso(ruta) * 100 + peso(host);
}

export function reglaDeUrl(reglas, url) {
  let mejor = null, puntos = -1;
  for (const regla of reglas) {
    if (!coincide(regla.patron, url)) continue;
    const p = especificidad(regla.patron);
    if (p > puntos) {
      mejor = regla;
      puntos = p;
    }
  }
  return mejor;
}

// Prioridad: regla de página o sitio > regla de ventana > valor general.
// minutos === null significa que esa pestaña nunca se duerme.
export function decidir(config, url, reglaVentana) {
  const regla = reglaDeUrl(config.reglas, url);
  if (regla) return { minutos: regla.minutos, origen: "regla", patron: regla.patron };
  if (reglaVentana) return { minutos: reglaVentana.minutos, origen: "ventana" };
  return { minutos: config.minutos, origen: "general" };
}

// Qué regla crearía el popup para una URL. null en páginas internas del navegador.
export function alcancesDeUrl(urlTexto) {
  const url = aUrl(urlTexto);
  if (!url) return null;
  const sitio = normalizarPatron(url.host);
  if (!sitio) return null;
  const ruta = url.pathname.replace(/\/+$/, "");
  return { sitio, pagina: ruta ? normalizarPatron(url.host + url.pathname) : sitio };
}

// Agrega o reemplaza; minutos === undefined la borra.
export function aplicarRegla(reglas, patron, minutos) {
  const resto = reglas.filter(r => r.patron !== patron);
  return minutos === undefined ? resto : [...resto, { patron, minutos }];
}

// Toda configuración (guardada o importada) pasa por aquí: lo inválido se descarta.
export function sanearConfig(crudo) {
  const base = configInicial();
  if (!crudo || typeof crudo !== "object") return base;
  const minutos = normalizarMinutos(crudo.minutos);
  const reglas = new Map();
  if (Array.isArray(crudo.reglas)) {
    for (const r of crudo.reglas.slice(0, MAX_REGLAS)) {
      const patron = normalizarPatron(r?.patron);
      const min = normalizarMinutos(r?.minutos);
      if (patron && min !== undefined) reglas.set(patron, { patron, minutos: min });
    }
  }
  return {
    version: base.version,
    activo: typeof crudo.activo === "boolean" ? crudo.activo : base.activo,
    minutos: minutos === undefined || minutos === null ? base.minutos : minutos,
    respetarFijadas: crudo.respetarFijadas === true,
    reglas: Array.isArray(crudo.reglas) ? [...reglas.values()] : base.reglas,
  };
}

export function urlsDeVentana(tabs) {
  const urls = new Set();
  for (const tab of tabs) {
    const texto = tab.url || tab.pendingUrl || "";
    if (aUrl(texto)) urls.add(texto.split("#")[0]);
    if (urls.size >= MAX_URLS_VENTANA) break;
  }
  return [...urls].sort();
}

// El navegador cambia los id de ventana al reiniciar: una ventana restaurada se reconoce porque
// comparte al menos la mitad de sus pestañas con la que tenía la regla.
// libres: reglas sin ventana; abiertas: [{id, urls}] sin regla. Devuelve [[idRegla, idVentana]].
export function emparejarVentanas(libres, abiertas, enArranque) {
  const candidatos = [];
  for (const regla of libres) {
    const guardadas = new Set(regla.urls);
    for (const ventana of abiertas) {
      const comunes = ventana.urls.filter(u => guardadas.has(u)).length;
      if (!comunes) continue;
      const parecido = comunes / Math.max(guardadas.size, ventana.urls.length);
      // Pasado el arranque, una sola pestaña igual no basta para reconocer una ventana.
      if (parecido >= 0.5 && (enArranque || comunes >= 2)) {
        candidatos.push({ regla: regla.id, ventana: ventana.id, parecido });
      }
    }
  }
  candidatos.sort((a, b) => b.parecido - a.parecido);
  const pares = [], reglasUsadas = new Set(), ventanasUsadas = new Set();
  for (const c of candidatos) {
    if (reglasUsadas.has(c.regla) || ventanasUsadas.has(c.ventana)) continue;
    reglasUsadas.add(c.regla);
    ventanasUsadas.add(c.ventana);
    pares.push([c.regla, c.ventana]);
  }
  return pares;
}

export function ventanaCaducada(regla, ahora) {
  return ahora - regla.visto > CADUCA_VENTANA_MS;
}

export function sanearVentanas(crudo) {
  if (!Array.isArray(crudo)) return [];
  const validas = [];
  for (const v of crudo) {
    const minutos = normalizarMinutos(v?.minutos);
    if (typeof v?.id !== "string" || minutos === undefined || !Array.isArray(v.urls)) continue;
    validas.push({
      id: v.id,
      minutos,
      urls: v.urls.filter(u => typeof u === "string").slice(0, MAX_URLS_VENTANA),
      nombre: typeof v.nombre === "string" ? v.nombre.slice(0, 120) : "",
      visto: Number.isFinite(v.visto) ? v.visto : 0,
    });
  }
  return validas;
}

export function textoMinutos(minutos) {
  if (minutos === null) return "∞";
  if (minutos < 1) return `${Math.round(minutos * 60)} s`;
  if (minutos < 60) return `${minutos} min`;
  const horas = minutos / 60;
  return `${Number.isInteger(horas) ? horas : horas.toFixed(1)} h`;
}

// Descartar una pestaña que aún carga (o la activa) la deja en blanco: el navegador no la recarga al volver.
export function sePuedeDescartar(tab) {
  return !tab.active && !tab.audible && !tab.discarded && tab.status === "complete";
}

export function quedoEnBlanco(tab) {
  return !!tab.active && (!!tab.discarded || tab.status === "unloaded");
}

export function estaDormida(tab) {
  return !tab.active && (!!tab.discarded || tab.status === "unloaded");
}
