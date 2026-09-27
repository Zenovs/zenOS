// Suche im Befehlsfeld ohne QML: Bewertung von Treffern, Argumente für die Dateisuche und die
// lokale Nutzungsstatistik. Getestet mit node (test/einheiten/suche.test.mjs).

// Kleinbuchstaben, ohne Akzente, ß → ss («Über» → «uber»)
export function normalisieren(text) {
    if (typeof text !== "string")
        return "";
    return text.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/ß/g, "ss").trim();
}

// Suchwörter einer Eingabe (normalisiert, ohne leere)
export function woerter(anfrage) {
    return normalisieren(anfrage).split(/\s+/).filter(w => w.length > 0);
}

function wortgrenze(text, index) {
    return index === 0 || !/[a-z0-9]/.test(text[index - 1]);
}

// Bewertung eines Suchworts in einem (normalisierten) Text:
// 100 Präfix, 80 Wortanfang, 60 enthalten (erst ab 3 Zeichen, sonst zu viel Rauschen), 0 kein Treffer
export function wortBewerten(text, wort) {
    if (!text || !wort)
        return 0;
    if (text.startsWith(wort))
        return 100;
    let index = text.indexOf(wort, 1);
    let enthalten = false;
    while (index > 0) {
        if (wortgrenze(text, index))
            return 80;
        enthalten = true;
        index = text.indexOf(wort, index + 1);
    }
    return enthalten && wort.length >= 3 ? 60 : 0;
}

// Bewertet einen Eintrag mit mehreren Feldern [{text, gewicht}] (Texte normalisiert).
// Jedes Suchwort muss in einem Feld vorkommen; sonst 0. Ganze Eingabe als Präfix des ersten Felds: +10.
export function bewerten(felder, anfrage) {
    const liste = woerter(anfrage);
    if (liste.length === 0 || !Array.isArray(felder) || felder.length === 0)
        return 0;
    let summe = 0;
    for (const wort of liste) {
        let bestes = 0;
        for (const feld of felder) {
            if (!feld || !feld.text)
                continue;
            const wert = wortBewerten(feld.text, wort) * (feld.gewicht ?? 1);
            if (wert > bestes)
                bestes = wert;
        }
        if (bestes === 0)
            return 0;
        summe += bestes;
    }
    const ganz = liste.join(" ");
    const bonus = felder[0] && felder[0].text && felder[0].text.startsWith(ganz) ? 10 : 0;
    return summe / liste.length + bonus;
}

// Name des Programms aus einem Exec-Befehl («/usr/bin/firefox %u» → «firefox»)
export function programmName(befehl) {
    const erstes = Array.isArray(befehl) ? befehl[0] : (typeof befehl === "string" ? befehl.trim().split(/\s+/)[0] : "");
    if (!erstes)
        return "";
    const teile = erstes.split("/");
    return teile[teile.length - 1];
}

// Sortiert Treffer [{punkte, name, …}] absteigend nach Punkten, dann kürzerer Name, dann alphabetisch
export function sortieren(treffer) {
    return treffer.slice().sort((a, b) => {
        if (b.punkte !== a.punkte)
            return b.punkte - a.punkte;
        const la = (a.name ?? "").length;
        const lb = (b.name ?? "").length;
        if (la !== lb)
            return la - lb;
        return (a.name ?? "").localeCompare(b.name ?? "", "de");
    });
}

// --- Dateisuche -----------------------------------------------------------------

// Ordner, die die Dateisuche nie betritt (neben allen versteckten)
export const DATEISUCHE_AUSGESCHLOSSEN = ["node_modules", "__pycache__", "snap"];

// Glob-Zeichen maskieren, damit die Eingabe für find nur Text ist
export function globMaskieren(text) {
    return text.replace(/[\\*?[\]]/g, "\\$&");
}

// Argumentliste für find (nie über eine Shell). null, wenn die Eingabe zu kurz ist.
// Sucht im Home-Ordner nach Namen, die alle Wörter enthalten; versteckte und ausgeschlossene Ordner aus.
// Ausgabe je Treffer: «<Typ>\t<Pfad>\0» (Typ d = Ordner, f = Datei).
export function findArgumente(home, anfrage, tiefe) {
    const text = typeof anfrage === "string" ? anfrage.trim() : "";
    if (!home || !home.startsWith("/") || text.length < 2)
        return null;
    const teile = text.split(/[\s/]+/).filter(w => w.length > 0);
    if (teile.length === 0)
        return null;
    const args = ["find", home, "-xdev", "-mindepth", "1", "-maxdepth", String(tiefe > 0 ? tiefe : 5), "("];
    args.push("-name", ".*");
    for (const name of DATEISUCHE_AUSGESCHLOSSEN)
        args.push("-o", "-name", name);
    args.push(")", "-prune", "-o", "(", "-type", "f", "-o", "-type", "d", ")");
    for (const teil of teile)
        args.push("-iname", "*" + globMaskieren(teil) + "*");
    args.push("-printf", "%y\\t%p\\0");
    return args;
}

// Eine Zeile der find-Ausgabe → {ordner, pfad, name, tiefe} oder null
export function findZeile(zeile, home) {
    if (typeof zeile !== "string")
        return null;
    const tab = zeile.indexOf("\t");
    if (tab !== 1)
        return null;
    const typ = zeile[0];
    const pfad = zeile.slice(tab + 1);
    if ((typ !== "d" && typ !== "f") || !pfad.startsWith(home + "/"))
        return null;
    const relativ = pfad.slice(home.length + 1);
    const teile = relativ.split("/");
    return { ordner: typ === "d", pfad, name: teile[teile.length - 1], tiefe: teile.length };
}

