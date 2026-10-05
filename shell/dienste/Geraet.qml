pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste
import "geraet.js" as Logik

// Gerätezustand aus /run/zenos/geraet.json (zenos-argon, Systemdienst): Akku, Lüfter und Deckel des Argon ONE, dazu
// der Lüfterwunsch, den zenos-argon umsetzt (einstellen: Luefter).
// Die Datei wird bei jeder Änderung gelesen (watchChanges; ein Wechsel des Deckels steht sofort darin) und dazu alle
// 5 s, was zugleich ihr Alter prüft. Fehlt sie, ist sie kaputt oder älter als 60 s, gilt alles als unbekannt; ein
// Akku, der in dieser Sitzung schon da war, bleibt dann gedämpft in der Leiste stehen, im Menü «unbekannt».
// Bei niedrigem Akku (10 % und 5 %, nur beim Entladen, je einmal pro Unterschreiten) eine Mitteilung über den eigenen
// Mitteilungsdienst (notify-send): 10 % normal, 5 % dringend (kommt sofort, ruhig, ohne Ton). Es gibt immer nur
// eine Akku-Mitteilung; beim Laden wird sie zurückgezogen.
// Ausschalten bei leerem Akku (Entscheid Oktober 2026, bisher fuhr zenOS nie selbst herunter): Bei 3 % im
// Akkubetrieb schaltet zenos-argon nach 60 s Vorwarnung kontrolliert aus, auch am Login-Bildschirm. Hier wird daraus
// eine dringende Mitteilung mit der Uhrzeit (sie ersetzt die Akku-Mitteilung); die Sperre zeigt die Uhrzeit ebenfalls.
// Abbrechen kann nur das Netzteil.
// Deckel (Argon ONE UP): Signal deckelGeklappt bei jedem Wechsel; dienste/Energie.qml sperrt beim Zuklappen und
// schaltet den Bildschirm aus, beim Aufklappen wieder an.
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
        // Uhrzeit (ms) des Ausschaltens bei leerem Akku, die schon gemeldet ist (0 = keine)
        property real ausschaltenGemeldet: 0
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

    // zenos-argon schaltet bei leerem Akku um diese Uhrzeit aus (ms seit 1970), 0: keine Vorwarnung
    readonly property real akkuAusschaltenUm: _daten.ausschaltenUm > 0 ? _daten.ausschaltenUm : 0

    // Deckel (Argon ONE UP): vorhanden, wenn zenos-argon GPIO27 liest
    readonly property bool deckelVorhanden: _daten.deckel.vorhanden
    readonly property bool deckelZu: _daten.deckel.zustand === "zu"
    // "zuklappen" (sperren und Bildschirm aus), "aufklappen" (Bildschirm an), "sperren" (das Zuklappen verpasst)
    signal deckelGeklappt(string aktion)

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
    // Zuletzt bekannter Deckel { zustand, seit } (null: noch keiner). Eine veraltete Datei überschreibt ihn nicht:
    // Ein Wechsel in einer Lücke fällt so beim nächsten frischen Wert auf.
    property var _deckelVorher: null

    function _auswerten(): void {
        const jetzt = Date.now();
        const daten = Logik.lesen(_text, jetzt);
        if (JSON.stringify(daten) !== JSON.stringify(_daten))
            _daten = daten;
        if (daten.akku.vorhanden && !persist.akkuGesehen)
            persist.akkuGesehen = true;
        _warnen(daten.akku);
        _ausschaltenMelden(daten.ausschaltenUm, daten.akku);
        _deckel(daten.deckel, jetzt);
    }

    function _deckel(deckel: var, jetzt: real): void {
        const aktion = Logik.deckelAktion(root._deckelVorher, deckel, jetzt);
        if (deckel.vorhanden && deckel.zustand !== "")
            root._deckelVorher = {
                zustand: deckel.zustand,
                seit: deckel.seit
            };
        if (aktion !== "")
            root.deckelGeklappt(aktion);
    }

    // Ausschalten bei leerem Akku: dringende Mitteilung mit der Uhrzeit (ersetzt die Akku-Mitteilung). Endet die
    // Vorwarnung ohne Netzteil, kommt wieder die Mitteilung von 5 % (die Uhrzeit stimmt dann nicht mehr).
    function _ausschaltenMelden(um: real, akku: var): void {
        if (!Konfig.verfuegbar)
            return;
        const was = Logik.ausschaltenFolge(persist.ausschaltenGemeldet, um, akku);
        if (was === "")
            return;
        persist.ausschaltenGemeldet = was === "melden" ? um : 0;
        if (was === "melden") {
            console.info("Gerät: Akku fast leer, zenos-argon schaltet um", Logik.uhrzeit(um), "aus");
            _naechste = Logik.ausschaltenMitteilung(um);
            _senden();
        } else if (was === "ersetzen") {
            _naechste = Logik.mitteilung(5, akku.prozent);
            _senden();
        } else if (was === "verwerfen" && persist.mitteilung > 0) {
            _naechste = null;
            if (_eigene(persist.mitteilung))
                Mitteilungen.verwerfen(persist.mitteilung);
            persist.mitteilung = 0;
        }
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
        // zenos-argon schreibt atomar (neue Datei): ein Wechsel des Deckels kommt so ohne Verzögerung an
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root._text = text();
            root._auswerten();
        }
        onLoadFailed: {
            root._text = "";
            root._auswerten();
        }
    }

    // Der Dienst schreibt alle 15 s (atomar, neue Datei): Der ruhige Takt prüft das Alter und fängt eine Änderung auf,
    // die watchChanges verpasst hätte
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.aktualisieren()
    }
}
