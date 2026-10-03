pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
// eigenes Modul, damit qmllint die Singletons dieses Ordners kennt
import qs.dienste

// Lüfter einstellen: «auto» oder Mindeststufe 1–4 (Zeile «Lüfter» im System-Menü).
//
// - Gesetzt wird über pkexec mit dem Helfer zenos-luefter (Argumentliste, keine Shell). polkit erlaubt das in der
//   aktiven Sitzung am Gerät ohne Passwort (system/polkit/org.zenos.luefter.policy). Der Helfer schreibt nur den
//   Wunsch nach /var/lib/zenos/luefter; zenos-argon setzt ihn um und meldet ihn in /run/zenos/geraet.json (Geraet).
// - Bis geraet.json den neuen Wunsch zeigt (zenos-argon braucht höchstens 2 s, beim Argon ONE V3 5 s), gilt «ziel»
//   als gewählt. Kommt keine Bestätigung, ein ruhiger Hinweis; Fehler ebenso.
// - Während der Sperre nie (die Menüs sind dann ohnehin zu).
Singleton {
    id: root

    // Fester Pfad: Die polkit-Aktion gilt genau für dieses Programm (pkexec vergleicht den echten Pfad).
    // Ein Arbeits-Checkout (ZENOS_CODE) zählt hier bewusst nicht.
    readonly property string helfer: "/opt/zenos/scripts/bin/zenos-luefter"
    readonly property var wahlen: ["auto", "1", "2", "3", "4"]

    // Gewählt, aber noch nicht in geraet.json bestätigt: "auto", "1" … "4" oder ""
    readonly property string ziel: _ziel
    // pkexec läuft
    readonly property bool laeuft: _laeuft

    property string _ziel: ""
    property bool _laeuft: false
    property int _code: -1

    function setzen(wahl: string): void {
        if (_laeuft || Oberflaeche.gesperrt || wahlen.indexOf(wahl) < 0)
            return;
        if (_ziel === "" && wahl === Geraet.luefterWahl)
            return;
        bestaetigung.stop();
        _ziel = wahl;
        _code = -1;
        _laeuft = true;
        prozess.command = ["pkexec", helfer, wahl];
        prozess.running = true;
    }

    function _fertig(): void {
        if (!_laeuft)
            return;
        _laeuft = false;
        const code = _code;
        if (code === 0) {
            Geraet.aktualisieren();
            if (Geraet.luefterWahl === _ziel)
                _ziel = "";
            else
                bestaetigung.start();
            return;
        }
        _ziel = "";
        // Abgebrochen (z. B. Sperre während der Anfrage): ruhig, die Wahl springt zurück
        if (code === 126)
            return;
        const zeilen = fehlerText.text.trim().split("\n");
        const grund = (zeilen[zeilen.length - 1] ?? "").replace(/^zenos-luefter:\s*/, "").trim();
        let meldung = "";
        if (code < 0)
            meldung = "Lüfter: pkexec lässt sich nicht starten (install.sh ausführen)";
        else if (code === 127 && /authentication agent/i.test(fehlerText.text))
            meldung = "Lüfter: keine Bestätigung möglich (polkit-Agent nicht angemeldet)";
        else if (code === 127)
            meldung = "Lüfter: nicht erlaubt (nur in der aktiven Sitzung am Gerät)";
        else
            meldung = "Lüfter liess sich nicht einstellen" + (grund !== "" ? ": " + grund : "");
        console.warn(meldung, "(Exit " + code + ")");
        Oberflaeche.hinweis(meldung, "warnung");
    }

    Process {
        id: prozess

        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: fehlerText
        }
        onExited: code => root._code = code
        onRunningChanged: {
            if (!running)
                Qt.callLater(root._fertig);
        }
    }

    // Auf zenos-argon warten: alle 1,5 s geraet.json neu lesen, höchstens achtmal (12 s)
    Timer {
        id: bestaetigung

        property int versuche: 0

        interval: 1500
        repeat: true
        onRunningChanged: if (running) versuche = 0
        onTriggered: {
            versuche += 1;
            Geraet.aktualisieren();
            if (Geraet.luefterWahl === root._ziel) {
                stop();
                root._ziel = "";
            } else if (versuche >= 8) {
                stop();
                root._ziel = "";
                Oberflaeche.hinweis("Lüfter: Wunsch gespeichert, zenos-argon übernimmt ihn nicht (läuft der Dienst?)", "warnung");
            }
        }
    }

    // Bestätigt schon der gewöhnliche Takt von Geraet, ist die Wahl sofort fertig
    Connections {
        target: Geraet

        function onLuefterWahlChanged(): void {
            if (root._ziel !== "" && !root._laeuft && Geraet.luefterWahl === root._ziel) {
                bestaetigung.stop();
                root._ziel = "";
            }
        }
    }
}
