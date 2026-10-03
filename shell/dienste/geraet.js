.pragma library
// Logik der Geräteanzeige ohne QML: /run/zenos/geraet.json (von zenos-argon) prüfen und für Leiste und
// System-Menü aufbereiten, dazu die Warnungen bei niedrigem Akku. Getestet mit test/einheiten/geraet.test.mjs.
//
// Datei (Version 1, siehe docs/module/m13.md):
//   { version: 1, zeit: ISO-8601, geraet: "argon-one-v3" | "argon-one-up",
//     akku: { vorhanden, prozent (int|null), laedt (bool|null),
//             zustand: "ok" | "unbekannt" | "fehler" | "freigabe" (misst nicht, Freigabe fehlt: zen akku freigeben) },
//     luefter: { vorhanden, prozent } (V3) oder { vorhanden, stufe, stufen, upm } (Kernel), seit Oktober 2026 dazu
//              modus ("auto" | "mindest"), mindeststufe (1–4 | null), steuerbar (zenos-argon kann den Wunsch umsetzen),
//     temperatur: { cpu } }
// Fehlen modus, mindeststufe und steuerbar (älterer Dienst), bleibt die Zeile «Lüfter» reine Anzeige.

// Der Dienst schreibt alle 15 s (beim V3 alle 5 s). Ältere Werte gelten als unbekannt (Dienst hängt oder ist aus).
var MAX_ALTER_MS = 60000;
// Warnstufen in %: nur beim Entladen, je einmal pro Unterschreiten, zurückgesetzt beim Laden
var WARNSTUFEN = [10, 5];
// Ab hier (und beim Entladen) steht der Akku in der Leiste in der Warnfarbe
var NIEDRIG = 10;

function _ganz(wert, min, max) {
    return typeof wert === "number" && isFinite(wert) && Math.round(wert) === wert && wert >= min && wert <= max ? wert : -1;
}

// Leerer Zustand: nichts vorhanden, alles unbekannt
function leer() {
    return {
        frisch: false,
        geraet: "",
        akku: { vorhanden: false, prozent: -1, laedt: null, zustand: "unbekannt" },
        luefter: { vorhanden: false, prozent: -1, stufe: -1, stufen: -1, upm: -1, modus: "", mindeststufe: 0, steuerbar: false }
    };
}

// Text der Datei → geprüfter Zustand. jetztMs: Date.now(). Ungültiges, Fremdes oder zu Altes gilt als leer
// (frisch: false); einzelne unplausible Felder als unbekannt.
function lesen(text, jetztMs) {
    var ergebnis = leer();
    var daten = null;
    try {
        daten = JSON.parse(text);
    } catch (e) {
        return ergebnis;
    }
    if (!daten || typeof daten !== "object" || daten.version !== 1 || typeof daten.zeit !== "string")
        return ergebnis;
    var alter = jetztMs - Date.parse(daten.zeit);
    // auch in der Zukunft (z. B. nach einer Uhrkorrektur) höchstens 60 s daneben
    if (!isFinite(alter) || Math.abs(alter) > MAX_ALTER_MS)
        return ergebnis;
    ergebnis.frisch = true;
    ergebnis.geraet = typeof daten.geraet === "string" ? daten.geraet : "";

    var a = daten.akku;
    if (a && typeof a === "object" && a.vorhanden === true) {
        var prozent = _ganz(a.prozent, 0, 100);
        var zustand = a.zustand === "ok" || a.zustand === "fehler" || a.zustand === "freigabe" ? a.zustand : "unbekannt";
        // «ok» nur mit gültigem Ladestand; sonst gibt es auch keine sichere Laderichtung
        if (zustand === "ok" && prozent < 0)
            zustand = "unbekannt";
        ergebnis.akku = {
            vorhanden: true,
            prozent: zustand === "ok" ? prozent : -1,
            laedt: zustand === "ok" && typeof a.laedt === "boolean" ? a.laedt : null,
            zustand: zustand
        };
    }

    var l = daten.luefter;
    if (l && typeof l === "object" && l.vorhanden === true) {
        var stufen = _ganz(l.stufen, 1, 20);
        var stufe = stufen > 0 ? _ganz(l.stufe, 0, stufen) : -1;
        // Wunsch: «mindest» nur mit gültiger Stufe; sonst unbekannt (dann nicht bedienbar)
        var modus = l.modus === "auto" || l.modus === "mindest" ? l.modus : "";
        var mindeststufe = modus === "mindest" ? _ganz(l.mindeststufe, 1, 4) : -1;
        if (modus === "mindest" && mindeststufe < 1)
            modus = "";
        ergebnis.luefter = {
            vorhanden: true,
            prozent: _ganz(l.prozent, 0, 100),
            stufe: stufe,
            stufen: stufe >= 0 ? stufen : -1,
            upm: _ganz(l.upm, 0, 30000),
            modus: modus,
            mindeststufe: mindeststufe > 0 ? mindeststufe : 0,
            steuerbar: modus !== "" && l.steuerbar === true
        };
    }
    return ergebnis;
}

