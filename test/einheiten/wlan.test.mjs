// Einheitentests für shell/leiste/wlan.js (WLAN-Abschnitt im System-Menü: Signalstufe, Reihenfolge der Netze,
// Passwort-Prüfung, Texte). Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const quelle = readFileSync(join(wurzel, "shell", "leiste", "wlan.js"), "utf8");

// Die Datei ist ein QML-Skript («.pragma library»); ohne diese Zeile ist es gewöhnliches JavaScript.
const W = vm.createContext({});
vm.runInContext(quelle.replace(/^\.pragma library\s*$/m, ""), W);

const roh = (wert) => JSON.parse(JSON.stringify(wert));

// Neutrale Beispielnetze
function netz(name, teile = {}) {
  return Object.assign({ name, stufe: 2, sicherheit: "passwort", wpa3: false, bekannt: false, verbunden: false, verbindet: false }, teile);
}

test("stufe: Grenzen und unbekanntes Signal", () => {
  assert.equal(W.stufe(100), 3);
  assert.equal(W.stufe(60), 3);
  assert.equal(W.stufe(59), 2);
  assert.equal(W.stufe(35), 2);
  assert.equal(W.stufe(34), 1);
  assert.equal(W.stufe(0), 1);
  // unbekannt: volles Symbol wie bisher
  assert.equal(W.stufe(-1), 3);
  assert.equal(W.stufe(undefined), 3);
  assert.equal(W.stufe(NaN), 3);
  assert.equal(W.stufe("70"), 3);
});

test("symbol: Stufe zu Symbolname", () => {
  assert.equal(W.symbol(3), "wlan");
  assert.equal(W.symbol(2), "wlan-2");
  assert.equal(W.symbol(1), "wlan-1");
  assert.equal(W.symbol(0), "wlan-aus");
  assert.equal(W.symbol(-1), "wlan-aus");
});

test("sortieren: verbunden, verbindet, bekannt, Signal, Name", () => {
  const liste = W.sortieren([
    netz("Zeta", { stufe: 3 }),
    netz("Alpha", { stufe: 3 }),
    netz("Schwach", { stufe: 1 }),
    netz("Gespeichert", { stufe: 1, bekannt: true }),
    netz("Daheim", { stufe: 2, bekannt: true, verbunden: true }),
    netz("Neu", { stufe: 1, verbindet: true }),
  ]);
  assert.deepEqual(roh(liste.map((n) => n.name)), ["Daheim", "Neu", "Gespeichert", "Alpha", "Zeta", "Schwach"]);
});

test("sortieren: ohne Namen, Doppelte und Netze ausser Reichweite", () => {
  const liste = W.sortieren([
    netz(""),
    netz("Beispielnetz"),
    netz("Beispielnetz", { stufe: 3 }),
    // bekannt, aber nicht in Reichweite: nicht in der Liste
    netz("Weit weg", { stufe: 0, bekannt: true }),
    // verbunden zählt auch ohne Signal
    netz("Telefon", { stufe: 0, verbunden: true }),
    null,
    { stufe: 2 },
  ]);
  assert.deepEqual(roh(liste.map((n) => n.name)), ["Telefon", "Beispielnetz"]);
  assert.deepEqual(roh(W.sortieren(null)), []);
  assert.deepEqual(roh(W.sortieren([])), []);
});

test("verbindbar und brauchtPasswort", () => {
  assert.equal(W.verbindbar(netz("A")), true);
  assert.equal(W.verbindbar(netz("A", { sicherheit: "offen" })), true);
  assert.equal(W.verbindbar(netz("A", { sicherheit: "unbekannt" })), true);
  assert.equal(W.verbindbar(netz("Firma", { sicherheit: "unternehmen" })), false);
  assert.equal(W.verbindbar(netz("Alt", { sicherheit: "wep" })), false);
  assert.equal(W.verbindbar(null), false);

  assert.equal(W.brauchtPasswort(netz("Neu")), true);
  // bekannt: verbindet mit dem gespeicherten Passwort
  assert.equal(W.brauchtPasswort(netz("Alt", { bekannt: true })), false);
  assert.equal(W.brauchtPasswort(netz("Offen", { sicherheit: "offen" })), false);
  // unbekannte Sicherheit: erst ohne versuchen
  assert.equal(W.brauchtPasswort(netz("?", { sicherheit: "unbekannt" })), false);
});

