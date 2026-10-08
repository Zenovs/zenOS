.pragma library
.import "kanal.js" as Kanal
// Logik der Basis-Updates in der Oberfläche (dienste/Basis.qml) ohne QML: stand.json, letzte.json, automatik.json und
// /run/reboot-required lesen, die Texte für Einstellungen › System › Updates (Abschnitt Ubuntu-Basis), den
// Neustart-Hinweis in Leiste und System-Menü, die Mitteilungen (jede nur einmal) und die Argumentlisten für den Helfer.
// Getestet mit test/einheiten/basis.test.mjs (node). Reiner Text, Zeiten und notify-send wie beim Kanal (kanal.js).
//
// Quellen (von root geschrieben, für alle lesbar; die Oberfläche liest nur):
//   /var/lib/zenos/basis/stand.json      letzte Prüfung (zenos-basis pruefen; Felder in docs/image-und-releases.md)
//   /var/lib/zenos/basis/letzte.json     letzte Installation, nur wenn apt lief (installiert, kaputt, fehler); ein
//                                        «kaputt» mit «behoben» (zenos-basis quittieren) gilt als behoben
//   /var/lib/zenos/basis/automatik.json  letzter Lauf der Automatik (zustimmung, gesperrt: wartet auf Zeno)
//   /etc/xdg/zenos/kanal-automatik-aus   gemeinsamer Notschalter von Kanal und Basis (es zählt, ob es ihn gibt)
//   /run/reboot-required(.pkgs)          Neustart nötig (Ubuntu, unattended-upgrades; zenos-basis trägt greetd ein)

// Ergebnisse der Prüfung (verdict in zenos-basis), der Installation (RESULT_TEXT) und der Automatik (AutoRun)
var ERGEBNISSE = Object.freeze(["aktuell", "bereit", "zustimmung", "gesperrt", "fehler"]);
var INSTALLATIONEN = Object.freeze(["installiert", "aktuell", "kaputt", "fehler", "abgelehnt", "wartet"]);
var AUTOMATIK = Object.freeze(["aus", "nichts", "aktuell", "wartet", "zustimmung", "gesperrt", "installiert", "kaputt", "fehler", "abgelehnt"]);
// Wer installiert hat (ORIGINS in zenos-basis)
var HERKUNFT = Object.freeze({ "zen update": "zen update", "einstellungen": "Einstellungen", "automatik": "automatisch", "hand": "von Hand" });
var INSTALLATION_TEXT = Object.freeze({ installiert: "installiert", aktuell: "aktuell", kaputt: "kaputt", behoben: "kaputt, behoben", fehler: "gescheitert", abgelehnt: "abgelehnt", wartet: "wartet" });
// So meldet Zeno ein «kaputt» als behoben (im Terminal; prüft nach, was sich prüfen lässt)
var QUITTIEREN = "sudo /usr/local/libexec/zenos/zenos-basis quittieren";
// So viele Paketnamen in einem Satz, dann «und N weitere»
var NAMEN_SATZ = 3;
// Ein «installiert», das älter ist, meldet die Oberfläche nicht mehr (wie beim Kanal)
var ERGEBNIS_FRISCH_MS = 24 * 3600 * 1000;
// Beginn des Grundes, wenn apt-get update scheiterte (cmd_check in zenos-basis): meist ohne Netz
var OHNE_NETZ = "Prüfung gescheitert: apt-get update endete mit Exit";

var LISTE_RE = /^[0-9a-f]{40}$/;
var PAKET_RE = /^[a-z0-9][a-z0-9+.-]{0,127}(?::[a-z0-9]+)?$/;

// Was für jeden Zeitpunkt gilt, nur für die Basis (unter der Erklärung in «Automatisch installieren»)
var AUTOMATIK_IMMER = "Pakete der Ubuntu-Basis kommen auch auf dev, aber nie während einer SSH-Sitzung und nie mit Kernel, Firmware, Bootloader oder Entfernungen; neu gestartet wird nie.";

