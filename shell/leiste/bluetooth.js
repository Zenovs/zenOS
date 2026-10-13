.pragma library
.import "wlan.js" as Wlan
// Logik des Bluetooth-Abschnitts im System-Menü ohne QML: Symbol je Gerätetyp, Reihenfolge, Akku und Texte.
// Getestet mit test/einheiten/bluetooth.test.mjs.
//
// Ein Gerät kommt als einfaches Objekt von BluetoothQuelle.qml (oder einer Attrappe im Test):
//   { adresse (nur als Schlüssel, nie angezeigt), name, typ (BlueZ-Icon wie «input-mouse»), verbunden, gekoppelt,
//     verbindet, trennt, koppelt, akku (0–100, -1 unbekannt) }
// Der Name kommt ungeprüft aus der Luft: angezeigt wird er nur über anzeigeName() und als reiner Text, wie Netznamen
// (wlan.js), sonst könnte ein Gerät mit unsichtbaren Zeichen wie ein anderes aussehen.

// Ohne Namen meldet BlueZ die Adresse als Namen («AA-BB-CC-DD-EE-FF»); solche Geräte stehen nur in der Liste, wenn sie
// schon gekoppelt sind
var ADRESSE = /^([0-9a-f]{2}[-:]){5}[0-9a-f]{2}$/i;

// BlueZ-Icon (Freedesktop-Name, aus der Geräteklasse) zu einem Symbol aus symbole.js
function symbol(typ) {
    if (typeof typ !== "string")
        return "bluetooth";
    if (typ === "input-mouse" || typ === "input-tablet")
        return "maus";
    if (typ === "input-keyboard")
        return "tastatur";
    if (typ.indexOf("audio-") === 0)
        return "kopfhoerer";
    return "bluetooth";
}

function hatNamen(name) {
    return typeof name === "string" && name.trim() !== "" && !ADRESSE.test(name.trim());
}

function anzeigeName(name) {
    return hatNamen(name) ? Wlan.anzeigeName(name) : "Gerät ohne Namen";
}

// Akku von Quickshell (0.0–1.0) in ganzen Prozent; unbekannt -1
function akku(verfuegbar, wert) {
    if (!verfuegbar || typeof wert !== "number" || !isFinite(wert) || wert < 0)
        return -1;
    const prozent = wert <= 1 ? wert * 100 : wert;
    return Math.max(0, Math.min(100, Math.round(prozent)));
}

// Gehört das Gerät in die Liste? Gekoppelte immer, fremde nur mit Namen
function sichtbar(geraet) {
    return !!geraet && (geraet.gekoppelt || geraet.verbunden || hatNamen(geraet.name));
}

// Sortierschlüssel ohne Spracheinstellung (die QML-Engine kennt localeCompare mit «de» nicht): klein, ß wie ss,
// ohne Akzente, also Ä wie A
function schluessel(name) {
    let s = anzeigeName(name).toLowerCase().replace(/ß/g, "ss");
    if (typeof s.normalize === "function")
        s = s.normalize("NFD").replace(/[̀-ͯ]/g, "");
    return s;
}

// Verbundene zuerst, dann gekoppelte, dann gefundene; jeweils nach Namen
function sortieren(liste) {
    function rang(g) {
        return g.verbunden ? 0 : g.gekoppelt ? 1 : 2;
    }
    return liste.filter(sichtbar).sort((a, b) => {
        const r = rang(a) - rang(b);
        if (r !== 0)
            return r;
        const x = schluessel(a.name);
        const y = schluessel(b.name);
        return x < y ? -1 : x > y ? 1 : 0;
    });
}

// Wert rechts in Mono: was gerade geschieht, sonst Akku bzw. «gekoppelt»
function zeilenWert(geraet) {
    if (!geraet)
        return "";
    if (geraet.koppelt)
        return "koppelt …";
    if (geraet.verbindet)
        return "verbindet …";
    if (geraet.trennt)
        return "trennt …";
    if (geraet.verbunden)
        return geraet.akku >= 0 ? geraet.akku + " %" : "";
    if (geraet.gekoppelt)
        return "gekoppelt";
    return "";
}

// Ruhiger Fehler unter der Zeile eines Geräts
function fehlerText(fehler) {
    if (fehler === "koppeln")
        return "Koppeln hat nicht geklappt. Ist das Gerät im Kopplungsmodus?";
    if (fehler === "zeit")
        return "Keine Antwort. Ist das Gerät an und in der Nähe?";
    if (fehler === "verbinden")
        return "Verbinden hat nicht geklappt. Ist das Gerät an und in der Nähe?";
    return "";
}
