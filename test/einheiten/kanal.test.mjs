// Einheitentests für shell/dienste/kanal.js (Update-Kanal in der Oberfläche: stand.json, letzte.json und Zeitpunkt
// lesen, Texte für Einstellungen › System › Updates, Mitteilungen je einmal, Argumentlisten für den Helfer) und den
// Abgleich mit Kanal.qml, dem Helfer, der polkit-Richtlinie und zenos-kanal. Läuft ohne Abhängigkeiten:
// node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

// Feste Zeitzone für «heute, 14:03» (wie auf dem Gerät)
process.env.TZ = "Europe/Zurich";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const lesen = (...teile) => readFileSync(join(wurzel, ...teile), "utf8");

// QML-Skript («.pragma library»): ohne diese Zeile gewöhnliches JavaScript
const L = vm.createContext({});
vm.runInContext(lesen("shell", "dienste", "kanal.js").replace(/^\.pragma library\s*$/m, ""), L);

const roh = (x) => JSON.parse(JSON.stringify(x));
const JETZT = Date.parse("2026-10-05T12:00:00Z"); // 14:00 in Zürich
const H = 3600 * 1000;
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, "Z");

const WURZEL_FP = "SHA256:9xQZHFzUT4CF87GQ2VrCo6oGEC1DimrsHOtEmnB5pDk";
const RELEASE_FP = "SHA256:6CAhnfU9qHJz36663u/A/HxmZkKxao0r2QxT3oy+DzI";
const C1 = "1".repeat(40);
const C2 = "2".repeat(40);
const OBJ = "ab".repeat(20);

// stand.json wie von zenos-kanal pruefen
function stand(teile = {}) {
  return JSON.stringify(Object.assign({
    version: 1,
    kanal: "vorschau",
    zustand: "aktuell",
    grund: "Keine neuere gültig signierte Version im Kanal vorschau.",
    geprueft: iso(JETZT - 2 * H),
    letzter_kontakt: iso(JETZT - 2 * H),
    holen_fehler: null,
    anker: { serie: 1, wurzel: WURZEL_FP, release: [RELEASE_FP], widerrufen: [] },
    anker_problem: null,
    installiert: { commit: C1, version: "v0.1.0-rc4" },
    hoechste: "v0.1.0-rc4",
    bereit: null,
    dev: null,
    gueltig: ["v0.1.0-rc4"],
    abgelehnt: [],
    hinweise: [],
    wunsch: null,
    installation: "0123456789abcdef",
  }, teile));
}

const BEREIT = { version: "v0.1.0-rc5", commit: C2, objekt: OBJ, erstmals: iso(JETZT - H), frei_ab: iso(JETZT - H), rueckfrage: [] };

function letzte(ergebnis, endeMs, grund = "") {
  return JSON.stringify({ version: 1, ergebnis, grund, beginn: iso(endeMs - 60000), ende: iso(endeMs), ziel: { commit: C2, zweig: null, tag: "v0.1.0-rc5", version: "v0.1.0-rc5" } });
}

function lage(standText, letzteText = null, zeitpunktText = null) {
  const s = L.standLesen(standText);
  const l = L.letzteLesen(letzteText);
  return { stand: s, letzte: l, zeitpunkt: L.zeitpunktLesen(zeitpunktText), veraltet: L.veraltet(s, l) };
}

// Mitteilungen auswerten wie Kanal.qml: gemerkt wird, was zurückkommt
function melden(l, gemeldet, jetzt = JETZT) {
  const e = L.meldungen(l, gemeldet ?? L.gemeldetLesen(""), jetzt);
  return { neu: roh(e.neu), gemeldet: e.gemeldet };
}

// --- Zeitpunkt -----------------------------------------------------------------

