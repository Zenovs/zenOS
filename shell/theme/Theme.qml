pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste

// Einzige Stelle mit Farbwerten. Alle Werte kommen aus tokens.json;
// Änderungen an der Datei werden live übernommen.
Singleton {
    id: root

    // Erscheinungsbild (wirksam) und aktiver Akzent
    readonly property bool dunkel: Erscheinung.dunkel
    readonly property string akzentName: akzentNamen.indexOf(Erscheinung.akzentName) >= 0 ? Erscheinung.akzentName : standardAkzent

    // Farben im aktuellen Erscheinungsbild
    readonly property color grund: _paletteColor("grund")
    readonly property color flaeche: _paletteColor("flaeche")
    readonly property color flaeche2: _paletteColor("flaeche2")
    readonly property color fenster: _paletteColor("fenster")
    readonly property color linie: _paletteColor("linie")
    readonly property color linie2: _paletteColor("linie2")
    readonly property color trennlinie: _paletteColor("trennlinie")
    readonly property color eingabeRand: _paletteColor("eingabeRand")
    readonly property color tasteRand: _paletteColor("tasteRand")
    readonly property color abgesetzt: _paletteColor("abgesetzt")
    readonly property color wasserzeichen: _paletteColor("wasserzeichen")
    readonly property color schatten: _paletteColor("schatten")
    readonly property color text: _paletteColor("text")
    readonly property color text2: _paletteColor("text2")
    readonly property color gedaempft: _paletteColor("gedaempft")
    readonly property color abdunkeln: _paletteColor("abdunkeln")
    readonly property color akzent: akzentFarbe(akzentName)
    // Text und Symbole auf Akzentflächen
    readonly property color aufAkzent: dunkel ? grund : flaeche
    readonly property color sitzung: _signalColor("sitzung")
    readonly property color fehler: _signalColor("fehler")
    readonly property color warnung: _signalColor("warnung")
    // Für Flächen ohne Füllung (statt eines Farbnamens im QML)
    readonly property color durchsichtig: Qt.rgba(0, 0, 0, 0)

    readonly property list<string> akzentNamen: Object.keys(_t?.farben?.akzente ?? {})
    readonly property string standardAkzent: _t?.farben?.standardAkzent ?? (akzentNamen.length > 0 ? akzentNamen[0] : "")

    // Schrift
    readonly property string schriftAnzeige: _t?.schrift?.anzeige ?? "serif"
    readonly property string schriftText: _t?.schrift?.text ?? "sans-serif"
    readonly property string schriftMono: _t?.schrift?.mono ?? "monospace"
    readonly property int groesseKlein: _number(_t?.schrift?.groessen?.klein, 12)
    readonly property int groesseLabel: _number(_t?.schrift?.groessen?.label, 13)
    readonly property int groesseText: _number(_t?.schrift?.groessen?.text, 14)
    readonly property int groesseGross: _number(_t?.schrift?.groessen?.gross, 16)
    readonly property int groesseTitel: _number(_t?.schrift?.groessen?.titel, 36)
    readonly property int groesseAnzeige: _number(_t?.schrift?.groessen?.anzeige, 180)

    // Radien
    readonly property int radiusXs: _number(_t?.radius?.xs, 6)
    readonly property int radiusChip: _number(_t?.radius?.chip, 8)
    readonly property int radiusFeld: _number(_t?.radius?.feld, 10)
    readonly property int radiusFenster: _number(_t?.radius?.fenster, 12)
    readonly property int radiusBefehlsfeld: _number(_t?.radius?.befehlsfeld, 16)
    readonly property int radiusPille: _number(_t?.radius?.pille, 999)

    // Abstände
    readonly property list<int> abstand: Array.isArray(_t?.abstand) && _t.abstand.length === 7 ? _t.abstand : [4, 8, 12, 16, 24, 32, 48]
    readonly property int a1: abstand[0]
    readonly property int a2: abstand[1]
    readonly property int a3: abstand[2]
    readonly property int a4: abstand[3]
    readonly property int a5: abstand[4]
    readonly property int a6: abstand[5]
    readonly property int a7: abstand[6]

    // Bewegung (höchstens 200 ms, OutCubic)
    readonly property int dauerKurz: Math.min(_number(_t?.bewegung?.kurz, 120), 200)
    readonly property int dauerMax: Math.min(_number(_t?.bewegung?.maximal, 200), 200)
    readonly property int kurve: Easing.OutCubic

    // Masse
    readonly property int leisteHoehe: _number(_t?.leiste?.hoehe, 40)
    readonly property int titelzeile: _number(_t?.fenster?.titelzeile, 34)
    readonly property int rasterAbstand: _number(_t?.fenster?.rasterAbstand, 8)
    readonly property int aktiverRand: _number(_t?.fenster?.aktiverRand, 1)
    readonly property int befehlsfeldBreite: _number(_t?.befehlsfeld?.breite, 720)
    readonly property int befehlsfeldOben: _number(_t?.befehlsfeld?.abstandOben, 104)

    // Farbe eines Akzents im aktuellen Erscheinungsbild
    function akzentFarbe(name: string): color {
        const pair = _t?.farben?.akzente?.[name] ?? _t?.farben?.akzente?.[standardAkzent];
        return _parseColor(pair?.[dunkel ? "dunkel" : "hell"], dunkel ? 0.7 : 0.3);
    }

    // Anzeigename eines Akzents («salbei» → «Salbei»)
    function akzentAnzeige(name: string): string {
        return name.length > 0 ? name.charAt(0).toUpperCase() + name.slice(1) : "";
    }

    // Zuletzt gültiger Inhalt von tokens.json
    property var _t: null

    function _paletteColor(name: string): color {
        const value = _t?.farben?.[dunkel ? "dunkel" : "hell"]?.[name];
        return _parseColor(value, _fallbackLevel(name));
    }

    function _signalColor(name: string): color {
        return _parseColor(_t?.farben?.signal?.[name]?.[dunkel ? "dunkel" : "hell"], 0.5);
    }

    // "#RRGGBB", "#RRGGBBAA" oder "rgba(r, g, b, a)"
    function _parseColor(value: var, fallback: real): color {
        if (typeof value === "string") {
            const s = value.trim();
            let m = /^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})?$/.exec(s);
            if (m)
                return Qt.rgba(parseInt(m[1], 16) / 255, parseInt(m[2], 16) / 255, parseInt(m[3], 16) / 255, m[4] === undefined ? 1 : parseInt(m[4], 16) / 255);
            m = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/.exec(s);
            if (m)
                return Qt.rgba(Number(m[1]) / 255, Number(m[2]) / 255, Number(m[3]) / 255, m[4] === undefined ? 1 : Number(m[4]));
        }
        // Notfall, falls tokens.json fehlt oder einen Wert nicht enthält: neutrales Grau
        return Qt.rgba(fallback, fallback, fallback, 1);
    }

    function _fallbackLevel(name: string): real {
        const foreground = ["text", "text2", "gedaempft"].indexOf(name) >= 0;
        return (foreground !== dunkel) ? 0.1 : 0.9;
    }

    function _number(value: var, fallback: int): int {
        return typeof value === "number" && isFinite(value) ? Math.round(value) : fallback;
    }

    function _load(): void {
        const content = file.text();
        if (!content)
            return;
        let t;
        try {
            t = JSON.parse(content);
        } catch (e) {
            console.warn("Theme: tokens.json ist kein gültiges JSON, die bisherigen Werte bleiben:", e);
            return;
        }
        if (typeof t?.farben?.dunkel !== "object" || typeof t?.farben?.hell !== "object" || typeof t?.farben?.akzente !== "object") {
            console.warn("Theme: tokens.json ohne farben.dunkel/hell/akzente, die bisherigen Werte bleiben");
            return;
        }
        if (JSON.stringify(t) !== JSON.stringify(_t))
            _t = t;
    }

    FileView {
        id: file

        path: Qt.resolvedUrl("tokens.json")
        // Synchron beim Start, damit das erste Bild schon die richtigen Farben hat
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._load()
        onLoadFailed: error => console.error("Theme: tokens.json nicht lesbar:", FileViewError.toString(error))
    }

    Component.onCompleted: _load()
}
