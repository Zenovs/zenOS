// Einheitentests für shell/modi/zustandslogik.js (Mischen, Leitplanken, Auslöser, Ende).
// Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const quelle = readFileSync(join(wurzel, "shell", "modi", "zustandslogik.js"), "utf8");

// Die Datei ist ein QML-Skript («.pragma library»); ohne diese Zeile ist es gewöhnliches JavaScript.
const L = vm.createContext({});
vm.runInContext(quelle.replace(/^\.pragma library\s*$/m, ""), L);

const fokus = {
  id: "fokus",
  name: "Fokus",
  mitteilungen: "nur-dringend",
  leiste: "reduziert",
  fenster: "fokus",
  heute: false,
  widgets: false,
  ausloeser: ["manuell"],
  ende: { art: "timer", minuten: 50 },
};
const sitzung = {
  id: "sitzung",
  name: "Sitzung",
  mitteilungen: "keine",
  leiste: "reduziert",
  fenster: "normal",
  heute: false,
  widgets: false,
  ausloeser: ["bildschirmfreigabe"],
  ende: { art: "ausloeser-endet" },
};
const morgen = { id: "morgen", name: "Morgen", ausloeser: ["uhrzeit:07:30", "manuell"], ende: { art: "manuell" } };
const wechsel = { id: "wechsel", name: "Wechsel", ausloeser: ["moduswechsel"], ende: { art: "ausloeser-endet" } };
const modus = {
  name: "Beispiel",
  zustaende: ["fokus", "sitzung", "wechsel"],
  anpassungen: { fokus: { mitteilungen: "gebuendelt-30" } },
};
const T0 = Date.UTC(2026, 8, 28, 8, 0, 0);
const MIN = 60000;
const plain = (x) => JSON.parse(JSON.stringify(x));

test("Leitplanken sind fest und unveränderbar", () => {
  assert.equal(L.LEITPLANKEN.inhalteBeiFreigabe, false);
  assert.equal(L.LEITPLANKEN.sperreZeigtInhalte, false);
  assert.equal(L.LEITPLANKEN.sperreAbschaltbar, false);
  assert.ok(Object.isFrozen(L.LEITPLANKEN));
  assert.throws(() => {
    "use strict";
    L.LEITPLANKEN.sperreAbschaltbar = true;
  });
  assert.equal(L.LEITPLANKEN.sperreAbschaltbar, false);
});

test("sperreMinuten begrenzt auf 1–15, Standard 5", () => {
  assert.equal(L.sperreMinuten(5), 5);
  assert.equal(L.sperreMinuten(0), 1);
  assert.equal(L.sperreMinuten(-3), 1);
  assert.equal(L.sperreMinuten(30), 15);
  assert.equal(L.sperreMinuten(7.4), 7);
  assert.equal(L.sperreMinuten("12"), 12);
  assert.equal(L.sperreMinuten(undefined), 5);
  assert.equal(L.sperreMinuten(null), 5);
  assert.equal(L.sperreMinuten("aus"), 5);
  assert.equal(L.sperreMinuten(Infinity), 5);
  assert.equal(L.sperreMinuten(true), 5);
});

test("wirksam = Vorlage + Anpassung des Modus + Leitplanken", () => {
  const w = plain(L.wirksam(fokus, modus, { freigabe: false }));
  assert.equal(w.mitteilungen, "gebuendelt-30");
  assert.equal(w.leiste, "reduziert");
  assert.deepEqual(w.ende, { art: "timer", minuten: 50 });
  assert.deepEqual(w.angepasst, ["mitteilungen"]);
  assert.equal(w.inhalteVerbergen, false);
  assert.deepEqual(w.leitplanken, { inhalteBeiFreigabe: false, sperreZeigtInhalte: false, sperreAbschaltbar: false });
  // Vorlage bleibt unverändert
  assert.equal(fokus.mitteilungen, "nur-dringend");
});

test("ohne Modus gilt die Vorlage", () => {
  const w = plain(L.wirksam(fokus, null, {}));
  assert.equal(w.mitteilungen, "nur-dringend");
  assert.deepEqual(w.angepasst, []);
});

