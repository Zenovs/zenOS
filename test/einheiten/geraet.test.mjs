// Einheitentests für shell/dienste/geraet.js (Statusdatei von zenos-argon lesen, Anzeige von Akku und Lüfter,
// Warnungen bei niedrigem Akku). Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const quelle = readFileSync(join(wurzel, "shell", "dienste", "geraet.js"), "utf8");

// Die Datei ist ein QML-Skript («.pragma library»); ohne diese Zeile ist es gewöhnliches JavaScript.
const L = vm.createContext({});
vm.runInContext(quelle.replace(/^\.pragma library\s*$/m, ""), L);

const JETZT = Date.parse("2026-10-02T10:00:00+02:00");

// Statusdatei wie von zenos-argon, «zeit» relativ zu JETZT in Sekunden
function datei(teile, sekunden = -5) {
  const zeit = new Date(JETZT + sekunden * 1000).toISOString().replace(/\.\d+Z$/, "+00:00");
  return JSON.stringify(Object.assign({ version: 1, zeit, geraet: "argon-one-up" }, teile));
}

const UP = {
  akku: { vorhanden: true, prozent: 87, laedt: true, zustand: "ok" },
  luefter: { vorhanden: true, stufe: 2, stufen: 4, upm: 3120 },
  temperatur: { cpu: 41.2 },
};

// Objekte aus dem VM-Kontext in gewöhnliche umwandeln (deepEqual prüft sonst auch den Prototyp)
const roh = (wert) => JSON.parse(JSON.stringify(wert));

test("lesen: Argon ONE UP", () => {
  const d = roh(L.lesen(datei(UP), JETZT));
  assert.equal(d.frisch, true);
  assert.deepEqual(d.akku, { vorhanden: true, prozent: 87, laedt: true, zustand: "ok" });
  assert.deepEqual(d.luefter, { vorhanden: true, prozent: -1, stufe: 2, stufen: 4, upm: 3120 });
});

test("lesen: Argon ONE V3 ohne Akku, Lüfter in Prozent", () => {
  const d = roh(L.lesen(datei({ geraet: "argon-one-v3", akku: { vorhanden: false }, luefter: { vorhanden: true, prozent: 55 } }), JETZT));
  assert.equal(d.akku.vorhanden, false);
  assert.equal(L.luefterWert(d.luefter), "55 %");
});

test("lesen: fehlend, kaputt, fremd oder zu alt ist leer", () => {
  for (const text of ["", "{", "null", "[]", JSON.stringify({ version: 2, zeit: "2026-10-02T08:00:00+00:00", akku: UP.akku }), datei(UP, -61), datei(UP, 61), datei(Object.assign({}, UP, { zeit: "gestern" }))]) {
    const d = roh(L.lesen(text, JETZT));
    assert.equal(d.frisch, false, text);
    assert.equal(d.akku.vorhanden, false, text);
    assert.equal(d.luefter.vorhanden, false, text);
  }
  // 60 s alt gilt noch
  assert.equal(L.lesen(datei(UP, -60), JETZT).frisch, true);
});

test("lesen: unplausible Felder werden unbekannt", () => {
  const faelle = [
    [{ vorhanden: true, prozent: 101, laedt: true, zustand: "ok" }, { prozent: -1, laedt: null, zustand: "unbekannt" }],
    [{ vorhanden: true, prozent: 50.5, laedt: false, zustand: "ok" }, { prozent: -1, laedt: null, zustand: "unbekannt" }],
    [{ vorhanden: true, prozent: "50", laedt: false, zustand: "ok" }, { prozent: -1, laedt: null, zustand: "unbekannt" }],
    [{ vorhanden: true, prozent: 50, laedt: "ja", zustand: "ok" }, { prozent: 50, laedt: null, zustand: "ok" }],
    [{ vorhanden: true, prozent: 50, laedt: true, zustand: "fehler" }, { prozent: -1, laedt: null, zustand: "fehler" }],
    [{ vorhanden: true, prozent: null, laedt: null, zustand: "unbekannt" }, { prozent: -1, laedt: null, zustand: "unbekannt" }],
    [{ vorhanden: true, prozent: 50, zustand: "seltsam" }, { prozent: -1, laedt: null, zustand: "unbekannt" }],
  ];
  for (const [akku, erwartet] of faelle) {
    const d = roh(L.lesen(datei({ akku }), JETZT));
    assert.deepEqual(d.akku, Object.assign({ vorhanden: true }, erwartet), JSON.stringify(akku));
  }
  const l = roh(L.lesen(datei({ luefter: { vorhanden: true, stufe: 5, stufen: 4, upm: -3 } }), JETZT)).luefter;
  assert.deepEqual(l, { vorhanden: true, prozent: -1, stufe: -1, stufen: -1, upm: -1 });
});

