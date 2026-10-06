// Einheitentests für shell/greeter/bildschirm.js (Bildschirm am Login-Bildschirm: nach 1 Min. ohne Eingabe aus, die
// Eingabe, die weckt, wird verworfen, was scheitert, lässt ihn an) und die Verdrahtung in Bildschirm.qml,
// Anmeldefenster.qml und greeter.qml. Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const lesen = (...teile) => readFileSync(join(wurzel, ...teile), "utf8");
const ohneKopf = (quelle) => quelle.replace(/^\.pragma library\s*$/m, "").replace(/^\.import .*$/gm, "");

// QML-Skripte: «.pragma library» und «.import … as Name» weg, die Importe als eigene Kontexte unter demselben Namen
const Z = vm.createContext({});
vm.runInContext(ohneKopf(lesen("shell", "modi", "zustandslogik.js")), Z);
const E = vm.createContext({ Logik: Z });
vm.runInContext(ohneKopf(lesen("shell", "dienste", "energie.js")), E);
const quelle = lesen("shell", "greeter", "bildschirm.js");
const importe = [...quelle.matchAll(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/gm)].map((m) => [m[1], m[2]]);
const B = vm.createContext({ EnergieLogik: E });
vm.runInContext(ohneKopf(quelle), B);

const plain = (x) => JSON.parse(JSON.stringify(x));
const T0 = Date.UTC(2026, 9, 6, 22, 0, 0);
const OK = '{\n  "errors": [ ]\n}\n';

// Ein Aufruf von wlopm von Anfang bis Ende
function lauf(z, ok, jetzt = T0) {
  const befehl = B.naechster(z, jetzt);
  assert.notEqual(befehl, "", "ein Aufruf steht an");
  z = B.gestartet(z, befehl);
  assert.equal(B.naechster(z, jetzt), "", "nie zwei Aufrufe zugleich");
  return [befehl, B.fertig(z, befehl, ok, jetzt)];
}

// Bis zum dunklen Bildschirm
function dunkel() {
  let z = B.leerlauf(B.zustand(), false);
  let befehl;
  [befehl, z] = lauf(z, true);
  assert.equal(befehl, "aus");
  return z;
}

test("bildschirm.js importiert genau energie.js; die Minute steht eingefroren in den Leitplanken", () => {
  assert.deepEqual(importe, [["../dienste/energie.js", "EnergieLogik"]]);
  assert.equal(Z.LEITPLANKEN.loginBildschirmAusMinuten, 1);
  assert.ok(Object.isFrozen(Z.LEITPLANKEN));
  assert.throws(() => {
    "use strict";
    Z.LEITPLANKEN.loginBildschirmAusMinuten = 0;
  });
  assert.equal(Z.LEITPLANKEN.loginBildschirmAusMinuten, 1);
  // Leitplanken.qml reicht den Wert weiter (Seite «Energie»)
  assert.match(lesen("shell", "dienste", "Leitplanken.qml"),
    /readonly property int loginBildschirmAusMinuten: Logik\.LEITPLANKEN\.loginBildschirmAusMinuten\n/);
});

test("Ablauf: eine Minute ohne Eingabe aus, eine Eingabe wieder an", () => {
  let z = B.zustand();
  assert.equal(B.naechster(z, T0), "", "beim Start an, nichts zu tun");
  assert.equal(B.wecktasteOffen(z), false);

  z = B.leerlauf(z, false);
  assert.equal(z.soll, "aus");
  assert.equal(B.naechster(z, T0), "aus");
  z = B.gestartet(z, "aus");
  // Die Wecktaste steht schon vor dem Abschalten aus: Eine Taste genau dann landet nicht im Feld
  assert.equal(B.wecktasteOffen(z), true);
  z = B.fertig(z, "aus", true, T0);
  assert.deepEqual([z.ist, z.dunkelSicher, z.laeuft], ["aus", true, ""]);
  assert.equal(B.naechster(z, T0 + 3600e3), "", "dunkel bleibt dunkel, bis eine Eingabe kommt");

  z = B.eingabe(z);
  assert.equal(B.naechster(z, T0), "an");
  let befehl;
  [befehl, z] = lauf(z, true, T0 + 10);
  assert.equal(befehl, "an");
  assert.deepEqual([z.ist, z.dunkelSicher], ["an", false]);
  // Weckte die Maus, gilt die Wecktaste nur noch für die Schonfrist (Timer in Bildschirm.qml)
  assert.equal(B.wecktasteOffen(z), true);
  z = B.schonfristVorbei(z);
  assert.equal(B.wecktasteOffen(z), false);
  assert.equal(B.naechster(z, T0 + 20), "");
});