// Symbol der Leiste: Ladeblitz beim Laden, sonst vier Füllstände (leer bis 10 %, wenig bis 35 %, halb bis 70 %)
function akkuSymbol(akku) {
    if (!akku || !akku.vorhanden)
        return "";
    if (akku.laedt === true)
        return "akku-laedt";
    var p = akku.prozent;
    if (p < 0)
        return "akku-leer";
    if (p <= NIEDRIG)
        return "akku-leer";
    if (p <= 35)
        return "akku-wenig";
    if (p <= 70)
        return "akku-halb";
    return "akku-voll";
}

// Kurztext der Leiste: «87 %», leer ohne Messwert
function akkuText(akku) {
    return akku && akku.vorhanden && akku.prozent >= 0 ? akku.prozent + " %" : "";
}

// Wert im System-Menü: «87 % · lädt», «100 % · Netzteil», «87 %», «wird gemessen», «nicht lesbar»,
// «nicht freigegeben» (Geraet.qml zeigt «unbekannt», wenn die Datei fehlt, kaputt oder zu alt ist)
function akkuWert(akku) {
    if (!akku || !akku.vorhanden)
        return "";
    if (akku.zustand === "fehler")
        return "nicht lesbar";
    if (akku.zustand === "freigabe")
        return "nicht freigegeben";
    if (akku.prozent < 0)
        return "wird gemessen";
    if (akku.laedt === true)
        return akku.prozent >= 100 ? "100 % · Netzteil" : akku.prozent + " % · lädt";
    return akku.prozent + " %";
}

// Niedrig: höchstens 10 % und sicher am Entladen (dann Warnfarbe, ruhig, ohne Blinken)
function akkuNiedrig(akku) {
    return !!akku && akku.vorhanden && akku.prozent >= 0 && akku.prozent <= NIEDRIG && akku.laedt === false;
}

// Lüfter im System-Menü: «aus», «Stufe 2 von 4 · 3120 U/min» (Kernel), «55 %» (Argon ONE V3)
function luefterWert(luefter) {
    if (!luefter || !luefter.vorhanden)
        return "";
    if (luefter.prozent >= 0)
        return luefter.prozent === 0 ? "aus" : luefter.prozent + " %";
    if (luefter.stufe === 0)
        return "aus";
    var teile = [];
    if (luefter.stufe > 0)
        teile.push("Stufe " + luefter.stufe + " von " + luefter.stufen);
    if (luefter.upm >= 0)
        teile.push(luefter.upm + " U/min");
    return teile.join(" · ");
}

// Zeile «Lüfter» im System-Menü mit dem Wunsch, vom längsten zum kürzesten Text (die Zeile nimmt den ersten, der
// passt): «Stufe 2 von 4 · 3120 U/min · mind. 2», «Stufe 2 · 3120 U/min · mind. 2», «Stufe 2 · mind. 2»; «aus · Auto»,
// «55 % · Auto» (Argon ONE V3). Den Wunsch nur, wenn zenos-argon ihn umsetzen kann (steuerbar), sonst wie luefterWert.
function luefterWerte(luefter) {
    var basis = luefterWert(luefter);
    if (basis === "")
        return [];
    var zusatz = "";
    if (luefter.steuerbar === true)
        zusatz = luefter.modus === "mindest" ? "mind. " + luefter.mindeststufe : "Auto";
    var mit = function (text) {
        return zusatz !== "" ? text + " · " + zusatz : text;
    };
    var werte = [mit(basis)];
    if (luefter.prozent < 0 && luefter.stufe > 0) {
        if (luefter.upm >= 0)
            werte.push(mit("Stufe " + luefter.stufe + " · " + luefter.upm + " U/min"));
        werte.push(mit("Stufe " + luefter.stufe));
    }
    return werte.filter(function (w, i) {
        return werte.indexOf(w) === i;
    });
}

