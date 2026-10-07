// Einheitentests für shell/dienste/basis.js (Basis-Updates in der Oberfläche: stand.json, letzte.json, automatik.json
// und /run/reboot-required lesen, Texte für Einstellungen › System › Updates, Hinweis «Neustart nötig» mit Leitplanke,
// Mitteilungen je einmal, Argumentlisten für den Helfer) und den Abgleich mit Basis.qml, der Leiste, dem Helfer, der
// polkit-Richtlinie, zenos-basis und dem Rundgang in pruefen.sh. Läuft ohne Abhängigkeiten: node --test test/einheiten/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

// Feste Zeitzone für «heute, 14:03» (wie auf dem Gerät); die Zeit kommt immer als Argument, nie von der Uhr
process.env.TZ = "Europe/Zurich";

const wurzel = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const lesen = (...teile) => readFileSync(join(wurzel, ...teile), "utf8");

// QML-Skripte («.pragma library», «.import … as Kanal»): ohne diese Zeilen gewöhnliches JavaScript. Den Import ersetzt
// ein eigener Kontext mit kanal.js unter demselben Namen.
const K = vm.createContext({});
vm.runInContext(lesen("shell", "dienste", "kanal.js").replace(/^\.pragma library\s*$/m, ""), K);
const quelle = lesen("shell", "dienste", "basis.js");
const importe = [...quelle.matchAll(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/gm)].map((m) => [m[1], m[2]]);
const B = vm.createContext({ Kanal: K });
vm.runInContext(quelle.replace(/^\.pragma library\s*$/m, "").replace(/^\.import .*$/gm, ""), B);

const roh = (x) => JSON.parse(JSON.stringify(x));
const JETZT = Date.parse("2026-10-05T12:00:00Z"); // 14:00 in Zürich
const H = 3600 * 1000;
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, "Z");
const L1 = "1".repeat(40);
const L2 = "2".repeat(40);

const paket = (name, alt, neu, teile = {}) => Object.assign({ name, arch: "arm64", alt, neu, tasche: "resolute-updates", herkunft: "Ubuntu", sicherheit: false, heikel: false }, teile);

// stand.json wie von zenos-basis pruefen (evaluate): hier «bereit» mit drei Paketen, eines aus -security
function stand(teile = {}) {
  return JSON.stringify(Object.assign({
    version: 1,
    zeit: iso(JETZT - 2 * H),
    geprueft: iso(JETZT - 2 * H),
    fehler: null,
    ergebnis: "bereit",
    grund: "3 Updates (1 Sicherheit) bereit.",
    liste: L1,
    anzahl: 3,
    sicherheit: 1,
    heikel: [],
    entfernen: [],
    geschuetzt: [],
    neustart: false,
    neustart_wegen: [],
    pakete: [paket("curl", "8.5.0-2", "8.5.0-2ubuntu1"), paket("libssl3t64", "3.4.1-1", "3.4.1-1ubuntu1", { tasche: "resolute-security", sicherheit: true }), paket("code", "1.104.0", "1.105.0", { herkunft: "code stable", tasche: "stable" })],
    entfernungen: [],
  }, teile));
}

// Kernel und Firmware dabei: «zustimmung»
const KERNEL = {
  ergebnis: "zustimmung",
  grund: "4 Updates (Kernel/Firmware/Bootloader); braucht eine Zustimmung: Kernel, Firmware oder Bootloader (linux-firmware-raspi, linux-raspi).",
  anzahl: 4,
  sicherheit: 0,
  heikel: ["linux-firmware-raspi", "linux-raspi"],
  neustart: true,
  neustart_wegen: ["linux-firmware-raspi", "linux-raspi"],
  pakete: [paket("curl", "8.5.0-2", "8.5.0-2ubuntu1"), paket("linux-raspi", "6.17.0-1004.4", "6.17.0-1005.5", { heikel: true }), paket("linux-firmware-raspi", "10", "11", { heikel: true }), paket("vim", "2:9.1", "2:9.1ubuntu1")],
};

function letzte(ergebnis, endeMs, teile = {}) {
  return JSON.stringify(Object.assign({ version: 1, ergebnis, grund: "", beginn: iso(endeMs - 60000), ende: iso(endeMs), liste: L1, von: "automatik", zustimmung: false, anzahl: 3, geaendert: 3, neustart: false, probleme: [], hinweise: [] }, teile));
}

function automatik(ergebnis, liste, teile = {}) {
  return JSON.stringify(Object.assign({ version: 1, art: "lauf", beginn: iso(JETZT - H - 60000), ende: iso(JETZT - H), ergebnis, grund: "", zeitpunkt: "sperre", liste }, teile));
}

function lage(standText, letzteText = null, automatikText = null) {
  const s = B.standLesen(standText);
  const l = B.letzteLesen(letzteText);
  return { stand: s, letzte: l, automatik: B.automatikLesen(automatikText), veraltet: B.veraltet(s, l) };
}

function melden(l, gemeldet, jetzt = JETZT) {
  const e = B.meldungen(l, gemeldet ?? B.gemeldetLesen(""), jetzt);
  return { neu: roh(e.neu), gemeldet: e.gemeldet };
}

// --- Lesen ---------------------------------------------------------------------

