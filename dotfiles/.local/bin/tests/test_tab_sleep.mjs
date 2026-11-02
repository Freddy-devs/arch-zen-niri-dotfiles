// node --test dotfiles/.local/bin/tests/test_tab_sleep.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  alcancesDeUrl, coincide, configInicial, decidir, emparejarVentanas, normalizarMinutos,
  normalizarPatron, reglaDeUrl, sanearConfig, urlsDeVentana,
} from "../../share/zen-tab-sleep/reglas.js";

test("normaliza direcciones", () => {
  assert.equal(normalizarPatron("HTTPS://WWW.GitHub.com/a/b/?x=1#y"), "github.com/a/b");
  assert.equal(normalizarPatron("  ejemplo.com  "), "ejemplo.com");
  assert.equal(normalizarPatron("localhost:3000/app"), "localhost:3000/app");
  assert.equal(normalizarPatron("*.atlassian.net/jira/*"), "*.atlassian.net/jira/*");
  assert.equal(normalizarPatron("ñandú.pe"), "xn--and-6ma2c.pe");
  for (const malo of ["", "   ", "*", "/ruta", "a b.com", "mal dominio", "user:pw@x.com", null, 5, "x".repeat(301)]) {
    assert.equal(normalizarPatron(malo), null, String(malo));
  }
});

test("el sitio abarca subdominios pero no dominios parecidos", () => {
  assert.ok(coincide("github.com", "https://github.com/x"));
  assert.ok(coincide("github.com", "https://gist.github.com/x"));
  assert.ok(coincide("github.com", "https://www.github.com/"));
  assert.ok(!coincide("github.com", "https://notgithub.com/"));
  assert.ok(!coincide("github.com", "https://github.com.evil.pe/"));
});

test("la página abarca sus hijas pero no rutas parecidas", () => {
  assert.ok(coincide("github.com/foo", "https://github.com/foo"));
  assert.ok(coincide("github.com/foo", "https://github.com/foo/bar?x=1"));
  assert.ok(!coincide("github.com/foo", "https://github.com/foobar"));
});

test("comodines", () => {
  assert.ok(coincide("*.atlassian.net/jira/*", "https://acme.atlassian.net/jira/board/1"));
  assert.ok(!coincide("*.atlassian.net/jira/*", "https://acme.atlassian.net/wiki"));
  assert.ok(coincide("github.com/*/issues", "https://github.com/a/issues/4"));
  assert.ok(coincide("*/admin", "https://cualquiera.pe/admin"));
  const inicio = Date.now();
  assert.ok(!coincide("a.com/*a*a*a*a*a*a*a*a*b", "https://a.com/" + "a".repeat(5000)));
  assert.ok(Date.now() - inicio < 1000, "comodines sin explosión de tiempo");
});

test("puerto y páginas internas", () => {
  assert.ok(coincide("localhost:3000", "http://localhost:3000/x"));
  assert.ok(!coincide("localhost:3000", "http://localhost:4000/x"));
  assert.ok(coincide("localhost", "http://localhost:4000/x"));
  assert.ok(!coincide("settings", "brave://settings/"));
  assert.equal(alcancesDeUrl("brave://settings/"), null);
  assert.deepEqual(alcancesDeUrl("https://www.x.pe/a/b/?q=1"), { sitio: "x.pe", pagina: "x.pe/a/b" });
  assert.deepEqual(alcancesDeUrl("https://x.pe/"), { sitio: "x.pe", pagina: "x.pe" });
});

test("gana la regla más específica sin importar el orden", () => {
  const reglas = [
    { patron: "github.com/a/*", minutos: 7 },
    { patron: "github.com", minutos: 10 },
    { patron: "github.com/a/b", minutos: null },
  ];
  for (const lista of [reglas, [...reglas].reverse()]) {
    assert.equal(reglaDeUrl(lista, "https://github.com/a/b/c").minutos, null);
    assert.equal(reglaDeUrl(lista, "https://github.com/a/z").minutos, 7);
    assert.equal(reglaDeUrl(lista, "https://github.com/z").minutos, 10);
  }
});

