.pragma library
// Logik des Update-Kanals in der Oberfläche (dienste/Kanal.qml) ohne QML: stand.json, letzte.json und den Zeitpunkt
// lesen, die Texte für Einstellungen › System › Updates, die Mitteilungen (jede nur einmal je Zustand) und die
// Argumentlisten für den Helfer. Getestet mit test/einheiten/kanal.test.mjs (node).
//
// Quellen (alle von root geschrieben, für alle lesbar; die Oberfläche liest nur):
//   /var/lib/zenos/kanal/stand.json   letzte Prüfung (zenos-kanal pruefen; Felder in docs/image-und-releases.md)
//   /var/lib/zenos/kanal/letzte.json  letzte Installation über den Kanal (installiert, zurueck, gescheitert, kaputt …)
//   /etc/xdg/zenos/kanal-zeitpunkt    Zeitpunkt automatischer Updates (zenos-kanal zeitpunkt; dieselben Regeln wie
//                                     parse_schedule dort, test/einheiten/kanal.test.mjs gleicht die Fälle ab)
// Alles, was angezeigt wird, ist reiner Text; Steuer- und unsichtbare Zeichen werden ersetzt.

var ZEITPUNKTE = Object.freeze(["sperre", "fenster", "jederzeit", "hand"]);
var FENSTER_STANDARD = Object.freeze({ von: "02:00", bis: "05:00" });
var FENSTER_MIN_MINUTEN = 60;
// Ohne Kontakt zu origin so lange: einmal eine Mitteilung
var KONTAKT_TAGE = 14;
// Ein «installiert», das älter ist, meldet die Oberfläche nicht mehr (etwa beim ersten Start nach Tagen). Gescheitert,
// zurück, abgebrochen und kaputt melden sich immer genau einmal, auch nach einem langen Wochenende.
var ERGEBNIS_FRISCH_MS = 24 * 3600 * 1000;
// Akku: so viel Ladung braucht ein automatisches Update im Akkubetrieb (MIN_BATTERY in zenos-kanal)
var AKKU_MIN_PROZENT = 50;
// Gemerkte abgelehnte Tags (je Name einmal gemeldet)
var ABGELEHNT_MERKEN = 50;

var ZUSTAENDE = Object.freeze(["aktuell", "bereit", "zustimmung", "dev", "anker_fehlt", "blockiert", "kein_kontakt", "fehler"]);
var KANAELE = Object.freeze(["stabil", "vorschau", "dev"]);
var ERGEBNISSE = Object.freeze(["installiert", "zurueck", "gescheitert", "kaputt", "fehler", "wartet", "abgelehnt", "nichts", "unterbrochen"]);
// Lage der Installation (installation_summary in zenos-kanal, Feld installation_lage in stand.json)
var LAGEN = Object.freeze(["unterbrochen", "kaputt", "angehalten", "zurueck", "gescheitert", "fehler", "unbestaetigt", "gut", "keine"]);
// Ergebnisse, die als «Letztes Update» stehen bleiben, bis eine spätere Installation sie ablöst
var PROBLEME = Object.freeze(["kaputt", "zurueck", "gescheitert", "fehler"]);
var ERGEBNIS_TEXT = Object.freeze({
    kaputt: "kaputt",
    zurueck: "gescheitert, zurück auf dem Stand davor",
    gescheitert: "gescheitert",
    fehler: "abgebrochen"
});

var OBJEKT_RE = /^[0-9a-f]{40}$/;
var ZEIT_RE = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/;
var UHRZEIT_RE = /^([01][0-9]|2[0-3]):([0-5][0-9])$/;
var VERSION_RE = /^v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(?:-rc([1-9][0-9]{0,8}))?$/;
var TAG_RE = /^[A-Za-z0-9][A-Za-z0-9._\/-]{0,99}$/;
var FINGERABDRUCK_RE = /^SHA256:[A-Za-z0-9+\/]{43}$/;
// Steuerzeichen, Zeichen ohne Breite, Richtungs- und Trennzeichen
var UNSICHTBAR = /[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u115f\u1160\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]/g;

var MONATE = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."];

// --- Lesen --------------------------------------------------------------------

// Reiner, kurzer Text: unsichtbare Zeichen werden «?», Leerraum zusammengefasst, höchstens max Zeichen (dann «…»)
function text(wert, max) {
    if (typeof wert !== "string")
        return "";
    var t = wert.replace(/[\t\n\r]+/g, " ").replace(UNSICHTBAR, "?").replace(/ {2,}/g, " ").trim();
    var n = typeof max === "number" && max > 1 ? max : 400;
    return t.length > n ? t.slice(0, n - 1) + "…" : t;
}

// Zeitpunkt «2026-10-05T12:00:00Z» (wie zenos-kanal iso()) als ms, sonst NaN
function zeitMs(wert) {
    if (typeof wert !== "string" || !ZEIT_RE.test(wert))
        return NaN;
    return Date.parse(wert);
}

function _objekt(json) {
    if (typeof json !== "string" || json.trim() === "")
        return null;
    try {
        var daten = JSON.parse(json);
        return daten !== null && typeof daten === "object" && !Array.isArray(daten) ? daten : null;
    } catch (e) {
        return null;
    }
}

function _commit(wert) {
    return typeof wert === "string" && OBJEKT_RE.test(wert) ? wert : "";
}

function _version(wert) {
    return typeof wert === "string" && VERSION_RE.test(wert) ? wert : "";
}

function _tag(wert) {
    return typeof wert === "string" && TAG_RE.test(wert) ? wert : "";
}

function _liste(wert, max, umwandeln) {
    if (!Array.isArray(wert))
        return [];
    var aus = [];
    for (var i = 0; i < wert.length && aus.length < max; i++) {
        var x = umwandeln(wert[i]);
        if (x !== null && x !== "")
            aus.push(x);
    }
    return aus;
}

// Ziel einer Installation (gut.json, letzte.json: ziel) als { commit, tag, version, zweig }
function _ziel(wert) {
    if (!wert || typeof wert !== "object")
        return null;
    var commit = _commit(wert.commit);
    if (commit === "")
        return null;
    return {
        commit: commit,
        tag: _tag(wert.tag),
        version: _version(wert.version),
        zweig: typeof wert.zweig === "string" && TAG_RE.test(wert.zweig) ? wert.zweig : ""
    };
}