test("basis.js importiert genau kanal.js als Kanal (Text, Zeiten, notify-send wie beim Kanal)", () => {
  assert.deepEqual(importe, [["kanal.js", "Kanal"]]);
});

test("standLesen: Felder, Hersteller, Fehlerfälle", () => {
  const s = B.standLesen(stand());
  assert.equal(s.ergebnis, "bereit");
  assert.equal(s.liste, L1);
  assert.equal(s.anzahl, 3);
  assert.equal(s.sicherheit, 1);
  assert.deepEqual(roh(s.hersteller), ["code stable"]);
  assert.equal(s.geprueftMs, JETZT - 2 * H);
  assert.equal(B.standLesen(""), null);
  assert.equal(B.standLesen("{kaputt"), null);
  assert.equal(B.standLesen(stand({ version: 2 })), null);
  assert.equal(B.standLesen("[]"), null);
  // Unbekanntes Ergebnis oder «bereit» ohne gültige Liste: nichts installierbar
  assert.equal(B.standLesen(stand({ ergebnis: "ganz-neu" })).ergebnis, "fehler");
  assert.equal(B.standLesen(stand({ liste: "ABC" })).ergebnis, "fehler");
  assert.equal(B.standLesen(stand({ liste: null })).liste, "");
  // Namen nur als Paketnamen, Zahlen nur ganz und ab 0
  const z = B.standLesen(stand({ heikel: ["linux-raspi", "../x", "linux-raspi", 7, "Grub"], anzahl: -3, sicherheit: "2" }));
  assert.deepEqual(roh(z.heikel), ["linux-raspi"]);
  assert.equal(z.anzahl, 0);
  assert.equal(z.sicherheit, 0);
  // Unsichtbare Zeichen im Grund werden ersetzt
  assert.equal(B.standLesen(stand({ grund: "a‮b\nc" })).grund, "a?b c");
});

test("standLesen: wartetSchluessel hängt nur an Kernel, Firmware, Bootloader, Entfernungen und Geschütztem", () => {
  const a = B.standLesen(stand(Object.assign({}, KERNEL, { liste: L1 })));
  const b = B.standLesen(stand(Object.assign({}, KERNEL, { liste: L2, anzahl: 9, pakete: KERNEL.pakete.concat([paket("zsh", "5", "6")]) })));
  assert.equal(a.wartetSchluessel, "linux-firmware-raspi=11 linux-raspi=6.17.0-1005.5");
  assert.equal(a.wartetSchluessel, b.wartetSchluessel, "andere Liste, derselbe Kernel");
  const c = B.standLesen(stand(Object.assign({}, KERNEL, { pakete: [paket("linux-raspi", "6.17.0-1004.4", "6.17.0-1006.6", { heikel: true })] })));
  assert.notEqual(c.wartetSchluessel, a.wartetSchluessel, "neuer Kernel");
  const d = B.standLesen(stand({ ergebnis: "zustimmung", heikel: [], entfernen: ["alt-paket"], pakete: [] }));
  assert.equal(d.wartetSchluessel, "-alt-paket");
});

test("letzteLesen und automatikLesen", () => {
  const l = B.letzteLesen(letzte("installiert", JETZT - H, { grund: "3 Pakete aktualisiert, gesund.", von: "einstellungen" }));
  assert.deepEqual(roh(l), { ergebnis: "installiert", grund: "3 Pakete aktualisiert, gesund.", endeMs: JETZT - H, liste: L1, von: "einstellungen", geaendert: 3, neustart: false });
  assert.equal(B.letzteLesen(letzte("explodiert", JETZT)), null);
  assert.equal(B.letzteLesen(letzte("installiert", JETZT, { version: 3 })), null);
  assert.equal(B.letzteLesen(letzte("installiert", JETZT, { von: "fremd" })).von, "");
  const a = B.automatikLesen(automatik("zustimmung", L1, { grund: "Basis-Updates warten auf dich: …" }));
  assert.equal(a.ergebnis, "zustimmung");
  assert.equal(a.liste, L1);
  assert.equal(a.art, "lauf");
  assert.equal(B.automatikLesen(automatik("irgendwas", L1)), null);
  assert.equal(B.automatikLesen(automatik("wartet", "nicht-hex")).liste, "");
});

test("neustartLesen: /run/reboot-required und .pkgs", () => {
  assert.deepEqual(roh(B.neustartLesen(false, "linux-raspi\n")), { noetig: false, pakete: [] });
  assert.deepEqual(roh(B.neustartLesen(true, "")), { noetig: true, pakete: [] });
  assert.deepEqual(roh(B.neustartLesen(true, "linux-raspi\ngreetd\n\nlinux-raspi\n$(boese)\n")), { noetig: true, pakete: ["greetd", "linux-raspi"] });
});

// --- Leitplanke ----------------------------------------------------------------

