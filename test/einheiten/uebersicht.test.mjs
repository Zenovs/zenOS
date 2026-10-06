// Tests für die Fensterübersicht (shell/uebersicht/liste.mjs) und «Schreibtisch zeigen»
// (shell/uebersicht/schreibtisch.mjs). Ohne Abhängigkeiten: node --test test/einheiten/

import { test } from "node:test";
import assert from "node:assert/strict";
import { gruppieren, verlaufNachfuehren } from "../../shell/appleiste/fenster.mjs";
import { bewegen, eintraege, filtern, spalten, spaltenMax, startIndex } from "../../shell/uebersicht/liste.mjs";
import {
    entscheiden, frei, merken, nochOffen, sichtbare, vonUntenNachOben, zurueckReihenfolge
} from "../../shell/uebersicht/schreibtisch.mjs";

// Fenster wie Toplevel aus Quickshell: appId, title, minimized; verglichen wird die Identität
function fenster(appId, title, minimized) {
    return { appId: appId, title: title ?? "", minimized: minimized === true };
}

// Gruppen wie in der App-Leiste (dort kommen Name und Symbol aus dem Starter dazu)
function gruppen(liste, reihenfolge) {
    return gruppieren(liste, reihenfolge ?? []).gruppen.map(g => Object.assign({ name: g.appId }, g));
}

// Fenster eines Eintrags
function nurFenster(liste) {
    return liste.map(e => e.fenster);
}

// --- Liste ----------------------------------------------------------------------------------------------

test("Einträge: Apps nach ihrem ersten Fenster, die Fenster einer App nebeneinander", () => {
    const k1 = fenster("kitty", "eins");
    const c = fenster("google-chrome", "Seite");
    const k2 = fenster("kitty", "zwei");
    const e = fenster("org.quickshell", "Einstellungen");
    const m = fenster("coremail", "Posteingang");
    const g = gruppen([k1, c, e, k2, m]);
    const liste = eintraege(g);
    assert.deepEqual(nurFenster(liste), [k1, k2, c, m]);
    assert.equal(liste[0].app, g[0]);
    assert.equal(liste[1].app, g[0]);
    assert.equal(liste[2].app.appId, "google-chrome");
    // Die Fenster der Oberfläche fehlen wie in der App-Leiste
    assert.equal(liste.some(x => x.fenster === e), false);
});

test("Einträge: feste Reihenfolge der Apps, neue hinten", () => {
    const k1 = fenster("kitty");
    const c = fenster("google-chrome");
    const k2 = fenster("kitty");
    const erst = gruppieren([k1, c, k2], []);
    assert.deepEqual(nurFenster(eintraege(erst.gruppen)), [k1, k2, c]);
    // Kommt die Liste anders sortiert an, bleibt Kitty vorn. Innerhalb einer App gilt die Reihenfolge der Liste
    // (bei Quickshell die des Erscheinens).
    const dann = gruppieren([c, k2, k1], erst.reihenfolge);
    assert.deepEqual(nurFenster(eintraege(dann.gruppen)), [k2, k1, c]);
    // Eine neue App steht hinten
    const m = fenster("coremail");
    const neu = gruppieren([m, k1, c, k2], dann.reihenfolge);
    assert.deepEqual(nurFenster(eintraege(neu.gruppen)), [k1, k2, c, m]);
});

test("Einträge: leere und unvollständige Eingaben", () => {
    assert.deepEqual(eintraege(null), []);
    assert.deepEqual(eintraege([]), []);
    const a = fenster("kitty");
    assert.deepEqual(nurFenster(eintraege([{ appId: "kitty", fenster: [null, a] }, null, { appId: "x" }])), [a]);
    // Listen aus QML sind nur array-ähnlich
    const g = { length: 1, 0: { appId: "kitty", fenster: { length: 1, 0: a } } };
    assert.deepEqual(nurFenster(eintraege(g)), [a]);
});

