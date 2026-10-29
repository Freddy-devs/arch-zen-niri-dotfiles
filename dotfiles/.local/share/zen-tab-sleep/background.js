// Duerme (descarta de la RAM) las pestañas que no usas hace más de 2 minutos.
// Al volver a una pestaña dormida, Brave la recarga sola.
// Nunca se duermen: la pestaña visible de cada ventana, las que suenan,
// y WhatsApp / Teams / Outlook (notificaciones en tiempo real).

const LIMITE_MS = 2 * 60 * 1000;

const SIEMPRE_ACTIVOS = [
  "web.whatsapp.com",
  "teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft",
  "outlook.office.com", "outlook.office365.com", "outlook.live.com", "outlook.cloud.microsoft",
];

function siempreActivo(url) {
  try {
    const host = new URL(url).hostname;
    return SIEMPRE_ACTIVOS.some(s => host === s || host.endsWith("." + s));
  } catch {
    return false;
  }
}

async function revisar() {
  const ahora = Date.now();
  for (const tab of await chrome.tabs.query({})) {
    const url = tab.url || tab.pendingUrl || "";
    if (siempreActivo(url)) {
      // que el Ahorro de memoria de Brave tampoco las duerma
      if (tab.autoDiscardable) chrome.tabs.update(tab.id, { autoDiscardable: false }).catch(() => {});
      continue;
    }
    if (tab.active || tab.discarded || tab.audible) continue;
    if (ahora - tab.lastAccessed < LIMITE_MS) continue;
    chrome.tabs.discard(tab.id).catch(() => {});
  }
}

// cada 30 s (el mínimo que permite Chrome): una pestaña duerme entre 2:00 y 2:30 sin uso
chrome.alarms.get("revisar", a => { if (!a) chrome.alarms.create("revisar", { periodInMinutes: 0.5 }); });
chrome.alarms.onAlarm.addListener(revisar);
chrome.runtime.onStartup.addListener(revisar);
chrome.tabs.onUpdated.addListener((id, cambio, tab) => { if (cambio.url && siempreActivo(cambio.url)) revisar(); });
