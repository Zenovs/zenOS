// Einheitentests für shell/dienste/energie.js (wirksame Werte, Zeitleiste, Vorwarnung, Wecktaste, auch gehalten), die
// Verdrahtung der Wecktaste in Sperre.qml und den Abgleich mit Einstellungen.qml und dem Schema. Läuft ohne
// Abhängigkeiten: node --test test/einheiten/
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

  // Login-Bildschirm (fest, ohne Einstellung): nur sicher im Akkubetrieb
  assert.equal(E.loginAusschaltenAktiv(akku), true);
  assert.equal(E.loginAusschaltenAktiv(Object.assign({}, akku, { laedt: true })), false);
  assert.equal(E.loginAusschaltenAktiv(Object.assign({}, akku, { zustand: "unbekannt" })), false);
  assert.equal(E.loginAusschaltenAktiv(null), false);
  assert.equal(Z.LEITPLANKEN.loginAusschaltenMinuten, 30);
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

// n Takte zu 1 s
function takte(z, n) {
  for (let i = 0; i < n; i++) z = E.vorwarnungTakt(z);
  return z;
}

test("Vorwarnung: 60 Takte zu 1 s, dann ausschalten; Eingabe bricht ab", () => {
  let z = E.vorwarnung();
  assert.equal(z.phase, "aus");
  assert.equal(E.vorwarnungSchritt(z, T0), "nichts");
  z = E.vorwarnungStarten(z, T0);
  assert.deepEqual(plain(z), { phase: "laeuft", seit: T0, um: T0 + 60 * S, grund: "", takte: 0 });
  // Ein zweiter Start setzt die Zeit nicht zurück
  assert.equal(E.vorwarnungStarten(z, T0 + 30 * S), z);
  assert.equal(E.vorwarnungSchritt(z, T0), "nichts");
  assert.equal(E.vorwarnungSchritt(takte(z, 59), T0 + 59 * S), "nichts");
  assert.equal(E.vorwarnungSchritt(takte(z, 60), T0 + 60 * S), "ausschalten");
  assert.equal(E.vorwarnungSchritt(takte(z, 300), T0 + 5 * MIN), "ausschalten");
  // Zu alt (der Helfer hängt) oder kaputt: nie ausschalten
  assert.equal(E.vorwarnungSchritt(takte(z, 301), T0 + 5 * MIN + S), "abbrechen");
  for (const kaputt of [NaN, -1, "60", undefined, Infinity])
    assert.equal(E.vorwarnungSchritt({ phase: "laeuft", seit: T0, um: T0, takte: kaputt }, T0), "abbrechen", String(kaputt));
  // Ausserhalb der Vorwarnung zählt kein Takt
  assert.equal(E.vorwarnungTakt(E.vorwarnung()).takte, 0);

  const ab = E.vorwarnungAbbrechen(z, "eingabe");
  assert.deepEqual(plain(ab), { phase: "aus", seit: 0, um: 0, grund: "eingabe", takte: 0 });
  assert.equal(E.vorwarnungSchritt(ab, T0 + 60 * S), "nichts");
  assert.equal(E.vorwarnungAbbrechen(z, 42).grund, "");
  // Nach dem Abbruch beginnt eine neue Vorwarnung wieder mit vollen 60 s
  assert.equal(E.vorwarnungStarten(ab, T0 + 10 * MIN).um, T0 + 10 * MIN + 60 * S);
  assert.equal(E.vorwarnungStarten(takte(z, 59), T0 + 10 * MIN).takte, 59, "läuft schon: bleibt");
  assert.equal(E.vorwarnungStarten(ab, T0 + 10 * MIN).takte, 0);
});

test("Vorwarnung: Ein Sprung der Uhr verkürzt sie nie", () => {
  // Die Uhr springt während der Vorwarnung um 4 Min. nach vorn (NTP nach langer Zeit offline): Es zählen nur Takte
  let z = takte(E.vorwarnungStarten(E.vorwarnung(), T0), 5);
  assert.equal(E.vorwarnungSchritt(z, T0 + 4 * MIN), "nichts");
  // … oder zurück: ebenfalls nur Takte
  assert.equal(E.vorwarnungSchritt(z, T0 - 10 * MIN), "nichts");
  z = takte(z, 55);
  assert.equal(E.vorwarnungSchritt(z, T0 - 10 * MIN), "ausschalten");
});