// --- Lesen --------------------------------------------------------------------

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

// Ganze Zahl ab 0, sonst 0
function _zahl(wert) {
    return typeof wert === "number" && isFinite(wert) && wert >= 0 ? Math.floor(wert) : 0;
}

// Paketnamen (ohne Doppelte, höchstens max)
function _namen(wert, max) {
    var aus = [];
    if (!Array.isArray(wert))
        return aus;
    var n = typeof max === "number" ? max : 200;
    for (var i = 0; i < wert.length && aus.length < n; i++) {
        if (typeof wert[i] === "string" && PAKET_RE.test(wert[i]) && aus.indexOf(wert[i]) < 0)
            aus.push(wert[i]);
    }
    return aus;
}

function _liste(wert) {
    return typeof wert === "string" && LISTE_RE.test(wert) ? wert : "";
}

// «linux-raspi, flash-kernel, rpi-eeprom und 2 weitere» (wie names_text in zenos-basis, kürzer)
function namenText(namen, max) {
    var n = typeof max === "number" && max >= 1 ? max : NAMEN_SATZ;
    if (!Array.isArray(namen) || namen.length === 0)
        return "";
    return namen.slice(0, n).join(", ") + (namen.length > n ? " und " + (namen.length - n) + " weitere" : "");
}

// «1 Update», «12 Updates»
function anzahlText(n) {
    return n + (n === 1 ? " Update" : " Updates");
}

// stand.json (Version 1) geprüft und vereinfacht, null wenn sie fehlt oder unbrauchbar ist
function standLesen(json) {
    var d = _objekt(json);
    if (d === null || d.version !== 1)
        return null;
    var ergebnis = ERGEBNISSE.indexOf(d.ergebnis) >= 0 ? d.ergebnis : "fehler";
    var liste = _liste(d.liste);
    // Ohne gültige Liste lässt sich nichts installieren
    if ((ergebnis === "bereit" || ergebnis === "zustimmung") && liste === "")
        ergebnis = "fehler";
    var pakete = Array.isArray(d.pakete) ? d.pakete.slice(0, 5000) : [];
    // Herstellerquellen (Herkunft nicht Ubuntu), und für die Mitteilung «warten auf dich» die heiklen Pakete mit Version
    var hersteller = [];
    var heikelStand = [];
    for (var i = 0; i < pakete.length; i++) {
        var p = pakete[i];
        if (!p || typeof p !== "object")
            continue;
        var herkunft = Kanal.text(p.herkunft, 40);
        if (herkunft !== "" && herkunft !== "Ubuntu" && hersteller.indexOf(herkunft) < 0 && hersteller.length < 8)
            hersteller.push(herkunft);
        if (p.heikel === true && typeof p.name === "string" && PAKET_RE.test(p.name))
            heikelStand.push(p.name + "=" + Kanal.text(p.neu, 80));
    }
    heikelStand.sort();
    var entfernen = _namen(d.entfernen);
    var geschuetzt = _namen(d.geschuetzt);
    return {
        ergebnis: ergebnis,
        grund: Kanal.text(d.grund, 400),
        liste: liste,
        anzahl: _zahl(d.anzahl),
        sicherheit: _zahl(d.sicherheit),
        heikel: _namen(d.heikel),
        entfernen: entfernen,
        geschuetzt: geschuetzt,
        neustart: d.neustart === true,
        neustartWegen: _namen(d.neustart_wegen),
        hersteller: hersteller,
        zeitMs: Kanal.zeitMs(d.zeit),
        geprueftMs: Kanal.zeitMs(d.geprueft),
        // Was eine Zustimmung braucht oder sperrt, unabhängig von den übrigen Paketen: Die Mitteilung «warten auf dich»
        // kommt so nicht bei jeder neuen Liste wieder, sondern nur, wenn sich Kernel, Firmware, Bootloader oder die
        // Entfernungen ändern (höchstens einmal je Liste)
        wartetSchluessel: heikelStand.concat(entfernen.map(function (n) {
            return "-" + n;
        })).concat(geschuetzt.map(function (n) {
            return "!" + n;
        })).join(" ")
    };
}

