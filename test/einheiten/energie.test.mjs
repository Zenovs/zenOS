// Einheitentests für shell/dienste/energie.js (wirksame Werte, Zeitleiste, Vorwarnung, Wecktaste) und den
// Abgleich mit Einstellungen.qml und dem Schema. Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const lesen = (...teile) => readFileSync(join(wurzel, ...teile), "utf8");

// QML-Skripte («.pragma library», «.import … as Logik»): ohne diese Zeilen gewöhnliches JavaScript. Den Import
// ersetzt ein eigener Kontext mit modi/zustandslogik.js unter demselben Namen.
const Z = vm.createContext({});
vm.runInContext(lesen("shell", "modi", "zustandslogik.js").replace(/^\.pragma library\s*$/m, ""), Z);
const quelle = lesen("shell", "dienste", "energie.js");
const importe = [...quelle.matchAll(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/gm)].map((m) => [m[1], m[2]]);
const E = vm.createContext({ Logik: Z });
vm.runInContext(quelle.replace(/^\.pragma library\s*$/m, "").replace(/^\.import .*$/gm, ""), E);

const plain = (x) => JSON.parse(JSON.stringify(x));
const T0 = Date.UTC(2026, 9, 5, 20, 0, 0);
const S = 1000;
const MIN = 60 * S;

test("energie.js importiert genau zustandslogik.js als Logik", () => {
  assert.deepEqual(importe, [["../modi/zustandslogik.js", "Logik"]]);
  assert.equal(E.LP, Z.LEITPLANKEN);
});

test("bildschirmMinuten: 1–10, gerundet, Standard 1", () => {
  const faelle = [
    [1, 1], [5, 5], [10, 10], [0, 1], [-3, 1], [11, 10], [99, 10], [2.4, 2], [2.5, 3], [9.6, 10],
    ["4", 4], [" 7 ", 7], ["2,5", 3], ["2.5", 3], [".5", 1], ["5.", 5], ["+3", 3], ["-2", 1],
    [undefined, 1], [null, 1], [true, 1], [false, 1], ["", 1], ["  ", 1], ["aus", 1], ["nie", 1], ["1e1", 1],
    ["0x5", 1], ["5 Min.", 1], ["1_0", 1], [NaN, 1], [Infinity, 1], [-Infinity, 1], [[5], 1], [{ wert: 5 }, 1],
  ];
  for (const [wunsch, erwartet] of faelle)
    assert.equal(E.bildschirmMinuten(wunsch), erwartet, `bildschirmMinuten(${JSON.stringify(wunsch)})`);
});

test("ausschaltenMinuten: 30–240, gerundet, Standard 60", () => {
  const faelle = [
    [60, 60], [30, 30], [240, 240], [29, 30], [0, 30], [-60, 30], [241, 240], [1e9, 240], [90.4, 90],
    [45, 45], ["120", 120], ["90,6", 91], [undefined, 60], [null, 60], ["nie", 60], [true, 60], [NaN, 60],
  ];
  for (const [wunsch, erwartet] of faelle)
    assert.equal(E.ausschaltenMinuten(wunsch), erwartet, `ausschaltenMinuten(${JSON.stringify(wunsch)})`);
});

test("ausschaltenArt und einAusTaste: feste Wörter, sonst der Standard", () => {
  for (const art of ["nie", "akku", "immer"]) assert.equal(E.ausschaltenArt(art), art);
  for (const art of [undefined, null, "", "Akku", "ja", true, 1, ["immer"]]) assert.equal(E.ausschaltenArt(art), "akku");
  for (const t of ["sperren", "menue", "ausschalten"]) assert.equal(E.einAusTaste(t), t);
  for (const t of [undefined, "menü", "MENUE", "neustart", 0]) assert.equal(E.einAusTaste(t), "sperren");
  assert.deepEqual(plain(E.AUSSCHALTEN), ["nie", "akku", "immer"]);
  assert.deepEqual(plain(E.EIN_AUS_TASTE), ["sperren", "menue", "ausschalten"]);
  assert.ok(Object.isFrozen(E.AUSSCHALTEN) && Object.isFrozen(E.EIN_AUS_TASTE) && Object.isFrozen(E.STANDARD));
});

