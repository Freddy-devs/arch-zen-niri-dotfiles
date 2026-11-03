// Duerme (descarta de la RAM) las pestañas que llevan tiempo sin usarse; al volver a una, Brave la
// recarga sola. El tiempo se decide por pestaña: regla de página o sitio > regla de ventana > general.
// Nunca se duermen la pestaña visible de cada ventana ni las que suenan.
//
// Este worker es el único que escribe la configuración: popup y opciones le mandan mensajes, y todo
// pasa por una cola, así dos cambios seguidos no se pisan.

import {
  alcancesDeUrl, aplicarRegla, configInicial, decidir, emparejarVentanas, normalizarMinutos,
  normalizarPatron, quedoEnBlanco, sanearConfig, sanearVentanas, sePuedeDescartar,
  estaDormida, textoMinutos, urlsDeVentana, ventanaCaducada, MAX_REGLAS,
} from "./reglas.js";
import { t } from "./i18n.js";

const ALARMA = "revisar";
const VENTANA_ARRANQUE_MS = 5 * 60 * 1000; // lo que puede tardar en restaurarse la sesión
const ESPERA_DESPERTAR_MS = 1500;

let cola = Promise.resolve();
function enCola(trabajo) {
  const resultado = cola.then(trabajo);
  cola = resultado.catch(error => console.error("zen-tab-sleep:", error));
  return resultado;
}

async function leerConfig() {
  const { config } = await chrome.storage.local.get("config");
  return sanearConfig(config);
}

async function leerVentanas() {
  const { ventanas } = await chrome.storage.local.get("ventanas");
  return sanearVentanas(ventanas);
}

// Estado de esta sesión del navegador; storage.session sobrevive a que el worker se apague.
async function leerSesion() {
  const { sesion } = await chrome.storage.session.get("sesion");
  return { arranque: Date.now(), vistas: {}, activas: {}, enlaces: {}, ...sesion };
}

const guardarSesion = sesion => chrome.storage.session.set({ sesion });

// Enlaza las reglas de ventana con las ventanas abiertas y recuerda sus pestañas para la próxima vez.
async function sincronizarVentanas(sesion, tabs, ahora) {
  let ventanas = await leerVentanas();
  const viejas = structuredClone(ventanas);
  const porVentana = new Map();
  for (const tab of tabs) {
    if (!porVentana.has(tab.windowId)) porVentana.set(tab.windowId, []);
    porVentana.get(tab.windowId).push(tab);
  }

  for (const [idRegla, idVentana] of Object.entries(sesion.enlaces)) {
    if (!porVentana.has(idVentana) || !ventanas.some(v => v.id === idRegla)) delete sesion.enlaces[idRegla];
  }

  const enlazadas = new Set(Object.values(sesion.enlaces));
  const libres = ventanas.filter(v => !sesion.enlaces[v.id]);
  const abiertas = [...porVentana].filter(([id]) => !enlazadas.has(id))
    .map(([id, pestanas]) => ({ id, urls: urlsDeVentana(pestanas) }));
  const enArranque = ahora - sesion.arranque < VENTANA_ARRANQUE_MS;
  for (const [idRegla, idVentana] of emparejarVentanas(libres, abiertas, enArranque)) {
    sesion.enlaces[idRegla] = idVentana;
  }

  for (const regla of ventanas) {
    const idVentana = sesion.enlaces[regla.id];
    if (idVentana === undefined) continue;
    const pestanas = porVentana.get(idVentana);
    const urls = urlsDeVentana(pestanas);
    // Si la sesión aún se está restaurando, no se pisan las URL guardadas con una lista a medias.
    if (urls.length) regla.urls = urls;
    regla.visto = ahora;
  }
  ventanas = ventanas.filter(v => !ventanaCaducada(v, ahora));

  // "visto" cambia en cada revisión: solo se guarda si hay otro cambio o cada hora, para no gastar disco.
  const sinVisto = lista => JSON.stringify(lista.map(({ visto, ...resto }) => resto));
  const visitaAntigua = viejas.some(v => ahora - v.visto > 60 * 60 * 1000);
  if (sinVisto(ventanas) !== sinVisto(viejas) || visitaAntigua) {
    await chrome.storage.local.set({ ventanas });
  }
  return ventanas;
}

