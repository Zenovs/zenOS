// Einheitentests für shell/installer/installer.js (zen Installer in der Oberfläche: Pfad prüfen, Antwort von
// «zenos-installer ansehen --json» lesen, das Fenster je Phase, pkexec-Aufruf, Ergebnis aus Exit und letzte.json,
// Mitteilung, Liste in Einstellungen › Apps mit «Entfernen …») und den Abgleich mit Installer.qml,
// InstallerInhalt.qml, dienste/InstallerListe.qml, SeiteApps.qml, shell.qml, dem Programm zenos-installer, dem Helfer,
// der polkit-Richtlinie, dem Starter, den mimeapps, «zen install» und dem Rundgang in pruefen.sh.
// Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const lesen = (...teile) => readFileSync(join(wurzel, ...teile), "utf8");

// QML-Skript («.pragma library»): ohne diese Zeile gewöhnliches JavaScript
const L = vm.createContext({});
vm.runInContext(lesen("shell", "installer", "installer.js").replace(/^\.pragma library\s*$/m, ""), L);
const K = vm.createContext({});
vm.runInContext(lesen("shell", "dienste", "kanal.js").replace(/^\.pragma library\s*$/m, ""), K);

const roh = (x) => JSON.parse(JSON.stringify(x));
const SHA = "3f".repeat(32);
const PLAN = "a1".repeat(20);
const PFAD = "/home/zeno/Downloads/beispiel_1.4.2_arm64.deb";
const SYMBOL = "/run/user/1000/zenos-installer/" + "0123456789abcdef".repeat(2) + ".png";
const JETZT = Date.parse("2026-10-08T12:00:00Z");

// Antwort von «zenos-installer ansehen --json» (Felder wie Evaluation.data in zenos-installer)
function antwort(teile = {}) {
  return Object.assign({
    version: 1,
    ergebnis: "bereit",
    grund: "Beispiel 1.4.2 ist bereit zum Installieren.",
    ablehnung: null,
    pfad: PFAD,
    datei: "beispiel_1.4.2_arm64.deb",
    groesse: 19293798,
    sha256: SHA,
    plan: PLAN,
    name: "Beispiel",
    paket: {
      name: "beispiel",
      version: "1.4.2",
      architektur: "arm64",
      herausgeber: "Beispiel Hersteller <info@example.org>",
      homepage: "https://example.org/app",
      zusammenfassung: "Fernzugriff auf andere Rechner",
      beschreibung: "Erste Zeile,\nvon Hand umbrochen.\n\nZweiter Absatz:\n- eins\n- zwei",
      installiert_groesse: 54840320,
      abschnitt: "net",
    },
    zustand: "neu",
    installierte_version: null,
    ueber_installer: false,
    symbol: SYMBOL,
    programme: [{ id: "beispiel.desktop", name: "Beispiel" }],
    zusaetzlich: [{ name: "libxdo3", version: "1:3.2-1", alt: null }],
    entfernen: [],
    hinweise: [
      { art: "skripte", stufe: "hinweis", text: "Führt bei der Installation eigene Skripte als root aus (postinst, prerm)." },
      { art: "dienste", stufe: "hinweis", text: "Startet Systemdienste: beispiel.service." },
    ],
    dateien: 42,
  }, teile);
}

const ansicht = (teile = {}, pfad = PFAD) => L.ansichtLesen(JSON.stringify(antwort(teile)), pfad);

function letzte(teile = {}) {
  return Object.assign({
    version: 1, art: "installieren", ergebnis: "installiert", grund: "Beispiel 1.4.2 ist installiert (dazu 1 Paket).",
    paket: "beispiel", anzeigename: "Beispiel", version_neu: "1.4.2", version_alt: null, sha256: SHA,
    datei: "beispiel_1.4.2_arm64.deb", beginn: "2026-10-08T12:00:05Z", ende: "2026-10-08T12:00:40Z",
    programme: [{ id: "beispiel.desktop", name: "Beispiel" }], hinweise: [], von: "pkexec",
  }, teile);
}

test("pfadProblem: absolut, .deb, ohne Steuerzeichen, nicht zu lang", () => {
  assert.equal(L.pfadProblem(PFAD), "");
  assert.equal(L.pfadProblem("/a b/ä ö (1).deb"), "");
  for (const p of ["", "beispiel.deb", "./x.deb", "~/x.deb", "/x.zip", "/x.deb.zip", "/x.DEB", "/a/.deb", "/x\n.deb", "/x\u0000.deb", "/x\u009b.deb", "/" + "a".repeat(4096) + ".deb", null, undefined, 3, ["/x.deb"]])
    assert.notEqual(L.pfadProblem(p), "", JSON.stringify(p));
  assert.equal(L.pfadProblem("x.deb"), "Der Pfad muss absolut sein.");
  assert.equal(L.pfadProblem("/x.zip"), "Der zen Installer nimmt nur Pakete mit der Endung .deb.");
});

test("text und textZeilen: reiner Text ohne Steuer- und unsichtbare Zeichen, gekürzt", () => {
  assert.equal(L.text("  a\tb\nc  ", 10), "a b c");
  assert.equal(L.text("Bös\u202eartig\u200b", 50), "Bös?artig?");
  assert.equal(L.text("x".repeat(20), 10), "x".repeat(9) + "…");
  assert.equal(L.text(5), "");
  assert.equal(L.textZeilen("a\r\nb\n\n\n\nc\u0007", 100), "a\nb\n\nc?");
  assert.equal(L.absaetze("Ein Satz,\n umbrochen.\n\n\n1. erstens\n2) zweitens\n• drittens\n* viertens"), "Ein Satz, umbrochen.\n\n1. erstens\n2) zweitens\n• drittens\n* viertens");
  assert.equal(L.absaetze(null), "");
  // Dieselben unsichtbaren Zeichen wie kanal.js
  assert.equal(L.UNSICHTBAR.source, K.UNSICHTBAR.source);
});

test("groesseText und namenText wie zenos-installer", () => {
  assert.equal(L.groesseText(512), "512 Byte");
  assert.equal(L.groesseText(1536), "1,5 kB");
  assert.equal(L.groesseText(19293798), "18,4 MB");
  assert.equal(L.groesseText(2 * 1073741824), "2,0 GB");
  assert.equal(L.groesseText(null), "–");
  assert.equal(L.namenText(["a", "b"]), "a, b");
  assert.equal(L.namenText(["a", "b", "c", "d", "e", "f", "g", "h"]), "a, b, c, d, e, f und 2 weitere");
});