test("Vorwarnung: blockiert, neuer Versuch nach 5 Min.", () => {
  const z = E.vorwarnungBlockiert(E.vorwarnungStarten(E.vorwarnung(), T0), T0 + 60 * S, "ssh");
  assert.deepEqual(plain(z), { phase: "warten", seit: T0 + 60 * S, um: T0 + 6 * MIN, grund: "ssh", takte: 0 });
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
  assert.equal(E.vorwarnungPruefbar(E.vorwarnung()), true);
  assert.equal(E.vorwarnungPruefbar(z), true);
  assert.equal(E.vorwarnungPruefbar(neu), false);
});

test("Vorwarnung: von logind abgelehnt, erst nach einer Eingabe wieder", () => {
  const z = E.vorwarnungAbgelehnt(takte(E.vorwarnungStarten(E.vorwarnung(), T0), 60), T0 + 61 * S, "polkit");
  assert.deepEqual(plain(z), { phase: "abgelehnt", seit: T0 + 61 * S, um: 0, grund: "polkit", takte: 0 });
  // Kein neuer Versuch, auch nach Stunden nicht (sonst ginge der Bildschirm alle 5 Min. an)
  assert.equal(E.vorwarnungSchritt(z, T0 + 6 * MIN), "nichts");
  assert.equal(E.vorwarnungSchritt(z, T0 + 600 * MIN), "nichts");
  assert.equal(E.vorwarnungPruefbar(z), false);
  assert.equal(E.vorwarnungTakt(z), z);
  // Eine Eingabe (Abbruch) gibt sie wieder frei
  assert.equal(E.vorwarnungPruefbar(E.vorwarnungAbbrechen(z, "eingabe")), true);
});

test("Zeile der Vorwarnung: leerer Akku vor dem Ausschalten nach langer Sperre", () => {
  assert.equal(E.vorwarnungText("", ""), "");
  assert.equal(E.vorwarnungText("", "22:41"), "zenOS schaltet um 22:41 aus · Eine Taste bricht ab");
  assert.equal(E.vorwarnungText("22:40", "22:41"), "Akku fast leer: zenOS schaltet um 22:40 aus · Netzteil anschliessen bricht ab");
  assert.equal(E.vorwarnungText(null, undefined), "");
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

  // «an» kommt knapp vor der Taste: die erste Taste innerhalb 300 ms verworfen, danach nicht mehr
  z = E.bildschirmHell(E.bildschirmDunkel(E.weckzustand()), T0);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 299), true);
  z = E.wecktasteGesehen(z);
  assert.equal(E.wecktasteVerwerfen(z, T0 + 300), false);

  // Geweckt mit Maus, Touchpad, Ein/Aus-Taste oder Aufklappen: Das Passwort danach bleibt ganz, auch wer sofort tippt
  z = E.bildschirmHell(E.bildschirmDunkel(E.weckzustand()), T0);
  for (const nach of [300, 500, 800, 3 * S])
    assert.equal(E.wecktasteVerwerfen(z, T0 + nach), false, `${nach} ms`);
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

// Ablauf wie in Sperre.qml: Jedes Drücken und Loslassen im Passwortfeld geht durch wecktasteSperre.
// Ereignisse als [druck, code, wiederholt]; QtWayland wiederholt eine gehaltene Taste als Loslassen und Drücken mit
// isAutoRepeat.
function sperrfeld(stand, ereignisse, jetzt = T0) {
  let { z, gehalten } = stand;
  const verworfen = [];
  for (const [druck, code, wiederholt] of ereignisse) {
    const r = E.wecktasteSperre(z, gehalten, druck, code, wiederholt, jetzt);
    z = r.z;
    gehalten = r.gehalten;
    verworfen.push(r.verwerfen);
  }
  return { verworfen, z, gehalten };
}