test("Filter: App-Name, Titel und appId, Reihenfolge bleibt", () => {
    const uebersetzer = fenster("org.example.Uebersetzer", "Größe der Schrift");
    const k = fenster("kitty", "tmux: bau");
    const c = fenster("google-chrome", "Über uns – Beispiel");
    const g = gruppen([uebersetzer, k, c]);
    g[0].name = "Übersetzer";
    g[1].name = "Terminal";
    g[2].name = "Chrome";
    const liste = eintraege(g);
    // Leer oder nur Leerzeichen: alles
    assert.deepEqual(nurFenster(filtern(liste, "", true)), [uebersetzer, k, c]);
    assert.deepEqual(nurFenster(filtern(liste, "   ", true)), [uebersetzer, k, c]);
    // Umlaute: «über» und «uber» finden den App-Namen und den Titel, Reihenfolge der Übersicht
    assert.deepEqual(nurFenster(filtern(liste, "über", true)), [uebersetzer, c]);
    assert.deepEqual(nurFenster(filtern(liste, "UBER", true)), [uebersetzer, c]);
    assert.deepEqual(nurFenster(filtern(liste, "grösse", true)), [uebersetzer]);
    assert.deepEqual(nurFenster(filtern(liste, "grosse", true)), [uebersetzer]);
    // Titel und appId
    assert.deepEqual(nurFenster(filtern(liste, "tmux", true)), [k]);
    assert.deepEqual(nurFenster(filtern(liste, "kitty", true)), [k]);
    // Mehrere Wörter: jedes muss passen
    assert.deepEqual(nurFenster(filtern(liste, "terminal bau", true)), [k]);
    assert.deepEqual(nurFenster(filtern(liste, "terminal uns", true)), []);
    assert.deepEqual(nurFenster(filtern(liste, "zzz", true)), []);
});

test("Filter: Bei einer Freigabe zählen die Titel nicht", () => {
    const k = fenster("kitty", "geheim.txt – Notizen");
    const c = fenster("google-chrome", "Bank");
    const g = gruppen([k, c]);
    g[0].name = "Terminal";
    g[1].name = "Chrome";
    const liste = eintraege(g);
    assert.deepEqual(nurFenster(filtern(liste, "geheim", true)), [k]);
    assert.deepEqual(nurFenster(filtern(liste, "geheim", false)), []);
    assert.deepEqual(nurFenster(filtern(liste, "bank", false)), []);
    // App-Name und appId gelten weiter
    assert.deepEqual(nurFenster(filtern(liste, "chrome", false)), [c]);
    assert.deepEqual(nurFenster(filtern(liste, "term", false)), [k]);
});

test("Startauswahl: das vorige Fenster, Enter führt zurück wie Alt+Tab", () => {
    const a = fenster("kitty");
    const b = fenster("google-chrome");
    const c = fenster("code");
    const liste = eintraege(gruppen([a, b, c]));
    // aktiv ist c, davor war a aktiv
    assert.equal(startIndex(liste, c, [c, a, b]), 0);
    assert.equal(startIndex(liste, c, [c, b, a]), 1);
    // Geschlossene Fenster im Verlauf zählen nicht
    assert.equal(startIndex(liste, c, [c, fenster("weg"), b]), 1);
    // Kein aktives Fenster (z. B. Schreibtisch frei): das zuletzt aktive
    assert.equal(startIndex(liste, null, [b, a]), 1);
    // Ohne Verlauf: das erste
    assert.equal(startIndex(liste, c, []), 0);
    assert.equal(startIndex(liste, null, null), 0);
});

test("Startauswahl: ein Fenster, nur minimierte, keine Fenster", () => {
    const a = fenster("kitty");
    const nurEins = eintraege(gruppen([a]));
    assert.equal(startIndex(nurEins, a, [a]), 0);
    // Alle minimiert (Schreibtisch frei): labwc meldet kein aktives, der Verlauf kennt das zuletzt aktive
    const m1 = fenster("kitty", "eins", true);
    const m2 = fenster("code", "zwei", true);
    const minimiert = eintraege(gruppen([m1, m2]));
    assert.equal(startIndex(minimiert, null, [m2, m1]), 1);
    assert.equal(startIndex(minimiert, null, []), 0);
    assert.equal(startIndex([], a, [a]), -1);
    assert.equal(startIndex(null, null, null), -1);
});

test("Spalten: ausgeglichen, höchstens so viele wie passen", () => {
    assert.equal(spalten(1, 7), 1);
    assert.equal(spalten(6, 7), 6);
    assert.equal(spalten(7, 7), 7);
    // 8 Fenster: 4×2 statt 7 und 1
    assert.equal(spalten(8, 7), 4);
    // 10 Fenster: 5×2
    assert.equal(spalten(10, 7), 5);
    // 40 Fenster: 7 Spalten, 6 Zeilen (das Raster scrollt)
    assert.equal(spalten(40, 7), 7);
    assert.equal(Math.ceil(40 / spalten(40, 7)), 6);
    // Schmal: eine Spalte
    assert.equal(spalten(5, 1), 1);
    assert.equal(spalten(5, 0), 1);
    assert.equal(spalten(0, 7), 1);
    assert.equal(spalten(-3, 7), 1);
});