test("ansichtLesen: vollständige Antwort", () => {
  const a = ansicht();
  assert.equal(a.ergebnis, "bereit");
  assert.equal(a.pfad, PFAD);
  assert.equal(a.sha256, SHA);
  assert.equal(a.plan, PLAN);
  assert.equal(a.name, "Beispiel");
  assert.equal(a.symbol, SYMBOL);
  assert.deepEqual(roh(a.paket), {
    name: "beispiel", version: "1.4.2", architektur: "arm64", herausgeber: "Beispiel Hersteller <info@example.org>",
    homepage: "https://example.org/app", zusammenfassung: "Fernzugriff auf andere Rechner",
    beschreibung: "Erste Zeile, von Hand umbrochen.\n\nZweiter Absatz:\n- eins\n- zwei", installiertGroesse: 54840320,
  });
  assert.deepEqual(roh(a.programme), [{ id: "beispiel.desktop", name: "Beispiel" }]);
  assert.deepEqual(roh(a.zusaetzlich), [{ name: "libxdo3", version: "1:3.2-1", alt: "" }]);
  assert.deepEqual(roh(a.hinweise.map((h) => [h.art, h.warnung])), [["skripte", false], ["dienste", false]]);
  assert.equal(a.dateien, 42);
});

test("ansichtLesen: Unbrauchbares fällt weg, ohne alles Nötige kein «bereit»", () => {
  for (const json of ["", "nicht json", "[]", "null", JSON.stringify({ version: 2 })]) {
    const a = L.ansichtLesen(json, PFAD);
    assert.equal(a.ergebnis, "fehler", json);
    assert.match(a.grund, /keine lesbare Antwort/);
    assert.equal(a.datei, "beispiel_1.4.2_arm64.deb");
  }
  assert.equal(ansicht({ ergebnis: "irgendwas" }).ergebnis, "fehler");
  for (const teile of [{ sha256: "ab" }, { plan: "XYZ" }, { paket: null }, { paket: { name: "Gross" } }, { pfad: "relativ.deb" }]) {
    const a = ansicht(teile, "kaputt");
    assert.equal(a.ergebnis, "fehler", JSON.stringify(teile));
    assert.equal(a.grund, "Die Antwort von zenos-installer ist unvollständig.");
  }
  // Ohne eigenen Pfad gilt der angefragte (wenn er gültig ist)
  assert.equal(ansicht({ pfad: null }).pfad, PFAD);
  // Symbol nur aus dem Laufzeitordner, nur PNG oder SVG, ohne Zeichen, die eine file://-Adresse brechen
  for (const s of ["/etc/passwd", "/run/user/1000/zenos-installer/x.png", "/tmp/a b/zenos-installer/" + "0".repeat(32) + ".png", "/tmp/a#b/zenos-installer/" + "0".repeat(32) + ".png", "relativ/zenos-installer/" + "0".repeat(32) + ".png", "/run/zenos-installer/" + "0".repeat(32) + ".gif"])
    assert.equal(ansicht({ symbol: s }).symbol, "", s);
  // Webseite nur http(s) aus druckbarem ASCII (kein ESC, keine Richtungszeichen, kein Leerzeichen), sonst weg
  for (const h of ["javascript:alert(1)", "https://example.org/\u001b[8m", "https://example.org/‮gpj.exe", "https://a b", "https://x\"y", "https://exämple.org/"])
    assert.equal(ansicht({ paket: Object.assign(antwort().paket, { homepage: h }) }).paket.homepage, "", JSON.stringify(h));
  assert.equal(ansicht({ paket: Object.assign(antwort().paket, { homepage: "https://example.org/a?b=1&c=%20#d" }) }).paket.homepage, "https://example.org/a?b=1&c=%20#d");
  // Eine riesige Antwort wird gar nicht erst gelesen (zenos-installer begrenzt sie auf 2 MiB)
  const riesig = JSON.stringify(antwort({ grund: "x".repeat(4 * 1024 * 1024) }));
  assert.equal(L.ansichtLesen(riesig, PFAD).ergebnis, "fehler");
  assert.match(L.ansichtLesen(riesig, PFAD).grund, /keine lesbare Antwort/);
  assert.equal(L.ansichtLesen(JSON.stringify(antwort({ grund: "x".repeat(1024 * 1024) })), PFAD).ergebnis, "bereit");
  // Fremde Namen, Starter und Hinweise
  const a = ansicht({
    name: "Böse\u202eApp\nZeile",
    programme: [{ id: "../x.desktop", name: "x" }, { id: "gut.desktop", name: "" }, "x"],
    zusaetzlich: [{ name: "Gross" }, { name: "ok", version: "1" }],
    entfernen: ["a", "a", "B", 3, "b"],
    hinweise: [{ art: "entfernen", stufe: "warnung", text: "Entfernt dafür: a, b." }, { art: "x", stufe: "hinweis", text: "" }, null, { art: "Böse Art", text: "bleibt" }],
  });
  assert.equal(a.name, "Böse?App Zeile");
  assert.deepEqual(roh(a.programme), [{ id: "gut.desktop", name: "gut" }]);
  assert.deepEqual(roh(a.zusaetzlich), [{ name: "ok", version: "1", alt: "" }]);
  assert.deepEqual(roh(a.entfernen), ["a", "b"]);
  assert.deepEqual(roh(a.hinweise), [{ art: "entfernen", warnung: true, text: "Entfernt dafür: a, b." }, { art: "", warnung: false, text: "bleibt" }]);
  // Eine Ablehnung bleibt eine Ablehnung, mit Grund
  const ab = ansicht({ ergebnis: "abgelehnt", ablehnung: "architektur", grund: "Das Paket ist für amd64, dieser Rechner braucht arm64.", sha256: SHA, plan: null });
  assert.equal(ab.ergebnis, "abgelehnt");
  assert.equal(ab.ablehnung, "architektur");
  assert.match(ab.grund, /amd64/);
});