test("zeitpunktLesen: dieselben Fälle wie parse_schedule in zenos-kanal (kanal-zeitpunkt.json)", () => {
  const faelle = JSON.parse(lesen("test", "einheiten", "kanal-zeitpunkt.json"));
  assert.ok(faelle.gueltig.length >= 5 && faelle.ungueltig.length >= 5);
  for (const fall of faelle.gueltig) {
    const z = roh(L.zeitpunktLesen(fall.text));
    assert.equal(z.problem, "", fall.text);
    assert.equal(z.art, fall.art, fall.text);
    if (fall.art === "fenster")
      assert.deepEqual([z.von, z.bis], [fall.von, fall.bis], fall.text);
  }
  for (const text of faelle.ungueltig) {
    const z = roh(L.zeitpunktLesen(text));
    assert.equal(z.art, "sperre", text);
    assert.notEqual(z.problem, "", text);
    assert.deepEqual([z.von, z.bis], ["02:00", "05:00"], "das Formular zeigt den Standard");
  }
  // Ohne Datei: «sperre» ohne Problem
  for (const leer of [null, undefined, "", "  \n"])
    assert.deepEqual(roh(L.zeitpunktLesen(leer)), { art: "sperre", von: "02:00", bis: "05:00", problem: "" });
});

test("fensterProblem: mindestens 60 Minuten, über Mitternacht erlaubt", () => {
  assert.equal(L.fensterProblem("02:00", "03:00"), "");
  assert.equal(L.fensterProblem("23:30", "00:30"), "");
  assert.match(L.fensterProblem("23:30", "00:29"), /mindestens 60 Minuten/);
  assert.match(L.fensterProblem("2:00", "05:00"), /HH:MM/);
  assert.match(L.fensterProblem("02:00", null), /HH:MM/);
  assert.equal(L.minuten("23:59"), 1439);
  assert.equal(L.minuten("24:00"), -1);
});

// --- stand.json und letzte.json ------------------------------------------------

test("standLesen: vereinfacht und geprüft", () => {
  const s = roh(L.standLesen(stand({ bereit: BEREIT, zustand: "bereit" })));
  assert.equal(s.kanal, "vorschau");
  assert.equal(s.zustand, "bereit");
  assert.deepEqual(s.anker, { serie: 1, wurzel: WURZEL_FP, release: [RELEASE_FP], widerrufen: [] });
  assert.deepEqual(s.installiert, { commit: C1, version: "v0.1.0-rc4" });
  assert.equal(s.bereit.objekt, OBJ);
  assert.equal(s.bereit.freiAbMs, JETZT - H);
  assert.deepEqual(s.bereit.rueckfrage, []);
  assert.equal(s.geprueftMs, JETZT - 2 * H);
});

test("standLesen: fehlt, kaputt oder fremd ist null; Unbekanntes wird vorsichtig", () => {
  for (const text of [null, "", "{", "null", "[]", "42", JSON.stringify({ version: 2, zustand: "aktuell" })])
    assert.equal(L.standLesen(text), null, String(text));
  const s = L.standLesen(stand({ zustand: "installiere-alles", kanal: "main", hoechste: "1.0", anker: { serie: 1, wurzel: "SHA256:kurz" } }));
  assert.equal(s.zustand, "fehler");
  assert.equal(s.kanal, "");
  assert.equal(s.hoechste, "");
  assert.equal(s.anker, null, "ein Anker ohne gültigen Fingerabdruck gilt nicht");
  // bereit ohne gültiges Objekt zählt nicht (sonst könnte «Zustimmen» einem Unsinn gelten)
  const ohne = L.standLesen(stand({ zustand: "zustimmung", bereit: Object.assign({}, BEREIT, { objekt: "x" }) }));
  assert.equal(ohne.bereit, null);
  assert.equal(L.zustimmungObjekt(ohne), "");
});

test("text: reiner Text, ohne Steuer- und Richtungszeichen, gekürzt", () => {
  assert.equal(L.text("a\u202eb\u0007c\u200bd\n  e"), "a?b?c?d e");
  assert.equal(L.text("x".repeat(10), 5), "xxxx…");
  assert.equal(L.text(42), "");
  const s = L.standLesen(stand({ zustand: "blockiert", grund: "ALARM\u202e: v0.2.0" }));
  assert.equal(s.grund, "ALARM?: v0.2.0");
});

