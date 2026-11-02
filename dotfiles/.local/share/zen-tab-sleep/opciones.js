import { normalizarMinutos } from "./reglas.js";
import { t, traducirPagina } from "./i18n.js";

traducirPagina();

const $ = id => document.getElementById(id);

async function pedir(mensaje) {
  const respuesta = await chrome.runtime.sendMessage(mensaje);
  if (!respuesta?.ok) throw new Error(respuesta?.error || t("errorGuardar"));
  return respuesta.resultado;
}

function elemento(etiqueta, propiedades = {}, ...hijos) {
  const nodo = document.createElement(etiqueta);
  Object.assign(nodo, propiedades);
  nodo.append(...hijos);
  return nodo;
}

// Control común de una regla: "Nunca dormir" o "Dormir a los N min".
function controlTiempo(minutos, etiqueta, alCambiar, alError) {
  const modo = elemento("select", { ariaLabel: t("queHacerCon", etiqueta) },
    elemento("option", { value: "nunca", textContent: t("nuncaDormir") }),
    elemento("option", { value: "minutos", textContent: t("dormirALosOpcion") }));
  const entrada = elemento("input", {
    type: "number", min: "0.5", max: "10080", step: "0.5",
    value: minutos === null ? "30" : String(minutos),
    ariaLabel: t("minutosDe", etiqueta),
  });
  modo.value = minutos === null ? "nunca" : "minutos";
  entrada.hidden = minutos === null;

  const enviar = () => {
    entrada.hidden = modo.value === "nunca";
    if (modo.value === "nunca") return alCambiar(null);
    const valor = normalizarMinutos(entrada.value);
    const valido = valor !== undefined && valor !== null;
    entrada.setAttribute("aria-invalid", String(!valido));
    if (!valido) return alError(t("errorMinutos"));
    alCambiar(valor);
  };
  modo.addEventListener("change", enviar);
  entrada.addEventListener("change", enviar);
  return [modo, entrada];
}

function pintarReglas(reglas) {
  const lista = $("reglas");
  const ordenadas = [...reglas].sort((a, b) => a.patron.localeCompare(b.patron));
  if (!ordenadas.length) {
    lista.replaceChildren(elemento("li", { className: "vacio", textContent: t("sinReglas") }));
    return;
  }
  lista.replaceChildren(...ordenadas.map(regla => {
    const alError = texto => { $("errorRegla").textContent = texto; };
    const cambiar = minutos => ejecutar($("errorRegla"), () => pedir({ tipo: "regla", patron: regla.patron, minutos }));
    return elemento("li", {},
      elemento("span", { className: "nombre", textContent: regla.patron }),
      ...controlTiempo(regla.minutos, regla.patron, cambiar, alError),
      botonQuitar(regla.patron, () => cambiar(undefined)));
  }));
}

function botonQuitar(nombre, accion) {
  const boton = elemento("button", { className: "peligro", textContent: t("quitar"), ariaLabel: t("quitarNombre", nombre) });
  boton.addEventListener("click", accion);
  return boton;
}

function pintarVentanas(ventanas) {
  const lista = $("ventanas");
  if (!ventanas.length) {
    lista.replaceChildren(elemento("li", { className: "vacio", textContent: t("sinVentanas") }));
    return;
  }
  lista.replaceChildren(...ventanas.map(ventana => {
    const nombre = ventana.nombre || t("ventanaSinTitulo");
    const pestanas = ventana.pestanas === 1 ? t("unaPestana") : t("nPestanas", ventana.pestanas);
    const alError = texto => { $("errorRegla").textContent = texto; };
    return elemento("li", {},
      elemento("span", { className: "nombre" },
        nombre,
        elemento("br"),
        elemento("small", { className: "tenue", textContent: `${pestanas} · ${t(ventana.abierta ? "abierta" : "cerrada")}` })),
      ...controlTiempo(ventana.minutos, nombre, minutos => ejecutar($("errorRegla"),
        () => pedir({ tipo: "minutosVentanaPorId", id: ventana.id, minutos })), alError),
      botonQuitar(nombre, () => ejecutar($("errorRegla"), () => pedir({ tipo: "quitarVentanaPorId", id: ventana.id }))));
  }));
}

async function refrescar() {
  const { config, ventanas } = await pedir({ tipo: "estadoOpciones" });
  $("activo").checked = config.activo;
  $("fijadas").checked = config.respetarFijadas;
  if (document.activeElement !== $("minutos")) $("minutos").value = config.minutos;
  // Si se está editando una fila, redibujar la lista le quitaría el foco.
  const editando = document.activeElement?.closest?.("#reglas, #ventanas");
  if (!editando) {
    pintarReglas(config.reglas);
    pintarVentanas(ventanas);
  }
}

async function ejecutar(nodoError, trabajo) {
  nodoError.textContent = "";
  try {
    return await trabajo();
  } catch (error) {
    nodoError.textContent = error.message;
  }
}

$("activo").addEventListener("change", () =>
  ejecutar($("errorGeneral"), () => pedir({ tipo: "general", activo: $("activo").checked })));

$("fijadas").addEventListener("change", () =>
  ejecutar($("errorGeneral"), () => pedir({ tipo: "general", respetarFijadas: $("fijadas").checked })));

$("minutos").addEventListener("change", () =>
  ejecutar($("errorGeneral"), () => pedir({ tipo: "general", minutos: $("minutos").value })));

$("modoNueva").addEventListener("change", () => {
  $("minutosNueva").hidden = $("modoNueva").value === "nunca";
});

$("formRegla").addEventListener("submit", async evento => {
  evento.preventDefault();
  const nunca = $("modoNueva").value === "nunca";
  const minutos = nunca ? null : normalizarMinutos($("minutosNueva").value);
  if (minutos === undefined) {
    $("errorRegla").textContent = t("errorMinutos");
    return;
  }
  $("errorRegla").textContent = "";
  try {
    await pedir({ tipo: "regla", patron: $("patron").value, minutos });
    $("patron").value = "";
    $("patron").focus();
  } catch (error) {
    $("errorRegla").textContent = error.message;
  }
});

$("exportar").addEventListener("click", () => ejecutar($("errorCopia"), async () => {
  const datos = await pedir({ tipo: "exportar" });
  const enlace = elemento("a", {
    href: URL.createObjectURL(new Blob([JSON.stringify(datos, null, 2)], { type: "application/json" })),
    download: "zen-tab-sleep.json",
  });
  enlace.click();
  URL.revokeObjectURL(enlace.href);
}));

$("importar").addEventListener("click", () => $("archivo").click());

$("archivo").addEventListener("change", () => ejecutar($("errorCopia"), async () => {
  $("okCopia").textContent = "";
  const archivo = $("archivo").files[0];
  $("archivo").value = "";
  if (!archivo) return;
  let datos;
  try {
    datos = JSON.parse(await archivo.text());
  } catch {
    throw new Error(t("errorJson"));
  }
  const cuantas = await pedir({ tipo: "importar", datos });
  $("okCopia").textContent = t("importado", cuantas);
}));

$("restablecer").addEventListener("click", () => {
  if (!confirm(t("confirmarReset"))) return;
  ejecutar($("errorCopia"), () => pedir({ tipo: "restablecer" }));
});

chrome.storage.onChanged.addListener((_cambios, area) => {
  if (area === "local") refrescar().catch(error => { $("errorGeneral").textContent = error.message; });
});

await refrescar().catch(error => { $("errorGeneral").textContent = error.message; });
