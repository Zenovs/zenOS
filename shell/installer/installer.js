.pragma library
// Logik des zen Installers in der Oberfläche (installer/Installer.qml, Fenster in InstallerInhalt.qml) ohne QML: Pfad
// prüfen, die Antwort von «zenos-installer ansehen --json» lesen, das Fenster in jeder Phase beschreiben (Kopf, Lage,
// Werte, Hinweise, Knöpfe), die Argumentliste für pkexec, das Ergebnis einer Installation aus Exit und letzte.json und
// die Mitteilung, wenn das Fenster inzwischen zu ist. Getestet mit test/einheiten/installer.test.mjs (node).
//
// Phasen des Dienstes: "" (nichts offen), "ansehen" (zenos-installer liest das Paket), "ansicht" (Ergebnis da),
// "laeuft" (pkexec und die Unit arbeiten), "ende" (Ergebnis der Installation).
//
// Texte aus dem Paket (Name, Beschreibung, Herausgeber …) sind nicht vertrauenswürdig: zenos-installer bereinigt sie
// schon; hier noch einmal (ohne Steuer- und unsichtbare Zeichen, gekürzt), und das Fenster zeigt sie nur als reinen Text.

// Fester Pfad: Die polkit-Aktionen (system/polkit/org.zenos.installer.policy) gelten genau für dieses Programm
var HELFER = "/opt/zenos/scripts/bin/zenos-installer-bedienen";
var MAX_PFAD = 4096;

var ERGEBNISSE = Object.freeze(["bereit", "installiert", "abgelehnt", "fehler"]);
var ZUSTAENDE = Object.freeze(["neu", "update", "rueckschritt", "gleich"]);
// Ergebnisse in letzte.json (RESULT_TEXT in zenos-installer) und Phasen einer laufenden Unit (Session.note)
var LETZTE = Object.freeze(["installiert", "gleich", "entfernt", "abgelehnt", "fehler", "wartet"]);
var LAUF_PHASEN = Object.freeze(["wartet", "prueft", "installiert", "entfernt"]);

var SHA_RE = /^[0-9a-f]{64}$/;
var PLAN_RE = /^[0-9a-f]{40}$/;
var PAKET_RE = /^[a-z0-9][a-z0-9+.-]{0,127}$/;
var STARTER_RE = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,200}\.desktop$/;
var ART_RE = /^[a-z_]{1,30}$/;
var URL_RE = /^https?:\/\/[^\s<>"']{1,300}$/;
var ZEIT_RE = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/;
// Symbol des Pakets: nur aus dem Laufzeitordner des Benutzers (save_icon in zenos-installer), als file:// ladbar
var SYMBOL_RE = /^\/[A-Za-z0-9._\/-]{1,300}\/zenos-installer\/[0-9a-f]{32}\.(png|svg)$/;
var STEUER = /[\u0000-\u001f\u007f-\u009f]/;
// Wie kanal.js: Steuerzeichen und unsichtbare Zeichen (Bidi, Breite null) werden zu «?»
var UNSICHTBAR = /[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u115f\u1160\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]/g;

// So viele Namen in einem Satz, dann «und N weitere»
var NAMEN_SATZ = 6;

// --- Allgemein ----------------------------------------------------------------

// Reiner Text in einer Zeile: Zeilenumbrüche zu Leerzeichen, unsichtbare Zeichen zu «?», gekürzt
function text(wert, max) {
    if (typeof wert !== "string")
        return "";
    var t = wert.replace(/[\t\n\r]+/g, " ").replace(UNSICHTBAR, "?").replace(/ {2,}/g, " ").trim();
    var n = typeof max === "number" && max > 1 ? max : 400;
    return t.length > n ? t.slice(0, n - 1) + "…" : t;
}

// Reiner Text über mehrere Zeilen (Beschreibung): Umbrüche bleiben, höchstens eine Leerzeile am Stück
function textZeilen(wert, max) {
    if (typeof wert !== "string")
        return "";
    var zeilen = wert.replace(/\r\n?/g, "\n").split("\n").map(function (z) {
        return z.replace(/\t/g, " ").replace(UNSICHTBAR, "?").replace(/ {2,}/g, " ").trim();
    });
    var t = zeilen.join("\n").replace(/\n{3,}/g, "\n\n").trim();
    var n = typeof max === "number" && max > 1 ? max : 4000;
    return t.length > n ? t.slice(0, n - 1) + "…" : t;
}

// Beschreibung aus dem Paket (Debian bricht von Hand um): Zeilen eines Absatzes fliessen zusammen, Absätze und
// Aufzählungen («-», «*», «•», «1.») bleiben
function absaetze(wert) {
    var t = textZeilen(wert, 4000);
    if (t === "")
        return "";
    return t.split("\n\n").map(function (absatz) {
        var aus = "";
        var zeilen = absatz.split("\n");
        for (var i = 0; i < zeilen.length; i++) {
            if (zeilen[i] === "")
                continue;
            if (aus === "")
                aus = zeilen[i];
            else
                aus += (/^([-*\u2022]|[0-9]{1,3}[.)])\s/.test(zeilen[i]) ? "\n" : " ") + zeilen[i];
        }
        return aus;
    }).filter(function (a) {
        return a !== "";
    }).join("\n\n");
}