test("letzteLesen", () => {
  const l = roh(L.letzteLesen(letzte("installiert", JETZT - H, "v0.1.0-rc5 (222222222222) ist installiert und gesund.")));
  assert.equal(l.ergebnis, "installiert");
  assert.equal(l.endeMs, JETZT - H);
  assert.deepEqual(l.ziel, { commit: C2, tag: "v0.1.0-rc5", version: "v0.1.0-rc5", zweig: "" });
  assert.equal(L.letzteLesen(JSON.stringify({ version: 1, ergebnis: "unbekannt" })), null);
  assert.equal(L.letzteLesen("kaputt"), null);
});

test("veraltet: installiert nach der letzten Prüfung", () => {
  const s = L.standLesen(stand());
  assert.equal(L.veraltet(s, L.letzteLesen(letzte("installiert", JETZT - 3 * H))), false);
  assert.equal(L.veraltet(s, L.letzteLesen(letzte("installiert", JETZT - 2 * H + 1000))), false, "gleich danach geprüft");
  assert.equal(L.veraltet(s, L.letzteLesen(letzte("installiert", JETZT - H))), true);
  assert.equal(L.veraltet(null, L.letzteLesen(letzte("installiert", JETZT))), false);
});

// --- Anzeige -------------------------------------------------------------------

test("zeitText: heute, gestern, morgen, Datum (Ortszeit)", () => {
  assert.equal(L.zeitText(Date.parse("2026-10-05T12:03:00Z"), JETZT), "heute, 14:03");
  assert.equal(L.zeitText(Date.parse("2026-10-04T21:30:00Z"), JETZT), "gestern, 23:30");
  assert.equal(L.zeitText(Date.parse("2026-10-06T01:30:00Z"), JETZT), "morgen, 03:30");
  assert.equal(L.zeitText(Date.parse("2026-09-21T08:00:00Z"), JETZT), "21. Sept., 10:00");
  assert.equal(L.zeitText(Date.parse("2025-03-03T08:00:00Z"), JETZT), "3. März 2025");
  assert.equal(L.zeitText(NaN, JETZT), "–");
});

test("zeilen: Kanal, Versionen, Prüfung, Anker mit kurzen Fingerabdrücken", () => {
  const z = L.zeitpunktLesen(null);
  const s = L.standLesen(stand({ zustand: "bereit", bereit: Object.assign({}, BEREIT, { frei_ab: iso(JETZT + 14 * H) }) }));
  assert.deepEqual(roh(L.zeilen(s, z, JETZT)), [
    { titel: "Kanal", wert: "vorschau" },
    { titel: "Installiert", wert: "v0.1.0-rc4 · 111111111111" },
    { titel: "Bereit", wert: "v0.1.0-rc5 · 222222222222 · automatisch ab morgen, 04:00" },
    { titel: "Geprüft", wert: "heute, 12:00" },
    { titel: "Kontakt", wert: "heute, 12:00" },
    { titel: "Anker", wert: "Serie 1" },
    { titel: "Wurzel", wert: "SHA256:9xQZHFzU…" },
    { titel: "Release", wert: "SHA256:6CAhnfU9…" },
  ]);
  // Von Hand: keine Zeit für die Automatik; ohne Anker «fehlt»; Kontakt nie mit Fehler
  const ohne = L.standLesen(stand({ zustand: "anker_fehlt", anker: null, letzter_kontakt: null, holen_fehler: "Zeitlimit", installiert: { commit: C1, version: null } }));
  const zeilen = roh(L.zeilen(ohne, L.zeitpunktLesen("zeitpunkt=hand\n"), JETZT));
  assert.deepEqual(zeilen.find((x) => x.titel === "Anker"), { titel: "Anker", wert: "fehlt" });
  assert.deepEqual(zeilen.find((x) => x.titel === "Kontakt"), { titel: "Kontakt", wert: "nie · letzter Versuch gescheitert" });
  assert.deepEqual(zeilen.find((x) => x.titel === "Installiert"), { titel: "Installiert", wert: "111111111111 · ohne signierte Version" });
  assert.deepEqual(roh(L.zeilen(null, z, JETZT)), []);
});