test("neustartHinweis: nur bei voller Leiste, nie bei Freigabe, reduzierter oder ausgeblendeter Leiste oder gesperrt", () => {
  assert.equal(B.neustartHinweis(true, false, "normal", false), true);
  assert.equal(B.neustartHinweis(true, false, undefined, false), true, "ohne Zustand: volle Leiste");
  assert.equal(B.neustartHinweis(false, false, "normal", false), false);
  assert.equal(B.neustartHinweis(true, true, "normal", false), false, "Bildschirm wird geteilt");
  assert.equal(B.neustartHinweis(true, false, "reduziert", false), false);
  assert.equal(B.neustartHinweis(true, false, "aus", false), false);
  assert.equal(B.neustartHinweis(true, false, "normal", true), false, "gesperrt");
  assert.equal(B.neustartHinweis("ja", false, "normal", false), false, "nur ein echtes true");
});

// --- Anzeige -------------------------------------------------------------------

test("zustandTitel und zustandSymbol je Lage", () => {
  const faelle = [
    [null, false, null, false, "Noch nie geprüft", "info", "gedaempft"],
    [stand(), false, null, true, "Update läuft", "info", "akzent"],
    [stand({ ergebnis: "aktuell", anzahl: 0, sicherheit: 0, liste: L1, pakete: [] }), false, null, false, "Aktuell", "haken", "akzent"],
    [stand(), false, null, false, "3 Updates bereit", "info", "akzent"],
    [stand({ anzahl: 1 }), false, null, false, "1 Update bereit", "info", "akzent"],
    [stand(KERNEL), false, null, false, "4 Updates warten auf dich", "schloss", "akzent"],
    [stand(Object.assign({}, KERNEL, { anzahl: 1 })), false, null, false, "1 Update wartet auf dich", "schloss", "akzent"],
    [stand({ ergebnis: "zustimmung", anzahl: 0, entfernen: ["x"] }), false, null, false, "Entfernungen warten auf dich", "schloss", "akzent"],
    [stand({ ergebnis: "gesperrt", geschuetzt: ["ubuntu-minimal"], entfernen: ["ubuntu-minimal"] }), false, null, false, "Gesperrt", "warnung", "warnung"],
    [stand({ ergebnis: "fehler", grund: "Prüfung gescheitert: apt-get update endete mit Exit 100 (Netz oder Paketserver?)" }), false, null, false, "Kein Kontakt zu den Paketquellen", "wolke", "gedaempft"],
    [stand({ ergebnis: "fehler", grund: "Prüfung gescheitert: apt-mark showmanual endete mit Exit 1" }), false, null, false, "Prüfung gescheitert", "warnung", "warnung"],
    [stand(), true, letzte("installiert", JETZT), false, "Seit der letzten Prüfung installiert", "info", "gedaempft"],
    [stand(), false, letzte("kaputt", JETZT - 3 * H), false, "Basis-Update kaputt", "warnung", "warnung"],
  ];
  for (const [s, v, l, laeuft, titel, symbol, ton] of faelle) {
    const st = B.standLesen(s), le = B.letzteLesen(l);
    assert.equal(B.zustandTitel(st, v, le, laeuft), titel);
    assert.deepEqual(roh(B.zustandSymbol(st, v, le, laeuft)), { symbol, ton }, titel);
  }
});

test("veraltet: nur wenn nach der Prüfung installiert wurde", () => {
  const s = B.standLesen(stand());
  assert.equal(B.veraltet(s, B.letzteLesen(letzte("installiert", JETZT - 3 * H))), false);
  assert.equal(B.veraltet(s, B.letzteLesen(letzte("installiert", JETZT - 2 * H + 1000))), false, "2 s Spielraum");
  assert.equal(B.veraltet(s, B.letzteLesen(letzte("installiert", JETZT - H))), true);
  assert.equal(B.veraltet(null, B.letzteLesen(letzte("installiert", JETZT))), false);
});

test("grundText: knapp und ehrlich, mit dem Wann je Zeitpunkt", () => {
  const s = B.standLesen(stand());
  const zeit = (inhalt) => K.zeitpunktLesen(inhalt);
  assert.equal(B.grundText(s, false, null, false, { zeitpunkt: zeit(null), automatikAn: true }),
    "3 Updates, davon 1 Sicherheit, ohne Kernel, Firmware, Bootloader und Entfernungen. Kommt automatisch bei der nächsten Sperre, nicht während einer SSH-Sitzung.");
  assert.match(B.grundText(s, false, null, false, { zeitpunkt: zeit("zeitpunkt=fenster\nvon=22:00\nbis=06:00\n"), automatikAn: true }), /zwischen 22:00 und 06:00 Uhr, nicht während einer SSH-Sitzung\.$/);
  assert.match(B.grundText(s, false, null, false, { zeitpunkt: zeit("zeitpunkt=jederzeit\n"), automatikAn: true }), /innert 15 Minuten/);
  assert.match(B.grundText(s, false, null, false, { zeitpunkt: zeit("zeitpunkt=hand\n"), automatikAn: true }), /Automatisch kommt nichts \(Zeitpunkt «Von Hand»\)\.$/);
  assert.match(B.grundText(s, false, null, false, { zeitpunkt: zeit(null), automatikAn: false }), /Automatik aus; einschalten: sudo zen kanal automatik an/);
  const k = B.grundText(B.standLesen(stand(KERNEL)), false, null, false, {});
  assert.equal(k, "4 Updates. Dabei sind Kernel, Firmware oder Bootloader (linux-firmware-raspi, linux-raspi): Das kommt nie automatisch, nur mit deinem Passwort oder mit zen update. Danach ist ein Neustart nötig.");
  const e = B.grundText(B.standLesen(stand({ ergebnis: "zustimmung", entfernen: ["a", "b", "c", "d", "e"] })), false, null, false, {});
  assert.match(e, /Entfernungen \(a, b, c und 2 weitere\)/);
  assert.doesNotMatch(e, /Neustart/);
  assert.match(B.grundText(null, false, null, false, {}), /Installiert wird dabei nichts\.$/);
  assert.match(B.grundText(s, false, null, true, {}), /Ausschalten und Neustart warten/);
  assert.equal(B.grundText(s, false, B.letzteLesen(letzte("kaputt", JETZT, { grund: "Nach dem Update schlechter als vorher: greetd ausgefallen." })), false, {}), "Nach dem Update schlechter als vorher: greetd ausgefallen.");
  assert.match(B.grundText(B.standLesen(stand({ ergebnis: "gesperrt", grund: "apt würde geschützte Pakete entfernen (ubuntu-minimal)." })), false, null, false, {}), /geschützte Pakete/);
});