test("zeilen: Werte zweispaltig, Version mit Zustand", () => {
  const z = L.zeilen(ansicht());
  assert.deepEqual(roh(z.map((r) => r.titel)), ["Version", "Paket", "Herausgeber", "Webseite", "Braucht", "Datei", "Dazu", "Programme", "SHA-256"]);
  const wert = (titel, a = ansicht()) => L.zeilen(a).find((r) => r.titel === titel)?.wert;
  assert.equal(wert("Version"), "1.4.2 · neu");
  assert.equal(wert("Paket"), "beispiel · arm64");
  assert.equal(wert("Braucht"), "52,3 MB auf dem Gerät");
  assert.equal(wert("Datei"), "beispiel_1.4.2_arm64.deb · 18,4 MB");
  assert.equal(wert("Dazu"), "1 Paket: libxdo3");
  assert.equal(wert("Programme"), "Beispiel");
  assert.equal(wert("SHA-256"), SHA);
  assert.equal(z.find((r) => r.titel === "SHA-256").umbruch, true);
  assert.equal(wert("Version", ansicht({ zustand: "update", installierte_version: "1.4.1" })), "1.4.2 · ersetzt 1.4.1");
  assert.equal(wert("Version", ansicht({ zustand: "rueckschritt", installierte_version: "1.5" })), "1.4.2 · älter als 1.5");
  assert.equal(wert("Version", ansicht({ zustand: "gleich", ergebnis: "installiert" })), "1.4.2 · schon installiert");
  assert.equal(wert("Programme", ansicht({ programme: [] })), "keins im Befehlsfeld");
  assert.equal(wert("Dazu", ansicht({ zusaetzlich: [{ name: "a" }, { name: "b" }, { name: "c" }] })), "3 Pakete: a, b, c");
  assert.equal(wert("Herausgeber", ansicht({ paket: Object.assign(antwort().paket, { herausgeber: null }) })), undefined);
  assert.deepEqual(roh(L.zeilen(ansicht({ ergebnis: "abgelehnt", paket: null }))), []);
  // Früh abgelehnt (Architektur): Der Inhalt wurde nicht gelesen, also kein «keins im Befehlsfeld»
  assert.equal(wert("Programme", ansicht({ ergebnis: "abgelehnt", programme: [], dateien: null })), undefined);
  assert.deepEqual(roh(L.zeilen(null)), []);
});

test("bild: ansehen, Ansicht, Lauf und Ende", () => {
  const ansehen = L.bild({ phase: "ansehen", pfad: PFAD, ansicht: null });
  assert.equal(ansehen.name, "beispiel_1.4.2_arm64.deb");
  assert.equal(ansehen.lage.titel, "Wird angesehen …");
  assert.equal(ansehen.primaer, null);
  assert.deepEqual(roh(ansehen.sekundaer), { text: "Abbrechen", aktion: "schliessen" });
  assert.deepEqual(roh(ansehen.zeilen), []);

  const bereit = L.bild({ phase: "ansicht", pfad: PFAD, ansicht: ansicht() });
  assert.equal(bereit.name, "Beispiel");
  assert.equal(bereit.zusammenfassung, "Fernzugriff auf andere Rechner");
  assert.equal(bereit.kennung, "beispiel 1.4.2");
  assert.equal(bereit.symbol, SYMBOL);
  assert.deepEqual(roh(bereit.lage), { symbol: "info", ton: "akzent", titel: "Bereit zum Installieren", satz: "«Installieren» verlangt dein Passwort. Das Paket läuft dabei mit allen Rechten; was es mitbringt, steht unten." });
  assert.match(L.bild({ phase: "ansicht", ansicht: ansicht({ zustand: "update" }) }).lage.satz, /^«Aktualisieren» verlangt dein Passwort/);
  assert.deepEqual(roh(bereit.primaer), { text: "Installieren", aktion: "installieren", aktiv: true, symbol: "schloss" });
  assert.equal(bereit.sekundaer.text, "Abbrechen");
  assert.equal(bereit.hinweise.length, 2);
  assert.equal(bereit.beschreibung, "Erste Zeile, von Hand umbrochen.\n\nZweiter Absatz:\n- eins\n- zwei");
  assert.equal(L.bild({ phase: "ansicht", ansicht: ansicht({ zustand: "update", installierte_version: "1" }) }).primaer.text, "Aktualisieren");
  assert.equal(L.bild({ phase: "ansicht", ansicht: ansicht({ zustand: "update" }) }).lage.titel, "Update bereit");
  assert.equal(L.bild({ phase: "ansicht", ansicht: ansicht({ zustand: "rueckschritt" }) }).primaer.text, "Ältere Version installieren");

  const gleich = L.bild({ phase: "ansicht", ansicht: ansicht({ ergebnis: "installiert", zustand: "gleich" }) });
  assert.equal(gleich.lage.titel, "Schon installiert");
  assert.deepEqual(roh(gleich.primaer), { text: "Öffnen", aktion: "programm", aktiv: true, symbol: "" });
  assert.equal(gleich.sekundaer.text, "Schliessen");
  assert.equal(L.bild({ phase: "ansicht", ansicht: ansicht({ ergebnis: "installiert", zustand: "gleich", programme: [] }) }).primaer, null);

  const abgelehnt = L.bild({ phase: "ansicht", ansicht: ansicht({ ergebnis: "abgelehnt", grund: "Das Paket ist für amd64, dieser Rechner braucht arm64.", plan: null }) });
  assert.deepEqual(roh(abgelehnt.lage), { symbol: "warnung", ton: "warnung", titel: "Lässt sich nicht installieren", satz: "Das Paket ist für amd64, dieser Rechner braucht arm64." });
  assert.equal(abgelehnt.primaer, null);
  assert.equal(abgelehnt.sekundaer.text, "Schliessen");
  const fehler = L.bild({ phase: "ansicht", pfad: PFAD, ansicht: L.ansichtLesen("", PFAD) });
  assert.equal(fehler.lage.titel, "Lässt sich nicht ansehen");
  assert.equal(fehler.name, "beispiel_1.4.2_arm64.deb");

  const lauf = L.bild({ phase: "laeuft", ansicht: ansicht(), laufPhase: "", polkitOffen: true });
  assert.equal(lauf.lage.titel, "Wartet auf dein Passwort …");
  assert.match(lauf.lage.satz, /Fenster schliessen/);
  assert.deepEqual(roh(lauf.primaer), { text: "Wartet …", aktion: "", aktiv: false, symbol: "" });
  assert.equal(L.bild({ phase: "laeuft", ansicht: ansicht(), laufPhase: "wartet" }).primaer.text, "Läuft …");
  assert.equal(lauf.zeilen.length, 9, "die Werte bleiben stehen");
  assert.equal(L.bild({ phase: "laeuft", ansicht: ansicht(), laufPhase: "installiert" }).lage.titel, "Wird installiert …");
  assert.equal(L.bild({ phase: "laeuft", ansicht: ansicht(), laufPhase: "wartet" }).lage.titel, "Wartet auf ein laufendes Update …");
  assert.equal(L.bild({ phase: "laeuft", ansicht: ansicht(), laufPhase: "prueft" }).lage.titel, "Prüft das Paket noch einmal …");

  const ok = L.abschluss(0, { letzte: L.letzteLesen(letzte()), sha256: SHA, beginnMs: JETZT, name: "Beispiel" });
  const fertig = L.bild({ phase: "ende", ansicht: ansicht(), ende: ok });
  assert.deepEqual(roh(fertig.lage), { symbol: "haken", ton: "akzent", titel: "Beispiel ist installiert", satz: "Du findest es im Befehlsfeld." });
  assert.deepEqual(roh(fertig.primaer), { text: "Öffnen", aktion: "programm", aktiv: true, symbol: "" });
  assert.deepEqual(roh(fertig.sekundaer), { text: "Fertig", aktion: "schliessen" });
  assert.deepEqual(roh(fertig.zeilen), [], "nach dem Ende nur noch das Ergebnis");
  const nochmal = L.bild({ phase: "ende", ansicht: ansicht(), ende: L.abschluss(3, { fehler: "zenos-installer: Die Datei hat sich seit dem Ansehen geändert. Noch einmal ansehen.\n", sha256: SHA, beginnMs: JETZT }) });
  assert.equal(nochmal.lage.satz, "Die Datei hat sich seit dem Ansehen geändert. Noch einmal ansehen.");
  assert.deepEqual(roh(nochmal.primaer), { text: "Noch einmal ansehen", aktion: "nochmal", aktiv: true, symbol: "" });
  assert.equal(nochmal.sekundaer.text, "Schliessen");
  const gescheitert = L.bild({ phase: "ende", ansicht: ansicht(), ende: L.abschluss(1, { letzte: L.letzteLesen(letzte({ ergebnis: "fehler", grund: "Die Installation ist gescheitert (apt-get Exit 100)." })), sha256: SHA, beginnMs: JETZT }) });
  assert.equal(gescheitert.lage.titel, "Installation gescheitert");
  assert.equal(gescheitert.primaer, null);
});