// letzte.json: { ergebnis, grund, endeMs, liste, von, anzahl, neustart } oder null. Ein «kaputt», das Zeno mit
// «zenos-basis quittieren» als behoben vermerkt hat, heisst hier «behoben»: keine Warnung, keine Mitteilung mehr
function letzteLesen(json) {
    var d = _objekt(json);
    if (d === null || d.version !== 1 || INSTALLATIONEN.indexOf(d.ergebnis) < 0)
        return null;
    return {
        ergebnis: d.ergebnis === "kaputt" && isFinite(Kanal.zeitMs(d.behoben)) ? "behoben" : d.ergebnis,
        grund: Kanal.text(d.grund, 400),
        endeMs: Kanal.zeitMs(d.ende),
        liste: _liste(d.liste),
        von: HERKUNFT[d.von] !== undefined ? d.von : "",
        geaendert: _zahl(d.geaendert),
        neustart: d.neustart === true
    };
}

// automatik.json: { art, ergebnis, grund, endeMs, liste } oder null
function automatikLesen(json) {
    var d = _objekt(json);
    if (d === null || d.version !== 1 || AUTOMATIK.indexOf(d.ergebnis) < 0)
        return null;
    return {
        art: d.art === "lauf" || d.art === "gelegenheit" ? d.art : "",
        ergebnis: d.ergebnis,
        grund: Kanal.text(d.grund, 300),
        endeMs: Kanal.zeitMs(d.ende),
        liste: _liste(d.liste)
    };
}

// /run/reboot-required: da (die Datei gibt es), pakete: Inhalt von /run/reboot-required.pkgs (eine Zeile je Paket)
function neustartLesen(da, pakete) {
    var namen = [];
    if (da && typeof pakete === "string") {
        var zeilen = pakete.split("\n");
        for (var i = 0; i < zeilen.length && namen.length < 100; i++) {
            var n = zeilen[i].trim();
            if (PAKET_RE.test(n) && namen.indexOf(n) < 0)
                namen.push(n);
        }
        namen.sort();
    }
    return { noetig: !!da, pakete: namen };
}

// Leitplanke (Code, nicht Konfiguration): Der Hinweis «Neustart nötig» in Leiste und System-Menü erscheint nur bei
// voller Leiste. Nie während der Bildschirm geteilt wird, nie bei reduzierter oder ausgeblendeter Leiste (etwa im
// Zustand «Sitzung»), nie gesperrt; keine Mitteilung, kein Popup. leiste: Schlüssel des wirksamen Zustands
function neustartHinweis(noetig, freigabe, leiste, gesperrt) {
    return noetig === true && freigabe !== true && gesperrt !== true && leiste !== "reduziert" && leiste !== "aus";
}

// --- Anzeige ------------------------------------------------------------------

// Seit der letzten Prüfung wurde installiert: Die Angaben in stand.json sind überholt, bis neu geprüft ist
function veraltet(stand, letzte) {
    return !!stand && !!letzte && isFinite(letzte.endeMs) && (!isFinite(stand.zeitMs) || letzte.endeMs > stand.zeitMs + 2000);
}

function _ohneNetz(stand) {
    return !!stand && stand.ergebnis === "fehler" && stand.grund.indexOf(OHNE_NETZ) === 0;
}

// «12 Updates, davon 3 Sicherheit» bzw. «keine Updates»
function ausstehendText(stand) {
    if (!stand || (stand.anzahl === 0 && stand.entfernen.length === 0))
        return "keine Updates";
    if (stand.anzahl === 0)
        return stand.entfernen.length === 1 ? "1 Entfernung" : stand.entfernen.length + " Entfernungen";
    return anzahlText(stand.anzahl) + (stand.sicherheit > 0 ? ", davon " + stand.sicherheit + " Sicherheit" : "");
}