test("Spalten: höchstens 7 bei 1920 px", () => {
    // Kachel 216, Lücke 16 (a4), Rand 48 (a7) wie in der Übersicht
    assert.equal(spaltenMax(1920, 216, 16, 48), 7);
    assert.equal(spaltenMax(2560, 216, 16, 48), 10);
    assert.equal(spaltenMax(1280, 216, 16, 48), 5);
    // Genau passend: 3 Kacheln brauchen 3·216 + 2·16 + 2·48 = 776
    assert.equal(spaltenMax(776, 216, 16, 48), 3);
    assert.equal(spaltenMax(775, 216, 16, 48), 2);
    // Zu schmal oder ungültig: eine Spalte
    assert.equal(spaltenMax(100, 216, 16, 48), 1);
    assert.equal(spaltenMax(0, 216, 16, 48), 1);
    assert.equal(spaltenMax(undefined, 216, 16, 48), 1);
});

test("Bewegen im Raster, auch an den Rändern", () => {
    // 8 Kacheln in 5 Spalten: 0 1 2 3 4 / 5 6 7
    assert.equal(bewegen(0, -1, 0, 8, 5), 0);
    assert.equal(bewegen(0, 1, 0, 8, 5), 1);
    // Rechts über das Zeilenende hinweg in die nächste Zeile
    assert.equal(bewegen(4, 1, 0, 8, 5), 5);
    assert.equal(bewegen(5, -1, 0, 8, 5), 4);
    // Am Ende bleibt sie stehen
    assert.equal(bewegen(7, 1, 0, 8, 5), 7);
    // Runter in derselben Spalte; fehlt dort eine Kachel, die letzte
    assert.equal(bewegen(1, 0, 1, 8, 5), 6);
    assert.equal(bewegen(4, 0, 1, 8, 5), 7);
    // In der letzten Zeile bleibt Runter stehen, in der ersten Hoch
    assert.equal(bewegen(6, 0, 1, 8, 5), 6);
    assert.equal(bewegen(2, 0, -1, 8, 5), 2);
    // Hoch in derselben Spalte
    assert.equal(bewegen(7, 0, -1, 8, 5), 2);
    // Ausserhalb liegende Auswahl wird zuerst begrenzt
    assert.equal(bewegen(42, 0, 0, 8, 5), 7);
    assert.equal(bewegen(-1, 0, 0, 8, 5), 0);
    // Eine Spalte: Hoch und Runter wie Links und Rechts
    assert.equal(bewegen(1, 0, 1, 3, 1), 2);
    assert.equal(bewegen(1, 0, -1, 3, 1), 0);
    // Keine Kacheln
    assert.equal(bewegen(0, 1, 0, 0, 5), -1);
});

// --- Schreibtisch ---------------------------------------------------------------------------------------

// Minimiert in der Reihenfolge der Liste (wie der Dienst) und gibt sie zurück
function minimieren(liste, wert) {
    for (const t of liste)
        t.minimized = wert;
    return liste;
}

test("Schreibtisch: sichtbar sind nur App-Fenster, die nicht minimiert sind", () => {
    const a = fenster("kitty");
    const b = fenster("google-chrome", "", true);
    const voll = Object.assign(fenster("mpv"), { fullscreen: true });
    const e = fenster("org.quickshell", "Einstellungen");
    assert.deepEqual(sichtbare([a, b, null, voll, e]), [a, voll]);
    assert.deepEqual(sichtbare(null), []);
    assert.deepEqual(sichtbare({ length: 1, 0: a }), [a]);
});

test("Schreibtisch: ohne App-Fenster passiert nichts", () => {
    assert.equal(entscheiden([], []), "nichts");
    assert.equal(entscheiden(null, null), "nichts");
    // Nur die Einstellungen offen: auch nichts
    assert.equal(entscheiden([fenster("org.quickshell")], []), "nichts");
    // Nur von Hand minimierte Fenster: nichts (sie bleiben unten)
    assert.equal(entscheiden([fenster("kitty", "", true)], []), "nichts");
    assert.equal(frei([fenster("kitty", "", true)], []), false);
});