test("Wecktaste: genau eine Eingabe wird verworfen, ob Taste, Klick oder Berührung", () => {
  let z = dunkel();
  assert.equal(B.wecktasteOffen(z), true);
  // Die erste Taste weckt und ist verworfen
  z = B.verworfen(z);
  assert.equal(B.wecktasteOffen(z), false, "nur eine");
  assert.equal(z.soll, "an");
  assert.equal(B.naechster(z, T0), "an");
  // Eine zweite Meldung ändert nichts (der Wecker gibt den Fokus nach der ersten Taste zurück)
  assert.deepEqual(plain(B.verworfen(z)), plain(z));
  let befehl;
  [befehl, z] = lauf(z, true);
  assert.equal(befehl, "an");
  assert.equal(B.wecktasteOffen(z), false, "nach dem Einschalten keine neue Wecktaste");
  assert.deepEqual(plain(B.schonfristVorbei(z)), plain(z));

  // Wieder dunkel: wieder genau eine
  z = B.leerlauf(z, false);
  [befehl, z] = lauf(z, true);
  assert.equal(befehl, "aus");
  assert.equal(B.wecktasteOffen(z), true);

  // Solange es dunkel ist, endet die Schonfrist nicht
  assert.equal(B.wecktasteOffen(B.schonfristVorbei(z)), true);

  // Kaputte Zustände verwerfen nichts
  for (const kaputt of [null, undefined, {}, { weck: null }, { weck: { offen: "ja" } }])
    assert.equal(B.wecktasteOffen(kaputt), false);
});

test("Zeitgeber: Jede Eingabe beginnt die Minute neu, aus erst nach einer neuen Minute ohne Eingabe", () => {
  // Eingabe, während das Ausschalten noch läuft: danach gleich wieder an, die Wecktaste bleibt bis dahin
  let z = B.leerlauf(B.zustand(), false);
  z = B.gestartet(z, B.naechster(z, T0));
  z = B.eingabe(z);
  assert.equal(B.naechster(z, T0), "", "erst fertig ausschalten");
  z = B.fertig(z, "aus", true, T0);
  assert.equal(B.naechster(z, T0), "an");
  assert.equal(B.wecktasteOffen(z), true);

  // Nach einer Eingabe bleibt er an, egal wie lange, bis der Compositor wieder eine Minute ohne Eingabe meldet
  z = B.eingabe(B.zustand());
  for (const nach of [0, 61e3, 3600e3])
    assert.equal(B.naechster(z, T0 + nach), "", `${nach} ms`);
  assert.equal(B.naechster(B.leerlauf(z, false), T0), "aus");

  // Gewecktes ohne Eingabe (Vorwarnung vorbei, Deckel auf): Die Minute beginnt neu, solange keine Eingabe kam
  z = B.wecken(dunkel());
  assert.equal(B.minuteNeu(z, true, false), true);
  assert.equal(B.minuteNeu(z, false, false), false, "nach einer Eingabe zählt der Compositor selbst");
  assert.equal(B.minuteNeu(z, true, true), false, "während der Vorwarnung bleibt er an");
  assert.equal(B.minuteNeu(null, true, false), false);
});

test("Zeitgeber in Bildschirm.qml: eine Minute im Compositor, ohne Rücksicht auf Hemmer, jede Eingabe weckt", () => {
  const qml = lesen("shell", "greeter", "Bildschirm.qml");
  assert.match(qml, /readonly property int _minuten: Logik\.LEITPLANKEN\.loginBildschirmAusMinuten\n/);
  const monitor = /IdleMonitor \{\s*id: ausMonitor\s*([\s\S]*?)\n {4}\}/.exec(qml);
  assert.ok(monitor, "IdleMonitor ausMonitor");
  assert.match(monitor[1], /respectInhibitors: false/);
  assert.match(monitor[1], /timeout: root\._minuten \* 60\n/);
  assert.match(monitor[1], /if \(isIdle\)\s*root\._leerlauf\(\);\s*else\s*root\._eingabe\(\);/);
  assert.doesNotMatch(monitor[1], /enabled:/, "zählt immer");
  assert.match(qml, /id: nachWecken\s*interval: root\._minuten \* 60000\n/);
  assert.match(qml, /id: schonfrist\s*interval: EnergieLogik\.WECKEN_SCHONFRIST_MS\n/);
  assert.equal(E.WECKEN_SCHONFRIST_MS, 300);
});