test("Titel, Symbol und Erklärung je Zustand", () => {
  assert.equal(L.zustandTitel(null, false), "Noch nie geprüft");
  const faelle = {
    aktuell: ["Aktuell", "haken", "akzent"],
    bereit: ["Neue Version bereit", "info", "akzent"],
    zustimmung: ["Wartet auf deine Zustimmung", "schloss", "akzent"],
    anker_fehlt: ["Anker fehlt", "schloss-offen", "warnung"],
    blockiert: ["Blockiert", "warnung", "warnung"],
    kein_kontakt: ["Kein Kontakt", "wolke", "gedaempft"],
    fehler: ["Prüfung abgebrochen", "warnung", "warnung"],
  };
  for (const [zustand, [titel, symbol, ton]] of Object.entries(faelle)) {
    const s = L.standLesen(stand({ zustand, bereit: BEREIT }));
    assert.equal(L.zustandTitel(s, false), titel, zustand);
    assert.deepEqual(roh(L.zustandSymbol(s, false)), { symbol, ton }, zustand);
    assert.notEqual(L.grundText(s, false, null), "", zustand);
  }
  const s = L.standLesen(stand());
  assert.equal(L.zustandTitel(s, true), "Seit der letzten Prüfung installiert");
  assert.match(L.grundText(s, true, L.letzteLesen(letzte("installiert", JETZT, "v0.1.0-rc5 ist installiert und gesund."))), /gesund\. «Jetzt prüfen»/);
  const dev = L.standLesen(stand({ kanal: "dev", zustand: "dev", dev: { commit: C2, neu: true, vorfahre: true, commits: 3, signiert: false, braucht_ja: true } }));
  assert.equal(L.zustandTitel(dev, false), "Neuer Stand auf dev");
  assert.match(L.grundText(dev, false, null), /nur im Terminal/);
});

test("Jetzt installieren und Zustimmen: nur, wenn es etwas gibt", () => {
  assert.equal(L.kannInstallieren(L.standLesen(stand({ zustand: "bereit", bereit: BEREIT }))), true);
  assert.equal(L.kannInstallieren(L.standLesen(stand({ zustand: "zustimmung", bereit: BEREIT }))), false);
  assert.equal(L.kannInstallieren(L.standLesen(stand())), false);
  assert.equal(L.kannInstallieren(null), false);
  const devSigniert = { commit: C2, neu: true, vorfahre: true, commits: 2, signiert: true, braucht_ja: false };
  assert.equal(L.kannInstallieren(L.standLesen(stand({ kanal: "dev", zustand: "dev", dev: devSigniert }))), true);
  assert.equal(L.kannInstallieren(L.standLesen(stand({ kanal: "dev", zustand: "dev", dev: Object.assign({}, devSigniert, { braucht_ja: true }) }))), false);

  const z = L.standLesen(stand({ zustand: "zustimmung", bereit: Object.assign({}, BEREIT, { rueckfrage: ["scripts/module/35-netzwerk.sh", "a", "b", "c"] }) }));
  assert.equal(L.zustimmungObjekt(z), OBJ);
  assert.equal(L.zustimmungText(z), "Ändert scripts/module/35-netzwerk.sh, a, b und 1 weitere. Zustimmen verlangt dein Passwort und gilt nur für v0.1.0-rc5 (Objekt abababababab).");
  const ohneVergleich = L.standLesen(stand({ zustand: "zustimmung", bereit: Object.assign({}, BEREIT, { rueckfrage: null }) }));
  assert.match(L.zustimmungText(ohneVergleich), /^Der Vergleich mit dem installierten Stand ist nicht möglich\./);
  // dev: Zustimmen bleibt beim Terminal
  assert.equal(L.zustimmungObjekt(L.standLesen(stand({ kanal: "dev", zustand: "zustimmung", bereit: BEREIT }))), "");
  assert.equal(L.zustimmungObjekt(L.standLesen(stand({ zustand: "bereit", bereit: BEREIT }))), "");
});

test("zeitpunktText", () => {
  assert.match(L.zeitpunktText(L.zeitpunktLesen(null)), /gesperrt ist oder niemand angemeldet/);
  assert.equal(L.zeitpunktText(L.zeitpunktLesen("zeitpunkt=fenster\nvon=22:00\nbis=06:00\n")), "Geprüfte Updates kommen nur zwischen 22:00 und 06:00 Uhr.");
  assert.match(L.zeitpunktText({ art: "hand" }), /Nie automatisch/);
  assert.match(L.zeitpunktText({ art: "jederzeit" }), /auch während du arbeitest/);
});