test("Anzeige des Akkus", () => {
  const a = (prozent, laedt, zustand = "ok") => ({ vorhanden: true, prozent, laedt, zustand });
  assert.equal(L.akkuSymbol(a(87, true)), "akku-laedt");
  assert.equal(L.akkuSymbol(a(87, false)), "akku-voll");
  assert.equal(L.akkuSymbol(a(70, false)), "akku-halb");
  assert.equal(L.akkuSymbol(a(35, false)), "akku-wenig");
  assert.equal(L.akkuSymbol(a(10, false)), "akku-leer");
  assert.equal(L.akkuSymbol(a(-1, null, "unbekannt")), "akku-leer");
  assert.equal(L.akkuSymbol({ vorhanden: false }), "");
  assert.equal(L.akkuText(a(87, true)), "87 %");
  assert.equal(L.akkuText(a(-1, null, "unbekannt")), "");
  assert.equal(L.akkuWert(a(87, true)), "87 % · lädt");
  assert.equal(L.akkuWert(a(100, true)), "100 % · Netzteil");
  assert.equal(L.akkuWert(a(9, false)), "9 %");
  assert.equal(L.akkuWert(a(-1, null, "unbekannt")), "wird gemessen");
  assert.equal(L.akkuWert(a(-1, null, "fehler")), "nicht lesbar");
  assert.equal(L.akkuNiedrig(a(10, false)), true);
  assert.equal(L.akkuNiedrig(a(9, true)), false);
  assert.equal(L.akkuNiedrig(a(11, false)), false);
  assert.equal(L.akkuNiedrig(a(9, null)), false);
});

test("Anzeige des Lüfters", () => {
  const k = (stufe, upm) => ({ vorhanden: true, prozent: -1, stufe, stufen: stufe >= 0 ? 4 : -1, upm });
  assert.equal(L.luefterWert(k(0, 0)), "aus");
  assert.equal(L.luefterWert(k(2, 3120)), "Stufe 2 von 4 · 3120 U/min");
  assert.equal(L.luefterWert(k(4, -1)), "Stufe 4 von 4");
  assert.equal(L.luefterWert(k(-1, 1800)), "1800 U/min");
  assert.equal(L.luefterWert({ vorhanden: true, prozent: 0, stufe: -1, stufen: -1, upm: -1 }), "aus");
  assert.equal(L.luefterWert({ vorhanden: false }), "");
});

// Ablauf: Akku-Werte nacheinander, gibt die gemeldeten Stufen zurück
function ablauf(werte) {
  let gewarnt = [];
  const gemeldet = [];
  for (const [prozent, laedt, zustand = "ok"] of werte) {
    const r = L.warnungPruefen({ vorhanden: true, prozent, laedt, zustand }, gewarnt);
    gewarnt = Array.from(r.gewarnt);
    if (r.stufe > 0)
      gemeldet.push([prozent, r.stufe]);
  }
  return gemeldet;
}

test("Warnung: je einmal bei 10 % und 5 %, nur beim Entladen", () => {
  assert.deepEqual(ablauf([[12, false], [11, false], [10, false], [10, false], [9, false], [6, false], [5, false], [4, false], [1, false]]),
    [[10, 10], [5, 5]]);
});

test("Warnung: Laden setzt zurück, Schwanken ohne Laden nicht", () => {
  assert.deepEqual(ablauf([[10, false], [12, false], [10, false], [9, true], [9, false]]), [[10, 10], [9, 10]]);
  assert.deepEqual(ablauf([[9, true], [8, true], [5, true]]), []);
});