test("Fehlerfall: Scheitert das Ausschalten, bleibt (oder wird) der Bildschirm an", () => {
  let z = B.leerlauf(B.zustand(), false);
  let befehl;
  [befehl, z] = lauf(z, false);
  assert.equal(befehl, "aus");
  assert.deepEqual([z.soll, z.ist, z.ausFehler, z.dunkelSicher], ["an", "unklar", 1, false]);
  assert.equal(B.wecktasteOffen(z), false, "keine Wecktaste, wenn er nicht sicher dunkel ist");
  // Sofort wieder an (ein Teil kann schon dunkel sein)
  [befehl, z] = lauf(z, true);
  assert.equal(befehl, "an");
  assert.equal(z.ist, "an");

  // Nach drei Fehlschlägen in Folge versucht es dieser Login nicht mehr
  for (let i = 2; i <= B.AUS_VERSUCHE; i++) {
    z = B.leerlauf(z, false);
    [befehl, z] = lauf(z, false);
    assert.equal(befehl, "aus");
    [befehl, z] = lauf(z, true);
    assert.equal(befehl, "an");
  }
  assert.equal(z.ausFehler, 3);
  assert.equal(B.leerlauf(z, false).soll, "an");
  assert.equal(B.naechster(B.leerlauf(z, false), T0), "");
  assert.equal(B.minuteNeu(z, true, false), false);

  // Ein Erfolg setzt die Zählung zurück
  z = B.leerlauf(B.zustand(), false);
  [, z] = lauf(z, false);
  [, z] = lauf(z, true);
  z = B.leerlauf(z, false);
  [, z] = lauf(z, true);
  assert.equal(z.ausFehler, 0);
});

test("Fehlerfall: wlopm fehlt oder antwortet unbrauchbar, dann gibt der Login auf und startet nicht neu", () => {
  let z = B.leerlauf(B.zustand(), false);
  [, z] = lauf(z, false);
  let jetzt = T0;
  for (let n = 1; n <= B.AN_VERSUCHE; n++) {
    const befehl = B.naechster(z, jetzt);
    assert.equal(befehl, "an", `Versuch ${n}`);
    z = B.fertig(B.gestartet(z, "an"), "an", false, jetzt);
    assert.equal(z.ist, "unklar");
    if (n < B.AN_VERSUCHE) {
      assert.equal(B.wartet(z), true);
      assert.equal(B.naechster(z, jetzt + n * 1000 - 1), "", "Pause");
      jetzt += n * 1000;
    }
  }
  assert.equal(B.wartet(z), false);
  assert.equal(B.naechster(z, jetzt + 3600e3), "");
  assert.equal(B.aufgegeben(z), true);
  assert.equal(B.neustartNoetig(z), false, "nie sicher dunkel: kein Neustart");
});

test("Fehlerfall: sicher dunkel und geht nicht mehr an, dann startet sich der Login neu", () => {
  let z = dunkel();
  z = B.verworfen(z);
  let jetzt = T0;
  for (let n = 1; n <= B.AN_VERSUCHE; n++) {
    assert.equal(B.neustartNoetig(z), false);
    assert.equal(B.naechster(z, jetzt), "an", `Versuch ${n}`);
    z = B.fertig(B.gestartet(z, "an"), "an", false, jetzt);
    assert.equal(z.ist, "aus", "bleibt sicher dunkel");
    jetzt += n * 1000;
  }
  assert.equal(B.neustartNoetig(z), true);
  assert.equal(B.aufgegeben(z), false);
  // Klappt es vorher doch, ist alles gut
  let w = dunkel();
  w = B.eingabe(w);
  w = B.fertig(B.gestartet(w, "an"), "an", false, T0);
  w = B.fertig(B.gestartet(w, "an"), "an", true, T0 + 1000);
  assert.deepEqual([w.ist, w.anFehler, B.neustartNoetig(w), B.wartet(w)], ["an", 0, false, false]);
});

test("Vorwarnung und Deckel: an ohne Wecktaste, während der Vorwarnung nie aus", () => {
  let z = B.zustand();
  assert.deepEqual(plain(B.leerlauf(z, true)), plain(z), "während der Vorwarnung bleibt er an");
  z = dunkel();
  z = B.wecken(z);
  assert.equal(z.soll, "an");
  assert.equal(B.wecktasteOffen(z), false, "wer jetzt tippt, tippt ins Feld");
  let befehl;
  [befehl, z] = lauf(z, true);
  assert.equal(befehl, "an");
  assert.equal(B.wecktasteOffen(z), false);
  // Vorwarnung vorbei, ohne Eingabe: nach der neuen Minute wieder aus
  assert.equal(B.minuteNeu(z, true, false), true);
  assert.equal(B.naechster(B.leerlauf(z, false), T0), "aus");
});