function reglaDeVentana(ventanas, sesion, idVentana) {
  return ventanas.find(v => sesion.enlaces[v.id] === idVentana) || null;
}

function deEstaPestana(tab, config, ventanas, sesion) {
  const url = tab.url || tab.pendingUrl || "";
  return decidir(config, url, reglaDeVentana(ventanas, sesion, tab.windowId));
}

function inactivoDesde(tab, sesion) {
  return Math.max(tab.lastAccessed || 0, sesion.vistas[tab.id] || 0);
}

// Por qué sí o no se dormiría esta pestaña ahora mismo.
function protegida(tab, decision, config) {
  if (decision.minutos === null) return "regla";
  if (tab.active) return "visible";
  if (tab.audible) return "sonido";
  if (tab.pinned && config.respetarFijadas) return "fijada";
  return null;
}

// La lista de una revisión puede llevar un rato vieja: se vuelve a mirar la pestaña justo antes de descartarla.
async function dormir(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab || !sePuedeDescartar(tab)) return false;
  return !!(await chrome.tabs.discard(tabId).catch(() => null));
}

// Red de seguridad, también para lo que descarte el Ahorro de memoria de Brave.
async function despertarSiQuedoEnBlanco(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (tab && quedoEnBlanco(tab)) await chrome.tabs.reload(tabId, { bypassCache: true }).catch(() => {});
}

async function revisar() {
  const ahora = Date.now();
  const [config, sesion, tabs] = await Promise.all([leerConfig(), leerSesion(), chrome.tabs.query({})]);
  const ventanas = await sincronizarVentanas(sesion, tabs, ahora);

  const vivas = new Set();
  for (const tab of tabs) {
    vivas.add(String(tab.id));
    if (tab.active) {
      sesion.vistas[tab.id] = ahora;
      sesion.activas[tab.windowId] = tab.id;
      if (quedoEnBlanco(tab)) await despertarSiQuedoEnBlanco(tab.id);
    }
    const decision = deEstaPestana(tab, config, ventanas, sesion);

    // Que el Ahorro de memoria de Brave tampoco duerma las protegidas, y que recupere las que ya no lo están.
    const descartable = decision.minutos !== null;
    if (tab.autoDiscardable !== descartable) {
      await chrome.tabs.update(tab.id, { autoDiscardable: descartable }).catch(() => {});
    }

    if (!config.activo || tab.discarded || protegida(tab, decision, config)) continue;
    if (ahora - inactivoDesde(tab, sesion) >= decision.minutos * 60000) await dormir(tab.id);
  }
  for (const id of Object.keys(sesion.vistas)) {
    if (!vivas.has(id)) delete sesion.vistas[id];
  }
  await guardarSesion(sesion);
  await actualizarIcono();
}

async function actualizarIcono() {
  const [config, sesion, ventanas, activas] = await Promise.all([
    leerConfig(), leerSesion(), leerVentanas(), chrome.tabs.query({ active: true }),
  ]);
  const dormidas = (await chrome.tabs.query({})).filter(estaDormida).length;
  await chrome.action.setBadgeText({ text: config.activo ? String(dormidas) : "off" }).catch(() => {});
  for (const tab of activas) {
    const decision = deEstaPestana(tab, config, ventanas, sesion);
    await chrome.action.setTitle({
      tabId: tab.id,
      title: !config.activo ? t("tituloPausa")
        : decision.minutos === null ? t("tituloNunca")
        : t("tituloMinutos", textoMinutos(decision.minutos)),
    }).catch(() => {});
  }
  const [foco] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!foco) return;
  const alcances = alcancesDeUrl(foco.url || "");
  const reglaSitio = alcances && config.reglas.find(r => r.patron === alcances.sitio);
  await actualizarMenu("sitio", { checked: reglaSitio?.minutos === null, enabled: !!alcances });
  await actualizarMenu("ventana", { checked: reglaDeVentana(ventanas, sesion, foco.windowId)?.minutos === null });
  await actualizarMenu("pausa", { checked: !config.activo });
}