test("Sperre: gehaltene Wecktaste, ihre Wiederholungen werden verworfen, bis sie los ist, nie eine andere Taste", () => {
  const Q = 32;
  const T = 28;
  const R = 44;
  const RETURN = 36;
  const SHIFT = 50;
  const dunkel = () => ({ z: E.bildschirmDunkel(E.weckzustand()), gehalten: -1 });
  const halten = (code, mal) => Array.from({ length: mal }, () => [[false, code, true], [true, code, true]]).flat();
  const tippen = (...codes) => codes.flatMap((c) => [[true, c, false], [false, c, false]]);

  // Dunkel, «q» 1,5 s gehalten (nach 600 ms 25 je Sekunde: rund 22 Wiederholungen), dann los: verworfen sind der Druck
  // und jede Wiederholung, das Loslassen beendet es. Danach kommt alles an, auch Wiederholungen einer anderen Taste.
  let s = sperrfeld(dunkel(), [[true, Q, false], ...halten(Q, 22), [false, Q, false]]);
  assert.deepEqual(s.verworfen, [true, ...Array(44).fill(true), false]);
  assert.equal(s.gehalten, -1, "losgelassen: vorbei");
  assert.equal(s.z.offen, false, "die Wecktaste ist erledigt");
  s = sperrfeld(s, [...tippen(T, R), [true, R, false], ...halten(R, 3), [false, R, false]]);
  assert.ok(s.verworfen.every((v) => v === false), "danach kommt alles an");

  // Return gehalten mit «tes» im Feld: keine Wiederholung erreicht das Feld (kein halbes Passwort an PAM). Ein neuer
  // Druck derselben Taste kommt an.
  s = sperrfeld(dunkel(), [[true, RETURN, false], ...halten(RETURN, 5), [false, RETURN, false], [true, RETURN, false]]);
  assert.deepEqual(s.verworfen, [true, ...Array(10).fill(true), false, false]);
  // Ebenso ohne Loslassen dazwischen (ein echter Druck derselben Taste beendet es)
  s = sperrfeld(dunkel(), [[true, RETURN, false], ...halten(RETURN, 2), [true, RETURN, false], ...halten(RETURN, 2)]);
  assert.deepEqual(s.verworfen, [true, true, true, true, true, false, false, false, false, false]);

  // Nie eine andere Taste: Ein Druck während des Haltens kommt an und beendet es
  s = sperrfeld(dunkel(), [[true, Q, false], ...halten(Q, 2), [true, R, false], ...halten(Q, 1), ...halten(R, 1)]);
  assert.deepEqual(s.verworfen, [true, true, true, true, true, false, false, false, false, false]);
  assert.equal(s.gehalten, -1);
  // Das Loslassen einer anderen Taste (Shift, vor dem Wecken gedrückt) beendet es nicht
  s = sperrfeld(dunkel(), [[true, Q, false], [false, SHIFT, false], ...halten(Q, 2), [false, Q, false]]);
  assert.deepEqual(s.verworfen, [true, false, true, true, true, true, false]);
  // Das Loslassen allein ist nie die Wecktaste (Taste vor dem Dunkelwerden gedrückt, danach losgelassen)
  s = sperrfeld(dunkel(), [[false, SHIFT, false]]);
  assert.deepEqual(s.verworfen, [false]);
  assert.equal(s.z.offen, true, "die Wecktaste steht weiter aus");

  // Hell und gesperrt: Wer festhält, bekommt alle Wiederholungen ins Feld, nichts wird verworfen
  s = sperrfeld({ z: E.weckzustand(), gehalten: -1 }, [[true, Q, false], ...halten(Q, 5), [false, Q, false]]);
  assert.ok(s.verworfen.every((v) => v === false));
  assert.equal(s.gehalten, -1);
  // Geweckt mit der Maus (mehr als 300 ms vorher): ebenso
  const geweckt = { z: E.bildschirmHell(E.bildschirmDunkel(E.weckzustand()), T0), gehalten: -1 };
  s = sperrfeld(geweckt, [[true, Q, false], ...halten(Q, 5)], T0 + 500);
  assert.ok(s.verworfen.every((v) => v === false));
  // «an» knapp vor der Taste (innert 300 ms): die Taste und ihre Wiederholungen verworfen
  s = sperrfeld(geweckt, [[true, Q, false], ...halten(Q, 2), [false, Q, false], ...tippen(T)], T0 + 100);
  assert.deepEqual(s.verworfen, [true, true, true, true, true, false, false, false]);

  // Bleibt «dunkel» hängen (kein «an»), geht trotzdem nur diese eine Taste verloren
  s = sperrfeld(dunkel(), [[true, Q, false], [false, Q, false], ...tippen(T, R), [true, Q, false]], T0 + 5 * MIN);
  assert.deepEqual(s.verworfen, [true, false, false, false, false, false, false]);
  assert.equal(s.z.dunkel, true);

  // Gehalten vor dem Dunkelwerden (die Wiederholung ist der erste Druck danach): bis zum Loslassen verworfen
  s = sperrfeld(dunkel(), [[true, Q, true], ...halten(Q, 2), [false, Q, false], ...tippen(T)]);
  assert.deepEqual(s.verworfen, [true, true, true, true, true, false, false, false]);

  // Ohne gültigen Code lässt sich die Taste nicht wiedererkennen: nur der eine Druck, nie mehr
  for (const code of [undefined, null, NaN, -1, "32"]) {
    s = sperrfeld(dunkel(), [[true, code, false], [false, code, true], [true, code, true], [true, Q, true]]);
    assert.deepEqual(s.verworfen, [true, false, false, false], String(code));
    assert.equal(s.gehalten, -1, String(code));
  }
  // Ein kaputter Stand verwirft nichts
  for (const gehalten of [undefined, null, "32", NaN])
    assert.deepEqual(sperrfeld({ z: E.weckzustand(), gehalten }, [[true, Q, true], [false, Q, true]]).verworfen, [false, false]);
});

