export const t = (clave, ...valores) => chrome.i18n.getMessage(clave, valores.map(String)) || clave;

const ATRIBUTOS = { i18nPlaceholder: "placeholder", i18nTitle: "title", i18nAria: "ariaLabel" };

export function traducirPagina() {
  document.documentElement.lang = chrome.i18n.getUILanguage();
  for (const nodo of document.querySelectorAll("[data-i18n]")) nodo.textContent = t(nodo.dataset.i18n);
  for (const [dato, propiedad] of Object.entries(ATRIBUTOS)) {
    const selector = `[data-${dato.replace(/[A-Z]/g, m => "-" + m.toLowerCase())}]`;
    for (const nodo of document.querySelectorAll(selector)) nodo[propiedad] = t(nodo.dataset[dato]);
  }
}