test("wirksam: alle Werte begrenzt, ohne Datei die Standards", () => {
  assert.deepEqual(plain(E.wirksam(null)), {
    sperreMinuten: 5, bildschirmMinuten: 1, ausschalten: "akku", ausschaltenMinuten: 60, einAusTaste: "sperren",
  });
  assert.deepEqual(plain(E.wirksam({
    sperreNachMinuten: 40, bildschirmAusNachSperre: 0, ausschalten: "immer", ausschaltenNachMinuten: 10, einAusTaste: "menue",
  })), { sperreMinuten: 15, bildschirmMinuten: 1, ausschalten: "immer", ausschaltenMinuten: 30, einAusTaste: "menue" });
  assert.deepEqual(plain(E.wirksam("kaputt")), plain(E.wirksam({})));
});

test("Akkubetrieb nur bei sicherer Messung; unbekannt gilt als Netzteil", () => {
  const akku = { vorhanden: true, prozent: 40, laedt: false, zustand: "ok" };
  assert.equal(E.imAkkubetrieb(akku), true);
  assert.equal(E.imAkkubetrieb(Object.assign({}, akku, { laedt: true })), false);
  assert.equal(E.imAkkubetrieb(Object.assign({}, akku, { laedt: null })), false);
  assert.equal(E.imAkkubetrieb(Object.assign({}, akku, { zustand: "unbekannt" })), false);
  assert.equal(E.imAkkubetrieb(Object.assign({}, akku, { zustand: "fehler" })), false);
  assert.equal(E.imAkkubetrieb(Object.assign({}, akku, { vorhanden: false })), false);
  assert.equal(E.imAkkubetrieb(null), false);
  assert.equal(E.imAkkubetrieb(undefined), false);

  assert.equal(E.ausschaltenAktiv("immer", null), true);
  assert.equal(E.ausschaltenAktiv("immer", Object.assign({}, akku, { laedt: true })), true);
  assert.equal(E.ausschaltenAktiv("akku", akku), true);
  assert.equal(E.ausschaltenAktiv("akku", Object.assign({}, akku, { laedt: true })), false);
  assert.equal(E.ausschaltenAktiv("akku", null), false);
  assert.equal(E.ausschaltenAktiv("nie", akku), false);
  // Unbekannte Art: der Standard «akku»
  assert.equal(E.ausschaltenAktiv("quatsch", akku), true);
  assert.equal(E.ausschaltenAktiv("quatsch", null), false);
});