// stand.json (Version 1) geprüft und vereinfacht, null wenn sie fehlt oder unbrauchbar ist
function standLesen(json) {
    var d = _objekt(json);
    if (d === null || d.version !== 1)
        return null;
    var zustand = ZUSTAENDE.indexOf(d.zustand) >= 0 ? d.zustand : "fehler";
    var anker = null;
    if (d.anker && typeof d.anker === "object" && FINGERABDRUCK_RE.test(d.anker.wurzel)) {
        anker = {
            serie: typeof d.anker.serie === "number" && d.anker.serie >= 1 && d.anker.serie <= 9999 ? Math.floor(d.anker.serie) : 0,
            wurzel: d.anker.wurzel,
            release: _liste(d.anker.release, 8, function (f) {
                return FINGERABDRUCK_RE.test(f) ? f : null;
            }),
            widerrufen: _liste(d.anker.widerrufen, 64, function (f) {
                return FINGERABDRUCK_RE.test(f) ? f : null;
            })
        };
    }
    var installiert = null;
    if (d.installiert && typeof d.installiert === "object" && _commit(d.installiert.commit) !== "")
        installiert = { commit: d.installiert.commit, version: _version(d.installiert.version) };
    var bereit = null;
    var b = d.bereit;
    if (b && typeof b === "object" && _version(b.version) !== "" && _commit(b.commit) !== "" && _commit(b.objekt) !== "") {
        bereit = {
            version: b.version,
            commit: b.commit,
            objekt: b.objekt,
            freiAbMs: zeitMs(b.frei_ab),
            // false: noch in der Wartezeit (stabil 24 h, nur mit synchronisierter Uhr); ältere stand.json ohne Feld: ja
            frei: b.frei !== false,
            // null: Vergleich nicht möglich (dann braucht es ebenfalls die Zustimmung)
            rueckfrage: Array.isArray(b.rueckfrage) ? _liste(b.rueckfrage, 50, function (p) {
                return text(p, 120) || null;
            }) : null
        };
    }
    var dev = null;
    if (d.dev && typeof d.dev === "object" && _commit(d.dev.commit) !== "") {
        dev = {
            commit: d.dev.commit,
            neu: d.dev.neu === true,
            signiert: d.dev.signiert === true,
            brauchtJa: d.dev.braucht_ja !== false,
            commits: typeof d.dev.commits === "number" && d.dev.commits >= 0 ? Math.floor(d.dev.commits) : -1
        };
    }
    // Automatisch installiert, wartet auf die Bestätigung nach einem Neustart (unbestaetigt.json)
    var unbestaetigt = null;
    if (d.unbestaetigt && typeof d.unbestaetigt === "object" && _commit(d.unbestaetigt.commit) !== "")
        unbestaetigt = { commit: d.unbestaetigt.commit, version: _version(d.unbestaetigt.version), seitMs: zeitMs(d.unbestaetigt.seit) };
    // Nach «zen rollback» für die Automatik zurückgestellt (zurueckgestellt.json)
    var zurueckgestellt = null;
    if (d.zurueckgestellt && typeof d.zurueckgestellt === "object" && _version(d.zurueckgestellt.version) !== "")
        zurueckgestellt = { version: d.zurueckgestellt.version, seitMs: zeitMs(d.zurueckgestellt.seit) };
    // Stand von Hand (install.sh aus einem Arbeitsstand): Die Automatik ruht bis zen update
    var angehalten = null;
    if (d.angehalten && typeof d.angehalten === "object")
        angehalten = { commit: _commit(d.angehalten.commit), seitMs: zeitMs(d.angehalten.seit) };
    // Lage der Installation zur Zeit der Prüfung; null in älteren stand.json
    var installationLage = null;
    if (d.installation_lage && typeof d.installation_lage === "object" && LAGEN.indexOf(d.installation_lage.schluessel) >= 0)
        installationLage = { schluessel: d.installation_lage.schluessel, text: text(d.installation_lage.text, 400) };
    // Antwort auf den Wunsch dieser Prüfung (zen update, «Jetzt installieren», Automatik), für die Rückmeldung
    var wunsch = null;
    if (d.wunsch && typeof d.wunsch === "object" && typeof d.wunsch.ergebnis === "string")
        wunsch = { ergebnis: text(d.wunsch.ergebnis, 40), grund: text(d.wunsch.grund, 300) };
    return {
        kanal: KANAELE.indexOf(d.kanal) >= 0 ? d.kanal : "",
        // Notschalter (sudo zen kanal automatik aus); ohne Angabe (ältere stand.json) gilt an
        automatikAn: !(d.automatik && typeof d.automatik === "object" && d.automatik.an === false),
        unbestaetigt: unbestaetigt,
        zurueckgestellt: zurueckgestellt,
        angehalten: angehalten,
        installationLage: installationLage,
        wunsch: wunsch,
        zustand: zustand,
        grund: text(d.grund, 400),
        geprueftMs: zeitMs(d.geprueft),
        kontaktMs: zeitMs(d.letzter_kontakt),
        holenFehler: text(d.holen_fehler, 160),
        anker: anker,
        ankerProblem: text(d.anker_problem, 160),
        installiert: installiert,
        hoechste: _version(d.hoechste),
        bereit: bereit,
        dev: dev,
        gueltig: _liste(d.gueltig, 200, function (v) {
            return _version(v) || null;
        }),
        abgelehnt: _liste(d.abgelehnt, 100, function (e) {
            return e && typeof e === "object" && _tag(e.tag) !== "" ? { tag: e.tag, grund: text(e.grund, 160) } : null;
        })
    };
}

// letzte.json: { ergebnis, grund, endeMs, ziel } oder null
function letzteLesen(json) {
    var d = _objekt(json);
    if (d === null || d.version !== 1 || ERGEBNISSE.indexOf(d.ergebnis) < 0)
        return null;
    return { ergebnis: d.ergebnis, grund: text(d.grund, 400), endeMs: zeitMs(d.ende), ziel: _ziel(d.ziel) };
}

// Minuten seit Mitternacht aus «HH:MM» (streng), sonst -1
function minuten(uhrzeit) {
    var m = typeof uhrzeit === "string" ? UHRZEIT_RE.exec(uhrzeit) : null;
    return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
}