test("zeilen: Werte für die Einstellungen", () => {
  const titel = (z) => z.map((e) => e.titel);
  const neustartNein = B.neustartLesen(false, "");
  // Bereit, mit Herstellerquelle, letzte Installation und letztem Lauf der Automatik
  const z1 = roh(B.zeilen(B.standLesen(stand()), B.letzteLesen(letzte("installiert", JETZT - 26 * H, { von: "zen update" })), neustartNein, {
    automatik: B.automatikLesen(automatik("wartet", L1, { grund: "3 Updates (1 Sicherheit) bereit, nicht jetzt: SSH-Sitzung." })),
    automatikAn: true,
    jetztMs: JETZT,
  }));
  assert.deepEqual(titel(z1), ["Ausstehend", "Hersteller", "Letztes Update", "Automatik", "Geprüft", "Liste"]);
  assert.equal(z1[0].wert, "3 Updates · 1 Sicherheit");
  assert.equal(z1[1].wert, "code stable");
  assert.equal(z1[2].wert, "installiert · gestern, 12:00 · zen update");
  assert.equal(z1[3].wert, "heute, 13:00 · nicht jetzt: SSH-Sitzung");
  assert.equal(z1[4].wert, "heute, 12:00");
  assert.equal(z1[5].wert, "111111111111");
  // Kernel: Kernel/Boot und Neustart voraussichtlich; mit /run/reboot-required «nötig» samt Paketen
  const z2 = roh(B.zeilen(B.standLesen(stand(KERNEL)), null, neustartNein, { automatikAn: true, jetztMs: JETZT }));
  assert.deepEqual(titel(z2), ["Ausstehend", "Kernel/Boot", "Neustart", "Geprüft", "Liste"]);
  assert.equal(z2[1].wert, "linux-firmware-raspi, linux-raspi");
  assert.equal(z2[2].wert, "voraussichtlich nach dem Update");
  const z3 = roh(B.zeilen(B.standLesen(stand({ ergebnis: "aktuell", anzahl: 0, sicherheit: 0, pakete: [] })), null, B.neustartLesen(true, "linux-raspi\ngreetd\n"), { automatikAn: false, jetztMs: JETZT }));
  assert.deepEqual(titel(z3), ["Ausstehend", "Neustart", "Automatik", "Geprüft"]);
  assert.equal(z3[0].wert, "keine");
  assert.equal(z3[1].wert, "nötig · greetd, linux-raspi");
  assert.equal(z3[2].wert, "aus · einschalten: sudo zen kanal automatik an");
  // Gesperrt: was ginge weg; Fehler: nur Geprüft mit Vermerk; nie geprüft, aber Neustart nötig (unattended-upgrades)
  const z4 = roh(B.zeilen(B.standLesen(stand({ ergebnis: "gesperrt", entfernen: ["ubuntu-minimal"], geschuetzt: ["ubuntu-minimal"] })), null, neustartNein, { jetztMs: JETZT }));
  assert.ok(z4.some((e) => e.titel === "Geschützt" && e.wert === "ubuntu-minimal ginge weg"));
  assert.ok(z4.some((e) => e.titel === "Entfernen"));
  const z5 = roh(B.zeilen(B.standLesen(stand({ ergebnis: "fehler", geprueft: null, grund: "Prüfung gescheitert: x" })), null, neustartNein, { jetztMs: JETZT }));
  assert.deepEqual(z5, [{ titel: "Geprüft", wert: "nie · letzter Versuch gescheitert" }]);
  assert.deepEqual(roh(B.zeilen(null, null, B.neustartLesen(true, ""), { jetztMs: JETZT })), [{ titel: "Neustart", wert: "nötig" }]);
});