test("Zeitleiste: Sperre, dann Bildschirm aus, dann ausschalten", () => {
  const akku = { vorhanden: true, prozent: 40, laedt: false, zustand: "ok" };
  // Ohne Akku schaltet «akku» (der Standard) nie aus: dann steht es auch nicht in der Zeitleiste
  assert.deepEqual(plain(E.zeitleiste({}, null)), [
    { was: "sperre", minuten: 5, aktiv: true },
    { was: "bildschirm", minuten: 6, aktiv: true },
  ]);
  assert.equal(E.zeitleiste({}, { vorhanden: false }).length, 2);
  // Mit Akku am Netzteil: steht da, gilt aber gerade nicht
  assert.deepEqual(plain(E.zeitleiste({}, Object.assign({}, akku, { laedt: true })))[2], { was: "ausschalten", minuten: 65, aktiv: false });
  assert.deepEqual(plain(E.zeitleiste({ ausschalten: "akku" }, akku))[2], { was: "ausschalten", minuten: 65, aktiv: true });
  assert.equal(E.zeitleiste({ ausschalten: "nie" }, akku).length, 2);
  assert.deepEqual(plain(E.zeitleiste({ ausschalten: "immer" }, null))[2], { was: "ausschalten", minuten: 65, aktiv: true });
  const lang = plain(E.zeitleiste({ sperreNachMinuten: 15, bildschirmAusNachSperre: 10, ausschalten: "immer", ausschaltenNachMinuten: 30 }, null));
  assert.deepEqual(lang.map((e) => e.minuten), [15, 25, 45]);
  // Reihenfolge gilt für alle Werte innerhalb der Leitplanken
  for (const s of [1, 15]) {
    for (const b of [1, 10]) {
      for (const m of [30, 240]) {
        const l = E.zeitleiste({ sperreNachMinuten: s, bildschirmAusNachSperre: b, ausschalten: "immer", ausschaltenNachMinuten: m }, null);
        assert.ok(l[0].minuten < l[1].minuten && l[1].minuten < l[2].minuten, `${s}/${b}/${m}`);
      }
    }
  }
  assert.equal(E.zeitleisteText({}, null), "Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min.");
  assert.equal(E.zeitleisteText({}, akku), "Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min. · Aus nach 65 Min. im Akkubetrieb");
  assert.equal(E.zeitleisteText({ ausschalten: "immer", ausschaltenNachMinuten: 55 }, null), "Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min. · Aus nach 1 Std.");
  assert.equal(E.zeitleisteText({ ausschalten: "immer", sperreNachMinuten: 15, ausschaltenNachMinuten: 225 }, null), "Gesperrt nach 15 Min. · Bildschirm aus nach 16 Min. · Aus nach 4 Std.");
  assert.equal(E.zeitleisteText({ ausschalten: "nie" }, null), "Gesperrt nach 5 Min. · Bildschirm aus nach 6 Min.");
});

test("Vorwarnung: 60 s, dann ausschalten; Eingabe bricht ab", () => {
  let z = E.vorwarnung();
  assert.equal(z.phase, "aus");
  assert.equal(E.vorwarnungSchritt(z, T0), "nichts");
  z = E.vorwarnungStarten(z, T0);
  assert.deepEqual(plain(z), { phase: "laeuft", seit: T0, um: T0 + 60 * S, grund: "" });
  // Ein zweiter Start setzt die Zeit nicht zurück
  assert.equal(E.vorwarnungStarten(z, T0 + 30 * S), z);
  assert.equal(E.vorwarnungSchritt(z, T0), "nichts");
  assert.equal(E.vorwarnungSchritt(z, T0 + 59 * S), "nichts");
  assert.equal(E.vorwarnungSchritt(z, T0 + 60 * S), "ausschalten");
  assert.equal(E.vorwarnungSchritt(z, T0 + 5 * MIN), "ausschalten");
  // Zu alt oder die Uhr ging zurück: nie ausschalten
  assert.equal(E.vorwarnungSchritt(z, T0 + 5 * MIN + 1), "abbrechen");
  assert.equal(E.vorwarnungSchritt(z, T0 - 1), "abbrechen");
  assert.equal(E.vorwarnungSchritt({ phase: "laeuft", seit: NaN, um: 0 }, T0), "abbrechen");

  const ab = E.vorwarnungAbbrechen(z, "eingabe");
  assert.deepEqual(plain(ab), { phase: "aus", seit: 0, um: 0, grund: "eingabe" });
  assert.equal(E.vorwarnungSchritt(ab, T0 + 60 * S), "nichts");
  assert.equal(E.vorwarnungAbbrechen(z, 42).grund, "");
  // Nach dem Abbruch beginnt eine neue Vorwarnung wieder mit vollen 60 s
  assert.equal(E.vorwarnungStarten(ab, T0 + 10 * MIN).um, T0 + 10 * MIN + 60 * S);
});

