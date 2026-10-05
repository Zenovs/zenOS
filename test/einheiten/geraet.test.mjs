// Einheitentests für shell/dienste/geraet.js (Statusdatei von zenos-argon lesen, Anzeige von Akku und Lüfter samt
// Lüfterwunsch, Warnungen bei niedrigem Akku, Ausschalten bei leerem Akku, Deckel). Läuft ohne Abhängigkeiten:
// node --test test/einheiten/
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
  // Älterer Dienst ohne Lüfterwunsch: nur Anzeige
  assert.deepEqual(d.luefter, { vorhanden: true, prozent: -1, stufe: 2, stufen: 4, upm: 3120, modus: "", mindeststufe: 0, steuerbar: false });
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
  assert.deepEqual(l, { vorhanden: true, prozent: -1, stufe: -1, stufen: -1, upm: -1, modus: "", mindeststufe: 0, steuerbar: false });
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

const luefter = (teile) => roh(L.lesen(datei({ luefter: Object.assign({ vorhanden: true, stufe: 2, stufen: 4, upm: 3120 }, teile) }), JETZT)).luefter;

test("lesen: Lüfterwunsch", () => {
  assert.deepEqual(luefter({ modus: "auto", mindeststufe: null, steuerbar: true }),
    { vorhanden: true, prozent: -1, stufe: 2, stufen: 4, upm: 3120, modus: "auto", mindeststufe: 0, steuerbar: true });
  assert.deepEqual(luefter({ modus: "mindest", mindeststufe: 3, steuerbar: true }),
    { vorhanden: true, prozent: -1, stufe: 2, stufen: 4, upm: 3120, modus: "mindest", mindeststufe: 3, steuerbar: true });
  // nicht steuerbar (z. B. Zone mit passivem Trip-Punkt): Wunsch bekannt, aber nicht bedienbar
  assert.equal(luefter({ modus: "mindest", mindeststufe: 2, steuerbar: false }).steuerbar, false);
  // unplausibel: Wunsch unbekannt, nicht bedienbar
  for (const teile of [{ modus: "mindest", mindeststufe: 5, steuerbar: true }, { modus: "mindest", mindeststufe: 0, steuerbar: true },
    { modus: "mindest", mindeststufe: "2", steuerbar: true }, { modus: "mindest", steuerbar: true }, { modus: "leise", steuerbar: true },
    { modus: "auto", steuerbar: "ja" }]) {
    const l = luefter(teile);
    assert.equal(l.steuerbar, false, JSON.stringify(teile));
    assert.equal(L.luefterWahl(l), "", JSON.stringify(teile));
  }
  assert.equal(luefter({ modus: "leise", steuerbar: true }).modus, "");
});

test("Zeile «Lüfter»: Wert mit Wunsch, vom längsten zum kürzesten", () => {
  assert.deepEqual(roh(L.luefterWerte(luefter({ modus: "mindest", mindeststufe: 2, steuerbar: true }))),
    ["Stufe 2 von 4 · 3120 U/min · mind. 2", "Stufe 2 · 3120 U/min · mind. 2", "Stufe 2 · mind. 2"]);
  assert.deepEqual(roh(L.luefterWerte(luefter({ stufe: 0, upm: 0, modus: "auto", steuerbar: true }))), ["aus · Auto"]);
  assert.deepEqual(roh(L.luefterWerte(luefter({ stufe: 3, upm: -1, modus: "auto", steuerbar: true }))), ["Stufe 3 von 4 · Auto", "Stufe 3 · Auto"]);
  // Argon ONE V3 (Prozent)
  const v3 = roh(L.lesen(datei({ geraet: "argon-one-v3", akku: { vorhanden: false }, luefter: { vorhanden: true, prozent: 55, modus: "mindest", mindeststufe: 1, steuerbar: true } }), JETZT)).luefter;
  assert.deepEqual(roh(L.luefterWerte(v3)), ["55 % · mind. 1"]);
  assert.equal(L.luefterWahl(v3), "1");
  // nicht steuerbar oder älterer Dienst: ohne Zusatz, wie bisher
  assert.deepEqual(roh(L.luefterWerte(luefter({ modus: "mindest", mindeststufe: 2, steuerbar: false })))[0], "Stufe 2 von 4 · 3120 U/min");
  assert.deepEqual(roh(L.luefterWerte(luefter({})))[0], "Stufe 2 von 4 · 3120 U/min");
  assert.deepEqual(roh(L.luefterWerte({ vorhanden: false })), []);
});