test("automatikKurz: letzter Lauf der Automatik in wenigen Worten", () => {
  const a = (ergebnis, grund = "") => B.automatikLesen(automatik(ergebnis, L1, { grund }));
  assert.equal(B.automatikKurz(a("wartet", "4 Updates (2 Sicherheit) bereit, nicht jetzt: Zeitpunkt «Bei Sperre»: nicht gesperrt.")), "nicht jetzt: Zeitpunkt «Bei Sperre»: nicht gesperrt");
  assert.equal(B.automatikKurz(a("wartet", "Ein install.sh von Hand läuft gerade (PID 7); beim nächsten Mal.")), "Ein install.sh von Hand läuft gerade (PID 7); beim nächsten Mal.");
  assert.equal(B.automatikKurz(a("zustimmung", "Basis-Updates warten auf dich: …")), "wartet auf dich (Kernel, Firmware, Bootloader oder Entfernungen)");
  assert.equal(B.automatikKurz(a("gesperrt")), "gesperrt (geschütztes Paket)");
  assert.equal(B.automatikKurz(a("aktuell")), "nichts zu tun");
  assert.equal(B.automatikKurz(a("installiert", "3 Pakete aktualisiert, gesund.")), "installiert");
  assert.equal(B.automatikKurz(a("aus")), "Automatik war aus");
  assert.equal(B.automatikKurz(a("fehler", "Prüfung gescheitert: apt-get update endete mit Exit 100")), "Prüfung gescheitert: apt-get update endete mit Exit 100");
  assert.equal(B.automatikKurz(a("kaputt")), "kaputt");
  assert.equal(B.automatikKurz(null), "");
});

test("installierenListe, zustimmungListe, knopfHinweis: nur der angezeigte, nicht veraltete Stand", () => {
  const s = B.standLesen(stand());
  const k = B.standLesen(stand(Object.assign({}, KERNEL, { liste: L2 })));
  assert.equal(B.installierenListe(s, false), L1);
  assert.equal(B.installierenListe(s, true), "", "veraltet");
  assert.equal(B.zustimmungListe(s, false), "");
  assert.equal(B.installierenListe(k, false), "", "Kernel nie ohne Passwort");
  assert.equal(B.zustimmungListe(k, false), L2);
  assert.equal(B.installierenListe(B.standLesen(stand({ ergebnis: "gesperrt" })), false), "");
  assert.equal(B.zustimmungListe(B.standLesen(stand({ ergebnis: "gesperrt" })), false), "", "gesperrt: auch nicht mit Passwort");
  assert.equal(B.installierenListe(null, false), "");
  assert.match(B.knopfHinweis(s, false), /^Installiert genau die angezeigte Liste \(111111111111\), ohne neue Prüfung\./);
  assert.match(B.knopfHinweis(k, false), /^Verlangt dein Passwort und gilt nur für die angezeigte Liste \(222222222222\)\. zenOS startet danach nie selbst neu\.$/);
  assert.equal(B.knopfHinweis(B.standLesen(stand({ ergebnis: "aktuell" })), false), "");
});

// --- Mitteilungen --------------------------------------------------------------

test("meldungen: Ergebnis einer Installation genau einmal", () => {
  // frisch installiert: still
  const a = melden(lage(stand(), letzte("installiert", JETZT - 5 * 60000, { grund: "3 Pakete aktualisiert, gesund. Neustart nötig." })));
  assert.deepEqual(a.neu, [{ schluessel: "installiert", titel: "Ubuntu-Basis aktualisiert", text: "3 Pakete aktualisiert, gesund. Neustart nötig.", dringlichkeit: "low" }]);
  assert.equal(melden(lage(stand(), letzte("installiert", JETZT - 5 * 60000)), a.gemeldet).neu.length, 0, "nicht zweimal");
  // alt (erster Start nach Tagen): nur merken
  const alt = melden(lage(stand(), letzte("installiert", JETZT - 30 * H)));
  assert.equal(alt.neu.length, 0);
  assert.match(alt.gemeldet.installation, /^installiert@/);
  // kaputt dringend, auch alt; gescheitert normal
  const k = melden(lage(stand(), letzte("kaputt", JETZT - 50 * H, { grund: "Nach dem Update schlechter als vorher: greetd ausgefallen." })));
  assert.deepEqual(k.neu.map((m) => [m.schluessel, m.dringlichkeit]), [["kaputt", "critical"]]);
  const f = melden(lage(stand(), letzte("fehler", JETZT - H, { grund: "apt-get full-upgrade endete mit Exit 100." })));
  assert.deepEqual(f.neu.map((m) => [m.schluessel, m.titel, m.dringlichkeit]), [["fehler", "Basis-Update gescheitert", "normal"]]);
  // «aktuell» und «abgelehnt» schreibt zenos-basis nicht in letzte.json; käme es doch, nichts
  assert.equal(melden(lage(stand(), letzte("abgelehnt", JETZT))).neu.length, 0);
});

