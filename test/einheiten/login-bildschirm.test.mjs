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

  // Gewecktes ohne Eingabe (Vorwarnung vorbei, Deckel auf, neuer Bildschirm): eine Minute lang an (wach)
  z = B.wecken(dunkel());
  assert.equal(z.wach, true);
  assert.equal(B.leerlauf(z, false).soll, "an", "ein «idle» in der Minute nach dem Wecken gilt nicht");
  assert.equal(B.leerlauf(B.wachVorbei(z), false).soll, "aus", "danach ohne Eingabe aus");
  assert.equal(B.eingabe(z).wach, false, "nach einer Eingabe zählt der Compositor selbst");
  assert.equal(B.leerlauf(B.eingabe(z), false).soll, "aus");
});

test("Deckel innerhalb der Minute aufgeklappt: eine Minute nach dem Aufklappen aus, nicht am Ende der alten Minute", () => {
  // Letzte Taste bei 0 s, Deckel zu bei 5 s (am Login ohne Wirkung), auf bei 58 s: wecken (Bildschirm.qml startet
  // nachWecken neu). Bei 60 s meldet der Compositor «idle» (das Aufklappen ist für ihn keine Eingabe).
  let z = B.eingabe(B.zustand());
  z = B.wecken(z);
  assert.equal(B.wecktasteOffen(z), false);
  z = B.leerlauf(z, false);
  assert.deepEqual([z.soll, B.naechster(z, T0)], ["an", ""], "2 s nach dem Aufklappen bleibt er an");
  // 118 s: nachWecken läuft ab, weiter «idle» (Bildschirm.qml: wachVorbei, dann leerlauf)
  z = B.leerlauf(B.wachVorbei(z), false);
  assert.equal(z.soll, "aus");
  let befehl;
  [befehl, z] = lauf(z, true);
  assert.equal(befehl, "aus");
  assert.equal(B.wecktasteOffen(z), true, "erst jetzt steht die Wecktaste aus");

  // Getippt nach dem Aufklappen: Die Minute zählt ab der letzten Eingabe (Compositor), die Wachminute endet
  z = B.eingabe(B.wecken(B.eingabe(B.zustand())));
  assert.equal(z.wach, false);
  assert.equal(B.leerlauf(z, false).soll, "aus");
  // Die Wecktaste ist eine Eingabe: auch sie beendet die Wachminute (Bildschirm.qml hält nachWecken dann an)
  z = B.verworfen(B.wecken(dunkel()));
  assert.equal(z.wach, false);
  // Nach drei gescheiterten Versuchen, auszuschalten, bleibt es auch nach dem Wecken an
  z = B.zustand();
  for (let i = 0; i < B.AUS_VERSUCHE; i++) {
    z = B.leerlauf(z, false);
    [, z] = lauf(z, false);
    [, z] = lauf(z, true);
  }
  assert.equal(B.leerlauf(B.wachVorbei(B.wecken(z)), false).soll, "an");
});

test("Neuer Bildschirm (Hotplug): weckt wie der Deckel, Ausstecken ändert nichts", () => {
  const a = { name: "A" };
  const b = { name: "B" };
  assert.equal(B.bildschirmDazu([a], [a, b]), true, "angesteckt");
  assert.equal(B.bildschirmDazu([], [a]), true, "der einzige kam wieder (KVM, Monitor ohne HPD im Standby)");
  assert.equal(B.bildschirmDazu([a, b], [a]), false, "ausgesteckt");
  assert.equal(B.bildschirmDazu([a, b], [b, a]), false, "nur umsortiert");
  assert.equal(B.bildschirmDazu([a], []), false);
  assert.equal(B.bildschirmDazu([{ name: "A" }], [a]), true, "ein neues Objekt gilt als neu (sichere Richtung)");
  assert.equal(B.bildschirmDazu(null, [a]), true);
  assert.equal(B.bildschirmDazu([a], null), false);
  assert.deepEqual(plain(B.liste({ length: 2, 0: "A", 1: "B" })), ["A", "B"]);
  assert.deepEqual(plain(B.liste(null)), []);

  // Dunkel mit offener Wecktaste, dann ein neuer Bildschirm: wecken schliesst die Wecktaste und schaltet alle an
  let z = dunkel();
  assert.equal(B.wecktasteOffen(z), true);
  z = B.wecken(z);
  assert.equal(B.wecktasteOffen(z), false, "das erste Zeichen auf dem hellen Bildschirm landet im Feld");
  let befehl;
  [befehl, z] = lauf(z, true);
  assert.equal(befehl, "an");
  assert.equal(B.wecktasteOffen(z), false);
  // Ohne Eingabe danach eine Minute später wieder aus (alle)
  assert.equal(B.naechster(B.leerlauf(B.wachVorbei(z), false), T0), "aus");

  // Kommt er, während das Ausschalten läuft: erst fertig, dann wieder an, ohne Wecktaste
  z = B.leerlauf(B.zustand(), false);
  z = B.gestartet(z, B.naechster(z, T0));
  z = B.wecken(z);
  assert.equal(B.naechster(z, T0), "", "nie zwei Aufrufe zugleich");
  z = B.fertig(z, "aus", true, T0);
  assert.equal(B.naechster(z, T0), "an");
  [befehl, z] = lauf(z, true);
  assert.equal(B.wecktasteOffen(z), false);
});