test("Wahl «Auto · 1 · 2 · 3 · 4» und Hinweis", () => {
  assert.equal(L.luefterWahl(luefter({ modus: "auto", steuerbar: true })), "auto");
  assert.equal(L.luefterWahl(luefter({ modus: "mindest", mindeststufe: 4, steuerbar: true })), "4");
  assert.equal(L.luefterWahl(luefter({ modus: "mindest", mindeststufe: 4, steuerbar: false })), "");
  assert.equal(L.luefterWahl(L.leer().luefter), "");
  assert.equal(L.luefterWahl(null), "");
  assert.equal(L.luefterHinweis("auto"), "Folgt der Temperatur.");
  assert.equal(L.luefterHinweis("2"), "Mindestens Stufe 2, bei Wärme schneller.");
  assert.equal(L.luefterHinweis(""), "");
  assert.equal(L.luefterHinweis("5"), "");
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

// --- Ausschalten bei leerem Akku (akku.ausschaltenUm) ---

const ISO = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, "+00:00");

test("lesen: ausschaltenUm nur gültig und nah an der Uhr", () => {
  const akku = (um) => ({ akku: { vorhanden: true, prozent: 3, laedt: false, zustand: "ok", ausschaltenUm: um } });
  assert.equal(L.lesen(datei(akku(ISO(JETZT + 55000))), JETZT).ausschaltenUm, JETZT + 55000);
  // Warten auf dpkg: bis 6 Min. in der Zukunft
  assert.equal(L.lesen(datei(akku(ISO(JETZT + 360000))), JETZT).ausschaltenUm, JETZT + 360000);
  for (const falsch of [null, "", "bald", 17, ISO(JETZT + 11 * 60000), ISO(JETZT - 11 * 60000)])
    assert.equal(L.lesen(datei(akku(falsch)), JETZT).ausschaltenUm, -1, String(falsch));
  // Älterer Dienst ohne das Feld, Argon ONE V3 ohne Akku, leere Datei
  assert.equal(L.lesen(datei(UP), JETZT).ausschaltenUm, -1);
  assert.equal(L.lesen(datei({ geraet: "argon-one-v3", akku: { vorhanden: false } }), JETZT).ausschaltenUm, -1);
  assert.equal(L.lesen("", JETZT).ausschaltenUm, -1);
  // Der Akku selbst bleibt, wie er war
  assert.deepEqual(roh(L.lesen(datei(akku(ISO(JETZT + 55000))), JETZT).akku), { vorhanden: true, prozent: 3, laedt: false, zustand: "ok" });
});

test("Mitteilung beim Ausschalten: dringend, mit Uhrzeit", () => {
  const um = new Date(2026, 9, 5, 22, 41, 30).getTime();
  assert.equal(L.uhrzeit(um), "22:41");
  assert.equal(L.uhrzeit(new Date(2026, 9, 5, 7, 5).getTime()), "07:05");
  assert.deepEqual(roh(L.ausschaltenMitteilung(um)), {
    titel: "Akku fast leer", text: "zenOS schaltet um 22:41 aus. Netzteil anschliessen bricht ab.", dringend: true,
  });
  const befehl = roh(L.befehl(L.ausschaltenMitteilung(um), 17));
  assert.ok(befehl.includes("--urgency=critical"));
  assert.ok(befehl.includes("--replace-id=17"));
});

test("Mitteilung beim Ausschalten: melden, ersetzen, verwerfen, vergessen", () => {
  const um = JETZT + 60000;
  const entlaedt = { vorhanden: true, prozent: 3, laedt: false, zustand: "ok" };
  assert.equal(L.ausschaltenFolge(0, um, entlaedt), "melden");
  assert.equal(L.ausschaltenFolge(um, um, entlaedt), "");
  // dpkg verschiebt die Uhrzeit: neu melden
  assert.equal(L.ausschaltenFolge(um, um + 300000, entlaedt), "melden");
  // Vorbei ohne Netzteil (unsicherer Messwert): wieder die Mitteilung von 5 %
  assert.equal(L.ausschaltenFolge(um, -1, entlaedt), "ersetzen");
  assert.equal(L.ausschaltenFolge(um, -1, { vorhanden: true, prozent: -1, laedt: null, zustand: "fehler" }), "verwerfen");
  assert.equal(L.ausschaltenFolge(um, -1, null), "verwerfen");
  // Vorbei mit dem Netzteil: das Zurückziehen beim Laden genügt
  assert.equal(L.ausschaltenFolge(um, -1, { vorhanden: true, prozent: 3, laedt: true, zustand: "ok" }), "vergessen");
  assert.equal(L.ausschaltenFolge(0, -1, entlaedt), "");
});

// --- Deckel ---

test("lesen: Deckel", () => {
  const seit = "2026-10-02T08:00:01.250+00:00";
  assert.deepEqual(roh(L.lesen(datei({ deckel: { vorhanden: true, zu: true, seit } }), JETZT).deckel),
    { vorhanden: true, zustand: "zu", seit: Date.parse(seit) });
  assert.deepEqual(roh(L.lesen(datei({ deckel: { vorhanden: true, zu: false, seit: null } }), JETZT).deckel),
    { vorhanden: true, zustand: "offen", seit: -1 });
  assert.deepEqual(roh(L.lesen(datei({ deckel: { vorhanden: true, zu: null, seit: "kaputt" } }), JETZT).deckel),
    { vorhanden: true, zustand: "", seit: -1 });
  for (const deckel of [undefined, null, { vorhanden: false }, { vorhanden: "ja", zu: true }, "zu"])
    assert.deepEqual(roh(L.lesen(datei({ deckel }), JETZT).deckel), { vorhanden: false, zustand: "", seit: -1 }, JSON.stringify(deckel));
  // Zu alte Datei: kein Deckel
  assert.equal(L.lesen(datei({ deckel: { vorhanden: true, zu: true, seit } }, -61), JETZT).deckel.vorhanden, false);
});

test("Deckel: Zuklappen, Aufklappen und nichts", () => {
  const d = (zustand, seit = -1) => ({ vorhanden: true, zustand, seit });
  const v = (zustand, seit = -1) => ({ zustand, seit });
  const T = JETZT - 2000;
  assert.equal(L.deckelAktion(v("offen"), d("zu", T), JETZT), "zuklappen");
  assert.equal(L.deckelAktion(v("zu", T), d("offen", T + 900), JETZT), "aufklappen");
  // unverändert
  assert.equal(L.deckelAktion(v("zu", T), d("zu", T), JETZT), "");
  assert.equal(L.deckelAktion(v("offen"), d("offen"), JETZT), "");
  // unbekannt oder kein Deckel: nichts, und auch kein Aufklappen
  assert.equal(L.deckelAktion(v("zu", T), { vorhanden: false, zustand: "", seit: -1 }, JETZT), "");
  assert.equal(L.deckelAktion(v("zu", T), d(""), JETZT), "");
  assert.equal(L.deckelAktion(v("zu", T), null, JETZT), "");
});

test("Deckel: Start des Dienstes ist kein Wechsel", () => {
  const d = (zustand, seit = -1) => ({ vorhanden: true, zustand, seit });
  const v = (zustand, seit = -1) => ({ zustand, seit });
  // Dienst neu gestartet (seit -1): nichts, ob offen oder zu
  assert.equal(L.deckelAktion(v("offen", JETZT - 9000), d("offen"), JETZT), "");
  assert.equal(L.deckelAktion(v("zu", JETZT - 9000), d("zu"), JETZT), "");
  // ... ausser er ging dabei auf: Bildschirm an
  assert.equal(L.deckelAktion(v("zu", JETZT - 9000), d("offen"), JETZT), "aufklappen");
  // Oberfläche startet (vorher unbekannt) mit zugeklapptem Deckel (z. B. mit externem Bildschirm): nichts
  assert.equal(L.deckelAktion(null, d("zu"), JETZT), "");
  assert.equal(L.deckelAktion(null, d("zu", JETZT - 61000), JETZT), "");
  assert.equal(L.deckelAktion(null, d("offen", JETZT - 1000), JETZT), "");
  // ... aber ein frisches Zuklappen gilt (z. B. die Oberfläche lud eben neu)
  assert.equal(L.deckelAktion(null, d("zu", JETZT - 1000), JETZT), "zuklappen");
});

test("Deckel: verpasste Wechsel sperren trotzdem", () => {
  const d = (zustand, seit = -1) => ({ vorhanden: true, zustand, seit });
  const v = (zustand, seit = -1) => ({ zustand, seit });
  // offen → (zu) → offen zwischen zwei Lesungen: nur sperren
  assert.equal(L.deckelAktion(v("offen", JETZT - 60000), d("offen", JETZT - 500), JETZT), "sperren");
  assert.equal(L.deckelAktion(v("offen"), d("offen", JETZT - 500), JETZT), "sperren");
  // zu → (offen) → zu: wieder zuklappen (sperren und dunkel)
  assert.equal(L.deckelAktion(v("zu", JETZT - 60000), d("zu", JETZT - 500), JETZT), "zuklappen");
  // auch wenn die Lücke lang war (veraltete Datei dazwischen): Zuklappen sperrt immer
  assert.equal(L.deckelAktion(v("offen", JETZT - 3600000), d("offen", JETZT - 600000), JETZT), "sperren");
});

test("Deckel: Ablauf wie in Geraet.qml (vorher = letzter bekannter Wert)", () => {
  const folge = [
    [{ vorhanden: true, zustand: "offen", seit: -1 }, ""],
    [{ vorhanden: true, zustand: "zu", seit: JETZT }, "zuklappen"],
    [{ vorhanden: true, zustand: "zu", seit: JETZT }, ""],
    // Datei kurz veraltet: unbekannt, vorher bleibt
    [{ vorhanden: false, zustand: "", seit: -1 }, ""],
    [{ vorhanden: true, zustand: "offen", seit: JETZT + 3000 }, "aufklappen"],
    [{ vorhanden: true, zustand: "offen", seit: JETZT + 3000 }, ""],
  ];
  let vorher = null;
  for (const [deckel, erwartet] of folge) {
    assert.equal(L.deckelAktion(vorher, deckel, JETZT + 4000), erwartet, JSON.stringify(deckel));
    if (deckel.vorhanden && deckel.zustand !== "")
      vorher = { zustand: deckel.zustand, seit: deckel.seit };
  }
});