test("statusText: Antwort von IPC installer status", () => {
  assert.equal(L.statusText("", null, null), "zu");
  assert.equal(L.statusText("ansehen", null, null), "ansehen");
  for (const e of ["bereit", "installiert", "abgelehnt", "fehler"])
    assert.equal(L.statusText("ansicht", { ergebnis: e }, null), e);
  assert.equal(L.statusText("laeuft", ansicht(), null), "laeuft");
  assert.equal(L.statusText("ende", ansicht(), { ok: true }), "fertig");
  assert.equal(L.statusText("ende", ansicht(), { ok: false }), "gescheitert");
});

test("befehl: pkexec nur mit fester Helfer-Stelle und genau der angezeigten Ansicht", () => {
  assert.deepEqual(roh(L.befehl(L.HELFER, ansicht())), ["pkexec", "/opt/zenos/scripts/bin/zenos-installer-bedienen", "installieren", PFAD, SHA, PLAN]);
  assert.equal(L.befehl("zenos-installer-bedienen", ansicht()), null);
  assert.equal(L.befehl(L.HELFER, null), null);
  assert.equal(L.befehl(L.HELFER, ansicht({ ergebnis: "installiert" })), null);
  assert.equal(L.befehl(L.HELFER, ansicht({ ergebnis: "abgelehnt" })), null);
  const a = ansicht();
  a.pfad = "/x\n.deb";
  assert.equal(L.befehl(L.HELFER, a), null);
});

test("letzteLesen, statusLesen, laufPhase", () => {
  const l = L.letzteLesen(letzte());
  assert.deepEqual(roh(l), { art: "installieren", ergebnis: "installiert", grund: "Beispiel 1.4.2 ist installiert (dazu 1 Paket).", paket: "beispiel", anzeigename: "Beispiel", sha256: SHA, endeMs: Date.parse("2026-10-08T12:00:40Z"), programme: [{ id: "beispiel.desktop", name: "Beispiel" }] });
  for (const kaputt of [null, "", "{", { version: 2, ergebnis: "installiert" }, { version: 1, ergebnis: "toll" }])
    assert.equal(L.letzteLesen(typeof kaputt === "string" ? kaputt : JSON.stringify(kaputt)), null);
  const s = L.statusLesen(JSON.stringify({ version: 1, laeuft: [{ art: "entfernen", paket: "x", phase: "entfernt" }, { art: "installieren", paket: "beispiel", phase: "prueft", seit: null }, { art: "x" }], letzte: letzte(), anzahl: 1, ablage: 0 }));
  assert.deepEqual(roh(s.laeuft), [{ art: "entfernen", paket: "x", phase: "entfernt" }, { art: "installieren", paket: "beispiel", phase: "prueft" }]);
  assert.equal(s.letzte.paket, "beispiel");
  assert.equal(L.laufPhase(s), "prueft");
  assert.equal(L.laufPhase(s, "entfernen"), "entfernt");
  assert.equal(L.laufPhase(s, "entfernen", "x"), "entfernt");
  assert.equal(L.laufPhase(s, "entfernen", "beispiel"), "");
  assert.equal(L.laufPhase(L.statusLesen("")), "");
  assert.deepEqual(roh(L.statusLesen("kaputt")), { laeuft: [], letzte: null });
});