test("Gehaltene Wecktaste: ihre Wiederholungen werden verworfen, bis sie los ist, nie eine andere Taste", () => {
  const Q = 32;
  const R = 44;
  // Ablauf wie im Anmeldefenster: der Wecker merkt sich den Code, das Feld fragt bei jedem Ereignis
  const feld = (gehalten, ereignisse) => {
    const verworfen = [];
    for (const [druck, code, wiederholt] of ereignisse) {
      const r = E.wecktasteGehalten(gehalten, druck, code, wiederholt);
      gehalten = r.gehalten;
      verworfen.push(r.verwerfen);
    }
    return [verworfen, gehalten];
  };
  // q 1,5 s gehalten (QtWayland: Loslassen und Drücken je Wiederholung, isAutoRepeat), dann los, dann «ter»
  const wiederholung = [[false, Q, true], [true, Q, true]];
  let [verworfen, gehalten] = feld(Q, [...wiederholung, ...wiederholung, ...wiederholung, [false, Q, false]]);
  assert.deepEqual(verworfen, [true, true, true, true, true, true, false]);
  assert.equal(gehalten, -1, "losgelassen: vorbei");
  [verworfen, gehalten] = feld(gehalten, [[true, R, false], [true, R, true], [false, R, false]]);
  assert.deepEqual(verworfen, [false, false, false], "danach kommt alles an, auch Wiederholungen");

  // Return gehalten: keine Wiederholung erreicht das Feld (kein halbes Passwort an PAM)
  [verworfen, gehalten] = feld(36, [[true, 36, true], [true, 36, true], [false, 36, false], [true, 36, false]]);
  assert.deepEqual(verworfen, [true, true, false, false], "derselben Taste neu gedrückt: kommt an");

  // Eine andere Taste während des Haltens: Sie kommt an und beendet es (nie eine andere Taste blockiert)
  [verworfen, gehalten] = feld(Q, [[true, Q, true], [true, R, false], [true, Q, true], [true, R, true]]);
  assert.deepEqual(verworfen, [true, false, false, false]);
  assert.equal(gehalten, -1);
  // Das Loslassen einer anderen Taste (etwa Shift) beendet es nicht, ihre Wiederholung schon
  [verworfen, gehalten] = feld(Q, [[false, 50, false], [true, Q, true], [true, R, true], [true, Q, true]]);
  assert.deepEqual(verworfen, [false, true, false, false]);
  assert.equal(gehalten, -1);
  // Der Wecker kam nicht zum Zug: nichts wird verworfen, auch keine Wiederholung
  for (const leer of [-1, undefined, null, "32", NaN])
    assert.deepEqual(feld(leer, [[true, Q, true], [true, -1, true]]), [[false, false], -1], String(leer));
  // Kein Code: eine Wiederholung ohne gleichen Code beendet es
  assert.deepEqual(plain(E.wecktasteGehalten(Q, true, undefined, true)), { verwerfen: false, gehalten: -1 });
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
  // Nach jedem Wecken ohne Eingabe eine Minute an, danach ohne Eingabe aus
  assert.match(qml, /onTriggered: \{\s*root\._z = BildschirmLogik\.wachVorbei\(root\._z\);\s*if \(ausMonitor\.isIdle\)\s*root\._leerlauf\(\);/);
  const wecken = /function _wecken\(grund: string\): void \{([\s\S]*?)\n {4}\}/.exec(qml);
  assert.ok(wecken, "_wecken");
  assert.match(wecken[1], /root\._z = BildschirmLogik\.wecken\(root\._z\);\s*nachWecken\.restart\(\);\s*root\._weiter\(\);/);
  // Wo nachWecken anhält, endet auch die Wachminute (Eingabe, Wecktaste): Sie bleibt nie ohne Timer stehen
  for (const name of ["verworfen", "_eingabe"]) {
    const f = new RegExp(`function ${name}\\([^)]*\\): void \\{([\\s\\S]*?)\\n {4}\\}`).exec(qml);
    assert.ok(f, name);
    assert.match(f[1], /nachWecken\.stop\(\);/);
    assert.match(f[1], new RegExp(`BildschirmLogik\\.${name.replace("_", "")}\\(root\\._z\\)`));
  }
  assert.equal((qml.match(/nachWecken\.stop\(\)/g) ?? []).length, 2);
  assert.match(qml, /function onVorwarnungLaeuftChanged\(\): void \{\s*root\._wecken\(/);
  assert.match(qml, /function onAufgeklappt\(\): void \{\s*root\._wecken\("Deckel offen"\);/);
  // Neue Bildschirme wecken
  assert.match(qml, /Connections \{\s*target: Quickshell\s*function onScreensChanged\(\): void \{\s*const jetzt = BildschirmLogik\.liste\(Quickshell\.screens\);\s*const dazu = BildschirmLogik\.bildschirmDazu\(root\._bildschirme, jetzt\);\s*root\._bildschirme = jetzt;\s*if \(dazu\)\s*root\._wecken\("Bildschirm neu"\);/);
  assert.match(qml, /Component\.onCompleted: root\._bildschirme = BildschirmLogik\.liste\(Quickshell\.screens\)\n/);
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
  // Vorwarnung vorbei, ohne Eingabe (Bildschirm.qml weckt erneut): nach der neuen Minute wieder aus
  z = B.wecken(z);
  assert.equal(B.leerlauf(z, false).soll, "an");
  assert.equal(B.naechster(B.leerlauf(B.wachVorbei(z), false), T0), "aus");
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
  assert.match(wecker[1], /Keys\.onPressed: event => \{\s*event\.accepted = true;\s*wecker\.gehalten = event\.nativeScanCode;\s*root\.bildschirm\.verworfen\("Taste"\);\s*[^\n]*\n\s*root\._weckerZurueck\(\);\s*\}/);
  assert.match(wecker[1], /property int gehalten: -1\n/);
  // Wiederholungen der gehaltenen Wecktaste: Das Formular fragt bei jedem Drücken und Loslassen in beiden Feldern
  assert.match(qml, /import "\.\.\/dienste\/energie\.js" as EnergieLogik\n/);
  assert.match(qml, /function _gehalten\(event: KeyEvent, druck: bool\): void \{\s*const r = EnergieLogik\.wecktasteGehalten\(wecker\.gehalten, druck, event\.nativeScanCode, event\.isAutoRepeat\);\s*wecker\.gehalten = r\.gehalten;\s*if \(r\.verwerfen\)\s*event\.accepted = true;\s*\}/);
  assert.match(qml, /Formular \{\s*id: formular[\s\S]*?onVorTaste: \(event, druck\) => root\._gehalten\(event, druck\)\n/);
  const formular = lesen("shell", "greeter", "Formular.qml");
  assert.match(formular, /signal vorTaste\(var event, bool druck\)\n/);
  for (const [feld, einzug] of [["namensfeld", 8], ["passwortfeld", 12]]) {
    const block = new RegExp(`Eingabe \\{\\s*id: ${feld}\\s*([\\s\\S]*?)\\n {${einzug}}\\}`).exec(formular);
    assert.ok(block, feld);
    const inhalt = block[1] + "\n";
    assert.match(inhalt, /onVorTaste: event => root\.vorTaste\(event, true\)\n/, feld);
    assert.match(inhalt, /onVorLoslassen: event => root\.vorTaste\(event, false\)\n/, feld);
  }
  const eingabe = lesen("shell", "komponenten", "Eingabe.qml");
  assert.match(eingabe, /signal vorLoslassen\(var event\)\n/);
  assert.match(eingabe, /Keys\.onReleased: event => root\.vorLoslassen\(event\)\n/);
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