// Grund, warum das Zeitfenster nicht gilt, sonst "" (wie window_problem in zenos-kanal)
function fensterProblem(von, bis) {
    var a = minuten(von), b = minuten(bis);
    if (a < 0 || b < 0)
        return "Uhrzeiten als HH:MM, etwa 02:00";
    if (((b - a) % 1440 + 1440) % 1440 < FENSTER_MIN_MINUTEN)
        return "Das Zeitfenster muss mindestens " + FENSTER_MIN_MINUTEN + " Minuten lang sein";
    return "";
}

// /etc/xdg/zenos/kanal-zeitpunkt wie parse_schedule in zenos-kanal: { art, von, bis, problem, seit, ueber }. Fehlt die
// Datei (json null oder leer), gilt «sperre» ohne Problem; ist sie ungültig, ebenfalls «sperre», mit Problem.
// von und bis sind immer gesetzt (bei «fenster» die gültigen, sonst der Standard fürs Formular).
function zeitpunktLesen(inhalt) {
    var standard = { art: "sperre", von: FENSTER_STANDARD.von, bis: FENSTER_STANDARD.bis, problem: "", seit: "", ueber: "" };
    if (typeof inhalt !== "string" || inhalt.trim() === "")
        return standard;
    var werte = {};
    var zeilen = inhalt.split("\n");
    for (var i = 0; i < zeilen.length; i++) {
        var zeile = zeilen[i].trim();
        if (zeile === "" || zeile.charAt(0) === "#")
            continue;
        var gleich = zeile.indexOf("=");
        if (gleich < 0) {
            standard.problem = "Zeile ohne «schluessel=wert»";
            return standard;
        }
        var schluessel = zeile.slice(0, gleich).trim();
        if (["zeitpunkt", "von", "bis", "seit", "ueber"].indexOf(schluessel) >= 0)
            werte[schluessel] = zeile.slice(gleich + 1).trim();
    }
    // Wann und über welchen Weg gesetzt (nur zur Anzeige in der Mitteilung, wenn es nicht die Einstellungen waren)
    var seit = typeof werte.seit === "string" && ZEIT_RE.test(werte.seit) ? werte.seit : "";
    var ueber = text(werte.ueber || "", 40);
    standard.seit = seit;
    standard.ueber = ueber;
    if (ZEITPUNKTE.indexOf(werte.zeitpunkt) < 0) {
        standard.problem = "unbekannter Zeitpunkt";
        return standard;
    }
    if (werte.zeitpunkt !== "fenster")
        return { art: werte.zeitpunkt, von: FENSTER_STANDARD.von, bis: FENSTER_STANDARD.bis, problem: "", seit: seit, ueber: ueber };
    var problem = fensterProblem(werte.von, werte.bis);
    if (problem !== "") {
        standard.problem = problem;
        return standard;
    }
    return { art: "fenster", von: werte.von, bis: werte.bis, problem: "", seit: seit, ueber: ueber };
}

// --- Versionen ----------------------------------------------------------------

// [X, Y, Z, final, rc] zum Vergleichen (vX.Y.Z-rcN liegt vor vX.Y.Z), null für andere Namen
function versionSchluessel(name) {
    var m = typeof name === "string" ? VERSION_RE.exec(name) : null;
    if (!m)
        return null;
    return m[4] === undefined ? [Number(m[1]), Number(m[2]), Number(m[3]), 1, 0] : [Number(m[1]), Number(m[2]), Number(m[3]), 0, Number(m[4])];
}

// < 0, 0, > 0 wie a gegenüber b (beide Versionen)
function versionVergleich(a, b) {
    var x = versionSchluessel(a), y = versionSchluessel(b);
    for (var i = 0; i < 5; i++) {
        if (x[i] !== y[i])
            return x[i] - y[i];
    }
    return 0;
}

function _imKanal(name, kanal) {
    var m = VERSION_RE.exec(name);
    return !!m && (kanal === "vorschau" || (kanal === "stabil" && m[4] === undefined));
}

// --- Anzeige ------------------------------------------------------------------

function _zwei(n) {
    return (n < 10 ? "0" : "") + n;
}