// --- Mitteilungen --------------------------------------------------------------

test("meldungen: jede nur einmal je Zustand", () => {
  const l = lage(stand({ zustand: "blockiert", grund: "ALARM: v0.1.0-rc4 zeigt jetzt gültig signiert auf einen anderen Commit." }));
  const erst = melden(l);
  assert.deepEqual(erst.neu.map((m) => [m.schluessel, m.dringlichkeit]), [["blockiert", "critical"]]);
  assert.match(erst.neu[0].text, /^ALARM/);
  assert.deepEqual(melden(l, erst.gemeldet).neu, [], "derselbe Zustand meldet sich nicht noch einmal");
  // Kein Kontakt oder ein Fehler der Prüfung dazwischen heisst nicht «vorbei»
  const zwischen = melden(lage(stand({ zustand: "kein_kontakt", grund: "Kein Kontakt zu origin" })), erst.gemeldet);
  assert.deepEqual(zwischen.neu, []);
  assert.deepEqual(melden(l, zwischen.gemeldet).neu, []);
  // Erst nach einem sicheren anderen Zustand kommt er wieder
  const vorbei = melden(lage(stand()), erst.gemeldet);
  assert.deepEqual(vorbei.neu, []);
  assert.equal(melden(l, vorbei.gemeldet).neu.length, 1);
  // Ein anderer Grund ist ein neuer Zustand
  assert.equal(melden(lage(stand({ zustand: "blockiert", grund: "hoechste fehlt" })), erst.gemeldet).neu.length, 1);
});

test("meldungen: Installationen (still, zurück, kaputt) und Frische", () => {
  const s = stand({ geprueft: iso(JETZT) });
  const inst = melden(lage(s, letzte("installiert", JETZT - H)));
  assert.deepEqual(inst.neu, [{ schluessel: "installiert", titel: "zenOS aktualisiert", text: "v0.1.0-rc5 ist installiert.", dringlichkeit: "low" }]);
  assert.deepEqual(melden(lage(s, letzte("installiert", JETZT - H)), inst.gemeldet).neu, []);

  const zurueck = melden(lage(s, letzte("zurueck", JETZT - H, "v0.1.0-rc5 (222222222222): install.sh endete mit Exit 1. Zurück auf v0.1.0-rc4 (111111111111), gesund.")));
  assert.deepEqual(zurueck.neu.map((m) => [m.schluessel, m.titel, m.dringlichkeit]), [["zurueck", "Update gescheitert", "normal"]]);
  assert.match(zurueck.neu[0].text, /Zurück auf v0\.1\.0-rc4/);

  const kaputt = melden(lage(s, letzte("kaputt", JETZT - 30 * 24 * H, "Auch der Rückweg scheiterte. ANLEITUNG.md, Abschnitt F")));
  assert.deepEqual(kaputt.neu.map((m) => [m.schluessel, m.dringlichkeit]), [["kaputt", "critical"]], "kaputt meldet sich auch alt");

  // Älter als 24 h (etwa beim ersten Start mit dieser Oberfläche): nur merken
  const alt = melden(lage(s, letzte("installiert", JETZT - 25 * H)));
  assert.deepEqual(alt.neu, []);
  assert.match(alt.gemeldet.installation, /^installiert@/);
  // Wartet, abgelehnt, nichts: keine Mitteilung
  assert.deepEqual(melden(lage(s, letzte("wartet", JETZT - H))).neu, []);
});