test("Vorwarnung: blockiert, neuer Versuch nach 5 Min.", () => {
  const z = E.vorwarnungBlockiert(E.vorwarnungStarten(E.vorwarnung(), T0), T0 + 60 * S, "ssh");
  assert.deepEqual(plain(z), { phase: "warten", seit: T0 + 60 * S, um: T0 + 6 * MIN, grund: "ssh" });
  assert.equal(E.vorwarnungSchritt(z, T0 + 5 * MIN), "nichts");
  assert.equal(E.vorwarnungSchritt(z, T0 + 6 * MIN), "neu-pruefen");
  assert.equal(E.vorwarnungSchritt(z, T0), "neu-pruefen");
  // Aus «warten» beginnt eine neue Vorwarnung (nie direkt ausschalten)
  const neu = E.vorwarnungStarten(z, T0 + 6 * MIN);
  assert.equal(neu.phase, "laeuft");
  assert.equal(E.vorwarnungSchritt(neu, T0 + 6 * MIN), "nichts");
  // Unbekanntes gilt als «aus»
  for (const kaputt of [null, undefined, {}, { phase: "ausschalten" }, "laeuft"])
    assert.equal(E.vorwarnungSchritt(kaputt, T0), "nichts");
});

test("Wecktaste: genau eine Taste wird verworfen", () => {
  let z = E.weckzustand();
  assert.equal(E.wecktasteVerwerfen(z, T0), false);

  // Taste weckt (kommt vor dem Signal «an»): verworfen, die nächste nicht mehr
  z = E.bildschirmDunkel(z);
  assert.equal(E.wecktasteVerwerfen(z, T0), true);
  z = E.wecktasteGesehen(z);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 1), false);
  z = E.bildschirmHell(z, T0 + 5);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 10), false);

  // «an» kommt vor der Taste: die erste Taste innerhalb 1 s verworfen, danach nicht mehr
  z = E.bildschirmHell(E.bildschirmDunkel(E.weckzustand()), T0);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 999), true);
  z = E.wecktasteGesehen(z);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 1000), false);

  // Geweckt mit dem Touchpad: Das Passwort danach (nach 1 s) bleibt ganz
  z = E.bildschirmHell(E.bildschirmDunkel(E.weckzustand()), T0);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 1000), false);
  assert.equal(E.wecktasteVerwerfen(z, T0 - 1), false);

  // Bleibt «dunkel» hängen, geht trotzdem nur eine Taste verloren
  z = E.bildschirmDunkel(E.weckzustand());
  assert.equal(E.wecktasteVerwerfen(z, T0), true);
  z = E.wecktasteGesehen(z);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 5 * MIN), false);
  // Doppelte Meldung «aus» gibt keine zweite Wecktaste
  assert.equal(E.wecktasteVerwerfen(E.bildschirmDunkel(z), T0), false);

  // «an», ohne dass es dunkel war (z. B. beim Start von zenos-idle): nichts wird verworfen
  z = E.bildschirmHell(E.weckzustand(), T0);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 1), false);
  for (const kaputt of [null, undefined, "dunkel", {}])
    assert.equal(E.wecktasteVerwerfen(kaputt, T0), false);
});

