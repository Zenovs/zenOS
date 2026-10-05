pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "geraet.js" as Logik

// Gerätezustand aus /run/zenos/geraet.json (zenos-argon, Systemdienst): Akku und Lüfter des Argon ONE, dazu der
// Lüfterwunsch, den zenos-argon umsetzt (einstellen: Luefter).
// Fehlt die Datei, ist sie kaputt oder älter als 60 s, gilt alles als unbekannt; ein Akku, der in dieser Sitzung
// schon da war, bleibt dann gedämpft in der Leiste stehen (statt zu verschwinden), im Menü «unbekannt».
// Bei niedrigem Akku (10 % und 5 %, nur beim Entladen, je einmal pro Unterschreiten) eine Mitteilung über den eigenen
// Mitteilungsdienst (notify-send): 10 % normal, 5 % dringend (kommt sofort, ruhig, ohne Ton). Es gibt immer nur
// eine Akku-Mitteilung; beim Laden wird sie zurückgezogen. zenOS fährt nie selbst herunter.
// Die Logik steht in geraet.js und ist dort getestet.
Singleton {
    id: root

    // Muss das erste Kind bleiben (wie in Mitteilungen): Beim Neuladen der Oberfläche bleiben die schon
    // gemeldeten Warnstufen erhalten, sonst käme die Mitteilung nach jedem Speichern einer QML-Datei erneut.
    PersistentProperties {
        id: persist

        reloadableId: "geraetWarnungen"

        // schon gemeldete Warnstufen, z. B. "10" oder "10,5"
        property string gewarnt: ""
        // ein Akku war in dieser Sitzung schon da
        property bool akkuGesehen: false
        // Nummer der aktuellen Akku-Mitteilung (0 = keine): wird ersetzt und beim Laden zurückgezogen
        property int mitteilung: 0
    }

    readonly property bool akkuVorhanden: _daten.akku.vorhanden || persist.akkuGesehen
    // 0–100, -1 wenn unbekannt
    readonly property int akkuProzent: _daten.akku.prozent
    readonly property bool akkuLaedt: _daten.akku.laedt === true
    // true, solange ein sicherer Messwert da ist
    readonly property bool akkuBekannt: _daten.akku.prozent >= 0
    // Geprüfter Akku aus geraet.js: { vorhanden, prozent, laedt, zustand } (Energie: Akkubetrieb)
    readonly property var akku: _daten.akku
    // höchstens 10 % beim Entladen: Warnfarbe in der Leiste
    readonly property bool akkuNiedrig: Logik.akkuNiedrig(_daten.akku)
    // Symbolname für qs.komponenten/Symbol (akku-laedt, akku-voll, akku-halb, akku-wenig, akku-leer)
    readonly property string akkuSymbol: akkuVorhanden ? (Logik.akkuSymbol(_daten.akku) || "akku-leer") : ""
    // «87 %» oder leer
    readonly property string akkuText: Logik.akkuText(_daten.akku)
    // System-Menü: «87 % · lädt», «100 % · Netzteil», «87 %», «wird gemessen», «nicht lesbar», «nicht freigegeben»,
    // «unbekannt» (Datei fehlt, ist kaputt oder zu alt)
    readonly property string akkuWert: _daten.akku.vorhanden ? Logik.akkuWert(_daten.akku) : (akkuVorhanden ? "unbekannt" : "")

    // Gehäuse laut zenos-argon: "argon-one-up" (Laptop mit Deckel), "argon-one-v3" oder leer (unbekannt)
    readonly property string modell: _daten.geraet

    readonly property bool luefterVorhanden: _daten.luefter.vorhanden
    // «aus», «Stufe 2 von 4 · 3120 U/min» oder «55 %»
    readonly property string luefterWert: Logik.luefterWert(_daten.luefter)
    // Zeile «Lüfter» im System-Menü mit dem Wunsch, vom längsten zum kürzesten («… · Auto», «… · mind. 2»)
    readonly property var luefterWerte: Logik.luefterWerte(_daten.luefter)
    // zenos-argon kann den Lüfterwunsch umsetzen: Die Zeile «Lüfter» klappt die Wahl auf (Luefter.setzen)
    readonly property bool luefterSteuerbar: _daten.luefter.steuerbar
    // Wunsch, den zenos-argon meldet: "auto", "1" … "4" oder "" (nicht steuerbar, unbekannt)
    readonly property string luefterWahl: Logik.luefterWahl(_daten.luefter)

    // Sofort neu einlesen (z. B. beim Öffnen des System-Menüs)
    function aktualisieren(): void {
        datei.reload();
        _auswerten();
    }

    // --- intern ---

    property var _daten: Logik.leer()
    property string _text: ""

    function _auswerten(): void {
        const daten = Logik.lesen(_text, Date.now());
        if (JSON.stringify(daten) !== JSON.stringify(_daten))
            _daten = daten;
        if (daten.akku.vorhanden && !persist.akkuGesehen)
            persist.akkuGesehen = true;
        _warnen(daten.akku);
    }

    function _warnen(akku: var): void {
        const bisher = persist.gewarnt === "" ? [] : persist.gewarnt.split(",").map(Number);
        const ergebnis = Logik.warnungPruefen(akku, bisher);
        const neu = ergebnis.gewarnt.join(",");
        if (neu !== persist.gewarnt)
            persist.gewarnt = neu;
        // Nur in der Sitzung (im Greeter gibt es keinen Mitteilungsdienst und keine Konfiguration)
        if (!Konfig.verfuegbar)
            return;
        // Netzteil dran: Die Akku-Mitteilung ist überholt, auch wenn sie noch auf ihre Zustellung wartet
        if (Logik.zurueckziehen(akku)) {
            _naechste = null;
            if (persist.mitteilung > 0) {
                if (_eigene(persist.mitteilung))
                    Mitteilungen.verwerfen(persist.mitteilung);
                persist.mitteilung = 0;
            }
        }
        if (ergebnis.stufe <= 0)
            return;
        _naechste = Logik.mitteilung(ergebnis.stufe, akku.prozent);
        _senden();
    }

    // Nächste Mitteilung, die noch gesendet werden muss (oder null)
    property var _naechste: null

    // Gibt es die Mitteilung mit dieser Nummer noch, und ist sie von zenOS? (Zeno kann sie längst geschlossen haben;
    // eine fremde Mitteilung wird nie ersetzt oder zurückgezogen.)
    function _eigene(nummer: int): bool {
        const eintrag = Mitteilungen.eintrag(nummer);
        return eintrag !== null && eintrag.app === "zenOS";
    }

    // Erst senden, wenn der vorige Aufruf fertig ist: Er liefert die Nummer, die der nächste ersetzt
    function _senden(): void {
        if (_naechste === null || sender.running)
            return;
        sender.command = Logik.befehl(_naechste, persist.mitteilung > 0 && _eigene(persist.mitteilung) ? persist.mitteilung : 0);
        _naechste = null;
        sender.running = true;
    }

    // notify-send mit Argumentliste, nie über eine Shell; --print-id gibt die Nummer der Mitteilung aus
    Process {
        id: sender

        stdout: StdioCollector {
            onStreamFinished: {
                const n = Logik.nummer(text);
                if (n > 0)
                    persist.mitteilung = n;
            }
        }
        onExited: Qt.callLater(() => root._senden())
    }

    FileView {
        id: datei

        path: "/run/zenos/geraet.json"
        printErrors: false
        onLoaded: {
            root._text = text();
            root._auswerten();
        }
        onLoadFailed: {
            root._text = "";
            root._auswerten();
        }
    }

    // Der Dienst schreibt alle 15 s (atomar, neue Datei): ein ruhiger Takt genügt und prüft zugleich das Alter
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.aktualisieren()
    }
}