test("abschluss: Exit von pkexec und letzte.json genau dieser Datei", () => {
  const info = (teile = {}) => Object.assign({ letzte: L.letzteLesen(letzte()), sha256: SHA, beginnMs: JETZT + 3000, fehler: "", name: "Beispiel", programme: [] }, teile);
  // Passwortabfrage abgebrochen: zurück, still
  assert.deepEqual(roh(L.abschluss(126, info())), { art: "zurueck" });
  const ok = L.abschluss(0, info());
  assert.equal(ok.ok, true);
  assert.equal(ok.ergebnis, "installiert");
  assert.deepEqual(roh(ok.programme), [{ id: "beispiel.desktop", name: "Beispiel" }]);
  // letzte.json einer anderen Datei oder von früher zählt nicht: Starter dann aus der Ansicht
  for (const anders of [{ letzte: L.letzteLesen(letzte({ sha256: "00".repeat(32) })) }, { beginnMs: JETZT + 60000 }, { letzte: null }, { letzte: L.letzteLesen(letzte({ art: "entfernen" })) }]) {
    const e = L.abschluss(0, info(Object.assign({ programme: [{ id: "aus-der-ansicht.desktop", name: "Ansicht" }] }, anders)));
    assert.equal(e.ok, true);
    assert.deepEqual(roh(e.programme), [{ id: "aus-der-ansicht.desktop", name: "Ansicht" }], JSON.stringify(anders));
  }
  // Sekunden in letzte.json: Ein Ende in derselben Sekunde wie der Klick zählt
  assert.equal(L.abschluss(0, info({ letzte: L.letzteLesen(letzte({ ende: "2026-10-08T12:00:03Z" })), beginnMs: JETZT + 3999 })).programme.length, 1);
  const ohneStarter = L.abschluss(0, info({ letzte: L.letzteLesen(letzte({ programme: [] })) }));
  assert.match(ohneStarter.satz, /nicht im Befehlsfeld/);
  const gleich = L.abschluss(0, info({ letzte: L.letzteLesen(letzte({ ergebnis: "gleich", grund: "Beispiel 1.4.2 ist schon installiert." })) }));
  assert.equal(gleich.ergebnis, "gleich");
  assert.equal(gleich.titel, "Schon installiert");

  const abgelehnt = L.abschluss(3, info({ letzte: L.letzteLesen(letzte({ ergebnis: "abgelehnt", grund: "Seit dem Ansehen hat sich geändert, was die Installation mitbrächte oder entfernte. Noch einmal ansehen und bestätigen." })) }));
  assert.equal(abgelehnt.ergebnis, "abgelehnt");
  assert.equal(abgelehnt.nochmal, true);
  assert.match(abgelehnt.satz, /^Seit dem Ansehen/);
  assert.match(L.abschluss(3, info({ letzte: null })).satz, /seit dem Ansehen geändert/);
  assert.equal(L.abschluss(10, info()).nochmal, true);
  const belegt = L.abschluss(75, info({ letzte: null }));
  assert.equal(belegt.titel, "Gerade nicht");
  assert.equal(belegt.nochmal, true);
  assert.equal(L.abschluss(127, info()).satz, "Installieren geht nur in der aktiven Sitzung am Gerät.");
  assert.match(L.abschluss(127, info({ fehler: "Error executing command as another user: No authentication agent found." })).satz, /polkit-Agent/);
  assert.equal(L.abschluss(-1, info()).satz, "pkexec lässt sich nicht starten.");
  const kaputt = L.abschluss(1, info({ letzte: L.letzteLesen(letzte({ ergebnis: "fehler", grund: "Die Installation ist gescheitert (apt-get Exit 100)." })) }));
  assert.equal(kaputt.ok, false);
  assert.equal(kaputt.satz, "Die Installation ist gescheitert (apt-get Exit 100).");
  assert.equal(L.abschluss(1, info({ letzte: null, fehler: "x\nzenos-installer-bedienen: /usr/local/libexec/zenos/zenos-installer fehlt (install.sh)\n" })).satz, "/usr/local/libexec/zenos/zenos-installer fehlt (install.sh)");
  assert.equal(L.abschluss(1, info({ letzte: null })).satz, "zenos-installer endete mit Exit 1.");
});

test("mitteilung: nur das Ergebnis, ruhig nach Erfolg", () => {
  const ok = L.abschluss(0, { letzte: L.letzteLesen(letzte()), sha256: SHA, beginnMs: JETZT, name: "Beispiel" });
  assert.deepEqual(roh(L.mitteilung(ok)), { titel: "Beispiel ist installiert", text: "Du findest es im Befehlsfeld.", dringlichkeit: "low" });
  assert.equal(L.mitteilung(L.abschluss(1, { name: "Beispiel" })).dringlichkeit, "normal");
  assert.equal(L.mitteilung({ art: "zurueck" }), null);
  assert.deepEqual(roh(L.mitteilungBefehl({ titel: "A\nB", text: "c", dringlichkeit: "critical" })), ["notify-send", "--app-name=zen Installer", "--icon=zenos", "--urgency=normal", "--category=system", "--", "A B", "c"]);
});

test("programmZiel: erster gültiger Starter", () => {
  assert.deepEqual(roh(L.programmZiel([{ id: "beispiel.desktop", name: "Beispiel" }, { id: "zwei.desktop" }])), { id: "beispiel", pfad: "/usr/share/applications/beispiel.desktop" });
  assert.deepEqual(roh(L.programmZiel([{ id: "../x.desktop" }, { id: "org.example.App.desktop" }])), { id: "org.example.App", pfad: "/usr/share/applications/org.example.App.desktop" });
  assert.equal(L.programmZiel([]), null);
  assert.equal(L.programmZiel(null), null);
});

// Antwort von «zenos-installer liste --json» (Felder wie list_entries)
function listeAntwort(pakete) {
  return JSON.stringify({ version: 1, pakete });
}
function eintrag(teile = {}) {
  return Object.assign({ name: "beispiel", anzeigename: "Beispiel", version: "1.4.2", installierte_version: "1.4.2", status: "installed", zeit: "2026-10-08T12:00:40Z", datei: "beispiel_1.4.2_arm64.deb", programme: [{ id: "beispiel.desktop", name: "Beispiel" }] }, teile);
}

test("listeLesen: Einträge nach Name, Zustand aus dpkg, Unbrauchbares fällt weg", () => {
  const l = L.listeLesen(listeAntwort([
    eintrag(),
    eintrag({ name: "zweites", anzeigename: "Alpha\u202e\nApp", version: "2.0", installierte_version: "2.1", zeit: "kaputt" }),
    eintrag({ name: "weg", anzeigename: "", version: "0.9", installierte_version: null, status: null }),
    eintrag({ name: "halb", anzeigename: "Halb", installierte_version: "1.0", status: "half-configured" }),
    eintrag({ name: "../boese" }),
    eintrag({ name: "beispiel", anzeigename: "Doppelt" }),
    null,
    "x",
  ]));
  assert.deepEqual(roh(l), [
    { paket: "zweites", name: "Alpha? App", version: "2.1", zustand: "installiert", seitMs: null },
    { paket: "beispiel", name: "Beispiel", version: "1.4.2", zustand: "installiert", seitMs: Date.parse("2026-10-08T12:00:40Z") },
    { paket: "halb", name: "Halb", version: "1.0", zustand: "halb", seitMs: Date.parse("2026-10-08T12:00:40Z") },
    { paket: "weg", name: "weg", version: "0.9", zustand: "weg", seitMs: Date.parse("2026-10-08T12:00:40Z") },
  ]);
  assert.deepEqual(roh(L.listeLesen(listeAntwort([]))), []);
  for (const kaputt of ["", "{", JSON.stringify({ version: 2, pakete: [] }), JSON.stringify({ version: 1 }), JSON.stringify([eintrag()])])
    assert.equal(L.listeLesen(kaputt), null, kaputt);
  // Höchstens LISTE_MAX Einträge
  const viele = Array.from({ length: L.LISTE_MAX + 5 }, (_, i) => eintrag({ name: `paket${i}` }));
  assert.equal(L.listeLesen(listeAntwort(viele)).length, L.LISTE_MAX);
});