function _objekt(json) {
    if (json !== null && typeof json === "object" && !Array.isArray(json))
        return json;
    if (typeof json !== "string" || json.trim() === "")
        return null;
    try {
        var d = JSON.parse(json);
        return d !== null && typeof d === "object" && !Array.isArray(d) ? d : null;
    } catch (e) {
        return null;
    }
}

function _zahl(wert) {
    return typeof wert === "number" && isFinite(wert) && wert >= 0 ? Math.floor(wert) : null;
}

// Zeitpunkt «2026-10-08T12:00:00Z» als ms, sonst NaN
function zeitMs(wert) {
    return typeof wert === "string" && ZEIT_RE.test(wert) ? Date.parse(wert) : NaN;
}

// «a, b, c und 2 weitere»
function namenText(namen, max) {
    if (!Array.isArray(namen) || namen.length === 0)
        return "";
    var n = typeof max === "number" && max >= 1 ? max : NAMEN_SATZ;
    return namen.slice(0, n).join(", ") + (namen.length > n ? " und " + (namen.length - n) + " weitere" : "");
}

// Wie size_text in zenos-installer: «18,4 MB», «512 Byte»
function groesseText(n) {
    if (typeof n !== "number" || !isFinite(n) || n < 0)
        return "–";
    var stufen = [["GB", 1073741824], ["MB", 1048576], ["kB", 1024]];
    for (var i = 0; i < stufen.length; i++) {
        if (n >= stufen[i][1])
            return (n / stufen[i][1]).toFixed(1).replace(".", ",") + " " + stufen[i][0];
    }
    return Math.floor(n) + " Byte";
}

// Letzter Teil eines Pfads
function dateiname(pfad) {
    if (typeof pfad !== "string")
        return "";
    var teile = pfad.split("/");
    return text(teile[teile.length - 1], 200);
}

// Grund, warum PFAD kein brauchbarer Pfad zu einer .deb ist (wie check_user_path in zenos-installer), sonst ""
function pfadProblem(pfad) {
    if (typeof pfad !== "string" || pfad === "" || pfad.length > MAX_PFAD || STEUER.test(pfad))
        return "Ungültiger Dateiname.";
    if (pfad.charAt(0) !== "/")
        return "Der Pfad muss absolut sein.";
    if (!/\.deb$/.test(pfad) || /\/\.deb$/.test(pfad))
        return "Der zen Installer nimmt nur Pakete mit der Endung .deb.";
    return "";
}

// --- Antwort von «zenos-installer ansehen --json» -------------------------------

