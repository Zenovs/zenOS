pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste

// Ein/Aus-Taste am Login-Bildschirm (Zenos Entscheid vom 08.10.2026): Ein kurzer Druck weckt nur. Die Taste kommt über
// labwc als XF86PowerOff an (system/greeter/labwc/rc.xml belegt sie bewusst nicht). Ist der Bildschirm aus, ist sie die
// Wecktaste wie jede andere (Bildschirm.qml, Wecker in Anmeldefenster.qml): Er geht an, sonst geschieht nichts. Ist er
// an, bewirkt sie nichts. Ausgeschaltet wird über «Ausschalten» unten rechts (Energie.qml, zweiter Klick); gedrückt
// halten schaltet immer hart aus (Hardware).
// Damit logind bei einem kurzen Druck nicht selbst ausschaltet (HandlePowerKey), hält «zenos-energie hemmer-login» den
// logind-Hemmer «handle-power-key», solange diese Oberfläche läuft (tail --pid auf Quickshell, endet also auch nach
// einem Absturz). Ausfallsicher: Bekommt er ihn nicht (polkit, logind) oder endet er, gilt logind wie bisher (ein
// kurzer Druck schaltet aus), im Journal steht es einmal, und nach 60 s folgt ein neuer Versuch. Der Notfall-Login
// nimmt keinen Hemmer. Prozesse nur mit Argumentlisten.
Scope {
    id: root

    // --- intern ---

    // Neuer Versuch, wenn der Hemmer unerwartet endet (ms)
    readonly property int _pauseMs: 60000
    // Ein Fehlschlag steht schon im Journal (nicht bei jedem Versuch erneut)
    property bool _gemeldet: false

    function _beendet(code: int, text: string, fehler: string): void {
        // Exit 0: kein Login unter greetd (Start-Test, eine Sitzung), es gibt nichts zu halten
        if (code === 0) {
            const zeile = text.trim();
            if (zeile.length > 0)
                console.info("Login:", zeile);
            return;
        }
        if (!root._gemeldet) {
            const grund = fehler.trim().replace(/\s+/g, " ");
            console.warn("Login: Hemmer für die Ein/Aus-Taste beendet (Exit " + code + (grund.length > 0 ? ": " + grund : "") + ") · ein kurzer Druck schaltet aus (logind), neuer Versuch in", root._pauseMs / 1000, "s");
        }
        root._gemeldet = true;
        neuerVersuch.restart();
    }

    Process {
        id: hemmer

        property int code: -1

        command: [Pfade.bin + "/zenos-energie", "hemmer-login"]
        running: true
        stdout: StdioCollector {
            id: hemmerAusgabe
        }
        stderr: StdioCollector {
            id: hemmerFehler
        }
        onExited: (code, status) => hemmer.code = status === 0 ? code : -1
        onRunningChanged: {
            if (running) {
                hemmer.code = -1;
                laeuft.restart();
            } else {
                laeuft.stop();
                Qt.callLater(() => root._beendet(hemmer.code, hemmerAusgabe.text, hemmerFehler.text));
            }
        }
    }

    // Läuft der Helfer nach 2 s noch, hält er den Hemmer (systemd-inhibit endet sofort, wenn logind ablehnt)
    Timer {
        id: laeuft

        interval: 2000
        onTriggered: {
            console.info("Login: Ein/Aus-Taste weckt nur (Hemmer handle-power-key" + (root._gemeldet ? ", wieder da)" : ")"));
            root._gemeldet = false;
        }
    }

    Timer {
        id: neuerVersuch

        interval: root._pauseMs
        onTriggered: hemmer.running = true
    }
}