test("seitText: heute, gestern, Datum, anderes Jahr (Ortszeit)", () => {
  const jetzt = new Date(2026, 9, 8, 9, 30).getTime();
  assert.equal(L.seitText(new Date(2026, 9, 8, 0, 5).getTime(), jetzt), "seit heute");
  assert.equal(L.seitText(new Date(2026, 9, 7, 23, 55).getTime(), jetzt), "seit gestern");
  assert.equal(L.seitText(new Date(2026, 9, 3, 12, 0).getTime(), jetzt), "seit 3. Okt.");
  assert.equal(L.seitText(new Date(2026, 2, 1, 12, 0).getTime(), jetzt), "seit 1. März");
  assert.equal(L.seitText(new Date(2025, 11, 24, 12, 0).getTime(), jetzt), "seit 24. Dez. 2025");
  assert.equal(L.seitText(NaN, jetzt), "");
  assert.equal(L.seitText(null, jetzt), "");
});

test("listeZeilen: zweite Zeile, «Entfernen …» mit Schloss, eine Bedienung zur Zeit", () => {
  const jetzt = Date.parse("2026-10-08T12:00:40Z");
  const liste = L.listeLesen(listeAntwort([eintrag(), eintrag({ name: "weg", anzeigename: "Weg", version: "0.9", installierte_version: null, status: null }), eintrag({ name: "halb", anzeigename: "Halb", installierte_version: "1.0", status: "half-configured" })]));
  const frei = L.listeZeilen(liste, { laeuft: "", frei: true, jetztMs: jetzt });
  assert.deepEqual(roh(frei), [
    { paket: "beispiel", name: "Beispiel", unter: "beispiel 1.4.2 · seit heute", knopf: { text: "Entfernen …", aktiv: true, symbol: "schloss" } },
    { paket: "halb", name: "Halb", unter: "halb 1.0 · nur halb installiert · seit heute", knopf: { text: "Entfernen …", aktiv: true, symbol: "schloss" } },
    { paket: "weg", name: "Weg", unter: "weg 0.9 · nicht mehr installiert", knopf: { text: "Aus der Liste …", aktiv: true, symbol: "schloss" } },
  ]);
  // Gesperrt oder ohne Angabe: kein Knopf bedienbar
  assert.ok(L.listeZeilen(liste, { laeuft: "", frei: false, jetztMs: jetzt }).every((z) => z.knopf.aktiv === false));
  assert.ok(L.listeZeilen(liste, {}).every((z) => z.knopf.aktiv === false));
  // Während «beispiel» entfernt wird: dort die Phase, alle anderen warten
  const lauf = (teile) => L.listeZeilen(liste, Object.assign({ laeuft: "beispiel", frei: true, jetztMs: jetzt }, teile));
  assert.deepEqual(roh(lauf({ polkitOffen: true })[0].knopf), { text: "Wartet …", aktiv: false, symbol: "" });
  assert.equal(lauf({ laufPhase: "wartet" })[0].knopf.text, "Wartet auf ein Update …");
  assert.equal(lauf({ laufPhase: "entfernt" })[0].knopf.text, "Wird entfernt …");
  assert.equal(lauf({ laufPhase: "" })[0].knopf.text, "Wird entfernt …");
  assert.deepEqual(roh(lauf({}).slice(1).map((z) => [z.knopf.text, z.knopf.aktiv])), [["Entfernen …", false], ["Aus der Liste …", false]]);
  assert.deepEqual(roh(L.listeZeilen(null, {})), []);
});

test("entfernenBefehl: pkexec nur mit fester Helfer-Stelle und einem gültigen Paketnamen", () => {
  assert.deepEqual(roh(L.entfernenBefehl(L.HELFER, "beispiel")), ["pkexec", L.HELFER, "entfernen", "beispiel"]);
  assert.deepEqual(roh(L.entfernenBefehl(L.HELFER, "lib.x+y-1")), ["pkexec", L.HELFER, "entfernen", "lib.x+y-1"]);
  for (const paket of ["", "-r", "Beispiel", "a b", "a;b", "../x", "x\n", null, 3, "a".repeat(129)])
    assert.equal(L.entfernenBefehl(L.HELFER, paket), null, String(paket));
  assert.equal(L.entfernenBefehl("zenos-installer-bedienen", "beispiel"), null);
});