test("Leitplanken gewinnen immer, auch gegen Vorlage und Anpassung", () => {
  const boese = Object.assign({}, fokus, { sperreAbschaltbar: true, inhalteBeiFreigabe: true, sperreNachMinuten: 0 });
  const boeserModus = {
    anpassungen: { fokus: { sperreZeigtInhalte: true, inhalteVerbergen: false, leitplanken: { sperreAbschaltbar: true } } },
  };
  const w = plain(L.wirksam(boese, boeserModus, { freigabe: true }));
  assert.equal(w.inhalteVerbergen, true);
  assert.equal(w.sperreAbschaltbar, undefined);
  assert.equal(w.inhalteBeiFreigabe, undefined);
  assert.equal(w.sperreNachMinuten, undefined);
  assert.equal(w.sperreZeigtInhalte, undefined);
  assert.deepEqual(w.leitplanken, { inhalteBeiFreigabe: false, sperreZeigtInhalte: false, sperreAbschaltbar: false });
});

test("ungültige Werte fallen auf die Vorlage zurück", () => {
  const m = { anpassungen: { fokus: { mitteilungen: "gebuendelt-0", leiste: "gross", heute: "ja", ende: { art: "timer", minuten: 0 } } } };
  const w = plain(L.wirksam(fokus, m, {}));
  assert.equal(w.mitteilungen, "nur-dringend");
  assert.equal(w.leiste, "reduziert");
  assert.equal(w.heute, false);
  assert.deepEqual(w.ende, { art: "timer", minuten: 50 });
  assert.deepEqual(w.angepasst, []);
});

test("Mitteilungswerte", () => {
  assert.ok(L.gueltigeMitteilungen("alle"));
  assert.ok(L.gueltigeMitteilungen("gebuendelt-60"));
  assert.ok(L.gueltigeMitteilungen("gebuendelt-1440"));
  assert.ok(!L.gueltigeMitteilungen("gebuendelt-1441"));
  assert.ok(!L.gueltigeMitteilungen("gebuendelt-05"));
  assert.ok(!L.gueltigeMitteilungen("gebuendelt-"));
  assert.ok(!L.gueltigeMitteilungen("laut"));
  assert.equal(L.gebuendeltMinuten("gebuendelt-30"), 30);
  assert.equal(L.gebuendeltMinuten("alle"), -1);
});

test("Auslöser", () => {
  assert.ok(L.gueltigerAusloeser("uhrzeit:07:30"));
  assert.ok(L.gueltigerAusloeser("kalender"));
  assert.ok(!L.gueltigerAusloeser("uhrzeit:24:00"));
  assert.ok(!L.gueltigerAusloeser("uhrzeit"));
  assert.ok(!L.gueltigerAusloeser("immer"));
  assert.ok(L.hatAusloeser(morgen, "uhrzeit"));
  assert.ok(L.hatAusloeser(morgen, "uhrzeit:07:30"));
  assert.ok(!L.hatAusloeser(morgen, "uhrzeit:07:31"));
  // ohne Auslöser: von Hand
  assert.ok(L.hatAusloeser({ id: "x", name: "X" }, "manuell"));
  assert.equal(L.ausloeserArt("uhrzeit:07:30"), "uhrzeit");
  assert.equal(L.ausloeserArt("kalender"), "manuell");
});

test("Angebot des Modus", () => {
  const liste = [fokus, sitzung, morgen, wechsel];
  assert.deepEqual(plain(L.angeboten(liste, modus).map((z) => z.id)), ["fokus", "sitzung", "wechsel"]);
  assert.deepEqual(plain(L.angeboten(liste, null).map((z) => z.id)), ["fokus", "sitzung", "morgen", "wechsel"]);
  assert.equal(L.angeboten(liste, { name: "ohne Liste" }).length, 4);
  assert.deepEqual(plain(L.startbar(liste, null).map((z) => z.id)), ["fokus", "morgen"]);
  assert.equal(L.waehleFuer(liste, modus, "bildschirmfreigabe", "sitzung").id, "sitzung");
  assert.equal(L.waehleFuer(liste, { zustaende: ["fokus"] }, "bildschirmfreigabe", "sitzung"), null);
  assert.equal(L.waehleFuer(liste, null, "moduswechsel", "").id, "wechsel");
});

