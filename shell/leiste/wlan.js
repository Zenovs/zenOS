.pragma library
// Logik des WLAN-Abschnitts im System-Menü ohne QML: Signalstufe, Reihenfolge der Netze, Passwort-Prüfung und
// Texte. Getestet mit test/einheiten/wlan.test.mjs.
//
// Ein Netz kommt als einfaches Objekt von WlanQuelle.qml (oder einer Attrappe im Test):
//   { name, stufe (1–3, 0 ohne Signal), sicherheit: "offen" | "passwort" | "unternehmen" | "wep" | "unbekannt",
//     wpa3 (bool: das Netz bietet WPA3 an, rein oder als WPA2/WPA3-Mischnetz; Quickshell unterscheidet das nicht),
//     bekannt, verbunden, verbindet }
// Der Name (SSID) kommt ungeprüft aus der Luft: angezeigt wird er nur über anzeigeName() und als reiner Text
// (textFormat: Text.PlainText in WlanZeile.qml), sonst könnte ein Netz mit Auszeichnungen wie ein anderes aussehen.

// Signal in % (NetworkManager), ab dem zwei bzw. drei Bögen stehen. NetworkManager rechnet −100 dBm als 0 % und
// −40 dBm als 100 %: 60 % sind etwa −64 dBm (gut), 35 % etwa −79 dBm (schwach, aber brauchbar).
var STUFE_DREI = 60;
var STUFE_ZWEI = 35;

// Länge eines WPA-Passworts: 8–63 Zeichen, oder genau 64 Hex-Zeichen (der Schlüssel selbst)
var PASSWORT_MIN = 8;
var PASSWORT_MAX = 63;

// Unsichtbares und Steuerndes im Netznamen: Steuerzeichen (C0, DEL, C1), weiche Trennung, Zeichen ohne Breite,
// Richtungszeichen, Zeilen- und Absatztrenner, leere Hangul-Füller, BOM. Variantenwähler (U+FE0F hinter Emoji)
// bleiben, sonst sähen Netznamen mit Emoji kaputt aus.
var UNSICHTBAR = /[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u115f\u1160\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\u3164\ufeff\uffa0]/g;

// Netzname für die Anzeige: Unsichtbares wird zu «�», damit ein nachgemachtes Netz («Heimnetz» mit einem Zeichen
// ohne Breite) nicht genau wie das echte aussieht. Gezeigt wird immer als reiner Text.
function anzeigeName(name) {
    if (typeof name !== "string")
        return "";
    return name.replace(UNSICHTBAR, "\ufffd");
}

// 1–3 Bögen für ein Signal in % (0–100). Unbekannt (keine Zahl, negativ) gilt als voll: Dann zeigt die Leiste
// das gewohnte WLAN-Symbol ohne Stufe.
function stufe(signal) {
    if (typeof signal !== "number" || !isFinite(signal) || signal < 0)
        return 3;
    if (signal >= STUFE_DREI)
        return 3;
    if (signal >= STUFE_ZWEI)
        return 2;
    return 1;
}

// Symbolname zur Stufe: 0 = WLAN aus bzw. ohne Verbindung
function symbol(s) {
    if (s >= 3)
        return "wlan";
    if (s === 2)
        return "wlan-2";
    if (s === 1)
        return "wlan-1";
    return "wlan-aus";
}

// Lässt sich das Netz aus dem Menü verbinden? Unternehmens-WLAN (802.1X) und WEP nicht.
function verbindbar(netz) {
    return !!netz && netz.sicherheit !== "unternehmen" && netz.sicherheit !== "wep";
}

// Braucht ein Klick zuerst ein Passwort? Bekannte und offene Netze verbinden direkt; bei unbekannter Sicherheit
// versucht das Menü es erst ohne und fragt erst nach, wenn NetworkManager eines verlangt.
function brauchtPasswort(netz) {
    return !!netz && !netz.bekannt && netz.sicherheit === "passwort";
}

// Netze für die Liste: ohne leere Namen und ohne Doppelte, nur was in Reichweite ist (oder gerade verbunden).
// Reihenfolge: verbunden, verbindet, bekannt, dann Signal (Stufe) und Name. Die Stufe statt des genauen Signals
// hält die Reihenfolge ruhig: Kleine Schwankungen nach jedem Suchlauf verschieben keine Zeile.
function sortieren(netze) {
    var gesehen = {};
    var liste = [];
    for (var i = 0; i < (netze ? netze.length : 0); i++) {
        var n = netze[i];
        if (!n || typeof n.name !== "string" || n.name === "" || gesehen[n.name])
            continue;
        if (!n.verbunden && !n.verbindet && !(n.stufe > 0))
            continue;
        gesehen[n.name] = true;
        liste.push(n);
    }
    var rang = function (n) {
        return n.verbunden ? 0 : n.verbindet ? 1 : n.bekannt ? 2 : 3;
    };
    liste.sort(function (a, b) {
        if (rang(a) !== rang(b))
            return rang(a) - rang(b);
        if ((b.stufe || 0) !== (a.stufe || 0))
            return (b.stufe || 0) - (a.stufe || 0);
        return a.name.localeCompare(b.name);
    });
    return liste;
}

// Prüft ein Passwort vor dem Senden (NetworkManager lehnt ungültige ohne Rückmeldung an das Menü ab).
// Rückgabe: "" in Ordnung, sonst ein ruhiger Hinweis für unter das Feld.
function passwortPruefen(passwort) {
    if (typeof passwort !== "string" || passwort.length === 0)
        return "Passwort eingeben";
    if (passwort.length === 64)
        return /^[0-9A-Fa-f]{64}$/.test(passwort) ? "" : "Höchstens 63 Zeichen";
    if (passwort.length < PASSWORT_MIN)
        return "Mindestens 8 Zeichen";
    if (passwort.length > PASSWORT_MAX)
        return "Höchstens 63 Zeichen";
    return "";
}

// Text unter dem Netz nach einem gescheiterten Versuch.
// grund: "passwort" | "abgelehnt" | "zeit" | "weg" | "keine-antwort" | anderes
function fehlerText(grund, wpa3) {
    // Der WLAN-Chip im Raspberry Pi kann kein reines WPA3 (siehe docs/module/netzwerk.md); bei Mischnetzen nimmt er
    // WPA2. wpa3 gilt auch für Mischnetze, deshalb nur als Möglichkeit, und nicht bei «Passwort falsch?» (das wäre bei
    // fast jedem neueren Router nach einem Tippfehler zu lesen).
    var zusatz = wpa3 ? " Bietet das Netz nur WPA3 an, geht es mit diesem WLAN-Chip nicht." : "";
    switch (grund) {
    case "passwort":
        return "Passwort falsch?";
    case "abgelehnt":
        return "Das Netz hat die Anmeldung abgelehnt." + zusatz;
    case "zeit":
        return "Anmeldung dauerte zu lange." + zusatz;
    case "weg":
        return "Das Netz ist nicht mehr in Reichweite.";
    default:
        return "Verbindung kam nicht zustande." + zusatz;
    }
}

// Wert rechts in einer Netzzeile (Mono): leer, «verbindet …» oder «nicht möglich»
function zeilenWert(netz) {
    if (!netz)
        return "";
    if (netz.verbindet && !netz.verbunden)
        return "verbindet …";
    if (!verbindbar(netz))
        return "nicht möglich";
    return "";
}