test("entfernenRueckmeldung: Hinweis nach dem eigenen Klick, still nach Abbruch", () => {
  const beginn = Date.parse("2026-10-08T12:00:00Z");
  const fertig = (teile = {}) => L.letzteLesen(JSON.stringify(Object.assign({ version: 1, art: "entfernen", ergebnis: "entfernt", grund: "Beispiel ist entfernt.", paket: "beispiel", anzeigename: "Beispiel", ende: "2026-10-08T12:00:09Z" }, teile)));
  const info = (teile = {}) => Object.assign({ letzte: fertig(), paket: "beispiel", name: "Beispiel", beginnMs: beginn, fehler: "" }, teile);
  assert.deepEqual(roh(L.entfernenRueckmeldung(0, info())), { text: "Beispiel ist entfernt", art: "" });
  assert.equal(L.entfernenRueckmeldung(0, info({ letzte: fertig({ grund: "weg war schon entfernt; aus der Liste genommen." }) })).text, "weg war schon entfernt; aus der Liste genommen");
  // letzte.json eines anderen Pakets, einer Installation oder von vorher zählt nicht
  for (const anders of [fertig({ paket: "zweites" }), fertig({ art: "installieren" }), fertig({ ende: "2026-10-08T11:59:00Z" }), null])
    assert.equal(L.entfernenRueckmeldung(0, info({ letzte: anders, name: "Mein Programm" })).text, "Mein Programm ist entfernt");
  assert.equal(L.entfernenRueckmeldung(0, info({ letzte: null, name: "" })).text, "beispiel ist entfernt");
  assert.equal(L.entfernenRueckmeldung(126, info()), null);
  const abgelehnt = L.entfernenRueckmeldung(3, info({ letzte: fertig({ ergebnis: "abgelehnt", grund: "Mit beispiel gingen auch libfoo. Das macht der zen Installer nicht; im Terminal: sudo apt remove beispiel" }) }));
  assert.deepEqual(roh(abgelehnt), { text: "Nicht entfernt: Mit beispiel gingen auch libfoo. Das macht der zen Installer nicht; im Terminal: sudo apt remove beispiel", art: "warnung" });
  assert.equal(L.entfernenRueckmeldung(3, info({ letzte: null, fehler: "zenos-installer: beispiel kam nicht über den zen Installer.\n" })).text, "Nicht entfernt: beispiel kam nicht über den zen Installer");
  assert.equal(L.entfernenRueckmeldung(75, info({ letzte: null })).art, "warnung");
  assert.match(L.entfernenRueckmeldung(75, info({ letzte: null })).text, /^Gerade läuft ein Update/);
  assert.equal(L.entfernenRueckmeldung(10, info({ letzte: null })).text, "Beispiel ist noch da: abgebrochen, bevor sich etwas änderte");
  assert.match(L.entfernenRueckmeldung(127, info({ fehler: "Error executing command as another user: No authentication agent found." })).text, /polkit-Agent/);
  assert.equal(L.entfernenRueckmeldung(127, info()).text, "Entfernen: nicht erlaubt (nur in der aktiven Sitzung am Gerät)");
  assert.equal(L.entfernenRueckmeldung(-1, info()).art, "warnung");
  assert.equal(L.entfernenRueckmeldung(1, info({ letzte: fertig({ ergebnis: "fehler", grund: "Entfernen ist gescheitert (apt-get Exit 100)." }) })).text, "Entfernen gescheitert: Entfernen ist gescheitert (apt-get Exit 100)");
  assert.equal(L.entfernenRueckmeldung(1, info({ letzte: null })).text, "Entfernen gescheitert: Exit 1");
});