test("meldungen: Anker fehlt, Zustimmung, Update bereit nur «von Hand»", () => {
  const anker = melden(lage(stand({ zustand: "anker_fehlt", anker: null, anker_problem: "ohne Schlüssel und ohne Serie" })));
  assert.deepEqual(anker.neu.map((m) => [m.schluessel, m.dringlichkeit]), [["anker", "normal"]]);
  assert.match(anker.neu[0].text, /sudo zen kanal anker \/opt\/zenos\/system\/vertrauen/);
  assert.deepEqual(melden(lage(stand({ zustand: "anker_fehlt", anker: null })), anker.gemeldet).neu, []);

  const zustimmung = lage(stand({ zustand: "zustimmung", bereit: BEREIT }));
  const z1 = melden(zustimmung);
  assert.deepEqual(z1.neu.map((m) => m.titel), ["Update wartet auf deine Zustimmung"]);
  assert.deepEqual(melden(zustimmung, z1.gemeldet).neu, []);
  // Ein neues Objekt (anderer Stand) meldet sich neu
  const anderes = lage(stand({ zustand: "zustimmung", bereit: Object.assign({}, BEREIT, { objekt: "cd".repeat(20) }) }));
  assert.equal(melden(anderes, z1.gemeldet).neu.length, 1);

  const bereit = stand({ zustand: "bereit", bereit: BEREIT });
  assert.deepEqual(melden(lage(bereit)).neu, [], "Bei Sperre: die Automatik installiert, keine Mitteilung");
  assert.deepEqual(melden(lage(bereit, null, "zeitpunkt=jederzeit\n")).neu, []);
  const hand = melden(lage(bereit, null, "zeitpunkt=hand\n"));
  assert.deepEqual(hand.neu, [{ schluessel: "bereit", titel: "Update bereit", text: "v0.1.0-rc5 ist geprüft und bereit. Installieren: Einstellungen › System oder zen update.", dringlichkeit: "normal" }]);
  assert.deepEqual(melden(lage(bereit, null, "zeitpunkt=hand\n"), hand.gemeldet).neu, []);
});

test("meldungen: abgelehnt nur für neue Tags über dem gültigen Stand", () => {
  const abgelehnt = [
    { tag: "v0.1.0-rc1", grund: "unsigniert" },
    { tag: "v0.1.0-rc3", grund: "unsigniert" },
    { tag: "v0.2.0", grund: "fremder Schlüssel" },
    { tag: "v0.1.0-rc2", grund: "auf origin verschoben, das neue Objekt ist ungültig (unsigniert)" },
  ];
  const e = melden(lage(stand({ abgelehnt })));
  assert.deepEqual(e.neu.map((m) => m.schluessel), ["abgelehnt"]);
  assert.equal(e.neu[0].text, "v0.2.0: fremder Schlüssel · v0.1.0-rc2: auf origin verschoben, das neue Objekt ist ungültig (unsigniert). zenOS installiert nur, was gültig signiert ist.");
  assert.deepEqual(roh(e.gemeldet.abgelehnt), ["v0.2.0", "v0.1.0-rc2"], "alte unsignierte rc1 und rc3 melden sich nicht");
  assert.deepEqual(melden(lage(stand({ abgelehnt })), e.gemeldet).neu, []);
  // Auf stabil zählt ein rc nicht, auf dev und ohne Anker nichts
  assert.deepEqual(melden(lage(stand({ kanal: "stabil", abgelehnt: [{ tag: "v0.2.0-rc1", grund: "unsigniert" }] }))).neu, []);
  assert.deepEqual(melden(lage(stand({ kanal: "dev", zustand: "dev", abgelehnt }))).neu, []);
  assert.deepEqual(melden(lage(stand({ zustand: "anker_fehlt", anker: null, abgelehnt }))).neu.map((m) => m.schluessel), ["anker"]);
});

test("meldungen: 14 Tage ohne Kontakt, einmal je Kontaktzeit", () => {
  const tag = 24 * H;
  assert.deepEqual(melden(lage(stand({ letzter_kontakt: iso(JETZT - 13 * tag) }))).neu, []);
  const e = melden(lage(stand({ letzter_kontakt: iso(JETZT - 15 * tag) })));
  assert.deepEqual(e.neu.map((m) => [m.schluessel, m.titel]), [["kontakt", "Seit 15 Tagen keine Updates geprüft"]]);
  assert.match(e.neu[0].text, /Letzter Kontakt mit origin: 20\. Sept\., 14:00/);
  assert.deepEqual(melden(lage(stand({ letzter_kontakt: iso(JETZT - 15 * tag) })), e.gemeldet, JETZT + 3 * tag).neu, []);
  // Nie Kontakt: keine Zeit, ab der es zählt
  assert.deepEqual(melden(lage(stand({ letzter_kontakt: null }))).neu, []);
});