test("meldungen: «Basis-Updates warten auf dich» einmal, bis sich Kernel, Firmware, Bootloader oder Entfernungen ändern", () => {
  const k1 = stand(Object.assign({}, KERNEL, { liste: L1 }));
  const a = melden(lage(k1, null, automatik("zustimmung", L1)));
  assert.equal(a.neu.length, 1);
  assert.equal(a.neu[0].titel, "Basis-Updates warten auf dich");
  assert.equal(a.neu[0].dringlichkeit, "normal");
  assert.match(a.neu[0].text, /^4 Updates\. Dabei sind Kernel, Firmware oder Bootloader \(linux-firmware-raspi, linux-raspi\).* Ansehen: Einstellungen › System › Updates\.$/);
  // Dieselbe Lage: nichts. Eine neue Liste mit demselben Kernel (andere Pakete dazu): nichts
  assert.equal(melden(lage(k1, null, automatik("zustimmung", L1)), a.gemeldet).neu.length, 0);
  const k2 = stand(Object.assign({}, KERNEL, { liste: L2, anzahl: 5, pakete: KERNEL.pakete.concat([paket("zsh", "5", "6")]) }));
  assert.equal(melden(lage(k2, null, automatik("zustimmung", L2)), a.gemeldet).neu.length, 0);
  // Ein neuerer Kernel: wieder einmal
  const k3 = stand(Object.assign({}, KERNEL, { liste: L2, pakete: [paket("linux-raspi", "6.17.0-1004.4", "6.17.0-1007.7", { heikel: true })] }));
  assert.equal(melden(lage(k3, null, automatik("zustimmung", L2)), a.gemeldet).neu.length, 1);
  // Nur, was die Automatik gesehen hat: von Hand geprüft (automatik.json älter, andere Liste) oder ohne automatik.json
  assert.equal(melden(lage(k1, null, automatik("zustimmung", L2))).neu.length, 0);
  assert.equal(melden(lage(k1, null, null)).neu.length, 0);
  assert.equal(melden(lage(k1, null, automatik("wartet", L1))).neu.length, 0);
  // Veraltet (seither installiert): nichts melden, nichts vergessen
  const v = melden(lage(k1, letzte("installiert", JETZT - 30 * H + 0), automatik("zustimmung", L1)));
  assert.equal(v.neu.length, 1, "nicht veraltet: Installation älter als die Prüfung");
  const neuer = melden(lage(stand(Object.assign({}, KERNEL, { liste: L1, zeit: iso(JETZT - 3 * H) })), letzte("fehler", JETZT - H), automatik("zustimmung", L1)), a.gemeldet);
  assert.equal(neuer.gemeldet.warten, a.gemeldet.warten);
  assert.deepEqual(neuer.neu.map((m) => m.schluessel), ["fehler"]);
});

test("meldungen: vorbei erst, wenn die Prüfung etwas anderes zeigt; gesperrt eigens", () => {
  const k1 = stand(Object.assign({}, KERNEL, { liste: L1 }));
  const a = melden(lage(k1, null, automatik("zustimmung", L1)));
  // Kein Netz (fehler): nichts vergessen
  const f = melden(lage(stand({ ergebnis: "fehler", grund: "Prüfung gescheitert: apt-get update endete mit Exit 100" }), null, null), a.gemeldet);
  assert.equal(f.gemeldet.warten, a.gemeldet.warten);
  // Kernel installiert, die Prüfung zeigt «bereit»: vorbei; kommt derselbe Kernel je wieder, meldet er sich wieder
  const b = melden(lage(stand(), null, automatik("wartet", L1)), a.gemeldet);
  assert.equal(b.gemeldet.warten, "");
  assert.equal(melden(lage(k1, null, automatik("zustimmung", L1)), b.gemeldet).neu.length, 1);
  // Gesperrt: eigener Titel
  const g = melden(lage(stand({ ergebnis: "gesperrt", entfernen: ["ubuntu-minimal"], geschuetzt: ["ubuntu-minimal"] }), null, automatik("gesperrt", L1)));
  assert.deepEqual(g.neu.map((m) => m.titel), ["Basis-Updates gesperrt"]);
  assert.match(g.neu[0].text, /\(ubuntu-minimal\)/);
});

test("gemeldetLesen und gemeldetText: robust und stabil", () => {
  assert.deepEqual(roh(B.gemeldetLesen("")), { installation: "", warten: "" });
  assert.deepEqual(roh(B.gemeldetLesen("{\"installation\": 5, \"warten\": \"x\"}")), { installation: "", warten: "x" });
  const g = { installation: "installiert@2026-10-05T11:00:00.000Z", warten: "zustimmung:linux-raspi=1" };
  assert.deepEqual(roh(B.gemeldetLesen(B.gemeldetText(g))), g);
  assert.ok(B.gemeldetText(g).endsWith("\n"));
  // notify-send nur als Argumentliste (aus kanal.js)
  const m = melden(lage(stand(), letzte("kaputt", JETZT))).neu[0];
  assert.deepEqual(roh(K.mitteilungBefehl(m)).slice(0, 6), ["notify-send", "--app-name=zenOS", "--icon=zenos", "--urgency=critical", "--category=system", "--"]);
});

// --- Bedienung -----------------------------------------------------------------

test("befehl: nur feste Wörter und eine Liste aus 40 Zeichen 0-9a-f", () => {
  const h = "/opt/zenos/scripts/bin/zenos-kanal-bedienen";
  assert.deepEqual(roh(B.befehl(h, "pruefen")), ["pkexec", h, "basis-pruefen"]);
  assert.deepEqual(roh(B.befehl(h, "installieren", L1)), ["pkexec", h, "basis-installieren", L1]);
  assert.deepEqual(roh(B.befehl(h, "zustimmen", L2)), ["pkexec", h, "basis-installieren-zustimmen", L2]);
  for (const falsch of [["installieren"], ["installieren", "x"], ["installieren", "ab".repeat(20).toUpperCase()], ["installieren", L1 + "0"], ["zustimmen", ""], ["update"], ["installieren", "1111111111111111111111111111111111111111; rm"]])
    assert.equal(B.befehl(h, ...falsch), null, falsch.join(" "));
  assert.equal(B.befehl("zenos-kanal-bedienen", "pruefen"), null, "nur ein fester Pfad");
});