test("wlopm: nur ein Objekt mit leerer Fehlerliste und Exit 0 ist Erfolg", () => {
  assert.equal(B.wlopmOk(0, OK), true);
  assert.equal(B.wlopmOk(0, '{"errors":[]}'), true);
  const falsch = [
    [1, OK], [-1, OK], [124, OK], [127, ""], [0, ""], [0, "kaputt"], [0, "[]"], [0, "null"], [0, "{}"],
    [0, '{"errors": null}'], [0, '{"errors": "keine"}'],
    [0, '{"errors": [{"output": "HDMI-A-1", "error": "set power mode failed"}]}'],
    [0, '[{"output": "HDMI-A-1", "power-mode": "off"}]'],
    ["0", OK], [null, OK], [0, undefined],
  ];
  for (const [code, text] of falsch)
    assert.equal(B.wlopmOk(code, text), false, `${code} ${text}`);
});

test("wlopm: feste Argumentliste mit Zeitlimit, keine Shell", () => {
  assert.deepEqual(plain(B.befehl("aus")), ["timeout", "5", "wlopm", "--json", "--off", "*"]);
  assert.deepEqual(plain(B.befehl("an")), ["timeout", "5", "wlopm", "--json", "--on", "*"]);
  // Alles andere schaltet an (die sichere Richtung)
  for (const was of ["", "AUS", null, "--off"])
    assert.deepEqual(plain(B.befehl(was)), ["timeout", "5", "wlopm", "--json", "--on", "*"]);
  const qml = lesen("shell", "greeter", "Bildschirm.qml");
  assert.match(qml, /wlopm\.command = BildschirmLogik\.befehl\(befehl\);/);
  assert.doesNotMatch(qml + quelle, /"(ba|da|z)?sh",\s*"-l?c"/);
});

test("Anmeldefenster: Wecker mit dem Tastaturfokus und Klickfang über allem, nur solange die Wecktaste aussteht", () => {
  const qml = lesen("shell", "greeter", "Anmeldefenster.qml");
  assert.match(qml, /required property Bildschirm bildschirm\n/);
  // Der Wecker verwirft genau eine Taste und gibt den Fokus spätestens dann zurück
  const wecker = /Item \{\s*id: wecker\s*([\s\S]*?)\n {4}\}/.exec(qml);
  assert.ok(wecker, "Item wecker");
  assert.match(wecker[1], /Keys\.onPressed: event => \{\s*event\.accepted = true;\s*root\.bildschirm\.verworfen\("Taste"\);\s*[^\n]*\n\s*root\._weckerZurueck\(\);\s*\}/);
  // Fokus: «focus», nicht «activeFocus» (ein Fenster ohne Tastaturfokus lässt den Wecker nie hängen)
  assert.match(qml, /function _weckerZurueck\(\): void \{\s*if \(!wecker\.focus\)\s*return;/);
  assert.match(qml, /function onWecktasteOffenChanged\(\): void \{\s*root\._weckerFokus\(\);/);
  // Klickfang: über allem, nur bei offener Wecktaste (oder solange der verworfene Klick gedrückt ist)
  const fang = /MouseArea \{\s*id: klickfang\s*([\s\S]*?)\n {4}\}/.exec(qml);
  assert.ok(fang, "MouseArea klickfang");
  assert.match(fang[1], /anchors\.fill: parent\n/);
  assert.match(fang[1], /z: 10\n/);
  assert.match(fang[1], /enabled: root\.bildschirm\.wecktasteOffen \|\| klickfang\.pressed\n/);
  assert.match(fang[1], /acceptedButtons: Qt\.AllButtons\n/);
  assert.match(fang[1], /onPressed: root\.bildschirm\.verworfen\("Klick"\)\n?/);
  // Der Klickfang ist das letzte Kind (liegt also auch ohne z über allem)
  assert.ok(qml.lastIndexOf("id: klickfang") > qml.lastIndexOf("Energie {"));

  const greeter = lesen("shell", "greeter.qml");
  assert.match(greeter, /Bildschirm \{\s*id: bildschirm\s*leerlauf: leerlauf\s*\}/);
  assert.match(greeter, /bildschirm: bildschirm\n/);
  // Der Notfall-Login bleibt, wie er ist: kein Ausschalten des Bildschirms
  assert.doesNotMatch(lesen("shell", "greeter", "notfall", "notfall.qml"), /wlopm|IdleMonitor/);
});