test("meldungen: veralteter Stand meldet nichts aus der Prüfung", () => {
  const l = lage(stand({ zustand: "zustimmung", bereit: BEREIT }), letzte("installiert", JETZT - H));
  assert.equal(l.veraltet, true);
  assert.deepEqual(melden(l).neu.map((m) => m.schluessel), ["installiert"]);
});

test("gemeldetLesen und gemeldetText: geprüft, rund", () => {
  const g = L.gemeldetLesen(JSON.stringify({ installation: "installiert@x", abgelehnt: ["v0.2.0", "../böse", 7], blockiert: 5 }));
  assert.equal(g.installation, "installiert@x");
  assert.equal(g.blockiert, "");
  assert.deepEqual(roh(g.abgelehnt), ["v0.2.0"]);
  assert.deepEqual(roh(L.gemeldetLesen(L.gemeldetText(g))), roh(g));
  assert.deepEqual(roh(L.gemeldetLesen("kaputt")).abgelehnt, []);
});

test("mitteilungBefehl: Argumentliste für notify-send", () => {
  assert.deepEqual(roh(L.mitteilungBefehl({ titel: "Updates blockiert", text: "ALARM\u202e", dringlichkeit: "critical" })),
    ["notify-send", "--app-name=zenOS", "--icon=zenos", "--urgency=critical", "--category=system", "--", "Updates blockiert", "ALARM?"]);
  assert.equal(L.mitteilungBefehl({ titel: "-x", text: "", dringlichkeit: "laut" })[3], "--urgency=normal");
});

// --- Bedienung -----------------------------------------------------------------

test("befehl: nur feste Wörter, Objekt und Uhrzeiten geprüft", () => {
  const h = "/opt/zenos/scripts/bin/zenos-kanal-bedienen";
  assert.deepEqual(roh(L.befehl(h, "pruefen")), ["pkexec", h, "pruefen"]);
  assert.deepEqual(roh(L.befehl(h, "installieren")), ["pkexec", h, "installieren"]);
  assert.deepEqual(roh(L.befehl(h, "zustimmen", OBJ)), ["pkexec", h, "zustimmen", OBJ]);
  assert.deepEqual(roh(L.befehl(h, "zeitpunkt", "hand")), ["pkexec", h, "zeitpunkt", "hand"]);
  assert.deepEqual(roh(L.befehl(h, "zeitpunkt", "fenster", "22:00", "06:00")), ["pkexec", h, "zeitpunkt", "fenster", "22:00", "06:00"]);
  for (const falsch of [["zustimmen", "x"], ["zustimmen", OBJ.toUpperCase()], ["zeitpunkt", "nachts"], ["zeitpunkt", "fenster", "02:00", "02:30"],
    ["zeitpunkt", "fenster", "2:00", "05:00"], ["rollback", "v0.1.0"], ["update"]])
    assert.equal(L.befehl(h, ...falsch), null, falsch.join(" "));
  assert.equal(L.befehl("zenos-kanal-bedienen", "pruefen"), null, "nur ein fester Pfad");
});