// Immer ein Objekt (nie null): Was fehlt oder ungültig ist, fällt weg; eine unlesbare Antwort gilt als «fehler».
// pfad: der angefragte Pfad (falls die Antwort keinen eigenen nennt)
function ansichtLesen(json, pfad) {
    var a = {
        ergebnis: "fehler",
        grund: "",
        ablehnung: "",
        pfad: pfadProblem(pfad) === "" ? pfad : "",
        datei: dateiname(pfad),
        groesse: null,
        sha256: "",
        plan: "",
        name: "",
        paket: null,
        zustand: "",
        installierteVersion: "",
        ueberInstaller: false,
        symbol: "",
        programme: [],
        zusaetzlich: [],
        entfernen: [],
        hinweise: [],
        dateien: null
    };
    var d = _objekt(json);
    if (d === null || d.version !== 1) {
        a.grund = "zenos-installer hat keine lesbare Antwort gegeben.";
        return a;
    }
    a.ergebnis = ERGEBNISSE.indexOf(d.ergebnis) >= 0 ? d.ergebnis : "fehler";
    a.grund = text(d.grund, 400);
    a.ablehnung = typeof d.ablehnung === "string" && ART_RE.test(d.ablehnung) ? d.ablehnung : "";
    if (typeof d.pfad === "string" && pfadProblem(d.pfad) === "")
        a.pfad = d.pfad;
    a.datei = text(d.datei, 200) || dateiname(a.pfad || pfad);
    a.groesse = _zahl(d.groesse);
    a.sha256 = typeof d.sha256 === "string" && SHA_RE.test(d.sha256) ? d.sha256 : "";
    a.plan = typeof d.plan === "string" && PLAN_RE.test(d.plan) ? d.plan : "";
    a.name = text(d.name, 80);
    var p = d.paket !== null && typeof d.paket === "object" && !Array.isArray(d.paket) ? d.paket : null;
    if (p !== null && typeof p.name === "string" && PAKET_RE.test(p.name)) {
        a.paket = {
            name: p.name,
            version: text(p.version, 100),
            architektur: text(p.architektur, 32),
            herausgeber: text(p.herausgeber, 200),
            homepage: typeof p.homepage === "string" && URL_RE.test(p.homepage) ? p.homepage : "",
            zusammenfassung: text(p.zusammenfassung, 200),
            beschreibung: absaetze(p.beschreibung),
            installiertGroesse: _zahl(p.installiert_groesse)
        };
    }
    a.zustand = ZUSTAENDE.indexOf(d.zustand) >= 0 ? d.zustand : "";
    a.installierteVersion = text(d.installierte_version, 100);
    a.ueberInstaller = d.ueber_installer === true;
    a.symbol = typeof d.symbol === "string" && SYMBOL_RE.test(d.symbol) ? d.symbol : "";
    a.programme = _programme(d.programme);
    if (Array.isArray(d.zusaetzlich)) {
        for (var i = 0; i < d.zusaetzlich.length && a.zusaetzlich.length < 500; i++) {
            var z = d.zusaetzlich[i];
            if (z && typeof z.name === "string" && PAKET_RE.test(z.name))
                a.zusaetzlich.push({ name: z.name, version: text(z.version, 100), alt: text(z.alt, 100) });
        }
    }
    if (Array.isArray(d.entfernen)) {
        for (var j = 0; j < d.entfernen.length && a.entfernen.length < 500; j++) {
            if (typeof d.entfernen[j] === "string" && PAKET_RE.test(d.entfernen[j]) && a.entfernen.indexOf(d.entfernen[j]) < 0)
                a.entfernen.push(d.entfernen[j]);
        }
    }
    if (Array.isArray(d.hinweise)) {
        for (var k = 0; k < d.hinweise.length && a.hinweise.length < 30; k++) {
            var h = d.hinweise[k];
            var t = h ? text(h.text, 300) : "";
            if (t !== "")
                a.hinweise.push({ art: typeof h.art === "string" && ART_RE.test(h.art) ? h.art : "", warnung: h.stufe === "warnung" || h.art === "entfernen", text: t });
        }
    }
    a.dateien = _zahl(d.dateien);
    // Installieren nur mit allem, was der Helfer verlangt
    if (a.ergebnis === "bereit" && (a.paket === null || a.sha256 === "" || a.plan === "" || a.pfad === "")) {
        a.ergebnis = "fehler";
        a.grund = "Die Antwort von zenos-installer ist unvollständig.";
    }
    if (a.grund === "")
        a.grund = a.ergebnis === "fehler" ? "Das Paket lässt sich nicht lesen." : "";
    return a;
}