async function actualizarMenu(id, cambios) {
  await chrome.contextMenus.update(id, cambios).catch(() => {});
}

async function crearMenu() {
  await chrome.contextMenus.removeAll();
  const contexts = ["action"];
  chrome.contextMenus.create({ id: "sitio", title: t("menuSitio"), type: "checkbox", contexts });
  chrome.contextMenus.create({ id: "ventana", title: t("menuVentana"), type: "checkbox", contexts });
  chrome.contextMenus.create({ id: "otras", title: t("menuOtras"), contexts });
  chrome.contextMenus.create({ id: "pausa", title: t("menuPausa"), type: "checkbox", contexts });
  chrome.contextMenus.create({ id: "ajustes", title: t("menuAjustes"), contexts });
}

async function guardarConfig(cambiar) {
  const config = await leerConfig();
  const nueva = sanearConfig(cambiar(config) ?? config);
  await chrome.storage.local.set({ config: nueva });
  return nueva;
}

async function fijarRegla(patronTexto, minutosCrudo) {
  const patron = normalizarPatron(patronTexto);
  if (!patron) throw new Error(t("errorDireccion"));
  let minutos;
  if (minutosCrudo !== undefined) {
    minutos = normalizarMinutos(minutosCrudo);
    if (minutos === undefined) throw new Error(t("errorMinutos"));
  }
  await guardarConfig(config => {
    const reglas = aplicarRegla(config.reglas, patron, minutos);
    if (reglas.length > MAX_REGLAS) throw new Error(t("errorMaxReglas", MAX_REGLAS));
    return { ...config, reglas };
  });
}

async function fijarVentana(idVentana, minutosCrudo) {
  const sesion = await leerSesion();
  let ventanas = await leerVentanas();
  const actual = reglaDeVentana(ventanas, sesion, idVentana);
  if (minutosCrudo === undefined) {
    if (actual) {
      ventanas = ventanas.filter(v => v !== actual);
      delete sesion.enlaces[actual.id];
    }
  } else {
    const minutos = normalizarMinutos(minutosCrudo);
    if (minutos === undefined) throw new Error(t("errorMinutos"));
    if (actual) {
      actual.minutos = minutos;
    } else {
      const tabs = await chrome.tabs.query({ windowId: idVentana });
      const activa = tabs.find(t => t.active);
      const nueva = {
        id: crypto.randomUUID(),
        minutos,
        urls: urlsDeVentana(tabs),
        nombre: activa?.title || "",
        visto: Date.now(),
      };
      ventanas.push(nueva);
      sesion.enlaces[nueva.id] = idVentana;
    }
  }
  await chrome.storage.local.set({ ventanas });
  await guardarSesion(sesion);
}

async function dormirOtras(idVentana) {
  const [config, sesion, ventanas, tabs] = await Promise.all([
    leerConfig(), leerSesion(), leerVentanas(), chrome.tabs.query({ windowId: idVentana }),
  ]);
  let dormidas = 0;
  for (const tab of tabs) {
    if (tab.discarded || protegida(tab, deEstaPestana(tab, config, ventanas, sesion), config)) continue;
    if (await dormir(tab.id)) dormidas++;
  }
  return dormidas;
}

