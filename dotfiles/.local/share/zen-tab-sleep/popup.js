import { normalizarMinutos, textoMinutos } from "./reglas.js";
import { t, traducirPagina } from "./i18n.js";

traducirPagina();
const $ = id => document.getElementById(id);
const ALCANCES = ["pagina", "sitio", "ventana"];
let tabId, estado, alcance;

async function pedir(mensaje) {
  const respuesta = await chrome.runtime.sendMessage(mensaje);
  if (!respuesta?.ok) throw new Error(respuesta?.error || t("errorGuardar"));
  return respuesta.resultado;
}

function mostrarError(error) {
  $("error").textContent = error ? error.message || String(error) : "";
}

function textoEstado() {
  const { config, decision, motivo, alcances } = estado;
  if (!config.activo) return [t("enPausa"), t("ningunaDuerme")];
  const detalle = decision.origen === "regla" ? t("porRegla", decision.patron)
    : decision.origen === "ventana" ? t("porVentana")
    : t(alcances ? "valorGeneral" : "paginaInterna");
  if (decision.minutos === null) return [t("nuncaDuerme"), detalle];
  const titulo = t("seDuerme", textoMinutos(decision.minutos));
  return [titulo, motivo === "sonido" ? t("ahoraNoSuena") : motivo === "fijada" ? t("ahoraNoFijada") : detalle];
}

function reglaDelAlcance() {
  return alcance === "ventana" ? estado.reglaVentana : estado.reglas[alcance];
}

function pintarAlcance() {
  for (const boton of $("alcances").children) {
    boton.setAttribute("aria-pressed", String(boton.dataset.alcance === alcance));
    boton.disabled = boton.dataset.alcance !== "ventana" && !estado.alcances;
  }
  $("destino").textContent = alcance === "ventana"
    ? t("destinoVentana")
    : estado.alcances[alcance];

  const regla = reglaDelAlcance();
  const modo = regla === undefined ? "heredar" : regla === null ? "nunca" : "minutos";
  document.querySelector(`input[name="modo"][value="${modo}"]`).checked = true;
  const entrada = $("minutosRegla");
  if (document.activeElement !== entrada) entrada.value = typeof regla === "number" ? regla : estado.config.minutos;
  $("modoHeredar").textContent = t("sinReglaPropia", textoMinutos(estado.config.minutos));
}

function pintar() {
  const { config } = estado;
  $("activo").checked = config.activo;
  $("activoTexto").textContent = t(config.activo ? "activa" : "enPausa");
  if (document.activeElement !== $("minutos")) $("minutos").value = config.minutos;
  const [titulo, detalle] = textoEstado();
  $("estadoTitulo").textContent = titulo;
  $("estadoDetalle").textContent = detalle;
  pintarAlcance();
}

async function refrescar() {
  estado = await pedir({ tipo: "estadoPestana", tabId });
  if (!alcance) {
    // Abre en el alcance que ya tiene regla; si no hay ninguna, en el sitio.
    alcance = !estado.alcances ? "ventana"
      : estado.reglas.pagina !== undefined && estado.alcances.pagina !== estado.alcances.sitio ? "pagina"
      : estado.reglas.sitio === undefined && estado.reglaVentana !== undefined ? "ventana"
      : "sitio";
  }
  pintar();
}

async function guardar(trabajo) {
  mostrarError(null);
  try {
    await trabajo();
  } catch (error) {
    mostrarError(error);
  }
  await refrescar().catch(mostrarError);
}

function guardarRegla(minutos) {
  return guardar(() => alcance === "ventana"
    ? pedir({ tipo: "ventana", ventanaId: estado.ventanaId, minutos })
    : pedir({ tipo: "regla", patron: estado.alcances[alcance], minutos }));
}

function aplicarModo(modo) {
  if (modo === "heredar") return guardarRegla(undefined);
  if (modo === "nunca") return guardarRegla(null);
  return guardarConMinutos();
}

function guardarConMinutos() {
  const entrada = $("minutosRegla");
  const minutos = normalizarMinutos(entrada.value);
  const valido = minutos !== undefined && minutos !== null;
  entrada.setAttribute("aria-invalid", String(!valido));
  if (!valido) {
    mostrarError(t("errorMinutos"));
    return;
  }
  return guardarRegla(minutos);
}

$("alcances").addEventListener("click", evento => {
  const elegido = evento.target.dataset?.alcance;
  if (ALCANCES.includes(elegido)) {
    alcance = elegido;
    pintar();
  }
});

for (const radio of document.querySelectorAll('input[name="modo"]')) {
  radio.addEventListener("change", () => aplicarModo(radio.value));
}

$("minutosRegla").addEventListener("focus", () => {
  document.querySelector('input[name="modo"][value="minutos"]').checked = true;
});
$("minutosRegla").addEventListener("change", guardarConMinutos);

$("minutos").addEventListener("change", () => {
  const minutos = normalizarMinutos($("minutos").value);
  const valido = minutos !== undefined && minutos !== null;
  $("minutos").setAttribute("aria-invalid", String(!valido));
  if (!valido) {
    mostrarError(t("errorMinutos"));
    return;
  }
  guardar(() => pedir({ tipo: "general", minutos }));
});

$("activo").addEventListener("change", () => guardar(() => pedir({ tipo: "general", activo: $("activo").checked })));

$("otras").addEventListener("click", async () => {
  mostrarError(null);
  try {
    const dormidas = await pedir({ tipo: "dormirOtras", ventanaId: estado.ventanaId });
    $("otras").textContent = t("dormidas", dormidas);
  } catch (error) {
    mostrarError(error);
  }
});

$("ajustes").addEventListener("click", () => {
  chrome.runtime.openOptionsPage();
  window.close();
});

const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
tabId = tab.id;
await refrescar().catch(mostrarError);