test("Warnung: schon unter 5 % beim Start meldet nur die tiefere Stufe", () => {
  assert.deepEqual(ablauf([[4, false], [3, false]]), [[4, 5]]);
});

test("Warnung: ohne sicheren Wert nichts, und nichts vergessen", () => {
  assert.deepEqual(ablauf([[8, null], [-1, null, "unbekannt"], [-1, null, "fehler"]]), []);
  assert.deepEqual(ablauf([[9, false], [-1, null, "fehler"], [9, false]]), [[9, 10]]);
  const r = L.warnungPruefen({ vorhanden: false }, [10]);
  assert.deepEqual(roh(r), { stufe: 0, gewarnt: [10] });
  // fremde Einträge (z. B. aus einer älteren Version) fallen weg
  assert.deepEqual(roh(L.warnungPruefen({ vorhanden: true, prozent: 50, laedt: false, zustand: "ok" }, [10, 20, "x"])), { stufe: 0, gewarnt: [10] });
});

test("Mitteilungstexte: 10 % normal, 5 % dringend", () => {
  assert.deepEqual(roh(L.mitteilung(10, 9)), { titel: "Akku bei 9 %", text: "Bald ans Netzteil anschliessen.", dringend: false });
  assert.deepEqual(roh(L.mitteilung(5, 5)), { titel: "Akku bei 5 %", text: "Jetzt ans Netzteil anschliessen, sonst geht das Gerät bald aus.", dringend: true });
});

test("notify-send: Argumentliste, Dringlichkeit, Nummer und Ersetzen", () => {
  assert.deepEqual(roh(L.befehl(L.mitteilung(10, 9), 0)), [
    "notify-send", "--app-name=zenOS", "--icon=zenos", "--urgency=normal", "--category=device", "--print-id",
    "--", "Akku bei 9 %", "Bald ans Netzteil anschliessen.",
  ]);
  const fuenf = roh(L.befehl(L.mitteilung(5, 4), 17));
  assert.ok(fuenf.includes("--urgency=critical"));
  assert.ok(fuenf.includes("--replace-id=17"));
  // Ersetzen-Nummer vor «--», Texte danach (nie als Option gelesen)
  assert.ok(fuenf.indexOf("--replace-id=17") < fuenf.indexOf("--"));
  for (const falsch of [-1, 0, 1.5, NaN, "17", null, undefined])
    assert.ok(!roh(L.befehl(L.mitteilung(10, 9), falsch)).some((a) => a.startsWith("--replace-id")), String(falsch));
  assert.equal(L.nummer("42\n"), 42);
  for (const falsch of ["", "0", "-3", "abc", "4294967296", "12 13", null, undefined])
    assert.equal(L.nummer(falsch), 0, String(falsch));
});

test("Zurückziehen nur bei sicherem Laden", () => {
  assert.equal(L.zurueckziehen({ vorhanden: true, prozent: 9, laedt: true, zustand: "ok" }), true);
  assert.equal(L.zurueckziehen({ vorhanden: true, prozent: 9, laedt: false, zustand: "ok" }), false);
  assert.equal(L.zurueckziehen({ vorhanden: true, prozent: -1, laedt: null, zustand: "unbekannt" }), false);
  assert.equal(L.zurueckziehen({ vorhanden: false }), false);
  assert.equal(L.zurueckziehen(null), false);
});

test("Ohne Freigabe: «nicht freigegeben», kein Messwert", () => {
  const d = roh(L.lesen(datei({ akku: { vorhanden: true, prozent: null, laedt: null, zustand: "freigabe" } }), JETZT));
  assert.deepEqual(d.akku, { vorhanden: true, prozent: -1, laedt: null, zustand: "freigabe" });
  assert.equal(L.akkuWert(d.akku), "nicht freigegeben");
  assert.equal(L.akkuText(d.akku), "");
  assert.equal(L.akkuNiedrig(d.akku), false);
  assert.equal(L.warnungPruefen(d.akku, []).stufe, 0);
});