test("Vorwarnung: Die Taste, die abbricht, landet nicht im Passwortfeld (genau eine)", () => {
  // Bildschirm war dunkel, die Vorwarnung schaltet ihn ohne Eingabe an
  let z = E.vorwarnungGezeigt(E.bildschirmDunkel(E.weckzustand()));
  assert.equal(z.dunkel, false);
  // Die Meldung «an» danach ändert nichts
  assert.deepEqual(plain(E.bildschirmHell(z, T0)), plain(z));
  // Auch nach 50 s: die erste Taste wird verworfen, die zweite nicht
  assert.equal(E.wecktasteVerwerfen(z, T0 + 50 * S), true);
  z = E.wecktasteGesehen(z);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 50 * S + 10), false);
  // Danach meldet der Dienst das Ende: keine weitere Taste geht verloren
  z = E.vorwarnungVorbei(z, T0 + 50 * S + 20);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 50 * S + 30), false);

  // Umgekehrt: Die Eingabe (Ende der Vorwarnung) kommt vor der Taste. Die Taste bis 1 s danach wird verworfen.
  z = E.vorwarnungVorbei(E.vorwarnungGezeigt(E.weckzustand()), T0);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 999), true);
  z = E.wecktasteGesehen(z);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 1000), false);
  // Abbruch mit der Maus: Das Passwort danach bleibt ganz
  z = E.vorwarnungVorbei(E.vorwarnungGezeigt(E.weckzustand()), T0);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 3 * S), false);
  // Ende ohne Vorwarnung (z. B. doppelt gemeldet): nichts ändert sich
  const ruhig = E.wecktasteGesehen(E.weckzustand());
  assert.deepEqual(plain(E.vorwarnungVorbei(ruhig, T0)), plain(ruhig));
  assert.deepEqual(plain(E.vorwarnungVorbei(null, T0)), plain(E.weckzustand()));
  // Blockiert: wieder dunkel, die nächste Taste ist wieder eine Wecktaste
  z = E.bildschirmDunkel(E.vorwarnungVorbei(E.wecktasteGesehen(E.vorwarnungGezeigt(E.weckzustand())), T0));
  assert.equal(E.wecktasteVerwerfen(z, T0 + 10 * MIN), true);
});

test("Ein/Aus-Taste gesperrt: dunkel oder eben geweckt heisst an, sonst aus", () => {
  assert.equal(E.tasteGesperrt(E.bildschirmDunkel(E.weckzustand()), T0), "an");
  // Der Druck selbst hat den Bildschirm schon geweckt (Eingabe), sein Befehl kommt danach an
  const geweckt = E.wecktasteGesehen(E.bildschirmHell(E.bildschirmDunkel(E.weckzustand()), T0));
  assert.equal(E.tasteGesperrt(geweckt, T0 + 300), "an");
  assert.equal(E.tasteGesperrt(geweckt, T0 + 1999), "an");
  assert.equal(E.tasteGesperrt(geweckt, T0 + 2000), "aus");
  assert.equal(E.tasteGesperrt(geweckt, T0 - 1), "aus");
  assert.equal(E.tasteGesperrt(E.weckzustand(), T0), "aus");
  assert.equal(E.tasteGesperrt(E.vorwarnungGezeigt(E.weckzustand()), T0), "aus");
  for (const kaputt of [null, undefined, "dunkel", 5])
    assert.equal(E.tasteGesperrt(kaputt, T0), "aus");
});

// --- Abgleich mit Einstellungen.qml, Leitplanken.qml und dem Schema ---------------

const SCHEMA = JSON.parse(lesen("config", "schema", "einstellungen.schema.json")).properties;
const EINSTELLUNGEN = lesen("shell", "dienste", "Einstellungen.qml");

function qmlDefaults() {
  const block = /readonly property var _defaults: \(\{([\s\S]*?)\}\)/.exec(EINSTELLUNGEN);
  assert.ok(block, "_defaults in Einstellungen.qml");
  return Object.fromEntries([...block[1].matchAll(/^\s*(\w+): (.+?),?\s*$/gm)].map((m) => [m[1], JSON.parse(m[2])]));
}

function adapterDefaults() {
  const block = /JsonAdapter \{([\s\S]*?)\n {4}\}/.exec(EINSTELLUNGEN);
  assert.ok(block, "JsonAdapter in Einstellungen.qml");
  return Object.fromEntries([...block[1].matchAll(/^\s*property (\w+) (\w+): (.+?)\s*$/gm)].map((m) => [m[2], { typ: m[1], wert: JSON.parse(m[3]) }]));
}