async function estadoPestana(tabId) {
  const [config, sesion, ventanas] = await Promise.all([leerConfig(), leerSesion(), leerVentanas()]);
  const tab = await chrome.tabs.get(tabId);
  const url = tab.url || tab.pendingUrl || "";
  const decision = deEstaPestana(tab, config, ventanas, sesion);
  const alcances = alcancesDeUrl(url);
  const buscar = patron => config.reglas.find(r => r.patron === patron)?.minutos;
  return {
    config,
    decision,
    alcances,
    ventanaId: tab.windowId,
    reglas: alcances
      ? { pagina: buscar(alcances.pagina), sitio: buscar(alcances.sitio) }
      : { pagina: undefined, sitio: undefined },
    reglaVentana: reglaDeVentana(ventanas, sesion, tab.windowId)?.minutos,
    motivo: protegida({ ...tab, active: false }, decision, config),
  };
}

const datosPestana = t => ({
  id: t.id,
  ventanaId: t.windowId,
  titulo: t.title || "",
  url: t.url || t.pendingUrl || "",
});

async function estadoOpciones() {
  const ahora = Date.now();
  const [config, sesion, ventanas, tabs] = await Promise.all([
    leerConfig(), leerSesion(), leerVentanas(), chrome.tabs.query({}),
  ]);
  const abiertas = new Set(tabs.map(t => t.windowId));
  return {
    config,
    dormidas: tabs.filter(estaDormida).map(datosPestana),
    despiertas: tabs.filter(t => !estaDormida(t)).map(t => {
      const decision = deEstaPestana(t, config, ventanas, sesion);
      const motivo = !config.activo ? "pausa"
        : protegida(t, decision, config) || (t.status === "complete" ? null : "cargando");
      return {
        ...datosPestana(t),
        motivo,
        restanteMs: motivo ? null : Math.max(0, decision.minutos * 60000 - (ahora - inactivoDesde(t, sesion))),
      };
    }),
    ventanas: ventanas.map(v => {
      const idVentana = sesion.enlaces[v.id];
      const abierta = abiertas.has(idVentana);
      return {
        id: v.id,
        minutos: v.minutos,
        nombre: v.nombre,
        pestanas: abierta ? tabs.filter(t => t.windowId === idVentana).length : v.urls.length,
        abierta,
      };
    }),
  };
}

const ACCIONES = {
  estadoPestana: m => estadoPestana(m.tabId),
  estadoOpciones,
  regla: m => fijarRegla(m.patron, m.minutos),
  ventana: m => fijarVentana(m.ventanaId, m.minutos),
  quitarVentanaPorId: async m => {
    const ventanas = await leerVentanas();
    await chrome.storage.local.set({ ventanas: ventanas.filter(v => v.id !== m.id) });
  },
  minutosVentanaPorId: async m => {
    const minutos = normalizarMinutos(m.minutos);
    if (minutos === undefined) throw new Error(t("errorMinutos"));
    const ventanas = await leerVentanas();
    const regla = ventanas.find(v => v.id === m.id);
    if (regla) regla.minutos = minutos;
    await chrome.storage.local.set({ ventanas });
  },
  general: m => guardarConfig(config => {
    const nueva = { ...config };
    if ("activo" in m) nueva.activo = !!m.activo;
    if ("respetarFijadas" in m) nueva.respetarFijadas = !!m.respetarFijadas;
    if ("minutos" in m) {
      const minutos = normalizarMinutos(m.minutos);
      if (minutos === undefined || minutos === null) throw new Error(t("errorMinutos"));
      nueva.minutos = minutos;
    }
    return nueva;
  }),
  dormirOtras: m => dormirOtras(m.ventanaId),
  irAPestana: async m => {
    await chrome.tabs.update(m.tabId, { active: true });
    await chrome.windows.update(m.ventanaId, { focused: true });
  },
  exportar: async () => ({ config: await leerConfig() }),
  importar: async m => {
    if (!m.datos || typeof m.datos.config !== "object" || !Array.isArray(m.datos.config?.reglas)) {
      throw new Error(t("errorCopia"));
    }
    const config = sanearConfig(m.datos.config);
    await chrome.storage.local.set({ config });
    return config.reglas.length;
  },
  restablecer: () => chrome.storage.local.set({ config: configInicial() }),
};

