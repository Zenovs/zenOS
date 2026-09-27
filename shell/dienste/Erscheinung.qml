pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

// Wirksames Erscheinungsbild und Akzent. Überträgt beides (entprellt) mit
// zenos-thema auf GTK, Qt, kitty, labwc und VS Code.
Singleton {
    id: root

    // "dunkel" oder "hell" erzwingt ein Erscheinungsbild (Greeter: "dunkel"); leer = Einstellungen
    property string erzwungen: ""
    // false: nichts nach aussen übertragen (Greeter)
    property bool synchronisieren: true

    // "hell" | "dunkel" | "tageszeit" laut Einstellungen
    readonly property string gewaehlt: _modes.indexOf(Einstellungen.erscheinungsbild) >= 0 ? Einstellungen.erscheinungsbild : "hell"
    readonly property bool dunkel: erzwungen === "dunkel" || (erzwungen !== "hell" && (gewaehlt === "dunkel" || (gewaehlt === "tageszeit" && _night)))
    readonly property string akzentName: _accentNames.indexOf(Modi.aktiv?.akzent ?? "") >= 0 ? Modi.aktiv.akzent : _defaultAccent

    function umschalten(): void {
        setzen(dunkel ? "hell" : "dunkel");
    }

    // modus: "hell" | "dunkel" | "tageszeit"
    function setzen(modus: string): void {
        if (_modes.indexOf(modus) < 0) {
            console.warn("Erscheinung: unbekanntes Erscheinungsbild", modus);
            return;
        }
        if (Einstellungen.erscheinungsbild !== modus) {
            Einstellungen.erscheinungsbild = modus;
            Einstellungen.speichern();
        }
    }

    readonly property list<string> _modes: ["hell", "dunkel", "tageszeit"]

    // Tageszeit: Nacht ab nachtAb bis tagAb
    readonly property bool _night: {
        const now = clock.hours * 60 + clock.minutes;
        const day = _minutes(Einstellungen.tagAb, 7 * 60);
        const night = _minutes(Einstellungen.nachtAb, 19 * 60);
        if (day === night)
            return false;
        return day < night ? (now < day || now >= night) : (now >= night && now < day);
    }

    function _minutes(hhmm: string, fallback: int): int {
        const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm ?? "");
        if (!m || Number(m[1]) > 23 || Number(m[2]) > 59)
            return fallback;
        return Number(m[1]) * 60 + Number(m[2]);
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
        enabled: root.gewaehlt === "tageszeit" && root.erzwungen === ""
    }

    // Akzentnamen und Standardakzent aus tokens.json (Dienste importieren qs.theme nicht)
    property var _accentNames: []
    property string _defaultAccent: "salbei"

    function _readTokens(): void {
        try {
            const t = JSON.parse(tokenFile.text());
            const names = Object.keys(t?.farben?.akzente ?? {});
            if (names.length === 0)
                return;
            if (JSON.stringify(names) !== JSON.stringify(_accentNames))
                _accentNames = names;
            const preferred = t?.farben?.standardAkzent;
            _defaultAccent = names.indexOf(preferred) >= 0 ? preferred : names[0];
        } catch (e) {
            // Theme meldet ungültige Tokens bereits
        }
    }

    FileView {
        id: tokenFile

        path: Qt.resolvedUrl("../theme/tokens.json")
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._readTokens()
    }

    // Übertragung nach aussen
    property string _lastApplied: ""
    property bool _started: false
    readonly property string _target: (dunkel ? "dunkel" : "hell") + " " + akzentName

    onDunkelChanged: if (_started) debounce.restart()
    onAkzentNameChanged: if (_started) debounce.restart()

    function _anwenden(): void {
        if (!synchronisieren || themeProcess.running)
            return;
        if (_target === _lastApplied)
            return;
        _lastApplied = _target;
        themeProcess.exec({
            command: [Pfade.bin + "/zenos-thema", "anwenden", "--modus", dunkel ? "dunkel" : "hell", "--akzent", akzentName]
        });
    }

    // Einmal nach dem Start (Modus und Einstellungen sind dann geladen), damit GTK und kitty stimmen
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            root._started = true;
            root._anwenden();
        }
    }

    Timer {
        id: debounce

        interval: 300
        onTriggered: root._anwenden()
    }

    Process {
        id: themeProcess

        // zenos-thema schreibt nur bei Fehlern auf stderr
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim();
                if (message.length > 0) {
                    console.warn("Erscheinung: zenos-thema meldet:", message);
                    // beim nächsten Wechsel erneut versuchen
                    root._lastApplied = "";
                }
            }
        }
        // Während des Laufs geändert?
        onRunningChanged: {
            if (!running && root._lastApplied !== "" && root._target !== root._lastApplied)
                debounce.restart();
        }
    }

    Component.onCompleted: tokenFile.text()
}