test("Schreibtisch: zeigen und zurück, von Hand minimierte bleiben unten", () => {
    const a = fenster("kitty", "a");
    const b = fenster("google-chrome", "b");
    const c = fenster("code", "c");
    const vonHand = fenster("coremail", "von Hand", true);
    const e = fenster("org.quickshell", "Einstellungen");
    const offen = [a, vonHand, b, c, e];
    // c ist aktiv, davor b, dann a
    const verlauf = [c, b, a];
    assert.equal(entscheiden(offen, []), "zeigen");
    assert.equal(frei(offen, []), false);

    const merker = merken(offen, verlauf);
    // Von unten nach oben: das aktive zuletzt; das von Hand minimierte und die Einstellungen fehlen
    assert.deepEqual(merker, [a, b, c]);
    minimieren(merker, true);
    assert.equal(frei(offen, merker), true);
    assert.equal(entscheiden(offen, merker), "zurueck");
    // Die Einstellungen bleiben stehen und zählen nicht
    assert.equal(e.minimized, false);

    const zurueck = zurueckReihenfolge(merker, offen);
    assert.deepEqual(zurueck, [a, b, c]);
    minimieren(zurueck, false);
    assert.equal(vonHand.minimized, true);
    assert.equal(frei(offen, merker), false);
    // Danach minimiert Super+H wieder alles Sichtbare, ohne das von Hand minimierte
    assert.equal(entscheiden(offen, merker), "zeigen");
    assert.deepEqual(merken(offen, verlauf), [a, b, c]);
});

test("Schreibtisch: geschlossene Fenster fallen aus dem Merker", () => {
    const a = fenster("kitty");
    const b = fenster("code");
    const merker = minimieren(merken([a, b], [b, a]), true);
    assert.deepEqual(merker, [a, b]);
    // b wird geschlossen, während der Schreibtisch frei ist
    assert.deepEqual(nochOffen(merker, [a]), [a]);
    assert.deepEqual(zurueckReihenfolge(merker, [a]), [a]);
    assert.equal(frei([a], merker), true);
    // Auch a geschlossen: nichts mehr zurückzuholen
    assert.deepEqual(zurueckReihenfolge(merker, []), []);
    assert.equal(frei([], merker), false);
    assert.equal(entscheiden([], merker), "nichts");
    // Doppelte und leere Einträge im Merker zählen einmal bzw. nicht
    assert.deepEqual(nochOffen([a, null, a], [a]), [a]);
    assert.deepEqual(nochOffen(null, [a]), []);
});

test("Schreibtisch: ein sichtbares Fenster beendet «frei», Super+H minimiert dann mit neuem Merker", () => {
    const a = fenster("kitty");
    const b = fenster("code");
    const merker = minimieren(merken([a, b], [b, a]), true);
    assert.equal(frei([a, b], merker), true);
    // b über App-Leiste, Alt+Tab oder Übersicht zurückgeholt
    b.minimized = false;
    assert.equal(frei([a, b], merker), false);
    assert.equal(entscheiden([a, b], merker), "zeigen");
    assert.deepEqual(merken([a, b], [b, a]), [b]);
    // Ein neues Fenster erscheint, während der Schreibtisch frei ist
    b.minimized = true;
    const neu = fenster("google-chrome");
    assert.equal(frei([a, b, neu], merker), false);
    assert.equal(entscheiden([a, b, neu], merker), "zeigen");
    assert.deepEqual(merken([a, b, neu], [neu, b, a]), [neu]);
});

test("Schreibtisch: eine Aktivierung allein ändert nichts", () => {
    // labwc aktiviert beim Minimieren kurz das nächste Fenster: frei hängt nur an der Lage der Fenster
    const a = fenster("kitty");
    const b = fenster("code");
    const merker = minimieren(merken([a, b], [b, a]), true);
    const verlauf = verlaufNachfuehren([b, a], a, [a, b]);
    assert.deepEqual(verlauf, [a, b]);
    assert.equal(frei([a, b], merker), true);
    assert.equal(entscheiden([a, b], merker), "zurueck");
});

test("Schreibtisch: Reihenfolge von unten nach oben über den Verlauf", () => {
    const a = fenster("kitty");
    const b = fenster("code");
    const c = fenster("google-chrome");
    const d = fenster("mpv");
    // Fenster ohne Verlauf (z. B. nach dem Neuladen der Oberfläche) zuunterst in ihrer Reihenfolge
    assert.deepEqual(vonUntenNachOben([a, b, c, d], [c, a]), [b, d, a, c]);
    // Verlauf mit geschlossenen, doppelten oder leeren Einträgen
    assert.deepEqual(vonUntenNachOben([a, b], [fenster("weg"), b, null, b, a]), [a, b]);
    assert.deepEqual(vonUntenNachOben([a, a, b], null), [a, b]);
    assert.deepEqual(vonUntenNachOben(null, [a]), []);
    // Ein Vollbild-Fenster wird wie jedes andere gemerkt
    const voll = Object.assign(fenster("mpv", "Film"), { fullscreen: true });
    assert.deepEqual(merken([a, voll], [voll, a]), [a, voll]);
});