function _tag0(ms) {
    var d = new Date(ms);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

// «heute, 14:03», «gestern, 14:03», «morgen, 03:30», «3. Okt., 14:03», in einem anderen Jahr «3. Okt. 2025»
// (Ortszeit); «–» ohne Zeit
function zeitText(ms, jetztMs) {
    if (typeof ms !== "number" || !isFinite(ms))
        return "–";
    var d = new Date(ms);
    var uhr = _zwei(d.getHours()) + ":" + _zwei(d.getMinutes());
    var tage = Math.round((_tag0(ms) - _tag0(jetztMs)) / 86400000);
    if (tage === 0)
        return "heute, " + uhr;
    if (tage === -1)
        return "gestern, " + uhr;
    if (tage === 1)
        return "morgen, " + uhr;
    var datum = d.getDate() + ". " + MONATE[d.getMonth()];
    if (d.getFullYear() !== new Date(jetztMs).getFullYear())
        return datum + " " + d.getFullYear();
    return datum + ", " + uhr;
}

// «SHA256:9xQZHFzU…»: die ersten 8 Zeichen, wie sie Zeno beim Setzen des Ankers aus 1Password abtippt
function fingerabdruckKurz(f) {
    return typeof f === "string" && FINGERABDRUCK_RE.test(f) ? f.slice(0, 15) + "…" : "–";
}

// Wie target_label in zenos-kanal: «v0.1.0-rc4 (1a2b3c4d5e6f)», «dev 1a2b3c4d5e6f» oder der Commit
function zielText(ziel) {
    if (!ziel)
        return "?";
    var commit = ziel.commit.slice(0, 12);
    if (ziel.tag !== "")
        return ziel.tag + " (" + commit + ")";
    if (ziel.zweig !== "")
        return ziel.zweig + " " + commit;
    return commit;
}

// Seit der letzten Prüfung wurde installiert: Die Angaben in stand.json sind überholt, bis neu geprüft ist
function veraltet(stand, letzte) {
    return !!stand && !!letzte && isFinite(letzte.endeMs) && (!isFinite(stand.geprueftMs) || letzte.endeMs > stand.geprueftMs + 2000);
}

// Lage der Installation wie «zen kanal status --installation»: unterbrochen, kaputt, angehalten, zurueck,
// gescheitert, fehler, unbestaetigt, gut, keine oder "". Aus stand.json (installation_lage, zur Zeit der Prüfung); ist
// seither installiert worden (veraltet) oder fehlt das Feld (ältere stand.json), aus letzte.json. So bleibt «kaputt»
// sichtbar, auch wenn die Prüfung danach jünger ist als letzte.json.
function installationLage(stand, letzte, istVeraltet) {
    if (stand && stand.installationLage && !istVeraltet)
        return stand.installationLage.schluessel;
    if (letzte && (PROBLEME.indexOf(letzte.ergebnis) >= 0 || letzte.ergebnis === "unterbrochen"))
        return letzte.ergebnis;
    return "";
}

var _TITEL = {
    aktuell: "Aktuell",
    bereit: "Neue Version bereit",
    zustimmung: "Wartet auf deine Zustimmung",
    dev: "Kanal dev, nur von Hand",
    anker_fehlt: "Anker fehlt",
    blockiert: "Blockiert",
    kein_kontakt: "Kein Kontakt",
    fehler: "Prüfung abgebrochen"
};

// Nach «zen rollback» läuft eine ältere Version als die zurückgestellte: «v0.1.0-rc5» (sonst "")
function _zurueckgestelltOffen(stand) {
    if (!stand || stand.zustand !== "aktuell" || !stand.zurueckgestellt)
        return "";
    var inst = stand.installiert && stand.installiert.version !== "" ? stand.installiert.version : "";
    return inst === "" || versionVergleich(stand.zurueckgestellt.version, inst) > 0 ? stand.zurueckgestellt.version : "";
}

// Titel der Lage in den Einstellungen. letzte: letzteLesen; laeuft: install.sh aus dem Kanal läuft gerade
function zustandTitel(stand, istVeraltet, letzte, laeuft) {
    if (laeuft)
        return "Update läuft";
    var lage = installationLage(stand, letzte, istVeraltet);
    if (lage === "kaputt")
        return "Update kaputt";
    if (lage === "unterbrochen")
        return "Update unterbrochen";
    if (!stand)
        return "Noch nie geprüft";
    if (istVeraltet)
        return "Seit der letzten Prüfung installiert";
    if (stand.zustand === "dev" && stand.dev && stand.dev.neu)
        return stand.dev.brauchtJa ? "Neuer Stand auf dev" : "Neuer Stand auf dev, signiert";
    var zurueck = _zurueckgestelltOffen(stand);
    if (zurueck !== "")
        return "Zurückgestellt: " + (stand.installiert && stand.installiert.version !== "" ? stand.installiert.version : "älterer Stand") + " läuft, " + zurueck + " vorhanden";
    return _TITEL[stand.zustand] ?? "Prüfung abgebrochen";
}

// Symbol und Ton der Lage: { symbol, ton: "akzent" | "warnung" | "gedaempft" }
function zustandSymbol(stand, istVeraltet, letzte, laeuft) {
    if (laeuft)
        return { symbol: "info", ton: "akzent" };
    var lage = installationLage(stand, letzte, istVeraltet);
    if (lage === "kaputt" || lage === "unterbrochen")
        return { symbol: "warnung", ton: "warnung" };
    if (!stand || istVeraltet)
        return { symbol: "info", ton: "gedaempft" };
    if (_zurueckgestelltOffen(stand) !== "")
        return { symbol: "info", ton: "gedaempft" };
    switch (stand.zustand) {
    case "aktuell":
        return { symbol: "haken", ton: "akzent" };
    case "bereit":
        return { symbol: "info", ton: "akzent" };
    case "zustimmung":
        return { symbol: "schloss", ton: "akzent" };
    case "dev":
        return { symbol: "code", ton: stand.dev && stand.dev.neu ? "akzent" : "gedaempft" };
    case "anker_fehlt":
        return { symbol: "schloss-offen", ton: "warnung" };
    case "kein_kontakt":
        return { symbol: "wolke", ton: "gedaempft" };
    default:
        return { symbol: "warnung", ton: "warnung" };
    }
}

// Erklärung unter dem Titel (reiner Text)
function grundText(stand, istVeraltet, letzte, laeuft) {
    if (laeuft)
        return "zenOS installiert gerade ein geprüftes Update. Ausschalten und Neustart warten, bis es fertig ist; danach lädt die Oberfläche neu, wenn sie sich geändert hat.";
    var lage = installationLage(stand, letzte, istVeraltet);
    if (lage === "kaputt") {
        var warum = letzte && letzte.ergebnis === "kaputt" && letzte.grund !== "" ? letzte.grund : stand && stand.installationLage ? stand.installationLage.text : "";
        // Der Grund von zenos-kanal nennt den Weg meist schon (ANLEITUNG F): dann nicht noch einmal
        if (/ANLEITUNG/.test(warum))
            return warum;
        return (warum !== "" ? warum + " " : "") + "Zuerst den Grund beheben, dann im Terminal zen update (ANLEITUNG.md, Abschnitt F).";
    }
    if (lage === "unterbrochen")
        return "Eine Installation wurde unterbrochen (Strom oder Neustart). Fortsetzen im Terminal: zen update.";
    if (!stand)
        return "Mit «Jetzt prüfen» holt zenOS die signierten Versionen von origin und prüft sie gegen den Anker des Geräts. Installiert wird dabei nichts.";
    if (istVeraltet)
        return (letzte && letzte.grund !== "" ? letzte.grund + " " : "") + "«Jetzt prüfen» zeigt den neuen Stand.";
    var zurueck = _zurueckgestelltOffen(stand);
    if (zurueck !== "")
        return "Nach «zen rollback» bringt die Automatik " + zurueck + " nicht wieder. Zurück dorthin: zen update.";
    switch (stand.zustand) {
    case "aktuell":
        return "Keine neuere gültig signierte Version im Kanal " + stand.kanal + ".";
    case "bereit":
        return stand.bereit ? stand.bereit.version + " ist gültig signiert und neuer als der installierte Stand." : stand.grund;
    case "zustimmung":
        return stand.bereit ? stand.bereit.version + " ist gültig signiert, ändert aber Firewall, Netz oder Boot. Installiert wird nur mit deiner Zustimmung." : stand.grund;
    case "dev":
        if (!stand.dev || !stand.dev.neu)
            return "Installiert ist der Stand von origin/dev. Auf dev kommt nie etwas automatisch.";
        if (!stand.dev.brauchtJa)
            return "Jeder neue Commit ist gültig signiert. Auf dev kommt nie etwas automatisch; «Jetzt installieren» oder «zen update» holt ihn.";
        return "Nicht jeder neue Commit ist gültig signiert. Auf dev geht das nur im Terminal mit «zen update» und deinem «ja».";
    case "anker_fehlt":
        return "Ohne Vertrauensanker lassen sich Signaturen nicht prüfen: Über den Kanal gilt nichts als gültig, nichts wird automatisch installiert. Setzen im Terminal: sudo zen kanal anker /opt/zenos/system/vertrauen";
    default:
        return stand.grund !== "" ? stand.grund : "Mehr im Terminal: zen kanal";
    }
}

// Wann ein bereites Update automatisch kommt, abgestimmt auf den Zeitpunkt: «kommt bei der nächsten Sperre»,
// «frühestens morgen, 10:54, danach zwischen 02:00 und 05:00», «nur über Jetzt installieren» … ("" ohne Automatik)
function bereitWann(stand, zeitpunkt, jetztMs) {
    if (!stand || !stand.bereit || stand.zustand !== "bereit" || !stand.automatikAn || stand.kanal === "dev")
        return "";
    var z = zeitpunkt || zeitpunktLesen(null);
    if (z.art === "hand")
        return "nur über «Jetzt installieren» oder zen update";
    if (stand.angehalten)
        return "Automatik ruht (Stand von Hand)";
    // Bei «jederzeit» kommt es gleich nach der Wartezeit; sonst zum nächsten passenden Moment danach
    var danach = z.art === "fenster" ? ", danach zwischen " + z.von + " und " + z.bis : z.art === "jederzeit" ? "" : ", danach bei der nächsten Sperre";
    if (isFinite(stand.bereit.freiAbMs) && stand.bereit.freiAbMs > jetztMs)
        return "frühestens " + zeitText(stand.bereit.freiAbMs, jetztMs) + danach;
    if (!stand.bereit.frei)
        return "erst mit synchronisierter Uhr" + danach;
    return z.art === "fenster" ? "kommt zwischen " + z.von + " und " + z.bis : z.art === "jederzeit" ? "kommt bald" : "kommt bei der nächsten Sperre";
}

// Zeilen unter der Lage: [{ titel, wert }] (Werte in Mono). letzte: letzteLesen (für «Letztes Update»)
function zeilen(stand, zeitpunkt, jetztMs, letzte) {
    if (!stand)
        return [];
    var aus = [];
    aus.push({ titel: "Kanal", wert: stand.kanal !== "" ? stand.kanal : "?" });
    var inst = stand.installiert;
    if (inst)
        aus.push({ titel: "Installiert", wert: (inst.version !== "" ? inst.version + " · " : "") + inst.commit.slice(0, 12) + (inst.version === "" ? " · ohne signierte Version" : "") });
    // Gescheitert, zurück, abgebrochen oder kaputt: bis eine spätere Installation es ablöst
    var lage = installationLage(stand, letzte, veraltet(stand, letzte));
    if (PROBLEME.indexOf(lage) >= 0 && letzte && letzte.ergebnis === lage)
        aus.push({ titel: "Letztes Update", wert: ERGEBNIS_TEXT[lage] + " · " + zeitText(letzte.endeMs, jetztMs) + (letzte.ziel ? " · " + zielText(letzte.ziel) : "") });
    if (stand.angehalten)
        aus.push({ titel: "Von Hand", wert: (stand.angehalten.commit !== "" ? stand.angehalten.commit.slice(0, 12) + " · " : "") + "seit " + zeitText(stand.angehalten.seitMs, jetztMs) + " · Automatik ruht bis zen update" });
    if (stand.bereit && (stand.zustand === "bereit" || stand.zustand === "zustimmung")) {
        var wann = bereitWann(stand, zeitpunkt, jetztMs);
        aus.push({ titel: "Bereit", wert: stand.bereit.version + " · " + stand.bereit.commit.slice(0, 12) + (wann !== "" ? " · " + wann : "") });
    }
    if (stand.unbestaetigt)
        aus.push({ titel: "Bestätigung", wert: (stand.unbestaetigt.version !== "" ? stand.unbestaetigt.version : stand.unbestaetigt.commit.slice(0, 12)) + " · automatisch installiert, gilt als gut nach dem nächsten Neustart mit Login" });
    if (stand.zurueckgestellt)
        aus.push({ titel: "Zurückgestellt", wert: stand.zurueckgestellt.version + " · nach zen rollback, kommt nicht automatisch wieder" });
    if (!stand.automatikAn)
        aus.push({ titel: "Automatik", wert: "aus · einschalten: sudo zen kanal automatik an" });
    if (stand.kanal === "dev" && stand.dev && stand.dev.neu)
        aus.push({ titel: "origin/dev", wert: stand.dev.commit.slice(0, 12) + (stand.dev.commits >= 0 ? " · " + stand.dev.commits + (stand.dev.commits === 1 ? " Commit" : " Commits") + " neuer" : "") });
    aus.push({ titel: "Geprüft", wert: zeitText(stand.geprueftMs, jetztMs) });
    aus.push({ titel: "Kontakt", wert: (isFinite(stand.kontaktMs) ? zeitText(stand.kontaktMs, jetztMs) : "nie") + (stand.holenFehler !== "" ? " · letzter Versuch gescheitert" : "") });
    if (stand.anker) {
        aus.push({ titel: "Anker", wert: "Serie " + stand.anker.serie });
        aus.push({ titel: "Wurzel", wert: fingerabdruckKurz(stand.anker.wurzel) });
        for (var i = 0; i < stand.anker.release.length; i++)
            aus.push({ titel: i === 0 ? "Release" : "", wert: fingerabdruckKurz(stand.anker.release[i]) });
    } else {
        aus.push({ titel: "Anker", wert: "fehlt" });
    }
    return aus;
}

// Kann «Jetzt installieren» etwas tun, ohne dass es ein «ja» braucht?
function kannInstallieren(stand) {
    return installierenZiel(stand) !== "";
}

// Ziel für «Jetzt installieren»: das Tag-Objekt der bereiten Version, auf dev (jeder Commit signiert) der Commit von
// origin/dev, sonst "". Installiert wird nur genau dieser, schon geprüfte Stand.
function installierenZiel(stand) {
    if (!stand)
        return "";
    if (stand.zustand === "bereit")
        return stand.bereit !== null && stand.kanal !== "dev" ? stand.bereit.objekt : "";
    if (stand.zustand === "dev" && !!stand.dev && stand.dev.neu && !stand.dev.brauchtJa && !!stand.anker)
        return stand.dev.commit;
    return "";
}

// Tag-Objekt, dem «Zustimmen …» gilt (nur gültig signierte Versionen auf stabil und vorschau), sonst ""
function zustimmungObjekt(stand) {
    if (!stand || stand.zustand !== "zustimmung" || !stand.bereit || stand.kanal === "dev")
        return "";
    return stand.bereit.objekt;
}

// Satz zur Zustimmung: was sich ändert und wofür sie gilt
function zustimmungText(stand) {
    if (zustimmungObjekt(stand) === "")
        return "";
    var b = stand.bereit;
    var was = b.rueckfrage === null ? "Der Vergleich mit dem installierten Stand ist nicht möglich." : b.rueckfrage.length === 0 ? "" : "Ändert " + b.rueckfrage.slice(0, 3).join(", ") + (b.rueckfrage.length > 3 ? " und " + (b.rueckfrage.length - 3) + " weitere" : "") + ".";
    return (was !== "" ? was + " " : "") + "Zustimmen verlangt dein Passwort und gilt nur für " + b.version + " (Objekt " + b.objekt.slice(0, 12) + ").";
}

// Erklärung zum gewählten Zeitpunkt: knapp und ehrlich, was die Automatik dann tut (zenos-kanal quiet_now)
function zeitpunktText(z) {
    switch (z ? z.art : "") {
    case "fenster":
        return "Kommt zwischen " + z.von + " und " + z.bis + " Uhr, auch wenn du gerade arbeitest. Das Gerät muss dann laufen.";
    case "jederzeit":
        return "Kommt, sobald es bereit ist, auch während du arbeitest; die Oberfläche lädt dabei kurz neu.";
    case "hand":
        return "Nie automatisch. Ist ein Update bereit, kommt eine Mitteilung; installiert wird mit «Jetzt installieren» oder zen update.";
    default:
        return "Kommt, wenn zenOS seit 5 Minuten gesperrt ist oder der Login-Bildschirm seit 5 Minuten wartet, nicht während jemand per SSH angemeldet ist (Standard).";
    }
}

// Was für jeden Zeitpunkt gilt (unter der Erklärung)
var ZEITPUNKT_IMMER = "Gilt für das ganze Gerät. Installiert wird immer nur, was gültig signiert ist. Was Firewall, Netz oder Boot ändert, wartet auf deine Zustimmung. Im Akkubetrieb kommt es erst ab " + AKKU_MIN_PROZENT + " % Ladung. Auf dev kommt nie etwas automatisch.";

// Kurz für die Mitteilung: «Bei Sperre», «Zeitfenster 02:00–05:00», «Jederzeit», «Von Hand»
function zeitpunktKurz(z) {
    switch (z ? z.art : "") {
    case "fenster":
        return "Zeitfenster " + z.von + "–" + z.bis;
    case "jederzeit":
        return "Jederzeit";
    case "hand":
        return "Von Hand";
    default:
        return "Bei Sperre";
    }
}

// --- Mitteilungen -------------------------------------------------------------

// Gemerkte Mitteilungen (~/.local/state/zenos/kanal-meldungen.json), geprüft
function gemeldetLesen(json) {
    var d = _objekt(json) || {};
    var s = function (w) {
        return typeof w === "string" ? w.slice(0, 600) : "";
    };
    return {
        installation: s(d.installation),
        blockiert: s(d.blockiert),
        anker: s(d.anker),
        zustimmung: s(d.zustimmung),
        kontakt: s(d.kontakt),
        bereit: s(d.bereit),
        zeitpunkt: s(d.zeitpunkt),
        abgelehnt: _liste(d.abgelehnt, ABGELEHNT_MERKEN, function (t) {
            return _tag(t) || null;
        })
    };
}

function gemeldetText(g) {
    return JSON.stringify({ version: 1, installation: g.installation, blockiert: g.blockiert, anker: g.anker, zustimmung: g.zustimmung, kontakt: g.kontakt, bereit: g.bereit, zeitpunkt: g.zeitpunkt, abgelehnt: g.abgelehnt }, null, 1) + "\n";
}

// Abgelehnte Tags, die eine Mitteilung wert sind: auf stabil und vorschau mit Anker, ein Tag im Kanal über allem, was
// schon gilt (hoechste, installiert, gültig), oder ein auf origin verschobener Tag. Alte unsignierte Stände darunter
// (etwa rc1 bis rc3) melden sich nicht.
function abgelehntWichtig(stand) {
    if (!stand || !stand.anker || (stand.kanal !== "stabil" && stand.kanal !== "vorschau") || stand.zustand === "anker_fehlt")
        return [];
    var basis = "";
    var kandidaten = stand.gueltig.slice();
    if (stand.hoechste !== "")
        kandidaten.push(stand.hoechste);
    if (stand.installiert && stand.installiert.version !== "")
        kandidaten.push(stand.installiert.version);
    for (var i = 0; i < kandidaten.length; i++) {
        if (basis === "" || versionVergleich(kandidaten[i], basis) > 0)
            basis = kandidaten[i];
    }
    return stand.abgelehnt.filter(function (e) {
        if (/^auf origin verschoben/.test(e.grund))
            return true;
        return _imKanal(e.tag, stand.kanal) && (basis === "" || versionVergleich(e.tag, basis) > 0);
    });
}

function _meldung(schluessel, titel, inhalt, dringlichkeit) {
    return { schluessel: schluessel, titel: text(titel, 120), text: text(inhalt, 400), dringlichkeit: dringlichkeit };
}

// Welche Mitteilungen jetzt fällig sind. lage: { stand, letzte, zeitpunkt, veraltet, zeitpunktSelbst } (gelesen wie
// oben; zeitpunktSelbst: die Einstellungen haben den Zeitpunkt eben selbst gesetzt), gemeldet: aus gemeldetLesen.
// Rückgabe: { neu: [{ schluessel, titel, text, dringlichkeit }], gemeldet } – gemeldet ist der neue Stand zum Merken.
// Jede Mitteilung kommt nur einmal je Zustand: Ein Zustand meldet sich erst wieder, wenn er vorher sicher vorbei war
// (ein anderer Zustand der Prüfung, nicht nur «kein Kontakt» oder «fehler»).
//   installiert  still (low)      eine Installation über den Kanal ist fertig und gesund (höchstens 24 h alt)
//   zurueck      normal           gescheitert, zurück auf dem Stand davor (ebenso «gescheitert», «fehler»; auch alt)
//   kaputt       dringend         auch der Rückweg scheiterte (auch alt)
//   blockiert    dringend         ALARM im Hauptbuch u. a.
//   anker        normal           Anker fehlt
//   abgelehnt    normal           ein neuer Tag im Kanal ist nicht gültig signiert (je Tag einmal)
//   zustimmung   normal           wartet auf Zustimmung (je Tag-Objekt einmal)
//   kontakt      normal           14 Tage ohne Kontakt zu origin (je Kontaktzeit einmal)
//   bereit       normal           Zeitpunkt «hand»: ein Update ist bereit (je Tag-Objekt einmal)
//   zeitpunkt    normal           der Zeitpunkt wurde geändert, nicht aus den Einstellungen (etwa sudo oder pkexec aus
//                                 einer anderen Anmeldung), mit dem Weg aus der Datei
function meldungen(lage, gemeldet, jetztMs) {
    var g = gemeldetLesen(gemeldet ? gemeldetText(gemeldet) : "");
    var neu = [];
    var stand = lage ? lage.stand : null;
    var letzte = lage ? lage.letzte : null;
    var zeitpunkt = lage && lage.zeitpunkt ? lage.zeitpunkt : zeitpunktLesen(null);

    // Installation (letzte.json)
    if (letzte && isFinite(letzte.endeMs)) {
        var schluessel = letzte.ergebnis + "@" + new Date(letzte.endeMs).toISOString();
        var frisch = letzte.endeMs >= jetztMs - ERGEBNIS_FRISCH_MS && letzte.endeMs <= jetztMs + 3600000;
        if (schluessel !== g.installation && ["installiert", "zurueck", "gescheitert", "kaputt", "fehler"].indexOf(letzte.ergebnis) >= 0) {
            g.installation = schluessel;
            var ziel = letzte.ziel ? (letzte.ziel.tag !== "" ? letzte.ziel.tag : zielText(letzte.ziel)) : "Das Update";
            if (letzte.ergebnis === "kaputt")
                neu.push(_meldung("kaputt", "Update kaputt", letzte.grund !== "" ? letzte.grund : "Auch der Rückweg scheiterte. Mehr: zen kanal", "critical"));
            else if (letzte.ergebnis === "installiert" && !frisch)
                ; // ein altes «installiert» (etwa beim ersten Start nach Tagen): nur merken
            else if (letzte.ergebnis === "installiert")
                neu.push(_meldung("installiert", "zenOS aktualisiert", ziel + " ist installiert.", "low"));
            else if (letzte.ergebnis === "zurueck")
                neu.push(_meldung("zurueck", "Update gescheitert", letzte.grund !== "" ? letzte.grund : "Zurück auf dem Stand davor.", "normal"));
            else
                neu.push(_meldung(letzte.ergebnis, letzte.ergebnis === "fehler" ? "Update abgebrochen" : "Update gescheitert", (letzte.grund !== "" ? letzte.grund : ziel) + " Mehr: zen kanal", "normal"));
        }
    }

    // Lage der Prüfung (stand.json); veraltet oder unklar: nichts melden, nichts vergessen
    var klar = !!stand && !(lage && lage.veraltet) && stand.zustand !== "fehler" && stand.zustand !== "kein_kontakt";
    if (klar) {
        var blockiert = stand.zustand === "blockiert" ? "blockiert:" + stand.grund : "";
        if (blockiert !== "" && blockiert !== g.blockiert)
            neu.push(_meldung("blockiert", "Updates blockiert", stand.grund !== "" ? stand.grund : "Mehr: zen kanal", "critical"));
        g.blockiert = blockiert;

        var anker = stand.zustand === "anker_fehlt" ? "anker_fehlt" : "";
        if (anker !== "" && anker !== g.anker)
            neu.push(_meldung("anker", "Updates: Anker fehlt", "Ohne Vertrauensanker prüft zenOS keine Signaturen und installiert nichts automatisch. Setzen im Terminal: sudo zen kanal anker /opt/zenos/system/vertrauen", "normal"));
        g.anker = anker;

        var objekt = zustimmungObjekt(stand);
        var zustimmung = objekt !== "" ? "zustimmung:" + objekt : stand.zustand === "zustimmung" ? g.zustimmung : "";
        if (objekt !== "" && zustimmung !== g.zustimmung)
            neu.push(_meldung("zustimmung", "Update wartet auf deine Zustimmung", stand.bereit.version + " ändert Firewall, Netz oder Boot. Ansehen und zustimmen: Einstellungen › System › Updates.", "normal"));
        g.zustimmung = zustimmung;

        var wichtig = abgelehntWichtig(stand).filter(function (e) {
            return g.abgelehnt.indexOf(e.tag) < 0;
        });
        if (wichtig.length > 0) {
            var teile = wichtig.slice(0, 2).map(function (e) {
                return e.tag + ": " + e.grund;
            });
            var mehr = wichtig.length > 2 ? " (und " + (wichtig.length - 2) + " weitere)" : "";
            neu.push(_meldung("abgelehnt", "Update abgelehnt", teile.join(" · ") + mehr + ". zenOS installiert nur, was gültig signiert ist.", "normal"));
            g.abgelehnt = g.abgelehnt.concat(wichtig.map(function (e) {
                return e.tag;
            })).slice(-ABGELEHNT_MERKEN);
        }

        var bereit = zeitpunkt.art === "hand" && stand.zustand === "bereit" && stand.bereit ? "bereit:" + stand.bereit.objekt : "";
        if (bereit !== "" && bereit !== g.bereit)
            neu.push(_meldung("bereit", "Update bereit", stand.bereit.version + " ist geprüft und bereit. Installieren: Einstellungen › System › Updates oder zen update.", "normal"));
        if (bereit !== "" || stand.zustand !== "bereit")
            g.bereit = bereit;
    }

    // Kontakt zu origin: einmal je Kontaktzeit, sobald sie 14 Tage zurückliegt
    if (stand && isFinite(stand.kontaktMs) && jetztMs - stand.kontaktMs >= KONTAKT_TAGE * 86400000) {
        var kontakt = "kontakt@" + new Date(stand.kontaktMs).toISOString();
        if (kontakt !== g.kontakt) {
            var tage = Math.floor((jetztMs - stand.kontaktMs) / 86400000);
            neu.push(_meldung("kontakt", "Seit " + tage + " Tagen kein Kontakt zu origin", "Geprüft wird weiter, aber nur der zuletzt geholte Stand. Letzter Kontakt: " + zeitText(stand.kontaktMs, jetztMs) + ". Netz prüfen, dann in Einstellungen › System › Updates «Jetzt prüfen».", "normal"));
            g.kontakt = kontakt;
        }
    }

    // Zeitpunkt geändert, ohne dass es die Einstellungen waren (allow_active gilt für jeden Prozess des Benutzers,
    // solange seine Sitzung am Gerät aktiv ist; sudo aus SSH ebenso): einmal je Änderung, mit dem Weg
    var zKey = [zeitpunkt.art, zeitpunkt.von, zeitpunkt.bis, zeitpunkt.seit || "", zeitpunkt.problem !== "" ? "ungueltig" : ""].join("|");
    if (g.zeitpunkt !== "" && zKey !== g.zeitpunkt && !(lage && lage.zeitpunktSelbst))
        neu.push(_meldung("zeitpunkt", "Zeitpunkt für Updates geändert", "Jetzt: " + zeitpunktKurz(zeitpunkt) + (zeitpunkt.ueber ? " (gesetzt über " + zeitpunkt.ueber + ")" : "") + ". Ansehen: Einstellungen › System › Updates.", "normal"));
    g.zeitpunkt = zKey;
    return { neu: neu, gemeldet: g };
}

// Argumentliste für notify-send (nie über eine Shell)
function mitteilungBefehl(m) {
    var dringlichkeit = ["low", "normal", "critical"].indexOf(m.dringlichkeit) >= 0 ? m.dringlichkeit : "normal";
    return ["notify-send", "--app-name=zenOS", "--icon=zenos", "--urgency=" + dringlichkeit, "--category=system", "--", text(m.titel, 120), text(m.text, 400)];
}

// --- Bedienung ----------------------------------------------------------------

// pkexec-Aufruf für den Helfer, null bei falschen Werten. aktion: pruefen | installieren (a: Ziel aus
// installierenZiel) | zustimmen (a: Objekt) | zeitpunkt (a: Wahl, b/c: von/bis bei «fenster»)
function befehl(helfer, aktion, a, b, c) {
    if (typeof helfer !== "string" || helfer.charAt(0) !== "/")
        return null;
    switch (aktion) {
    case "pruefen":
        return ["pkexec", helfer, aktion];
    case "installieren":
    case "zustimmen":
        return typeof a === "string" && OBJEKT_RE.test(a) ? ["pkexec", helfer, aktion, a] : null;
    case "zeitpunkt":
        if (a === "fenster")
            return fensterProblem(b, c) === "" ? ["pkexec", helfer, "zeitpunkt", "fenster", b, c] : null;
        return ZEITPUNKTE.indexOf(a) >= 0 ? ["pkexec", helfer, "zeitpunkt", a] : null;
    default:
        return null;
    }
}

// Rückmeldung nach einem Aufruf als { text, art: "" (Bestätigung) | "warnung" } oder null (nichts zeigen: die Seite
// oder eine Mitteilung sagt es schon). info: { fehler: letzte Zeile von stderr, installiert: true, wenn letzte.json
// seit dem Start neu ist, zustand: Zustand der Prüfung danach, wunsch: Antwort der Prüfung auf diesen Aufruf
// ({ ergebnis, grund } aus stand.json) }
function rueckmeldung(aktion, code, info) {
    var i = info || {};
    var fehler = text(i.fehler || "", 160).replace(/^zenos-kanal(-bedienen)?( [a-z]+)?:\s*/, "");
    if (code === 126)
        return null;
    if (code < 0)
        return { text: "Updates: pkexec lässt sich nicht starten (install.sh ausführen)", art: "warnung" };
    if (code === 127)
        return { text: /authentication agent/i.test(i.fehler || "") ? "Updates: keine Bestätigung möglich (polkit-Agent nicht angemeldet)" : "Updates: nicht erlaubt (nur in der aktiven Sitzung am Gerät)", art: "warnung" };
    if (code === 75)
        return { text: "Gerade läuft schon ein Update oder eine Prüfung. Später noch einmal.", art: "warnung" };
    switch (aktion) {
    case "pruefen":
        if (/Holen ist gescheitert/.test(i.fehler || ""))
            return { text: "Kein Kontakt zu origin: geprüft wurde der letzte geholte Stand", art: "warnung" };
        if (code === 0 || code === 3 || code === 10)
            return { text: "Updates geprüft", art: "" };
        return { text: "Prüfung gescheitert" + (fehler !== "" ? ": " + fehler : " (journalctl -u zenos-kanal-pruefen)"), art: "warnung" };
    case "installieren":
    case "zustimmen":
        if (i.installiert)
            return null; // die Mitteilung zur Installation kommt ohnehin
        if (code === 0)
            return { text: "zenOS ist schon aktuell", art: "" };
        var grund = i.wunsch && typeof i.wunsch.grund === "string" ? text(i.wunsch.grund, 160) : "";
        if (code === 10 && (aktion === "zustimmen" || /^Angezeigt war/.test(grund)))
            return { text: "Der Stand hat sich geändert: bitte noch einmal ansehen", art: "warnung" };
        if (code === 10 && i.zustand === "zustimmung")
            return { text: "Das Update braucht deine Zustimmung", art: "warnung" };
        if (code === 10)
            return { text: grund !== "" ? "Update wartet: " + grund : "Update wartet (Netz oder Platz) · mehr: zen kanal", art: "warnung" };
        if (code === 3 && aktion === "zustimmen")
            return { text: "Zustimmen geht hier nur für gültig signierte Versionen · sonst zen update", art: "warnung" };
        if (code === 3)
            return { text: "Nichts installiert: " + (grund !== "" ? grund : "kein gültig signierter Stand · mehr: zen kanal"), art: "warnung" };
        if (code === 4 || code === 5)
            return null;
        return { text: "Update gescheitert" + (fehler !== "" ? ": " + fehler : " · mehr: zen kanal"), art: "warnung" };
    case "zeitpunkt":
        if (code === 0)
            return null;
        return { text: "Zeitpunkt liess sich nicht setzen" + (fehler !== "" ? ": " + fehler : ""), art: "warnung" };
    default:
        return null;
    }
}
