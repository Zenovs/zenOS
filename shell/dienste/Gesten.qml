pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

// Wischen mit drei Fingern auf dem Touchpad: nach oben öffnet die Fensterübersicht, nach unten schliesst sie, wenn sie
// offen ist (sonst geschieht nichts, ein App-Exposé gibt es nicht). Die Geste erkennt der Systemdienst zenos-gesten
// (scripts/bin/zenos-gesten); die Oberfläche hat keinerlei Rechte am Touchpad und liest nur seine Zeilen vom Socket.
// Angenommen werden genau die Wörter «oben» und «unten», alles andere wird verworfen. Während Sperre und Einrichtung
// wirkt nichts.
// Verbinden nur, wenn der Dienst bereit ist: Er legt dann /run/zenos-gesten/bereit an (systemd räumt den Ordner weg,
// wenn er endet). Die Datei liest ein FileView ohne Meldungen, so bleibt das Protokoll auf einem Rechner ohne Touchpad
// still. Getrennt oder noch nicht bereit: erneut nach 2 s, dann jedes Mal doppelt so spät, höchstens alle 30 s.
// Quickshell v0.3.1 versucht einen Socket nach einem Fehler nicht wieder; jeder Versuch ist deshalb ein neues Objekt.
// IPC «gesten»: status (verbunden/getrennt)
Singleton {
    id: root

    readonly property string pfad: "/run/zenos-gesten/gesten.sock"
    readonly property string bereitPfad: "/run/zenos-gesten/bereit"
    readonly property int pauseErst: 2000
    readonly property int pauseHoechstens: 30000
    readonly property bool verbunden: _verbindung !== null && _verbindung.connected

    property Socket _verbindung: null
    property int _pause: pauseErst

    function _wort(zeile: string): void {
        if (zeile !== "oben" && zeile !== "unten")
            return;
        if (Oberflaeche.gesperrt || Oberflaeche.einrichtungOffen)
            return;
        if (zeile === "oben")
            Oberflaeche.uebersichtOeffnen();
        else if (Oberflaeche.uebersichtOffen)
            Oberflaeche.uebersichtSchliessen();
    }

    function _verbinden(): void {
        if (verbunden)
            return;
        if (_verbindung !== null) {
            const alt = _verbindung;
            _verbindung = null;
            alt.destroy();
        }
        const neu = vorlage.createObject(root) as Socket;
        if (neu === null)
            return;
        _verbindung = neu;
        // Erst jetzt verbinden, mit fertigem Objekt. Ein lokaler Socket verbindet sofort oder scheitert sofort
        // (Fehler wie «nicht gefunden» meldet Quickshell nur über das Signal error, ohne Zustandswechsel).
        neu.connected = true;
        if (!neu.connected)
            _loslassen(neu);
    }

    // Verbindung weg oder gescheitert: das Objekt einmal aufgeben, später neu versuchen
    function _loslassen(socket: Socket): void {
        if (socket !== _verbindung)
            return;
        _verbindung = null;
        socket.destroy();
        _spaeter();
    }

    function _spaeter(): void {
        if (!verbunden && !neuVersuch.running)
            neuVersuch.start();
    }

    Component {
        id: vorlage

        Socket {
            id: socket

            path: root.pfad
            parser: SplitParser {
                onRead: zeile => root._wort(zeile)
            }
            onConnectionStateChanged: {
                if (socket.connected)
                    root._pause = root.pauseErst;
                else
                    root._loslassen(socket);
            }
        }
    }

    FileView {
        id: bereit

        path: root.bereitPfad
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._verbinden()
        onLoadFailed: root._spaeter()
    }

    Timer {
        id: neuVersuch

        interval: root._pause
        onTriggered: {
            root._pause = Math.min(root._pause * 2, root.pauseHoechstens);
            bereit.reload();
        }
    }

    IpcHandler {
        target: "gesten"

        // "verbunden" oder "getrennt"
        function status(): string {
            return root.verbunden ? "verbunden" : "getrennt";
        }
    }
}