// Für die Zeile «Ausstehend»: «12 Updates · 3 Sicherheit · 1 Entfernung» bzw. «keine»
function ausstehendKurz(stand) {
    if (!stand || (stand.anzahl === 0 && stand.entfernen.length === 0))
        return "keine";
    var teile = [];
    if (stand.anzahl > 0)
        teile.push(anzahlText(stand.anzahl));
    if (stand.sicherheit > 0)
        teile.push(stand.sicherheit + " Sicherheit");
    if (stand.entfernen.length > 0)
        teile.push(stand.entfernen.length === 1 ? "1 Entfernung" : stand.entfernen.length + " Entfernungen");
    return teile.join(" · ");
}

// Titel der Lage. laeuft: ein Basis-Update läuft gerade (Übernahme-Marker)
function zustandTitel(stand, istVeraltet, letzte, laeuft) {
    if (laeuft)
        return "Update läuft";
    if (letzte && letzte.ergebnis === "kaputt")
        return "Basis-Update kaputt";
    if (!stand)
        return "Noch nie geprüft";
    if (istVeraltet)
        return "Seit der letzten Prüfung installiert";
    switch (stand.ergebnis) {
    case "aktuell":
        return "Aktuell";
    case "bereit":
        return anzahlText(stand.anzahl) + " bereit";
    case "zustimmung":
        if (stand.anzahl === 0)
            return "Entfernungen warten auf dich";
        return anzahlText(stand.anzahl) + (stand.anzahl === 1 ? " wartet auf dich" : " warten auf dich");
    case "gesperrt":
        return "Gesperrt";
    default:
        return _ohneNetz(stand) ? "Kein Kontakt zu den Paketquellen" : "Prüfung gescheitert";
    }
}

// Symbol und Ton der Lage: { symbol, ton: "akzent" | "warnung" | "gedaempft" }
function zustandSymbol(stand, istVeraltet, letzte, laeuft) {
    if (laeuft)
        return { symbol: "info", ton: "akzent" };
    if (letzte && letzte.ergebnis === "kaputt")
        return { symbol: "warnung", ton: "warnung" };
    if (!stand || istVeraltet)
        return { symbol: "info", ton: "gedaempft" };
    switch (stand.ergebnis) {
    case "aktuell":
        return { symbol: "haken", ton: "akzent" };
    case "bereit":
        return { symbol: "info", ton: "akzent" };
    case "zustimmung":
        return { symbol: "schloss", ton: "akzent" };
    default:
        return _ohneNetz(stand) ? { symbol: "wolke", ton: "gedaempft" } : { symbol: "warnung", ton: "warnung" };
    }
}

// Wann eine bereite Liste automatisch kommt, abgestimmt auf Zeitpunkt (kanal.js zeitpunktLesen) und Notschalter
function bereitWann(zeitpunkt, automatikAn) {
    if (!automatikAn)
        return "Automatisch kommt nichts (Automatik aus; einschalten: sudo zen kanal automatik an).";
    switch (zeitpunkt ? zeitpunkt.art : "sperre") {
    case "hand":
        return "Automatisch kommt nichts (Zeitpunkt «Von Hand»).";
    case "fenster":
        return "Kommt automatisch zwischen " + zeitpunkt.von + " und " + zeitpunkt.bis + " Uhr, nicht während einer SSH-Sitzung.";
    case "jederzeit":
        return "Kommt automatisch innert 15 Minuten, nicht während einer SSH-Sitzung.";
    default:
        return "Kommt automatisch bei der nächsten Sperre, nicht während einer SSH-Sitzung.";
    }
}