// [{id: "beispiel.desktop", name}] aus zenos-installer (ansehen, letzte.json)
function _programme(wert) {
    var aus = [];
    if (!Array.isArray(wert))
        return aus;
    for (var i = 0; i < wert.length && aus.length < 50; i++) {
        var e = wert[i];
        if (e && typeof e.id === "string" && STARTER_RE.test(e.id))
            aus.push({ id: e.id, name: text(e.name, 80) || e.id.replace(/\.desktop$/, "") });
    }
    return aus;
}

// --- Was das Fenster zeigt -----------------------------------------------------

// Anzeigename: aus dem Starter, sonst der Paketname, sonst der Dateiname
function anzeigeName(a, pfad) {
    if (a && a.name)
        return a.name;
    if (a && a.paket)
        return a.paket.name;
    return dateiname(a && a.pfad ? a.pfad : pfad) || "Paket";
}

function _versionText(a) {
    var v = a.paket.version;
    switch (a.zustand) {
    case "neu":
        return v + " · neu";
    case "update":
        return v + " · ersetzt " + (a.installierteVersion || "die installierte");
    case "rueckschritt":
        return v + " · älter als " + (a.installierteVersion || "die installierte");
    case "gleich":
        return v + " · schon installiert";
    default:
        return v;
    }
}

// Werte zweispaltig wie die Updates-Seite: [{titel, wert, umbruch}]
function zeilen(a) {
    if (!a || a.paket === null)
        return [];
    var p = a.paket;
    var z = [];
    z.push({ titel: "Version", wert: _versionText(a), umbruch: false });
    z.push({ titel: "Paket", wert: p.name + (p.architektur ? " · " + p.architektur : ""), umbruch: false });
    if (p.herausgeber)
        z.push({ titel: "Herausgeber", wert: p.herausgeber, umbruch: false });
    if (p.homepage)
        z.push({ titel: "Webseite", wert: p.homepage, umbruch: false });
    if (p.installiertGroesse !== null)
        z.push({ titel: "Braucht", wert: groesseText(p.installiertGroesse) + " auf dem Gerät", umbruch: false });
    z.push({ titel: "Datei", wert: a.datei + (a.groesse !== null ? " · " + groesseText(a.groesse) : ""), umbruch: false });
    if (a.zusaetzlich.length > 0) {
        var namen = a.zusaetzlich.map(function (e) {
            return e.name;
        });
        z.push({ titel: "Dazu", wert: (namen.length === 1 ? "1 Paket: " : namen.length + " Pakete: ") + namenText(namen), umbruch: true });
    }
    // Nur, wenn der Inhalt gelesen wurde (eine frühe Ablehnung liest ihn nicht)
    if (a.dateien !== null) {
        var programme = a.programme.map(function (e) {
            return e.name;
        });
        z.push({ titel: "Programme", wert: programme.length > 0 ? namenText(programme) : "keins im Befehlsfeld", umbruch: false });
    }
    if (a.sha256)
        z.push({ titel: "SHA-256", wert: a.sha256, umbruch: true });
    return z;
}

// Text des Knopfs zum Installieren je Zustand
function knopfText(a) {
    if (!a)
        return "Installieren";
    if (a.zustand === "update")
        return "Aktualisieren";
    if (a.zustand === "rueckschritt")
        return "Ältere Version installieren";
    return "Installieren";
}

// Lage während des Laufs: Passwortdialog, Warten auf die Sperre, Prüfen, apt
function laufTitel(laufPhase, polkitOffen) {
    if (polkitOffen)
        return "Wartet auf dein Passwort …";
    switch (laufPhase) {
    case "wartet":
        return "Wartet auf ein laufendes Update …";
    case "prueft":
        return "Prüft das Paket noch einmal …";
    case "installiert":
        return "Wird installiert …";
    default:
        return "Wird vorbereitet …";
    }
}

