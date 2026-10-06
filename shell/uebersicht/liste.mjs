// Fensterübersicht ohne QML: Einträge bilden, filtern, Startauswahl, Bildschirm, Spalten und Bewegen im Raster.
// Nutzt die Gruppierung der App-Leiste (appleiste/fenster.mjs) und die Bewertung des Befehlsfelds
// (befehlsfeld/suche.mjs). Getestet mit node (test/einheiten/uebersicht.test.mjs).
// Fenster sind Toplevel-Objekte aus Quickshell (in den Tests {appId, title}); verglichen wird nur ihre Identität.
import * as Fenster from "../appleiste/fenster.mjs";
import * as Suche from "../befehlsfeld/suche.mjs";

// Einträge in der Reihenfolge der App-Leiste: Apps nach ihrem ersten Fenster, die Fenster einer App nebeneinander
// in der Reihenfolge ihres Erscheinens. Nichts springt, wenn ein anderes Fenster aktiv wird.
// gruppen: Gruppen wie in der App-Leiste [{schluessel, appId, name, symbol, buchstabe, fenster: [Toplevel]}]
// Ergebnis: [{fenster: Toplevel, app: Gruppe}]
export function eintraege(gruppen) {
    const liste = [];
    for (const g of Fenster.alsListe(gruppen)) {
        for (const t of Fenster.alsListe(g?.fenster)) {
            if (!t)
                continue;
            liste.push({ fenster: t, app: g });
        }
    }
    return liste;
}

// Filtern nach App-Name, Titel und appId (bewertet wie im Befehlsfeld). Die Reihenfolge bleibt erhalten.
// titelSuchen: false während einer Bildschirmfreigabe (die Titel sind dann verborgen und zählen nicht).
export function filtern(liste, anfrage, titelSuchen) {
    const alle = Fenster.alsListe(liste);
    if (Suche.woerter(anfrage).length === 0)
        return alle;
    return alle.filter(e => Suche.bewerten([
        { text: Suche.normalisieren(e?.app?.name ?? ""), gewicht: 1 },
        { text: titelSuchen ? Suche.normalisieren(e?.fenster?.title ?? "") : "", gewicht: 0.9 },
        { text: Suche.normalisieren(e?.app?.appId ?? ""), gewicht: 0.6 }
    ], anfrage) > 0);
}

// Startauswahl: das zuletzt aktive Fenster ausser dem aktiven. Super+Tab und dann ↵ führt so zurück zum vorigen
// Fenster wie Alt+Tab. verlauf: zuletzt aktiv zuerst. Ohne passendes Fenster im Verlauf das erste; -1 ohne Einträge.
export function startIndex(liste, aktiv, verlauf) {
    const alle = Fenster.alsListe(liste);
    for (const f of Fenster.alsListe(verlauf)) {
        if (!f || f === aktiv)
            continue;
        const i = alle.findIndex(e => e?.fenster === f);
        if (i >= 0)
            return i;
    }
    return alle.length > 0 ? 0 : -1;
}

// Bildschirm mit Tastatur, Filter und Kacheln beim Öffnen: der des aktiven Fensters, wenn es ihn gibt, sonst der
// erste. Leer ohne Bildschirm. namen: Namen der Bildschirme in ihrer Reihenfolge (Quickshell.screens).
export function hauptBildschirm(gewuenscht, namen) {
    const liste = Fenster.alsListe(namen).map(n => String(n ?? "")).filter(n => n !== "");
    const name = String(gewuenscht ?? "");
    if (name !== "" && liste.indexOf(name) >= 0)
        return name;
    return liste.length > 0 ? liste[0] : "";
}

// Haben sich die Bildschirme geändert, seit die Übersicht aufging (abgesteckt, angesteckt, Ausgang aus oder an)? Dann
// geht sie zu. Fiel ihr Bildschirm weg, blieb sie auf den anderen ohne Tastatur offen, und Getipptes ging ungesehen an
// das Fenster dahinter. Kommt einer dazu, bekäme er nur die zugedeckte Fläche; neu geöffnet richtet sie sich nach der
// neuen Lage (kanshi stellt dabei oft mehrere Ausgänge zugleich um). Es zählt nur, welche Bildschirme es gibt, nicht
// ihre Reihenfolge, Lage oder Grösse.
export function bildschirmeGeaendert(vorher, jetzt) {
    const menge = namen => Fenster.alsListe(namen).map(n => String(n ?? "")).filter(n => n !== "").sort().join("\n");
    return menge(vorher) !== menge(jetzt);
}

// Höchstens so viele Spalten passen in die Breite: Kacheln mit Lücke dazwischen, links und rechts je ein Rand.
// Mindestens 1.
export function spaltenMax(breite, kachelBreite, luecke, rand) {
    const platz = Number(breite) - 2 * Number(rand) + Number(luecke);
    const je = Number(kachelBreite) + Number(luecke);
    if (!(platz > 0) || !(je > 0))
        return 1;
    return Math.max(1, Math.floor(platz / je));
}

// Spalten für n Kacheln: so wenige Zeilen wie möglich, die Zeilen ausgeglichen (10 Kacheln bei höchstens 7
// Spalten ergeben 5×2, nicht 7 und 3). Mindestens 1.
export function spalten(n, max) {
    if (!(n > 0))
        return 1;
    const m = Math.max(1, Math.floor(Number(max)) || 1);
    const zeilen = Math.ceil(n / m);
    return Math.max(1, Math.ceil(n / zeilen));
}

// Auswahl bewegen wie im App-Raster: dx über Zeilen hinweg (an den Enden bleibt sie stehen), dy zeilenweise
// in derselben Spalte (unter der letzten Zeile ohne Kachel an dieser Stelle: die letzte Kachel). -1 ohne Kacheln.
// i: aktuelle Auswahl, n: Anzahl Kacheln, sp: Spalten
export function bewegen(i, dx, dy, n, sp) {
    if (!(n > 0))
        return -1;
    const s = Math.max(1, sp);
    let j = Math.max(0, Math.min(n - 1, i));
    if (dx !== 0)
        j = Math.max(0, Math.min(n - 1, j + dx));
    if (dy > 0) {
        const zeile = Math.min(Math.floor((n - 1) / s), Math.floor(j / s) + dy);
        j = Math.min(n - 1, zeile * s + j % s);
    } else if (dy < 0) {
        j = Math.max(0, Math.floor(j / s) + dy) * s + j % s;
    }
    return j;
}