// Erklärung unter dem Titel (reiner Text). lage: { zeitpunkt, automatikAn }
function grundText(stand, istVeraltet, letzte, laeuft, lage) {
    var l = lage || {};
    if (laeuft)
        return "zenOS aktualisiert gerade die Pakete der Ubuntu-Basis (apt, danach install.sh). Ausschalten und Neustart warten, bis es fertig ist; danach lädt die Oberfläche neu, wenn sich etwas geändert hat.";
    if (letzte && letzte.ergebnis === "kaputt")
        return (letzte.grund !== "" ? letzte.grund : "Nach dem Update ist etwas schlechter als vorher. Zurückgerollt wird nichts; Einzelheiten: journalctl -u zenos-basis-installieren.") + " Behoben? Im Terminal: " + QUITTIEREN;
    if (!stand)
        return "Mit «Jetzt prüfen» holt zenOS die Paketlisten von Ubuntu und den Herstellerquellen (apt-get update) und zeigt, was ansteht. Installiert wird dabei nichts.";
    if (istVeraltet)
        return (letzte && letzte.grund !== "" ? letzte.grund + " " : "") + "«Jetzt prüfen» zeigt den neuen Stand.";
    switch (stand.ergebnis) {
    case "aktuell":
        return "Alle Pakete der Ubuntu-Basis sind aktuell. Sicherheitsupdates spielt Ubuntu weiter jeden Tag selbst ein.";
    case "bereit":
        return ausstehendText(stand) + ", ohne Kernel, Firmware, Bootloader und Entfernungen. " + bereitWann(l.zeitpunkt, l.automatikAn !== false);
    case "zustimmung":
        var was = [];
        if (stand.heikel.length > 0)
            was.push("Kernel, Firmware oder Bootloader (" + namenText(stand.heikel) + ")");
        if (stand.entfernen.length > 0)
            was.push("Entfernungen (" + namenText(stand.entfernen) + ")");
        return ausstehendText(stand) + ". Dabei sind " + was.join(" und ") + ": Das kommt nie automatisch, nur mit deinem Passwort oder mit zen update." + (stand.heikel.length > 0 ? " Danach ist ein Neustart nötig." : "");
    default:
        return stand.grund !== "" ? stand.grund : "Mehr im Terminal: zen update";
    }
}

// Letzter Lauf der Automatik, kurz für die Zeile «Automatik»: «nicht jetzt: SSH-Sitzung», «wartet auf dich (…)» …
function automatikKurz(a) {
    if (!a)
        return "";
    switch (a.ergebnis) {
    case "aus":
        return "Automatik war aus";
    case "nichts":
        return "noch keine Prüfung";
    case "aktuell":
        return "nichts zu tun";
    case "installiert":
        return "installiert";
    case "zustimmung":
        return "wartet auf dich (Kernel, Firmware, Bootloader oder Entfernungen)";
    case "gesperrt":
        return "gesperrt (geschütztes Paket)";
    default:
        var i = a.grund.indexOf("nicht jetzt: ");
        if (a.ergebnis === "wartet" && i >= 0)
            return a.grund.slice(i).replace(/\.$/, "");
        return a.grund !== "" ? a.grund : a.ergebnis;
    }
}