function _lageAnsicht(a) {
    switch (a.ergebnis) {
    case "bereit":
        return {
            symbol: "info",
            ton: "akzent",
            titel: a.zustand === "update" ? "Update bereit" : a.zustand === "rueckschritt" ? "Ältere Version bereit" : "Bereit zum Installieren",
            satz: "«" + knopfText(a) + "» verlangt dein Passwort. Das Paket läuft dabei mit allen Rechten; was es mitbringt, steht unten."
        };
    case "installiert":
        return { symbol: "haken", ton: "akzent", titel: "Schon installiert", satz: "Diese Version ist schon auf dem Gerät." };
    case "abgelehnt":
        return { symbol: "warnung", ton: "warnung", titel: "Lässt sich nicht installieren", satz: a.grund };
    default:
        return { symbol: "warnung", ton: "warnung", titel: "Lässt sich nicht ansehen", satz: a.grund };
    }
}

// Das ganze Fenster in einer Phase. z: { phase, pfad, ansicht, ende, laufPhase, polkitOffen }
// Ergebnis: { name, zusammenfassung, kennung, symbol, lage {symbol, ton, titel, satz}, zeilen, hinweise, beschreibung,
//             primaer {text, aktion, aktiv, symbol} | null, sekundaer {text, aktion} }
// aktion: "installieren", "programm", "nochmal", "schliessen" oder "" (nur Anzeige)
function bild(z) {
    var phase = z && typeof z.phase === "string" ? z.phase : "";
    var a = z && z.ansicht ? z.ansicht : null;
    var e = z && z.ende ? z.ende : null;
    var pfad = z && typeof z.pfad === "string" ? z.pfad : "";
    var b = {
        name: phase === "ansehen" || !a ? dateiname(pfad) || "Paket" : anzeigeName(a, pfad),
        zusammenfassung: a && a.paket && phase !== "ansehen" ? a.paket.zusammenfassung : "",
        kennung: a && a.paket && phase !== "ansehen" ? a.paket.name + " " + a.paket.version : "",
        symbol: a && phase !== "ansehen" ? a.symbol : "",
        lage: null,
        zeilen: [],
        hinweise: [],
        beschreibung: "",
        primaer: null,
        sekundaer: { text: "Schliessen", aktion: "schliessen" }
    };
    var details = false;
    if (phase === "ansehen" || (phase !== "" && !a)) {
        b.lage = { symbol: "paket", ton: "gedaempft", titel: "Wird angesehen …", satz: "Liest das Paket und fragt apt, was dazukäme. Noch ändert sich nichts." };
        b.sekundaer = { text: "Abbrechen", aktion: "schliessen" };
    } else if (phase === "ansicht") {
        b.lage = _lageAnsicht(a);
        details = true;
        if (a.ergebnis === "bereit") {
            b.primaer = { text: knopfText(a), aktion: "installieren", aktiv: true, symbol: "schloss" };
            b.sekundaer = { text: "Abbrechen", aktion: "schliessen" };
        } else if (a.ergebnis === "installiert" && a.programme.length > 0) {
            b.primaer = { text: "Öffnen", aktion: "programm", aktiv: true, symbol: "" };
        }
    } else if (phase === "laeuft") {
        b.lage = {
            symbol: "info",
            ton: "akzent",
            titel: laufTitel(z.laufPhase, z.polkitOffen === true),
            satz: "Du kannst das Fenster schliessen: Die Installation läuft weiter, und eine Mitteilung sagt, wie sie ausging."
        };
        details = true;
        b.primaer = { text: z.polkitOffen === true ? "Wartet …" : "Läuft …", aktion: "", aktiv: false, symbol: "" };
    } else if (phase === "ende" && e) {
        b.lage = { symbol: e.symbol, ton: e.ton, titel: e.titel, satz: e.satz };
        if (e.ok && e.programme.length > 0)
            b.primaer = { text: "Öffnen", aktion: "programm", aktiv: true, symbol: "" };
        else if (e.nochmal)
            b.primaer = { text: "Noch einmal ansehen", aktion: "nochmal", aktiv: true, symbol: "" };
        b.sekundaer = { text: e.ok ? "Fertig" : "Schliessen", aktion: "schliessen" };
    } else {
        b.lage = { symbol: "paket", ton: "gedaempft", titel: "", satz: "" };
    }
    if (details) {
        b.zeilen = zeilen(a);
        b.hinweise = a.hinweise.slice();
        b.beschreibung = a.paket ? a.paket.beschreibung : "";
    }
    return b;
}