// Passt ein Dateiname noch zur Eingabe? (wie find -iname: jedes Wort ist enthalten, ohne Gross/klein)
// Damit bleiben Treffer der vorigen Eingabe sichtbar, bis die neue Suche fertig ist.
export function dateiPasst(name, anfrage) {
    const klein = typeof name === "string" ? name.toLowerCase() : "";
    const teile = (typeof anfrage === "string" ? anfrage : "").toLowerCase().split(/[\s/]+/).filter(w => w.length > 0);
    return teile.length > 0 && teile.every(w => klein.includes(w));
}

// Steuerzeichen (z. B. Zeilenumbrüche in Dateinamen) für die einzeilige Anzeige ersetzen
export function einzeilig(text) {
    return typeof text === "string" ? text.replace(/[\u0000-\u001f\u007f]/g, "?") : "";
}

// Pfad für die Anzeige: Home als «~», der Name selbst steht schon im Titel
export function pfadAnzeige(pfad, home) {
    const ordner = pfad.slice(0, pfad.lastIndexOf("/"));
    if (ordner === home)
        return "~";
    return ordner.startsWith(home + "/") ? "~" + ordner.slice(home.length) : ordner;
}

// Dateitreffer ordnen: Bewertung des Namens, dann geringere Tiefe, dann kürzerer Name
export function dateienSortieren(treffer, anfrage) {
    return treffer.map(t => ({ t, p: bewerten([{ text: normalisieren(t.name), gewicht: 1 }], anfrage) }))
        .sort((a, b) => b.p - a.p || a.t.tiefe - b.t.tiefe || a.t.name.length - b.t.name.length || a.t.name.localeCompare(b.t.name, "de") || (a.t.pfad < b.t.pfad ? -1 : a.t.pfad > b.t.pfad ? 1 : 0))
        .map(x => x.t);
}

// --- Nutzungsstatistik ----------------------------------------------------------
// Nur App-IDs (Namen der Desktop-Dateien) und Zähler, dazu die Reihenfolge der zuletzt
// genutzten. Keine Zeiten, keine Fenstertitel. Datei: ~/.local/share/zenos/befehlsfeld.json

const MAX_APPS = 200;
const MAX_ZULETZT = 20;
const MAX_ZAEHLER = 1000;

export function nutzungLeer() {
    return { version: 1, anzahl: {}, zuletzt: [] };
}

// Geprüfte Kopie der gelesenen Daten (fremde oder kaputte Werte fallen weg)
export function nutzungPruefen(daten) {
    const ergebnis = nutzungLeer();
    if (daten === null || typeof daten !== "object")
        return ergebnis;
    const anzahl = daten.anzahl;
    if (anzahl !== null && typeof anzahl === "object" && !Array.isArray(anzahl)) {
        for (const id of Object.keys(anzahl)) {
            const n = anzahl[id];
            if (gueltigeAppId(id) && Number.isInteger(n) && n > 0)
                ergebnis.anzahl[id] = Math.min(n, MAX_ZAEHLER);
        }
    }
    if (Array.isArray(daten.zuletzt))
        ergebnis.zuletzt = daten.zuletzt.filter(id => gueltigeAppId(id) && ergebnis.anzahl[id] !== undefined).filter((id, i, a) => a.indexOf(id) === i).slice(0, MAX_ZULETZT);
    return ergebnis;
}

export function gueltigeAppId(id) {
    return typeof id === "string" && id.length > 0 && id.length <= 255 && !/[\/\u0000-\u001f]/.test(id);
}

// Start einer App zählen; gibt neue Daten zurück
export function nutzungMerken(daten, id) {
    const neu = nutzungPruefen(daten);
    if (!gueltigeAppId(id))
        return neu;
    neu.anzahl[id] = (neu.anzahl[id] ?? 0) + 1;
    // Alterung: Werden die Zähler gross, zählt Jüngeres wieder mehr
    if (neu.anzahl[id] >= MAX_ZAEHLER) {
        for (const k of Object.keys(neu.anzahl)) {
            const halb = Math.floor(neu.anzahl[k] / 2);
            if (halb > 0)
                neu.anzahl[k] = halb;
            else
                delete neu.anzahl[k];
        }
    }
    neu.zuletzt = [id].concat(neu.zuletzt.filter(x => x !== id)).filter(x => neu.anzahl[x] !== undefined).slice(0, MAX_ZULETZT);
    const ids = Object.keys(neu.anzahl);
    if (ids.length > MAX_APPS) {
        const behalten = new Set(neu.zuletzt);
        ids.filter(x => !behalten.has(x)).sort((a, b) => neu.anzahl[a] - neu.anzahl[b]).slice(0, ids.length - MAX_APPS).forEach(x => delete neu.anzahl[x]);
    }
    return neu;
}

// Gewicht einer App für Vorschläge: Zähler plus Bonus für die zuletzt genutzten
export function nutzungGewicht(daten, id) {
    const n = daten?.anzahl?.[id] ?? 0;
    const rang = Array.isArray(daten?.zuletzt) ? daten.zuletzt.indexOf(id) : -1;
    return n + (rang >= 0 ? Math.max(0, 10 - 2 * rang) : 0);
}

// App-IDs für Vorschläge bei leerem Feld, beste zuerst
export function nutzungRangliste(daten) {
    const d = nutzungPruefen(daten);
    return Object.keys(d.anzahl).sort((a, b) => nutzungGewicht(d, b) - nutzungGewicht(d, a) || a.localeCompare(b));
}

// Kleiner Vorteil für oft genutzte Apps bei der Suche (höchstens 10 Punkte)
export function nutzungBonus(daten, id) {
    return Math.min(10, nutzungGewicht(daten, id) / 2);
}