// Zeilen unter der Lage: [{ titel, wert }] (Werte in Mono). neustart: neustartLesen; lage: { automatik, automatikAn,
// jetztMs }
function zeilen(stand, letzte, neustart, lage) {
    var l = lage || {};
    var jetzt = typeof l.jetztMs === "number" ? l.jetztMs : Date.now();
    var aus = [];
    var offen = !!stand && (stand.ergebnis === "bereit" || stand.ergebnis === "zustimmung" || stand.ergebnis === "gesperrt");
    if (stand && stand.ergebnis !== "fehler")
        aus.push({ titel: "Ausstehend", wert: ausstehendKurz(stand) });
    if (offen && stand.heikel.length > 0)
        aus.push({ titel: "Kernel/Boot", wert: namenText(stand.heikel, 6) });
    if (offen && stand.entfernen.length > 0)
        aus.push({ titel: "Entfernen", wert: namenText(stand.entfernen, 6) });
    if (stand && stand.ergebnis === "gesperrt" && stand.geschuetzt.length > 0)
        aus.push({ titel: "Geschützt", wert: namenText(stand.geschuetzt, 6) + " ginge weg" });
    if (offen && stand.hersteller.length > 0)
        aus.push({ titel: "Hersteller", wert: stand.hersteller.join(", ") });
    if (neustart && neustart.noetig)
        aus.push({ titel: "Neustart", wert: "nötig" + (neustart.pakete.length > 0 ? " · " + namenText(neustart.pakete, 4) : "") });
    else if (offen && stand.neustart)
        aus.push({ titel: "Neustart", wert: "voraussichtlich nach dem Update" });
    if (letzte && isFinite(letzte.endeMs))
        aus.push({ titel: "Letztes Update", wert: INSTALLATION_TEXT[letzte.ergebnis] + " · " + Kanal.zeitText(letzte.endeMs, jetzt) + (letzte.von !== "" ? " · " + HERKUNFT[letzte.von] : "") });
    if (l.automatikAn === false)
        aus.push({ titel: "Automatik", wert: "aus · einschalten: sudo zen kanal automatik an" });
    else if (l.automatik && isFinite(l.automatik.endeMs))
        aus.push({ titel: "Automatik", wert: Kanal.zeitText(l.automatik.endeMs, jetzt) + " · " + automatikKurz(l.automatik) });
    if (stand)
        aus.push({ titel: "Geprüft", wert: (isFinite(stand.geprueftMs) ? Kanal.zeitText(stand.geprueftMs, jetzt) : "nie") + (stand.ergebnis === "fehler" ? " · letzter Versuch gescheitert" : "") });
    if (offen && stand.liste !== "")
        aus.push({ titel: "Liste", wert: stand.liste.slice(0, 12) });
    return aus;
}

// Liste für «Jetzt installieren» (ohne Passwort): nur «bereit», nicht veraltet, sonst ""
function installierenListe(stand, istVeraltet) {
    return !!stand && !istVeraltet && stand.ergebnis === "bereit" ? stand.liste : "";
}

// Liste für «Mit Passwort installieren»: nur «zustimmung» (Kernel, Firmware, Bootloader, Entfernungen), sonst ""
function zustimmungListe(stand, istVeraltet) {
    return !!stand && !istVeraltet && stand.ergebnis === "zustimmung" ? stand.liste : "";
}

// Satz unter den Knöpfen
function knopfHinweis(stand, istVeraltet) {
    if (installierenListe(stand, istVeraltet) !== "")
        return "Installiert genau die angezeigte Liste (" + stand.liste.slice(0, 12) + "), ohne neue Prüfung. Dienste starten dabei neu, die Anmeldung erst beim nächsten Neustart.";
    if (zustimmungListe(stand, istVeraltet) !== "")
        return "Verlangt dein Passwort und gilt nur für die angezeigte Liste (" + stand.liste.slice(0, 12) + ")." + (stand.heikel.length > 0 ? " zenOS startet danach nie selbst neu." : "");
    return "";
}

// --- Mitteilungen -------------------------------------------------------------

// Gemerkte Mitteilungen (~/.local/state/zenos/basis-meldungen.json), geprüft
function gemeldetLesen(json) {
    var d = _objekt(json) || {};
    var s = function (w) {
        return typeof w === "string" ? w.slice(0, 4000) : "";
    };
    return { installation: s(d.installation), warten: s(d.warten) };
}

function gemeldetText(g) {
    return JSON.stringify({ version: 1, installation: g.installation, warten: g.warten }, null, 1) + "\n";
}

function _meldung(schluessel, titel, inhalt, dringlichkeit) {
    return { schluessel: schluessel, titel: Kanal.text(titel, 120), text: Kanal.text(inhalt, 400), dringlichkeit: dringlichkeit };
}

