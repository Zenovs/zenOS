//@ pragma Env QT_NO_XDG_DESKTOP_PORTAL=1
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.dienste
import qs.theme

// Ersatzbild der Anzeige-Sitzung (Geräteprofil «Öffentlicher Bildschirm», docs/module/anzeige.md). Läuft als
// zenos-anzeige-ersatz.service des Anzeige-Kontos auf der Ebene Background unter jedem Fenster: Läuft die App, liegt sie
// im Vollbild darüber; läuft sie nicht oder stürzt sie ab, steht hier ruhig die Uhrzeit, «Anzeige startet …» und der
// Rechnername, nie ein leerer Desktop. Fehlt die App (nicht installiert, keine eingerichtet), steht statt «Anzeige
// startet …», was fehlt («zenos-anzeige hinweis», alle 30 s neu, so verschwindet es, sobald die App installiert ist).
// Keine Eingaben, keine Tastatur, nichts geht nach aussen. Die Uhr tickt minutengenau (sparsam für den Pi).
ShellRoot {
    id: root

    property string rechnername: ""
    property string hinweis: "Anzeige startet …"

    Process {
        id: hinweisAbfrage

        command: ["/usr/bin/python3", "-I", Pfade.bin + "/zenos-anzeige", "hinweis"]
        stdout: StdioCollector {
            onStreamFinished: {
                const zeile = text.trim().split("\n")[0];
                if (zeile.length > 0 && zeile.length <= 160)
                    root.hinweis = zeile;
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: hinweisAbfrage.running = true
    }

    SystemClock {
        id: uhr

        precision: SystemClock.Minutes
    }

    FileView {
        path: "/etc/hostname"
        printErrors: false
        onLoaded: root.rechnername = text().trim().split("\n")[0]
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            required property ShellScreen modelData

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.grund

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "zenos-anzeige-ersatz"

            Column {
                anchors.centerIn: parent
                spacing: Theme.a4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(uhr.date, "HH:mm")
                    color: Theme.text
                    font.family: Theme.schriftAnzeige
                    font.pixelSize: Theme.groesseAnzeige
                    font.letterSpacing: -0.01 * Theme.groesseAnzeige
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.hinweis
                    color: Theme.text2
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseGross
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.rechnername.length > 0
                    text: root.rechnername
                    color: Theme.gedaempft
                    font.family: Theme.schriftMono
                    font.pixelSize: Theme.groesseLabel
                }
            }
        }
    }
}