// Antwort von IPC «installer status»: zu, ansehen, bereit, installiert, abgelehnt, fehler, laeuft, fertig, gescheitert
function statusText(phase, ansicht, ende) {
    switch (phase) {
    case "ansehen":
        return "ansehen";
    case "ansicht":
        return ansicht ? ansicht.ergebnis : "ansehen";
    case "laeuft":
        return "laeuft";
    case "ende":
        return ende && ende.ok ? "fertig" : "gescheitert";
    default:
        return "zu";
    }
}

// --- Installieren -------------------------------------------------------------------

// pkexec-Aufruf für «Installieren», null, wenn die Ansicht nicht bereit oder unvollständig ist
function befehl(helfer, a) {
    if (typeof helfer !== "string" || helfer.charAt(0) !== "/" || !a || a.ergebnis !== "bereit")
        return null;
    if (pfadProblem(a.pfad) !== "" || !SHA_RE.test(a.sha256) || !PLAN_RE.test(a.plan))
        return null;
    return ["pkexec", helfer, "installieren", a.pfad, a.sha256, a.plan];
}

// letzte.json (oder das Feld «letzte» aus status --json): vereinfacht, null wenn unbrauchbar
function letzteLesen(json) {
    var d = _objekt(json);
    if (d === null || d.version !== 1 || LETZTE.indexOf(d.ergebnis) < 0)
        return null;
    return {
        art: d.art === "installieren" || d.art === "entfernen" ? d.art : "",
        ergebnis: d.ergebnis,
        grund: text(d.grund, 400),
        paket: typeof d.paket === "string" && PAKET_RE.test(d.paket) ? d.paket : "",
        anzeigename: text(d.anzeigename, 80),
        sha256: typeof d.sha256 === "string" && SHA_RE.test(d.sha256) ? d.sha256 : "",
        endeMs: zeitMs(d.ende),
        programme: _programme(d.programme)
    };
}

// «zenos-installer status --json»: { laeuft: [{art, paket, phase}], letzte }
function statusLesen(json) {
    var d = _objekt(json);
    var aus = { laeuft: [], letzte: null };
    if (d === null || d.version !== 1)
        return aus;
    if (Array.isArray(d.laeuft)) {
        for (var i = 0; i < d.laeuft.length && aus.laeuft.length < 10; i++) {
            var j = d.laeuft[i];
            if (j && (j.art === "installieren" || j.art === "entfernen"))
                aus.laeuft.push({ art: j.art, paket: typeof j.paket === "string" && PAKET_RE.test(j.paket) ? j.paket : "", phase: LAUF_PHASEN.indexOf(j.phase) >= 0 ? j.phase : "" });
        }
    }
    aus.letzte = letzteLesen(d.letzte);
    return aus;
}

// Phase der laufenden Installation aus status --json («wartet», «prueft», «installiert») oder ""
function laufPhase(status) {
    if (!status || !Array.isArray(status.laeuft))
        return "";
    for (var i = 0; i < status.laeuft.length; i++) {
        if (status.laeuft[i].art === "installieren")
            return status.laeuft[i].phase;
    }
    return "";
}

// Letzte Zeile von stderr ohne den Programmnamen davor
function _meldung(fehler) {
    var zeilen = typeof fehler === "string" ? fehler.trim().split("\n") : [];
    var t = text(zeilen[zeilen.length - 1] || "", 300);
    return t.replace(/^zenos-installer(-bedienen)?: /, "");
}