// Welche Mitteilungen jetzt fällig sind. lage: { stand, letzte, automatik, veraltet }, gemeldet: aus gemeldetLesen.
// Rückgabe: { neu: [{ schluessel, titel, text, dringlichkeit }], gemeldet } – gemeldet ist der neue Stand zum Merken.
//   installiert  still (low)  ein Basis-Update ist fertig und gesund (höchstens 24 h alt)
//   kaputt       dringend     nach dem Update schlechter als vorher (auch alt)
//   fehler       normal       apt scheiterte (auch alt)
//   warten       normal       die Automatik sah Kernel, Firmware, Bootloader oder Entfernungen («zustimmung») bzw. ein
//                             geschütztes Paket («gesperrt»): einmal, bis sich genau das ändert (höchstens einmal je
//                             Liste). Nichts zu «Neustart nötig» (dafür gibt es den stillen Hinweis in der Leiste).
function meldungen(lage, gemeldet, jetztMs) {
    var g = gemeldetLesen(gemeldet ? gemeldetText(gemeldet) : "");
    var neu = [];
    var stand = lage ? lage.stand : null;
    var letzte = lage ? lage.letzte : null;
    var automatik = lage ? lage.automatik : null;

    if (letzte && isFinite(letzte.endeMs)) {
        var schluessel = letzte.ergebnis + "@" + new Date(letzte.endeMs).toISOString();
        var frisch = letzte.endeMs >= jetztMs - ERGEBNIS_FRISCH_MS && letzte.endeMs <= jetztMs + 3600000;
        if (schluessel !== g.installation && ["installiert", "kaputt", "fehler"].indexOf(letzte.ergebnis) >= 0) {
            g.installation = schluessel;
            if (letzte.ergebnis === "kaputt")
                neu.push(_meldung("kaputt", "Basis-Update kaputt", letzte.grund !== "" ? letzte.grund : "Nach dem Update ist etwas schlechter als vorher. Mehr: Einstellungen › System › Updates.", "critical"));
            else if (letzte.ergebnis === "fehler")
                neu.push(_meldung("fehler", "Basis-Update gescheitert", letzte.grund !== "" ? letzte.grund : "Mehr: journalctl -u zenos-basis-installieren", "normal"));
            else if (frisch)
                neu.push(_meldung("installiert", "Ubuntu-Basis aktualisiert", letzte.grund !== "" ? letzte.grund : "Die Pakete sind aktualisiert.", "low"));
        }
    }

    // Nur, was die Automatik gesehen hat und die letzte Prüfung noch so zeigt (nicht veraltet, dieselbe Liste)
    var klar = !!stand && !(lage && lage.veraltet) && stand.ergebnis !== "fehler";
    if (klar) {
        var wartet = (stand.ergebnis === "zustimmung" || stand.ergebnis === "gesperrt") && !!automatik && automatik.ergebnis === stand.ergebnis && automatik.liste === stand.liste && stand.liste !== "";
        var warten = wartet ? stand.ergebnis + ":" + (stand.wartetSchluessel !== "" ? stand.wartetSchluessel : stand.liste) : "";
        if (warten !== "" && warten !== g.warten) {
            if (stand.ergebnis === "gesperrt")
                neu.push(_meldung("warten", "Basis-Updates gesperrt", "apt würde geschützte Pakete entfernen (" + namenText(stand.geschuetzt) + "). zenOS installiert das nicht, auch nicht mit Zustimmung. Ansehen: Einstellungen › System › Updates.", "normal"));
            else
                neu.push(_meldung("warten", "Basis-Updates warten auf dich", grundText(stand, false, null, false, null) + " Ansehen: Einstellungen › System › Updates.", "normal"));
        }
        // Vorbei erst, wenn die Prüfung etwas anderes zeigt als «zustimmung» oder «gesperrt»
        if (warten !== "" || (stand.ergebnis !== "zustimmung" && stand.ergebnis !== "gesperrt"))
            g.warten = warten;
    }
    return { neu: neu, gemeldet: g };
}