test("rueckmeldung: Hinweise nur nach eigenem Klick, Ergebnisse einer Installation als Mitteilung", () => {
  const s = B.standLesen(stand());
  const k = B.standLesen(stand(KERNEL));
  assert.equal(B.rueckmeldung("installieren", 126, {}), null, "abgebrochen: still");
  assert.match(B.rueckmeldung("pruefen", -1, {}).text, /pkexec lässt sich nicht starten/);
  assert.match(B.rueckmeldung("pruefen", 127, { fehler: "No authentication agent found" }).text, /polkit-Agent/);
  assert.match(B.rueckmeldung("pruefen", 127, {}).text, /aktiven Sitzung/);
  assert.match(B.rueckmeldung("installieren", 75, {}).text, /läuft schon/);
  assert.deepEqual(roh(B.rueckmeldung("pruefen", 0, { stand: s })), { text: "Ubuntu-Basis geprüft", art: "" });
  assert.deepEqual(roh(B.rueckmeldung("pruefen", 3, {})), { text: "Ubuntu-Basis geprüft: gesperrt", art: "warnung" });
  assert.match(B.rueckmeldung("pruefen", 1, { stand: B.standLesen(stand({ ergebnis: "fehler", grund: "Prüfung gescheitert: apt-get update endete mit Exit 100 (Netz oder Paketserver?)" })) }).text, /^Kein Kontakt zu den Paketquellen/);
  assert.equal(B.rueckmeldung("pruefen", 1, { stand: B.standLesen(stand({ ergebnis: "fehler", grund: "Prüfung gescheitert: apt-mark showmanual endete mit Exit 1" })) }).text, "Prüfung gescheitert: apt-mark showmanual endete mit Exit 1");
  assert.match(B.rueckmeldung("pruefen", 1, {}).text, /journalctl -u zenos-basis-pruefen/);
  assert.equal(B.rueckmeldung("installieren", 0, { installiert: true }), null, "die Mitteilung kommt ohnehin");
  assert.equal(B.rueckmeldung("installieren", 5, { installiert: false }), null, "kaputt: Mitteilung aus letzte.json");
  assert.deepEqual(roh(B.rueckmeldung("installieren", 0, {})), { text: "Die Ubuntu-Basis ist schon aktuell", art: "" });
  assert.match(B.rueckmeldung("installieren", 3, { stand: s }).text, /Liste hat sich geändert/);
  assert.match(B.rueckmeldung("zustimmen", 3, { stand: B.standLesen(stand({ ergebnis: "gesperrt" })) }).text, /geschützte Pakete/);
  assert.match(B.rueckmeldung("installieren", 10, { stand: k }).text, /nur mit deinem Passwort/);
  assert.match(B.rueckmeldung("installieren", 10, { stand: s, kanalProblem: true }).text, /zenOS-Kanal in Ordnung bringen/);
  assert.match(B.rueckmeldung("zustimmen", 10, { stand: k }).text, /^Basis-Update wartet/);
  assert.equal(B.rueckmeldung("zustimmen", 1, { fehler: "zenos-basis: /var/lib/zenos/basis gehört nicht root" }).text, "Basis-Update gescheitert: /var/lib/zenos/basis gehört nicht root");
  assert.equal(B.rueckmeldung("anderes", 0, {}), null);
});

// --- Abgleich ------------------------------------------------------------------