// Ergebnis nach dem Ende von pkexec. code: Exit (-1: liess sich nicht starten); info: { letzte (letzteLesen), sha256,
// beginnMs, fehler (stderr), name (Anzeigename), programme (aus der Ansicht) }.
// { art: "zurueck" } heisst: Passwortabfrage abgebrochen, zurück zur Ansicht ohne Meldung. Sonst { art: "ende", ok,
// ergebnis, symbol, ton, titel, satz, programme, nochmal }.
// letzte.json zählt nur, wenn sie zu genau dieser Datei gehört und nach dem Klick entstand.
function abschluss(code, info) {
    var i = info || {};
    var l = i.letzte || null;
    var passt = l !== null && l.art === "installieren" && l.sha256 !== "" && l.sha256 === i.sha256 && isFinite(l.endeMs) && typeof i.beginnMs === "number" && l.endeMs >= Math.floor(i.beginnMs / 1000) * 1000 - 2000;
    var name = (passt && l.anzeigename) || text(i.name, 80) || "Die Software";
    var meldung = _meldung(i.fehler);
    var ende = { art: "ende", ok: false, ergebnis: "fehler", symbol: "warnung", ton: "warnung", titel: "", satz: "", programme: [], nochmal: false };
    if (code === 126)
        return { art: "zurueck" };
    if (code === 0) {
        ende.ok = true;
        ende.symbol = "haken";
        ende.ton = "akzent";
        // Ohne passende letzte.json die Starter aus der Ansicht (dieselbe Datei)
        ende.programme = passt ? l.programme : _programme(i.programme);
        if (passt && l.ergebnis === "gleich") {
            ende.ergebnis = "gleich";
            ende.titel = "Schon installiert";
            ende.satz = l.grund || name + " ist schon installiert.";
        } else {
            ende.ergebnis = "installiert";
            ende.titel = name + " ist installiert";
            ende.satz = ende.programme.length > 0 ? "Du findest es im Befehlsfeld." : "Es bringt keinen Starter mit und erscheint deshalb nicht im Befehlsfeld.";
        }
        return ende;
    }
    switch (code) {
    case 3:
        ende.ergebnis = "abgelehnt";
        ende.titel = "Nicht installiert";
        ende.satz = (passt && l.grund) || meldung || "Die Datei oder das, was apt dazu bräuchte, hat sich seit dem Ansehen geändert.";
        ende.nochmal = true;
        break;
    case 10:
        ende.ergebnis = "wartet";
        ende.titel = "Abgebrochen";
        ende.satz = "Abgebrochen, bevor sich etwas änderte (wird das Gerät gerade ausgeschaltet?).";
        ende.nochmal = true;
        break;
    case 75:
        ende.ergebnis = "wartet";
        ende.titel = "Gerade nicht";
        ende.satz = (passt && l.grund) || "Gerade läuft ein Update oder ein anderer Paketvorgang. Später noch einmal.";
        ende.nochmal = true;
        break;
    case 127:
        ende.titel = "Nicht erlaubt";
        ende.satz = /authentication agent/i.test(i.fehler || "") ? "Es ist kein Passwortdialog erreichbar (polkit-Agent fehlt). Im Terminal: zen install." : "Installieren geht nur in der aktiven Sitzung am Gerät.";
        break;
    case -1:
        ende.titel = "Installation gescheitert";
        ende.satz = "pkexec lässt sich nicht starten.";
        break;
    default:
        ende.titel = "Installation gescheitert";
        ende.satz = (passt && l.grund) || meldung || "zenos-installer endete mit Exit " + code + ".";
    }
    return ende;
}

// Mitteilung, wenn das Fenster schon zu ist: ruhig (low) nach Erfolg, sonst normal
function mitteilung(ende) {
    if (!ende || ende.art !== "ende")
        return null;
    return { titel: ende.titel, text: ende.satz, dringlichkeit: ende.ok ? "low" : "normal" };
}

function mitteilungBefehl(m) {
    var d = ["low", "normal"].indexOf(m.dringlichkeit) >= 0 ? m.dringlichkeit : "normal";
    return ["notify-send", "--app-name=zen Installer", "--icon=zenos", "--urgency=" + d, "--category=system", "--", text(m.titel, 120), text(m.text, 400)];
}

// «Öffnen»: der erste Starter. { id (ohne .desktop, für DesktopEntries), pfad (für gio launch, falls DesktopEntries ihn
// noch nicht kennt) } oder null
function programmZiel(programme) {
    var liste = _programme(programme);
    if (liste.length === 0)
        return null;
    return { id: liste[0].id.replace(/\.desktop$/, ""), pfad: "/usr/share/applications/" + liste[0].id };
}
