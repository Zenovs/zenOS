pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "suche.mjs" as Suche

// Dateisuche im Home-Ordner: ab 2 Zeichen, entprellt, find mit Argumentliste (nie über eine Shell).
// Versteckte Ordner bleiben aussen vor, höchstens 20 Treffer; eine laufende Suche wird abgebrochen,
// sobald sich die Eingabe ändert.
QtObject {
    id: root

    property string home
    // Gewünschte Suche (vom Befehlsfeld gesetzt, leer = keine)
    property string anfrage
    property int maxTreffer: 20
    property int tiefe: 5

    // Treffer [{ordner, pfad, name, tiefe}] und die Eingabe, zu der sie gehören
    property var treffer: []
    property string trefferAnfrage: ""
    readonly property bool sucht: entprellen.running || prozess.running

    property var _sammlung: []
    property string _laufAnfrage: ""
    property string _naechsteAnfrage: ""

    onAnfrageChanged: {
        if (Suche.findArgumente(home, anfrage, tiefe) === null) {
            stoppen();
            treffer = [];
            trefferAnfrage = anfrage;
            return;
        }
        entprellen.restart();
    }

    function stoppen(): void {
        entprellen.stop();
        zwischenstand.stop();
        _naechsteAnfrage = "";
        if (prozess.running)
            prozess.running = false;
    }

    function _starten(): void {
        const args = Suche.findArgumente(home, anfrage, tiefe);
        if (args === null)
            return;
        _naechsteAnfrage = anfrage;
        // Beendet eine laufende Suche (SIGTERM) und startet danach die neue
        prozess.exec({
            command: args,
            workingDirectory: home
        });
    }

    function _zeile(daten: string): void {
        // Ausgabe einer abgebrochenen, älteren Suche verwerfen
        if (_laufAnfrage !== anfrage || _laufAnfrage === "")
            return;
        if (_sammlung.length >= maxTreffer)
            return;
        const t = Suche.findZeile(daten, home);
        if (t === null)
            return;
        _sammlung.push(t);
        if (_sammlung.length >= maxTreffer)
            prozess.running = false;
    }

    function _veroeffentlichen(): void {
        if (_laufAnfrage !== anfrage || _laufAnfrage === "")
            return;
        treffer = Suche.dateienSortieren(_sammlung, _laufAnfrage);
        trefferAnfrage = _laufAnfrage;
    }

    property Timer entprellen: Timer {
        interval: 200
        onTriggered: root._starten()
    }

    // Bei einer langsamen Suche die ersten Treffer schon zeigen
    property Timer zwischenstand: Timer {
        interval: 500
        onTriggered: root._veroeffentlichen()
    }

    property Process prozess: Process {
        stdout: SplitParser {
            splitMarker: "\u0000"
            onRead: daten => root._zeile(daten)
        }
        onStarted: {
            root._laufAnfrage = root._naechsteAnfrage;
            root._sammlung = [];
            root.zwischenstand.restart();
        }
        // Nach dem Ende (auch nach einem Abbruch) ist die Ausgabe vollständig gelesen
        onRunningChanged: {
            if (running)
                return;
            root.zwischenstand.stop();
            root._veroeffentlichen();
            root._laufAnfrage = "";
        }
    }
}