test("passwortPruefen: Länge und Hex-Schlüssel", () => {
  assert.equal(W.passwortPruefen(""), "Passwort eingeben");
  assert.equal(W.passwortPruefen(undefined), "Passwort eingeben");
  assert.equal(W.passwortPruefen("kurz"), "Mindestens 8 Zeichen");
  assert.equal(W.passwortPruefen("1234567"), "Mindestens 8 Zeichen");
  assert.equal(W.passwortPruefen("12345678"), "");
  assert.equal(W.passwortPruefen("ä".repeat(10)), "");
  assert.equal(W.passwortPruefen("x".repeat(63)), "");
  assert.equal(W.passwortPruefen("x".repeat(64)), "Höchstens 63 Zeichen");
  assert.equal(W.passwortPruefen("0a".repeat(32)), "");
  assert.equal(W.passwortPruefen("x".repeat(65)), "Höchstens 63 Zeichen");
});

test("fehlerText: Gründe und Hinweis zu WPA3", () => {
  assert.equal(W.fehlerText("passwort", false), "Passwort falsch?");
  // Mischnetze melden auch wpa3: kein WPA3-Hinweis nach einem Tippfehler
  assert.equal(W.fehlerText("passwort", true), "Passwort falsch?");
  assert.match(W.fehlerText("zeit", true), /Bietet das Netz nur WPA3 an/);
  assert.match(W.fehlerText("abgelehnt", true), /Bietet das Netz nur WPA3 an/);
  assert.match(W.fehlerText("keine-antwort", true), /Bietet das Netz nur WPA3 an/);
  assert.doesNotMatch(W.fehlerText("zeit", true), /Reines WPA3/);
  assert.match(W.fehlerText("abgelehnt", false), /abgelehnt\.$/);
  assert.equal(W.fehlerText("weg", true), "Das Netz ist nicht mehr in Reichweite.");
  assert.equal(W.fehlerText("keine-antwort", false), "Verbindung kam nicht zustande.");
  assert.equal(W.fehlerText("???", false), "Verbindung kam nicht zustande.");
});

test("zeilenWert", () => {
  assert.equal(W.zeilenWert(netz("A")), "");
  assert.equal(W.zeilenWert(netz("A", { verbindet: true })), "verbindet …");
  assert.equal(W.zeilenWert(netz("A", { verbindet: true, verbunden: true })), "");
  assert.equal(W.zeilenWert(netz("Firma", { sicherheit: "unternehmen" })), "nicht möglich");
  assert.equal(W.zeilenWert(null), "");
});

test("anzeigeName: Unsichtbares wird sichtbar, sonst unverändert", () => {
  assert.equal(W.anzeigeName("Heimnetz"), "Heimnetz");
  assert.equal(W.anzeigeName("Café 5G ✓"), "Café 5G ✓");
  // Zeichen ohne Breite, Richtungszeichen, Steuerzeichen, BOM, Zeilentrenner
  assert.equal(W.anzeigeName("Heim\u200bnetz"), "Heim\ufffdnetz");
  assert.equal(W.anzeigeName("\u202eztenmieH"), "\ufffdztenmieH");
  assert.equal(W.anzeigeName("A\u0000B\u0007C\u009b"), "A\ufffdB\ufffdC\ufffd");
  assert.equal(W.anzeigeName("\ufeffNetz\u2028"), "\ufffdNetz\ufffd");
  assert.equal(W.anzeigeName("Netz\u00ad"), "Netz\ufffd");
  // Auszeichnungen bleiben als Text stehen (WlanZeile zeigt reinen Text)
  assert.equal(W.anzeigeName("<s></s>Heimnetz"), "<s></s>Heimnetz");
  assert.equal(W.anzeigeName(undefined), "");
  assert.equal(W.anzeigeName(42), "");
});

test("WlanZeile zeigt jeden Text als reinen Text (SSID aus der Luft)", () => {
  const qml = readFileSync(join(wurzel, "shell", "leiste", "WlanZeile.qml"), "utf8");
  const texte = qml.match(/^\s*Text \{/gm) ?? [];
  const rein = qml.match(/^\s*textFormat: Text\.PlainText$/gm) ?? [];
  assert.ok(texte.length >= 2);
  assert.equal(rein.length, texte.length);
});
