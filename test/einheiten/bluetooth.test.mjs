// Einheitentests für shell/leiste/bluetooth.js (Bluetooth-Abschnitt im System-Menü: Symbol je Gerätetyp, Namen,
// Akku, Reihenfolge, Texte). Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const lesen = (name) => readFileSync(join(wurzel, "shell", "leiste", name), "utf8");

// QML-Skripte («.pragma library»): bluetooth.js holt wlan.js mit «.import "wlan.js" as Wlan». Ohne diese Zeilen ist
// es gewöhnliches JavaScript; Wlan kommt hier aus einem eigenen Kontext.
const Wlan = vm.createContext({});
vm.runInContext(lesen("wlan.js").replace(/^\.pragma library\s*$/m, ""), Wlan);
const quelle = lesen("bluetooth.js");
assert.match(quelle, /^\.import "wlan\.js" as Wlan$/m);
const B = vm.createContext({ Wlan });
vm.runInContext(quelle.replace(/^\.pragma library\s*$/m, "").replace(/^\.import .*$/m, ""), B);

const roh = (wert) => JSON.parse(JSON.stringify(wert));

// Neutrale Beispielgeräte
function geraet(name, teile = {}) {
  return Object.assign({ adresse: "00:11:22:33:44:55", name, typ: "", verbunden: false, gekoppelt: false,
    verbindet: false, trennt: false, koppelt: false, akku: -1 }, teile);
}

test("symbol: Gerätetyp von BlueZ zu einem Symbol", () => {
  assert.equal(B.symbol("input-mouse"), "maus");
  assert.equal(B.symbol("input-tablet"), "maus");
  assert.equal(B.symbol("input-keyboard"), "tastatur");
  assert.equal(B.symbol("audio-headset"), "kopfhoerer");
  assert.equal(B.symbol("audio-headphones"), "kopfhoerer");
  assert.equal(B.symbol("audio-card"), "kopfhoerer");
  for (const typ of ["phone", "computer", "input-gaming", "", undefined, null, 3])
    assert.equal(B.symbol(typ), "bluetooth", String(typ));
});

test("symbol: jedes Symbol gibt es in symbole.js", () => {
  const symbole = readFileSync(join(wurzel, "shell", "komponenten", "symbole.js"), "utf8");
  for (const name of ["bluetooth", "bluetooth-aus", "maus", "tastatur", "kopfhoerer"])
    assert.match(symbole, new RegExp(`^    "${name}": \\{ d: "`, "m"), name);
});

test("anzeigeName: Adresse statt Name gilt als ohne Namen, Unsichtbares wird sichtbar", () => {
  assert.equal(B.anzeigeName("Maus"), "Maus");
  assert.equal(B.anzeigeName("AA-BB-CC-DD-EE-FF"), "Gerät ohne Namen");
  assert.equal(B.anzeigeName("aa:bb:cc:dd:ee:ff"), "Gerät ohne Namen");
  assert.equal(B.anzeigeName("  "), "Gerät ohne Namen");
  assert.equal(B.anzeigeName(undefined), "Gerät ohne Namen");
  // wie bei Netznamen: ein Zeichen ohne Breite darf kein echtes Gerät nachmachen
  assert.equal(B.anzeigeName("Ma​us"), "Ma�us");
  assert.equal(B.hatNamen("AA-BB-CC-DD-EE-FF"), false);
  assert.equal(B.hatNamen("Kopfhörer"), true);
});

test("akku: Anteil von Quickshell in ganzen Prozent", () => {
  assert.equal(B.akku(true, 0.73), 73);
  assert.equal(B.akku(true, 1), 100);
  assert.equal(B.akku(true, 0), 0);
  assert.equal(B.akku(true, 0.005), 1);
  // schon in Prozent (ältere Stände)
  assert.equal(B.akku(true, 64), 64);
  assert.equal(B.akku(true, 140), 100);
  for (const [verfuegbar, wert] of [[false, 0.5], [true, -1], [true, NaN], [true, "0.5"], [true, undefined]])
    assert.equal(B.akku(verfuegbar, wert), -1, `${verfuegbar} ${wert}`);
});

test("sortieren: verbunden, gekoppelt, gefunden; fremde ohne Namen fallen weg", () => {
  const liste = [
    geraet("Zebra"),
    geraet("AA-BB-CC-DD-EE-FF"),
    geraet("BB-CC-DD-EE-FF-00", { gekoppelt: true }),
    geraet("kopfhörer", { gekoppelt: true }),
    geraet("Maus", { verbunden: true, gekoppelt: true }),
    geraet("Ärger"),
  ];
  assert.deepEqual(roh(B.sortieren(liste).map(g => g.name)),
    ["Maus", "BB-CC-DD-EE-FF-00", "kopfhörer", "Ärger", "Zebra"]);
  // die Eingabe bleibt, wie sie war
  assert.equal(liste[0].name, "Zebra");
  assert.deepEqual(roh(B.sortieren([])), []);
});

test("schluessel: ohne Spracheinstellung, Ä wie A, ß wie ss", () => {
  // Die QML-Engine kennt localeCompare mit «de» nicht; deshalb ein eigener Schlüssel, gleich in node und QML
  assert.equal(B.schluessel("Ärger"), "arger");
  assert.equal(B.schluessel("Straße"), "strasse");
  assert.equal(B.schluessel("Kopfhörer"), "kopfhorer");
  assert.equal(B.schluessel("AA-BB-CC-DD-EE-FF"), "gerat ohne namen");
});

test("zeilenWert: was geschieht, sonst Akku bzw. gekoppelt", () => {
  assert.equal(B.zeilenWert(geraet("M", { koppelt: true, verbindet: true })), "koppelt …");
  assert.equal(B.zeilenWert(geraet("M", { verbindet: true })), "verbindet …");
  assert.equal(B.zeilenWert(geraet("M", { verbunden: true, trennt: true })), "trennt …");
  assert.equal(B.zeilenWert(geraet("M", { verbunden: true, akku: 81 })), "81 %");
  assert.equal(B.zeilenWert(geraet("M", { verbunden: true })), "");
  assert.equal(B.zeilenWert(geraet("M", { gekoppelt: true })), "gekoppelt");
  assert.equal(B.zeilenWert(geraet("M")), "");
  assert.equal(B.zeilenWert(null), "");
});

test("fehlerText: ruhig und mit einem Rat", () => {
  assert.match(B.fehlerText("koppeln"), /Kopplungsmodus/);
  assert.match(B.fehlerText("zeit"), /Keine Antwort/);
  assert.match(B.fehlerText("verbinden"), /Verbinden hat nicht geklappt/);
  assert.equal(B.fehlerText(""), "");
  assert.equal(B.fehlerText("unbekannt"), "");
});

test("BluetoothQuelle: Adresse nur als Schlüssel, nie sichtbar", () => {
  // Der Abschnitt zeigt Namen nur über anzeigeName und die Adresse nirgends
  const abschnitt = lesen("BluetoothAbschnitt.qml");
  assert.doesNotMatch(abschnitt, /text:[^\n]*adresse/);
  assert.doesNotMatch(abschnitt, /wert:[^\n]*adresse/);
  // Sichtbar für andere macht zenOS den Rechner nie
  const quelleQml = lesen("BluetoothQuelle.qml");
  assert.doesNotMatch(quelleQml.replace(/^\s*\/\/.*$/gm, ""), /discoverable\s*=/);
});