test("Sperre.qml: jedes Drücken und Loslassen im Passwortfeld geht durch wecktasteSperre", () => {
  const qml = lesen("shell", "sperre", "Sperre.qml");
  assert.match(qml, /import "\.\.\/dienste\/energie\.js" as EnergieLogik\n/);
  assert.match(qml, /property int _gehalten: -1\n/);
  assert.match(qml, /function _vorTaste\(event: KeyEvent, druck: bool\): void \{\s*const r = EnergieLogik\.wecktasteSperre\(root\._weck, root\._gehalten, druck, event\.nativeScanCode, event\.isAutoRepeat, Date\.now\(\)\);\s*root\._weck = r\.z;\s*root\._gehalten = r\.gehalten;\s*if \(druck && root\.dunkel\)\s*Energie\.bildschirm\("an"\);\s*if \(r\.verwerfen\)\s*event\.accepted = true;\s*\}/);
  const feld = /Eingabe \{\s*id: passwortFeld\s*([\s\S]*?)\n {32}\}/.exec(qml);
  assert.ok(feld, "Eingabe passwortFeld");
  assert.match(feld[1] + "\n", /onVorTaste: event => root\._vorTaste\(event, true\)\n/);
  assert.match(feld[1] + "\n", /onVorLoslassen: event => root\._vorTaste\(event, false\)\n/);
  // Der alte Weg (nur der erste Druck) ist weg, die Logik steht nur in energie.js
  assert.doesNotMatch(qml, /wecktasteVerwerfen|wecktasteGesehen|wecktasteGehalten\(|_wecktaste\b/);
  // Wo der Weckzustand neu beginnt (sperren, entsperren, labwc beendet die Sperre), beginnt auch das Halten neu
  const neu = [...qml.matchAll(/root\._weck = EnergieLogik\.weckzustand\(\);\n(\s*)(.*)\n/g)];
  assert.equal(neu.length, 3);
  for (const m of neu) assert.equal(m[2], "root._gehalten = -1;");
  const eingabe = lesen("shell", "komponenten", "Eingabe.qml");
  assert.match(eingabe, /Keys\.onReleased: event => root\.vorLoslassen\(event\)\n/);
});

test("Vorwarnung: Wer das Passwort tippt, verliert kein Zeichen", () => {
  // Der Bildschirm war dunkel, die Vorwarnung schaltet ihn ohne Eingabe an (Meldung «an»). Das Feld ist zu sehen:
  // Eine Taste nach mehr als 300 ms landet im Feld, auch die erste.
  let z = E.bildschirmHell(E.bildschirmDunkel(E.weckzustand()), T0);
  for (const nach of [S, 10 * S, 50 * S])
    assert.equal(E.wecktasteVerwerfen(z, T0 + nach), false, `${nach} ms`);
  // Die Funktionen des alten Wegs gibt es nicht mehr (die Vorwarnung verwirft nichts)
  assert.equal(typeof E.vorwarnungGezeigt, "undefined");
  assert.equal(typeof E.vorwarnungVorbei, "undefined");
  // Blockiert: wieder dunkel, die nächste Taste ist wieder eine Wecktaste
  z = E.bildschirmDunkel(E.wecktasteGesehen(z));
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
    "ausschaltenMinutenMax", "vorwarnungSekunden", "sperreTrotzHemmerMinuten", "akkuAusschaltenProzent",
    "loginAusschaltenMinuten"])
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