chrome.runtime.onMessage.addListener((mensaje, _origen, responder) => {
  const accion = ACCIONES[mensaje?.tipo];
  if (!accion) return false;
  enCola(async () => {
    const resultado = await accion(mensaje);
    await actualizarIcono();
    return resultado;
  }).then(
    resultado => responder({ ok: true, resultado }),
    error => responder({ ok: false, error: error.message }),
  );
  return true; // respuesta asíncrona
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  enCola(async () => {
    if (info.menuItemId === "ajustes") return chrome.runtime.openOptionsPage();
    if (info.menuItemId === "pausa") {
      await guardarConfig(config => ({ ...config, activo: !info.checked }));
    } else if (info.menuItemId === "sitio") {
      const alcances = tab && alcancesDeUrl(tab.url || "");
      if (alcances) await fijarRegla(alcances.sitio, info.checked ? null : undefined);
    } else if (info.menuItemId === "ventana" && tab) {
      await fijarVentana(tab.windowId, info.checked ? null : undefined);
    } else if (info.menuItemId === "otras" && tab) {
      await dormirOtras(tab.windowId);
    }
    await actualizarIcono();
  });
});

// Al cambiar de pestaña, la que se deja cuenta como vista justo ahora (no cuando se abrió).
chrome.tabs.onActivated.addListener(({ tabId, windowId }) => {
  enCola(async () => {
    const sesion = await leerSesion();
    const ahora = Date.now();
    const anterior = sesion.activas[windowId];
    if (anterior !== undefined) sesion.vistas[anterior] = ahora;
    sesion.vistas[tabId] = ahora;
    sesion.activas[windowId] = tabId;
    await guardarSesion(sesion);
    await actualizarIcono();
  });
  // Lo normal es que a estas alturas ya esté cargando; si no, se le da el empujón que le faltó.
  setTimeout(() => enCola(() => despertarSiQuedoEnBlanco(tabId)), ESPERA_DESPERTAR_MS);
});

chrome.tabs.onUpdated.addListener((_id, cambio) => {
  if (cambio.url || "discarded" in cambio || cambio.status === "unloaded") enCola(actualizarIcono);
});
chrome.tabs.onCreated.addListener(() => { enCola(actualizarIcono); });
chrome.tabs.onRemoved.addListener(() => { enCola(actualizarIcono); });
chrome.windows.onFocusChanged.addListener(() => { enCola(actualizarIcono); });
chrome.windows.onRemoved.addListener(idVentana => {
  enCola(async () => {
    const sesion = await leerSesion();
    delete sesion.activas[idVentana];
    await guardarSesion(sesion);
  });
});

chrome.alarms.onAlarm.addListener(alarma => {
  if (alarma.name === ALARMA) enCola(revisar);
});

async function preparar() {
  await crearMenu();
  await chrome.action.setBadgeBackgroundColor({ color: "#7aa2f7" });
  await chrome.action.setBadgeTextColor?.({ color: "#16161e" });
  await revisar();
}

chrome.runtime.onInstalled.addListener(async () => {
  enCola(async () => {
    const { config } = await chrome.storage.local.get("config");
    if (!config) await chrome.storage.local.set({ config: configInicial() });
    await preparar();
  });
});
chrome.runtime.onStartup.addListener(() => { enCola(preparar); });

// Cada 30 s (el mínimo de Chrome): una pestaña duerme hasta 30 s después de cumplir su tiempo.
chrome.alarms.get(ALARMA, alarma => {
  if (!alarma) chrome.alarms.create(ALARMA, { periodInMinutes: 0.5 });
});