test("Standards überall gleich: energie.js, Einstellungen.qml, Schema", () => {
  const standard = plain(E.wirksam({}));
  const d = qmlDefaults();
  const a = adapterDefaults();
  const erwartet = {
    bildschirmAusNachSperre: standard.bildschirmMinuten,
    ausschalten: standard.ausschalten,
    ausschaltenNachMinuten: standard.ausschaltenMinuten,
    einAusTaste: standard.einAusTaste,
  };
  for (const [k, wert] of Object.entries(erwartet)) {
    assert.equal(d[k], wert, `_defaults.${k}`);
    assert.deepEqual(a[k], { typ: "var", wert }, `JsonAdapter.${k}`);
    assert.match(EINSTELLUNGEN, new RegExp(`property alias ${k}: json\\.${k}\\n`), `alias ${k}`);
    assert.ok(SCHEMA[k], `Schema ${k}`);
  }
  assert.equal(d.bildschirmAusNachSperre, Z.LEITPLANKEN.bildschirmAusNachSperreStandard);
  assert.equal(d.ausschaltenNachMinuten, Z.LEITPLANKEN.ausschaltenMinutenStandard);
});

test("Grenzen überall gleich: Leitplanken, Schema", () => {
  const LP = Z.LEITPLANKEN;
  assert.deepEqual([SCHEMA.bildschirmAusNachSperre.type, SCHEMA.bildschirmAusNachSperre.minimum, SCHEMA.bildschirmAusNachSperre.maximum],
    ["integer", LP.bildschirmAusNachSperreMin, LP.bildschirmAusNachSperreMax]);
  assert.deepEqual([SCHEMA.ausschaltenNachMinuten.type, SCHEMA.ausschaltenNachMinuten.minimum, SCHEMA.ausschaltenNachMinuten.maximum],
    ["integer", LP.ausschaltenMinutenMin, LP.ausschaltenMinutenMax]);
  assert.deepEqual([SCHEMA.sperreNachMinuten.minimum, SCHEMA.sperreNachMinuten.maximum], [LP.sperreMinutenMin, LP.sperreMinutenMax]);
  assert.deepEqual(SCHEMA.ausschalten.enum, plain(E.AUSSCHALTEN));
  assert.deepEqual(SCHEMA.einAusTaste.enum, plain(E.EIN_AUS_TASTE));
});

test("Leitplanken.qml reicht die Grenzen aus zustandslogik.js weiter", () => {
  const qml = lesen("shell", "dienste", "Leitplanken.qml");
  for (const k of ["bildschirmNurGesperrt", "bildschirmAusNachSperreMin", "bildschirmAusNachSperreMax", "ausschaltenMinutenMin",
    "ausschaltenMinutenMax", "vorwarnungSekunden", "sperreTrotzHemmerMinuten", "akkuAusschaltenProzent"])
    assert.match(qml, new RegExp(`readonly property \\w+ ${k}: Logik\\.LEITPLANKEN\\.${k}\\n`), k);
  assert.match(qml, /function bildschirmMinuten\(wunsch: var\): int \{\s*return EnergieLogik\.bildschirmMinuten\(wunsch\);/);
  assert.match(qml, /function ausschaltenMinuten\(wunsch: var\): int \{\s*return EnergieLogik\.ausschaltenMinuten\(wunsch\);/);
});

test("Beispiel einstellungen.energie.json: neutral und innerhalb der Leitplanken", () => {
  const b = JSON.parse(lesen("config", "beispiele", "einstellungen.energie.json"));
  assert.equal(b.name, undefined);
  assert.equal(b.ort, undefined);
  const w = plain(E.wirksam(b));
  assert.equal(w.bildschirmMinuten, b.bildschirmAusNachSperre);
  assert.equal(w.ausschaltenMinuten, b.ausschaltenNachMinuten);
  assert.equal(w.ausschalten, b.ausschalten);
  assert.equal(w.einAusTaste, b.einAusTaste);
});