test("rueckmeldung: Hinweise nach dem Helfer", () => {
  assert.equal(L.rueckmeldung("installieren", 126, {}), null, "abgebrochen: still");
  assert.equal(L.rueckmeldung("installieren", 0, { installiert: true }), null, "die Mitteilung kommt ohnehin");
  assert.deepEqual(roh(L.rueckmeldung("installieren", 0, {})), { text: "zenOS ist schon aktuell", art: "" });
  assert.deepEqual(roh(L.rueckmeldung("installieren", 10, { zustand: "zustimmung" })), { text: "Das Update braucht deine Zustimmung", art: "warnung" });
  assert.match(L.rueckmeldung("zustimmen", 10, {}).text, /noch einmal ansehen/);
  assert.match(L.rueckmeldung("zustimmen", 3, {}).text, /nur für gültig signierte/);
  assert.equal(L.rueckmeldung("installieren", 5, {}), null);
  assert.match(L.rueckmeldung("pruefen", 75, {}).text, /läuft schon/);
  assert.match(L.rueckmeldung("pruefen", 127, { fehler: "No authentication agent found" }).text, /polkit-Agent/);
  assert.match(L.rueckmeldung("pruefen", 127, {}).text, /aktiven Sitzung/);
  assert.deepEqual(roh(L.rueckmeldung("pruefen", 0, {})), { text: "Updates geprüft", art: "" });
  assert.match(L.rueckmeldung("pruefen", 0, { fehler: "zenos-kanal-bedienen: Holen ist gescheitert (…)" }).text, /Kein Kontakt/);
  assert.equal(L.rueckmeldung("zeitpunkt", 0, {}), null);
  assert.match(L.rueckmeldung("zeitpunkt", 2, { fehler: "zenos-kanal zeitpunkt: Das Zeitfenster muss mindestens 60 Minuten lang sein." }).text, /^Zeitpunkt liess sich nicht setzen: Das Zeitfenster/);
});

// --- Abgleich mit Kanal.qml, Helfer, polkit und zenos-kanal ------------------------------

test("Abgleich: Pfade und Wörter stimmen überall", () => {
  const qml = lesen("shell", "dienste", "Kanal.qml");
  const policy = lesen("system", "polkit", "org.zenos.kanal.policy");
  const helfer = lesen("scripts", "bin", "zenos-kanal-bedienen");
  const kanal = lesen("scripts", "bin", "zenos-kanal");
  const pfad = /readonly property string helfer: "([^"]+)"/.exec(qml)[1];
  assert.equal(pfad, "/opt/zenos/scripts/bin/zenos-kanal-bedienen");
  assert.equal([...policy.matchAll(/exec\.path">([^<]+)</g)].filter((m) => m[1] === pfad).length, 4);
  assert.deepEqual([...policy.matchAll(/exec\.argv1">([^<]+)</g)].map((m) => m[1]).sort(), ["installieren", "pruefen", "zeitpunkt", "zustimmen"]);
  for (const wort of ["pruefen", "installieren", "zustimmen", "zeitpunkt"])
    assert.match(helfer, new RegExp(`^  (?:[a-z]+ \\| )*${wort}\\b`, "m"), `Helfer kennt ${wort}`);
  assert.match(qml, /"\/var\/lib\/zenos\/kanal\/stand\.json"/);
  assert.match(qml, /"\/etc\/xdg\/zenos\/kanal-zeitpunkt"/);
  assert.match(kanal, /^SCHEDULE_FILE = "\/etc\/xdg\/zenos\/kanal-zeitpunkt"$/m);
  assert.match(kanal, /^SCHEDULES = \("sperre", "fenster", "jederzeit", "hand"\)$/m);
  assert.deepEqual(roh(L.ZEITPUNKTE), ["sperre", "fenster", "jederzeit", "hand"]);
  assert.match(kanal, /^MIN_WINDOW_MINUTES = 60$/m);
  assert.equal(L.FENSTER_MIN_MINUTEN, 60);
  assert.match(kanal, /^SCHEDULE_WINDOW = \("02:00", "05:00"\)$/m);
  assert.deepEqual(roh(L.FENSTER_STANDARD), { von: "02:00", bis: "05:00" });
  // Die Zustände der Prüfung und die Ergebnisse der Installation, die zenos-kanal kennt, kennt auch die Oberfläche
  const schluessel = (name) => {
    const block = kanal.slice(kanal.indexOf(`${name} = {`), kanal.indexOf("}", kanal.indexOf(`${name} = {`)));
    return [...block.matchAll(/^    "([a-z_]+)":/gm)].map((m) => m[1]);
  };
  assert.deepEqual(schluessel("STATE_TEXT").sort(), [...L.ZUSTAENDE].sort());
  for (const e of schluessel("RESULT_TEXT"))
    assert.ok(L.ERGEBNISSE.includes(e), `Ergebnis ${e}`);
  // Die Einstellungen ersetzen den alten Satz
  assert.doesNotMatch(lesen("shell", "einstellungen", "SeiteSystem.qml"), /aktualisiert sich nicht von selbst/);
});