// Gewählter Wunsch für die Wahl «Auto · 1 · 2 · 3 · 4»: "auto", "1" … "4" oder "" (nicht steuerbar, unbekannt)
function luefterWahl(luefter) {
    if (!luefter || luefter.vorhanden !== true || luefter.steuerbar !== true)
        return "";
    if (luefter.modus === "mindest" && luefter.mindeststufe >= 1 && luefter.mindeststufe <= 4)
        return String(luefter.mindeststufe);
    return luefter.modus === "auto" ? "auto" : "";
}

// Hinweis unter der Wahl (gedämpft, ruhig): was die gewählte Einstellung tut
function luefterHinweis(wahl) {
    if (wahl === "auto")
        return "Folgt der Temperatur.";
    if (["1", "2", "3", "4"].indexOf(wahl) >= 0)
        return "Mindestens Stufe " + wahl + ", bei Wärme schneller.";
    return "";
}

// Warnung bei niedrigem Akku. gewarnt: Liste der schon gemeldeten Stufen (z. B. [10]).
// Gibt { stufe: 0 | 10 | 5, gewarnt } zurück; stufe > 0 heisst: jetzt eine Mitteilung zeigen.
// Nur bei sicherem Messwert und sicherem Entladen; beim Laden beginnt alles von vorn. Liegt der Akku schon
// unter beiden Stufen (z. B. 4 % beim Anmelden), kommt nur die tiefere.
function warnungPruefen(akku, gewarnt) {
    var bisher = Array.isArray(gewarnt) ? gewarnt.filter(function (s) { return WARNSTUFEN.indexOf(s) >= 0; }) : [];
    if (!akku || !akku.vorhanden || akku.zustand !== "ok" || akku.prozent < 0 || akku.laedt === null)
        return { stufe: 0, gewarnt: bisher };
    if (akku.laedt)
        return { stufe: 0, gewarnt: [] };
    var erreicht = WARNSTUFEN.filter(function (s) { return akku.prozent <= s; });
    if (erreicht.length === 0)
        return { stufe: 0, gewarnt: bisher };
    var tiefste = Math.min.apply(null, erreicht);
    if (bisher.indexOf(tiefste) >= 0)
        return { stufe: 0, gewarnt: bisher };
    var neu = bisher.slice();
    erreicht.forEach(function (s) {
        if (neu.indexOf(s) < 0)
            neu.push(s);
    });
    return { stufe: tiefste, gewarnt: neu.sort(function (x, y) { return y - x; }) };
}

// Titel, Text und Dringlichkeit der Mitteilung für eine Warnstufe. 10 % ist normal (folgt der Regel des Zustands,
// ohne Zustand gebündelt). 5 % ist dringend: zenOS fährt nicht selbst herunter, also ist diese Mitteilung der
// einzige Schutz vor dem harten Ausschalten und darf nicht bis zur nächsten Zustellung warten. Dringendes kommt
// ausser im Zustand «keine» sofort, als ruhige Karte ohne Ton und ohne Blinken.
function mitteilung(stufe, prozent) {
    var titel = "Akku bei " + prozent + " %";
    if (stufe <= 5)
        return { titel: titel, text: "Jetzt ans Netzteil anschliessen, sonst geht das Gerät bald aus.", dringend: true };
    return { titel: titel, text: "Bald ans Netzteil anschliessen.", dringend: false };
}

// Argumentliste für notify-send (nie über eine Shell). ersetzen: Nummer der bisherigen Akku-Mitteilung (> 0) oder 0.
// Es gibt immer nur eine Akku-Mitteilung: Die von 5 % ersetzt die von 10 %; --print-id liefert die Nummer dafür.
function befehl(m, ersetzen) {
    var liste = ["notify-send", "--app-name=zenOS", "--icon=zenos", "--urgency=" + (m.dringend ? "critical" : "normal"),
        "--category=device", "--print-id"];
    if (typeof ersetzen === "number" && isFinite(ersetzen) && ersetzen > 0 && Math.round(ersetzen) === ersetzen)
        liste.push("--replace-id=" + ersetzen);
    liste.push("--", m.titel, m.text);
    return liste;
}

// Nummer aus der Ausgabe von notify-send --print-id, 0 wenn keine
function nummer(ausgabe) {
    var t = String(ausgabe || "").trim();
    return /^[1-9][0-9]{0,9}$/.test(t) && Number(t) <= 4294967295 ? Number(t) : 0;
}

// Akku-Mitteilung zurückziehen? Ja, sobald sicher geladen wird (sie ist dann überholt, auch wenn sie noch wartet).
function zurueckziehen(akku) {
    return !!akku && akku.vorhanden === true && akku.zustand === "ok" && akku.prozent >= 0 && akku.laedt === true;
}