test("Timer: Start, Restzeit, Ablauf", () => {
  const e = L.starten(null, L.wirksam(fokus, modus, {}), "manuell", T0);
  assert.equal(e.id, "fokus");
  assert.equal(e.endeArt, "timer");
  assert.equal(e.ausloeser, "manuell");
  assert.equal(new Date(e.ende).getTime(), T0 + 50 * MIN);
  assert.equal(L.restMinuten(e, T0), 50);
  assert.equal(L.restMinuten(e, T0 + 30 * 1000), 50);
  assert.equal(L.restMinuten(e, T0 + MIN), 49);
  assert.equal(L.naechsteAenderung(e, T0 + 20 * 1000), 40 * 1000);
  assert.equal(L.pruefen(e, T0 + 49 * MIN), e);
  assert.equal(L.pruefen(e, T0 + 50 * MIN), null);
  assert.equal(L.restMinuten(null, T0), -1);
});

test("Sitzung bei Freigabe merkt sich den laufenden Zustand und gibt ihn zurück", () => {
  const f = L.starten(null, fokus, "manuell", T0);
  const s = L.starten(f, sitzung, "bildschirmfreigabe", T0 + 10 * MIN);
  assert.equal(s.id, "sitzung");
  assert.equal(s.endeArt, "ausloeser-endet");
  assert.equal(s.vorher.id, "fokus");
  // Timer läuft während der Sitzung weiter
  const zurueck = L.ausloeserEndet(s, "bildschirmfreigabe", T0 + 20 * MIN);
  assert.equal(zurueck.id, "fokus");
  assert.equal(zurueck.ende, f.ende);
  assert.equal(zurueck.vorher, null);
  assert.equal(L.restMinuten(zurueck, T0 + 20 * MIN), 30);
});

test("abgelaufener Timer kommt nach der Sitzung nicht zurück", () => {
  const f = L.starten(null, fokus, "manuell", T0);
  const s = L.starten(f, sitzung, "bildschirmfreigabe", T0 + 10 * MIN);
  assert.equal(L.ausloeserEndet(s, "bildschirmfreigabe", T0 + 60 * MIN), null);
});

test("von Hand beendete Sitzung gibt den Zustand ebenfalls zurück", () => {
  const f = L.starten(null, fokus, "manuell", T0);
  const s = L.starten(f, sitzung, "bildschirmfreigabe", T0 + MIN);
  assert.equal(L.beenden(s, T0 + 2 * MIN).id, "fokus");
});

test("manuell gestarteter Zustand endet nicht mit der Freigabe", () => {
  const f = L.starten(null, fokus, "manuell", T0);
  assert.equal(L.ausloeserEndet(f, "bildschirmfreigabe", T0 + MIN), f);
});

test("Sitzung mit Timer endet nicht mit der Freigabe", () => {
  const s = L.starten(null, Object.assign({}, sitzung, { ende: { art: "timer", minuten: 90 } }), "bildschirmfreigabe", T0);
  assert.equal(L.ausloeserEndet(s, "bildschirmfreigabe", T0 + MIN).id, "sitzung");
});

test("Zustand mit Ende «manuell» kommt nach der Sitzung zurück, «ausloeser-endet» nicht", () => {
  const m = L.starten(null, morgen, "manuell", T0);
  const s = L.starten(m, sitzung, "bildschirmfreigabe", T0 + MIN);
  assert.equal(L.beenden(s, T0 + 5 * MIN).id, "morgen");
  const w = L.starten(null, wechsel, "moduswechsel", T0);
  const s2 = L.starten(w, sitzung, "bildschirmfreigabe", T0 + MIN);
  assert.equal(s2.vorher, null);
});

test("Moduswechsel-Zustand endet beim Verlassen des Modus", () => {
  const w = L.starten(null, wechsel, "moduswechsel", T0);
  assert.equal(L.ausloeserEndet(w, "moduswechsel", T0 + MIN), null);
});

test("automatische Auslöser überschreiben nichts von Hand Gestartetes", () => {
  const f = L.starten(null, fokus, "manuell", T0);
  const s = L.starten(null, sitzung, "bildschirmfreigabe", T0);
  const u = L.starten(null, morgen, "uhrzeit:07:30", T0);
  assert.ok(L.darfAutomatisch(null, "uhrzeit:07:30"));
  assert.ok(!L.darfAutomatisch(f, "uhrzeit:07:30"));
  assert.ok(!L.darfAutomatisch(s, "moduswechsel"));
  assert.ok(L.darfAutomatisch(u, "moduswechsel"));
  assert.ok(L.darfAutomatisch(f, "bildschirmfreigabe"));
});