test("Abgleich mit zenos-basis: Pfade, Ergebnisse, Herkunft, Grund ohne Netz", () => {
  const basis = lesen("scripts", "bin", "zenos-basis");
  const qml = lesen("shell", "dienste", "Basis.qml");
  const pfad = (name) => new RegExp(`readonly property string ${name}: "([^"]+)"`).exec(qml)[1];
  const py = (name) => new RegExp(`^${name} = "([^"]+)"$`, "m").exec(basis)[1];
  assert.equal(pfad("standPfad"), `${py("STATE_DIR")}/${py("STAND")}`);
  assert.equal(pfad("letztePfad"), `${py("STATE_DIR")}/${py("LAST")}`);
  assert.equal(pfad("automatikPfad"), `${py("STATE_DIR")}/${py("AUTO_LOG")}`);
  assert.equal(pfad("notschalterPfad"), py("AUTOMATIC_OFF_FILE"));
  assert.equal(pfad("neustartPfad"), py("REBOOT_FILE"));
  assert.equal(pfad("neustartPaketePfad"), py("REBOOT_PKGS"));
  assert.equal(pfad("helfer"), /readonly property string helfer: "([^"]+)"/.exec(lesen("shell", "dienste", "Kanal.qml"))[1]);
  // Ergebnisse der Prüfung (verdict, failed_stand), der Installation und der Automatik
  const verdict = basis.slice(basis.indexOf("def verdict("), basis.indexOf("def evaluate_now("));
  assert.deepEqual([...new Set([...verdict.matchAll(/return "([a-z]+)"/g)].map((m) => m[1]))].sort(), [...B.ERGEBNISSE].sort());
  const ergebnisse = basis.slice(basis.indexOf("RESULT_TEXT = {"), basis.indexOf("}", basis.indexOf("RESULT_TEXT = {")));
  assert.deepEqual([...ergebnisse.matchAll(/"([a-z]+)": "/g)].map((m) => m[1]).sort(), [...B.INSTALLATIONEN].sort());
  for (const e of B.INSTALLATIONEN)
    assert.ok(B.AUTOMATIK.includes(e), `Automatik übernimmt das Ergebnis der Installation ${e}`);
  for (const m of basis.matchAll(/self\.done\("([a-z]+)"/g))
    assert.ok(B.AUTOMATIK.includes(m[1]), `Automatik ${m[1]}`);
  assert.ok(B.AUTOMATIK.includes("zustimmung") && B.AUTOMATIK.includes("gesperrt"));
  const herkunft = /^ORIGINS = \(([^)]*)\)$/m.exec(basis)[1];
  assert.deepEqual([...herkunft.matchAll(/"([^"]+)"/g)].map((m) => m[1]).sort(), Object.keys(B.HERKUNFT).sort());
  assert.ok(basis.includes('f"apt-get update endete mit Exit {rc} (Netz oder Paketserver?)"'), "Grund ohne Netz");
  assert.ok(basis.includes('return "fehler", f"Prüfung gescheitert: {stand[\'fehler\']}"'), "Präfix des Grundes");
  assert.equal(B.OHNE_NETZ, "Prüfung gescheitert: apt-get update endete mit Exit");
  // Wörter des Helfers und der polkit-Richtlinie
  const helfer = lesen("scripts", "bin", "zenos-kanal-bedienen");
  const policy = lesen("system", "polkit", "org.zenos.kanal.policy");
  for (const wort of ["basis-pruefen", "basis-installieren", "basis-installieren-zustimmen"]) {
    assert.match(helfer, new RegExp(`^  (?:[a-z-]+ \\| )*${wort}(?: \\|[^)]*)?\\)`, "m"), `Helfer kennt ${wort}`);
    assert.match(policy, new RegExp(`exec\\.argv1">${wort}<`), `polkit kennt ${wort}`);
  }
  assert.match(policy, /<action id="org\.zenos\.kanal\.basis-zustimmen">[\s\S]*?<allow_active>auth_admin<\/allow_active>/);
});

test("Abgleich mit der Oberfläche: Startliste, IPC, Rundgang", () => {
  assert.match(lesen("shell", "shell.qml"), /\(\) => Basis\.zustand/);
  // Die Leitplanke steht nur in basis.js (eine Stelle), die Oberfläche fragt nur Basis.neustartHinweis
  const qml = lesen("shell", "dienste", "Basis.qml");
  assert.match(qml, /neustartHinweis: Logik\.neustartHinweis\(_neustart\.noetig, Freigabe\.aktiv, Zustaende\.wirksam\?\.leiste \?\? "normal", Oberflaeche\.gesperrt\)/);
  for (const f of ["status", "neustart", "hinweis", "pruefen"])
    assert.match(qml, new RegExp(`function ${f}\\(\\): string`), `IPC basis ${f}`);
  // Rundgang in pruefen.sh: nur lesende Aufrufe (prüfen startete pkexec und apt-get update)
  const pruefen = lesen("scripts", "pruefen.sh");
  assert.match(pruefen, /^  "basis status"$/m);
  assert.match(pruefen, /^  "basis neustart"$/m);
  assert.match(pruefen, /^  "basis hinweis → nein"$/m);
  assert.doesNotMatch(pruefen, /^  "basis pruefen/m);
});

test("Abgleich mit den Einstellungen: zwei Abschnitte, Knöpfe, Automatik", () => {
  const seite = lesen("shell", "einstellungen", "SeiteSystem.qml");
  assert.match(seite, /beschriftung: "Updates · zenOS"/);
  assert.match(seite, /beschriftung: "Updates · Ubuntu-Basis"/);
  assert.match(seite, /"Mit Passwort installieren"/);
  assert.match(seite, /onClicked: Dienste\.Basis\.installieren\(Dienste\.Basis\.installierenListe\)/);
  assert.match(seite, /onClicked: Dienste\.Basis\.zustimmen\(Dienste\.Basis\.zustimmungListe\)/);
  assert.match(seite, /Dienste\.Basis\.automatikImmer/);
});

test("Abgleich mit der Leiste: Symbol im System-Knopf und Wert im System-Menü", () => {
  const leiste = lesen("shell", "leiste", "LeistenInhalt.qml");
  assert.match(leiste, /visible: Basis\.neustartHinweis\s+name: "neustart"\s+groesse: 14\s+farbe: Theme\.gedaempft/);
  assert.match(leiste, /if \(Basis\.neustartHinweis\)\s+parts\.push\("Neustart nötig"\)/);
  const menue = lesen("shell", "leiste", "SystemMenue.qml");
  assert.match(menue, /wert: Kanal\.updateLaeuft \? "Update läuft" : Basis\.neustartHinweis \? "nötig" : ""/);
});