// --- Bedienung ----------------------------------------------------------------

// pkexec-Aufruf für den Helfer (zenos-kanal-bedienen, Wörter basis-…), null bei falschen Werten. aktion: pruefen |
// installieren (liste: installierenListe) | zustimmen (liste: zustimmungListe)
function befehl(helfer, aktion, liste) {
    if (typeof helfer !== "string" || helfer.charAt(0) !== "/")
        return null;
    switch (aktion) {
    case "pruefen":
        return ["pkexec", helfer, "basis-pruefen"];
    case "installieren":
        return typeof liste === "string" && LISTE_RE.test(liste) ? ["pkexec", helfer, "basis-installieren", liste] : null;
    case "zustimmen":
        return typeof liste === "string" && LISTE_RE.test(liste) ? ["pkexec", helfer, "basis-installieren-zustimmen", liste] : null;
    default:
        return null;
    }
}

// Rückmeldung nach einem Aufruf als { text, art: "" (Bestätigung) | "warnung" } oder null (nichts zeigen: die Seite
// oder eine Mitteilung sagt es schon). info: { fehler: stderr, installiert: letzte.json seit dem Start neu, stand:
// standLesen danach, kanalProblem: der zenOS-Kanal ist unterbrochen oder kaputt }
function rueckmeldung(aktion, code, info) {
    var i = info || {};
    var fehler = Kanal.text(i.fehler || "", 160).replace(/^zenos-(kanal-bedienen|basis)( [a-z]+)?:\s*/, "");
    var stand = i.stand || null;
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
        if (code === 0)
            return { text: "Ubuntu-Basis geprüft", art: "" };
        if (code === 3)
            return { text: "Ubuntu-Basis geprüft: gesperrt", art: "warnung" };
        if (_ohneNetz(stand))
            return { text: "Kein Kontakt zu den Paketquellen: geprüft wurde der letzte geholte Stand", art: "warnung" };
        if (fehler === "" && stand && stand.ergebnis === "fehler" && stand.grund !== "")
            fehler = Kanal.text(stand.grund.replace(/^Prüfung gescheitert:\s*/, ""), 160);
        return { text: "Prüfung gescheitert" + (fehler !== "" ? ": " + fehler : " (journalctl -u zenos-basis-pruefen)"), art: "warnung" };
    case "installieren":
    case "zustimmen":
        if (i.installiert)
            return null; // die Mitteilung zur Installation kommt ohnehin
        if (code === 0)
            return { text: "Die Ubuntu-Basis ist schon aktuell", art: "" };
        if (code === 3 && stand && stand.ergebnis === "gesperrt")
            return { text: "Nicht installiert: apt würde geschützte Pakete entfernen", art: "warnung" };
        if (code === 3)
            return { text: "Die Liste hat sich geändert: bitte noch einmal ansehen", art: "warnung" };
        if (code === 10 && i.kanalProblem)
            return { text: "Basis-Update wartet: zuerst den zenOS-Kanal in Ordnung bringen (zen update)", art: "warnung" };
        if (code === 10 && aktion === "installieren" && stand && stand.ergebnis === "zustimmung")
            return { text: "Kernel, Firmware, Bootloader oder Entfernungen: nur mit deinem Passwort", art: "warnung" };
        if (code === 10)
            return { text: "Basis-Update wartet · mehr: journalctl -u zenos-basis-installieren", art: "warnung" };
        if (code === 5)
            return null; // kaputt: letzte.json und die Mitteilung sagen es
        return { text: "Basis-Update gescheitert" + (fehler !== "" ? ": " + fehler : " · mehr: journalctl -u zenos-basis-installieren"), art: "warnung" };
    default:
        return null;
    }
}