test("Wiederherstellen nach Neustart der Oberfläche", () => {
  const f = L.starten(null, fokus, "manuell", T0);
  const s = L.starten(f, sitzung, "bildschirmfreigabe", T0 + MIN);
  const gespeichert = plain(s);
  const ids = ["fokus", "sitzung"];
  // Freigabe läuft noch: Sitzung bleibt
  assert.equal(L.wiederherstellen(gespeichert, ids, T0 + 2 * MIN, true).id, "sitzung");
  // Freigabe vorbei: Fokus kommt zurück
  assert.equal(L.wiederherstellen(gespeichert, ids, T0 + 2 * MIN, false).id, "fokus");
  // Zustand gelöscht
  assert.equal(L.wiederherstellen(gespeichert, ["fokus"], T0 + 2 * MIN, true), null);
  // Timer abgelaufen
  assert.equal(L.wiederherstellen(plain(f), ids, T0 + 51 * MIN, false), null);
  // Unsinn
  assert.equal(L.wiederherstellen({ id: "../x", endeArt: "manuell" }, ids, T0, false), null);
  assert.equal(L.wiederherstellen("fokus", ids, T0, false), null);
  assert.equal(L.wiederherstellen({ id: "fokus", endeArt: "timer", ende: "gestern" }, ids, T0, false), null);
});

test("Listen aus QML (Sequenzen statt Arrays) werden erkannt", () => {
  // Nachbau: array-ähnliches Objekt, für das Array.isArray falsch ist, JSON aber ein Array liefert
  const sequenz = (werte) => {
    const o = { length: werte.length, toJSON: () => werte.slice() };
    werte.forEach((w, i) => (o[i] = w));
    return o;
  };
  const sitzungQml = Object.assign({}, sitzung, { ausloeser: sequenz(["bildschirmfreigabe"]) });
  assert.equal(L.beschreibung(sitzungQml, {}, true), "Startet bei Bildschirmfreigabe · wie Vorlage");
  assert.ok(L.hatAusloeser(sitzungQml, "bildschirmfreigabe"));
  const modusQml = { zustaende: sequenz(["sitzung"]) };
  assert.deepEqual(plain(L.angeboten([fokus, sitzung], modusQml).map((z) => z.id)), ["sitzung"]);
});

test("slug", () => {
  assert.equal(L.slug("Arbeit", []), "arbeit");
  assert.equal(L.slug("Büro · Größe 2", []), "buero-groesse-2");
  assert.equal(L.slug("Café", []), "cafe");
  assert.equal(L.slug("Arbeit", ["arbeit", "arbeit-2"]), "arbeit-3");
  assert.equal(L.slug("  ", [], "modus"), "modus");
  assert.equal(L.slug("!!!", ["modus"], "modus"), "modus-2");
  assert.ok(L.gueltigeId(L.slug("x".repeat(100), [])));
  assert.ok(L.slug("x".repeat(100), []).length <= 40);
  assert.ok(!L.gueltigeId("../fokus"));
  assert.ok(!L.gueltigeId("Fokus"));
  assert.ok(!L.gueltigeId("a--b"));
});

test("Texte für die Tabelle «Zustände in diesem Modus»", () => {
  assert.equal(L.beschreibung(fokus, { mitteilungen: "gebuendelt-30" }, true), "Mitteilungen gebündelt alle 30 Min. · sonst wie Vorlage");
  assert.equal(L.beschreibung(sitzung, {}, true), "Startet bei Bildschirmfreigabe · wie Vorlage");
  assert.equal(L.beschreibung(fokus, {}, true), "Von Hand · 50 Min. · wie Vorlage");
  assert.equal(L.beschreibung(fokus, {}, false), "In diesem Modus nicht angeboten");
  // Anpassung gleich der Vorlage zählt nicht als angepasst
  assert.equal(L.beschreibung(fokus, { leiste: "reduziert" }, true), "Von Hand · 50 Min. · wie Vorlage");
  // «fenster» und «widgets» wirken in 0.1 noch nicht: der Text sagt das
  assert.equal(L.beschreibung(fokus, { fenster: "normal" }, true), "Fenster normal (später) · sonst wie Vorlage");
  assert.equal(L.beschreibung(sitzung, { widgets: true }, true), "Widgets an (später) · sonst wie Vorlage");
  assert.equal(L.mitteilungenText("keine"), "Mitteilungen pausiert");
  assert.equal(L.endeText({ art: "ausloeser-endet" }), "endet mit dem Auslöser");
});