test("Abgleich mit zenos-installer: Felder, Ergebnisse, Phasen, Pfadprüfung", () => {
  const py = lesen("scripts", "bin", "zenos-installer");
  // Felder der Antwort von ansehen (Evaluation.data): installer.js liest jedes, das das Fenster braucht
  const daten = py.match(/self\.data = \{([\s\S]*?)\}\n/)[1];
  const felder = [...daten.matchAll(/"([a-z0-9_]+)":/g)].map((m) => m[1]);
  assert.deepEqual(felder, ["version", "ergebnis", "grund", "ablehnung", "pfad", "datei", "groesse", "sha256", "plan", "name", "paket", "zustand", "installierte_version", "ueber_installer", "symbol", "programme", "zusaetzlich", "entfernen", "hinweise", "dateien"]);
  const js = lesen("shell", "installer", "installer.js");
  for (const f of felder)
    assert.match(js, new RegExp(`d\\.${f}\\b`), `installer.js liest ${f}`);
  // Ergebnisse von letzte.json und Phasen einer Unit
  const ergebnisse = [...py.match(/RESULT_TEXT = \{([\s\S]*?)\}/)[1].matchAll(/"([a-z_]+)": "/g)].map((m) => m[1]);
  assert.deepEqual([...L.LETZTE].sort(), ergebnisse.sort());
  const phasen = [...new Set([...py.matchAll(/session\.note\("([a-z]+)"\)|self\.note\("([a-z]+)"\)/g)].map((m) => m[1] || m[2]))];
  assert.deepEqual([...L.LAUF_PHASEN].sort(), phasen.sort());
  // Dieselben Texte wie check_user_path
  for (const satz of ["Ungültiger Dateiname.", "Der Pfad muss absolut sein.", "Der zen Installer nimmt nur Pakete mit der Endung .deb."])
    assert.ok(py.includes(`"${satz}"`), satz);
  // Felder von «liste --json» (list_entries): listeLesen liest jedes, das die Liste braucht
  const eintraege = py.match(/result\.append\(\{([\s\S]*?)\}\)/)[1];
  const listenFelder = [...eintraege.matchAll(/"([a-z_]+)":/g)].map((m) => m[1]);
  assert.deepEqual(listenFelder, ["name", "anzeigename", "version", "installierte_version", "status", "zeit", "datei", "programme"]);
  for (const f of ["name", "anzeigename", "version", "installierte_version", "status", "zeit"])
    assert.match(js, new RegExp(`p\\.${f}\\b`), `listeLesen liest ${f}`);
  assert.match(py, /print\(json\.dumps\(\{"version": 1, "pakete": entries\}/);
  // Antworten der Oberfläche, die «oeffnen» kennt
  for (const wort of ["offen", "laeuft", "gesperrt", "einrichtung", "ungueltig"])
    assert.ok(py.includes(`"${wort}"`), `zenos-installer kennt die Antwort ${wort}`);
});

test("Abgleich mit Helfer, polkit und Starter", () => {
  const policy = lesen("system", "polkit", "org.zenos.installer.policy");
  assert.match(policy, new RegExp(`exec\\.path">${L.HELFER.replace(/\//g, "\\/")}<`));
  assert.match(policy, /exec\.argv1">installieren</);
  assert.match(policy, /<action id="org\.zenos\.installer\.installieren">[\s\S]*?<allow_active>auth_admin<\/allow_active>/);
  assert.match(lesen("scripts", "bin", "zenos-installer-bedienen"), /^  installieren\)$/m);
  // Entfernen (Einstellungen › Apps): eigene Aktion, ebenfalls jedes Mal mit Passwort
  assert.match(policy, /exec\.argv1">entfernen</);
  assert.match(policy, /<action id="org\.zenos\.installer\.entfernen">[\s\S]*?<allow_active>auth_admin<\/allow_active>/);
  assert.match(lesen("scripts", "bin", "zenos-installer-bedienen"), /^  entfernen\)$/m);
  const starter = lesen("system", "applications", "zenos-installer.desktop");
  assert.match(starter, /^Name=zen Installer$/m);
  assert.match(starter, /^Exec=\/opt\/zenos\/scripts\/bin\/zenos-installer oeffnen %f$/m);
  assert.match(starter, /^NoDisplay=true$/m);
  assert.match(starter, /^MimeType=application\/vnd\.debian\.binary-package;application\/x-deb;$/m);
  // Thunar: «Mit zen Installer öffnen» für .deb (Aufruf wie der Starter, ohne Shell)
  assert.match(lesen("system", "thunar", "uca.xml"), /<command>\/opt\/zenos\/scripts\/bin\/zenos-installer oeffnen %f<\/command>\s+<description>[^<]*<\/description>\s+<patterns>\*\.deb<\/patterns>/);
  const mime = lesen("system", "xdg", "labwc-mimeapps.list");
  assert.match(mime, /^application\/vnd\.debian\.binary-package=zenos-installer\.desktop$/m);
  assert.match(mime, /^application\/x-deb=zenos-installer\.desktop$/m);
});

test("Abgleich mit der Oberfläche: shell.qml, IPC, Fenster, Rundgang, zen install", () => {
  const shell = lesen("shell", "shell.qml");
  assert.match(shell, /^import qs\.installer as InstallerModul$/m);
  assert.match(shell, /source: "installer\/Installer\.qml"\s+loading: true/);
  const qml = lesen("shell", "installer", "Installer.qml");
  assert.match(qml, /target: "installer"/);
  assert.match(qml, /function oeffnen\(pfad: string\): string/);
  assert.match(qml, /function status\(\): string/);
  assert.match(qml, /function schliessen\(\): void/);
  assert.match(qml, /Logik\.befehl\(Logik\.HELFER, ansicht\)/);
  assert.match(qml, /readonly property string titel: "zen Installer"/);
  // Nicht während Sperre und Einrichtung, keine Shell
  assert.match(qml, /if \(Dienste\.Oberflaeche\.gesperrt\)\s+return "gesperrt";/);
  assert.match(qml, /if \(Dienste\.Oberflaeche\.einrichtungOffen\)\s+return "einrichtung";/);
  assert.match(qml, /command: \[programm, "ansehen", pfad, "--json"\]/);
  for (const datei of ["Installer.qml", "InstallerInhalt.qml", "installer.js"]) {
    const t = lesen("shell", "installer", datei);
    assert.doesNotMatch(t, /"(?:ba|da|z|fi)?sh",\s*"-c"/, datei);
    assert.doesNotMatch(t, /#[0-9a-fA-F]{6}\b/, datei);
    assert.doesNotMatch(t, /\bduration:\s*(?:[3-9]\d\d|\d{4,})/, datei);
  }
  const inhalt = lesen("shell", "installer", "InstallerInhalt.qml");
  // Alles aus dem Paket als reiner Text
  assert.equal((inhalt.match(/^\s+Text \{$/gm) || []).length, (inhalt.match(/textFormat: Text\.PlainText/g) || []).length);
  // Rundgang in pruefen.sh: ansehen ja, installieren nie
  const pruefen = lesen("scripts", "pruefen.sh");
  for (const zeile of ["installer status → zu", "installer oeffnen paket.deb → ungueltig", "installer oeffnen @DEB@ → offen", "installer status ~> bereit", "installer schliessen", "installer oeffnen @DEB@ → einrichtung"])
    assert.ok(pruefen.includes(`  "${zeile}"`), zeile);
  assert.doesNotMatch(pruefen, /^  "installer installieren/m);
  // zen install: dasselbe Programm, sudo nur mit dem Helfer und genau SHA-256 und Plan aus der Ansicht
  const zen = lesen("scripts", "zen.d", "install.sh");
  assert.match(zen, /^# hilfe: install /m);
  assert.match(zen, /"\$programm" ansehen "\$pfad" --auftrag/);
  assert.match(zen, /\$SUDO "\$helfer" installieren "\$pfad" "\$sha" "\$plan"/);
  // Liste in Einstellungen › Apps: Dienst InstallerListe mit pkexec nur über entfernenBefehl, IPC «installer liste»
  // ohne Entfernen, die Seite ruft nur den Dienst
  const dienst = lesen("shell", "dienste", "InstallerListe.qml");
  assert.match(dienst, /^pragma Singleton$/m);
  assert.match(dienst, /import "\.\.\/installer\/installer\.js" as Logik/);
  assert.match(dienst, /const argv = Logik\.entfernenBefehl\(helfer, paket\);/);
  assert.match(dienst, /readonly property string helfer: Logik\.HELFER/);
  assert.match(dienst, /command: \[root\.programm, "liste", "--json"\]/);
  assert.match(dienst, /Oberflaeche\.hinweis\(antwort\.text, antwort\.art\)/);
  assert.match(dienst, /if \(_laeuft !== "" \|\| Oberflaeche\.gesperrt \|\| !_liste\.some\(e => e\.paket === paket\)\)\s+return false;/);
  assert.doesNotMatch(dienst, /notify-send/);
  assert.match(qml, /function liste\(\): string \{/);
  assert.doesNotMatch(qml, /InstallerListe\.entfernen/);
  const seite = lesen("shell", "einstellungen", "SeiteApps.qml");
  assert.match(seite, /onClicked: Dienste\.InstallerListe\.entfernen\(zeile\.modelData\.paket\)/);
  assert.match(seite, /model: Dienste\.InstallerListe\.zeilen/);
  assert.match(seite, /beschriftung: "Über den zen Installer"/);
  for (const [name, t] of [["InstallerListe.qml", dienst], ["SeiteApps.qml", seite]]) {
    assert.doesNotMatch(t, /"(?:ba|da|z|fi)?sh",\s*"-c"/, name);
    assert.doesNotMatch(t, /#[0-9a-fA-F]{6}\b/, name);
  }
  // Was aus dem Paket kommt (Name), steht als reiner Text da
  const zeile = seite.match(/component InstallerZeile: Item \{([\s\S]*?)\n    \}\n/)[1];
  assert.equal((zeile.match(/^\s+Text \{$/gm) || []).length, (zeile.match(/textFormat: Text\.PlainText/g) || []).length);
  assert.ok(pruefen.includes('  "installer liste"'), "Rundgang: installer liste");
  // Symbol «paket» gibt es
  assert.match(lesen("shell", "komponenten", "symbole.js"), /^    "paket": \{ d: "/m);
});