test("prioridad: regla > ventana > general", () => {
  const config = { ...configInicial(), minutos: 2, reglas: [{ patron: "web.whatsapp.com", minutos: null }, { patron: "x.pe", minutos: 9 }] };
  assert.equal(decidir(config, "https://y.pe/", null).minutos, 2);
  assert.equal(decidir(config, "https://y.pe/", { minutos: 30 }).minutos, 30);
  assert.equal(decidir(config, "https://y.pe/", { minutos: null }).minutos, null);
  assert.equal(decidir(config, "https://x.pe/", { minutos: null }).minutos, 9);
  assert.equal(decidir(config, "https://web.whatsapp.com/", { minutos: 1 }).minutos, null);
  assert.equal(decidir(config, "brave://settings/", null).minutos, 2);
});

test("minutos válidos", () => {
  assert.equal(normalizarMinutos(null), null);
  assert.equal(normalizarMinutos("2.5"), 2.5);
  for (const malo of ["", " ", "x", 0, 0.1, -1, 99999, NaN, Infinity, undefined, {}]) {
    assert.equal(normalizarMinutos(malo), undefined, String(malo));
  }
});

test("WhatsApp, Teams y Outlook vienen protegidos", () => {
  const config = configInicial();
  for (const url of ["https://web.whatsapp.com/", "https://teams.microsoft.com/v2/", "https://outlook.office.com/mail/"]) {
    assert.equal(decidir(config, url, null).minutos, null, url);
  }
});

test("una configuración rota nunca rompe", () => {
  for (const malo of [null, undefined, "x", 3]) assert.deepEqual(sanearConfig(malo), configInicial());
  const limpia = sanearConfig({
    activo: "si", minutos: -4, respetarFijadas: 1,
    reglas: [{ patron: "OK.com", minutos: 5 }, { patron: "", minutos: 5 }, { patron: "b.com", minutos: "x" }, null, { patron: "ok.com", minutos: null }],
  });
  assert.equal(limpia.activo, true);
  assert.equal(limpia.minutos, configInicial().minutos);
  assert.equal(limpia.respetarFijadas, false);
  assert.deepEqual(limpia.reglas, [{ patron: "ok.com", minutos: null }]);
  assert.deepEqual(sanearConfig({ reglas: [] }).reglas, [], "borrar todas las reglas se respeta");
});

test("reconoce las ventanas restauradas tras reiniciar", () => {
  const libres = [{ id: "r1", urls: ["https://a.pe/", "https://b.pe/", "https://c.pe/"] }];
  assert.deepEqual(emparejarVentanas(libres, [
    { id: 7, urls: ["https://z.pe/"] },
    { id: 8, urls: ["https://a.pe/", "https://b.pe/", "https://d.pe/"] },
  ], true), [["r1", 8]]);
  assert.deepEqual(emparejarVentanas(libres, [{ id: 8, urls: ["https://a.pe/", "https://x.pe/", "https://y.pe/", "https://w.pe/"] }], true), [], "poco parecido");

  const una = [{ id: "r2", urls: ["https://a.pe/"] }];
  const abierta = [{ id: 9, urls: ["https://a.pe/"] }];
  assert.deepEqual(emparejarVentanas(una, abierta, true), [["r2", 9]]);
  assert.deepEqual(emparejarVentanas(una, abierta, false), [], "fuera del arranque una pestaña no basta");

  const dos = [{ id: "a", urls: ["https://a.pe/", "https://b.pe/"] }, { id: "b", urls: ["https://a.pe/", "https://b.pe/"] }];
  assert.equal(emparejarVentanas(dos, [{ id: 1, urls: ["https://a.pe/", "https://b.pe/"] }], true).length, 1, "una ventana no toma dos reglas");
});

test("urls de ventana: sin internas, sin repetidas y sin ancla", () => {
  assert.deepEqual(urlsDeVentana([
    { url: "https://b.pe/#x" }, { url: "https://b.pe/" }, { pendingUrl: "https://a.pe/" }, { url: "brave://settings" },
  ]), ["https://a.pe/", "https://b.pe/"]);
});
