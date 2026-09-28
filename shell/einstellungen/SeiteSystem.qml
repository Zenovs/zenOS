pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.theme
import qs.komponenten
import qs.einstellungen.teile
import qs.dienste as Dienste

// Seite «System»: Ausgabe von «zen version», Kurzprüfung mit «zen doctor --kurz» auf Knopfdruck
// und Hinweise auf zen update und zen doctor. Nichts läuft automatisch.
Item {
    id: root

    property string unterauswahl

    readonly property string _zen: Dienste.Pfade.code + "/scripts/zen"
    property string versionText: ""
    property string pruefText: ""
    property bool pruefFehler: false

    Process {
        id: version

        command: [root._zen, "version"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.versionText = text.trim()
        }
        onExited: code => {
            if (code !== 0 && root.versionText === "")
                root.versionText = "zen version ist nicht verfügbar.";
        }
        onRunningChanged: {
            if (!running && root.versionText === "")
                root.versionText = "zen version ist nicht verfügbar.";
        }
    }

    Process {
        id: pruefung

        command: [root._zen, "doctor", "--kurz"]
        stdout: StdioCollector {
            onStreamFinished: {
                const zeilen = text.trim().split("\n");
                root.pruefText = zeilen[zeilen.length - 1] ?? "";
            }
        }
        onExited: code => {
            root.pruefFehler = code !== 0;
            if (root.pruefText === "")
                root.pruefText = "Keine Ausgabe von zen doctor.";
        }
    }

    Seite {
        id: seite

        anchors.fill: parent

        SeitenKopf {
            width: parent.width
            label: "Einstellungen"
            titel: "System"
        }

        Feld {
            width: parent.width
            beschriftung: "zen version"

            Rectangle {
                width: parent.width
                height: Math.max(1, versionAusgabe.lineCount) * versionAusgabe.lineHeight + 28
                radius: Theme.radiusFeld
                color: Qt.alpha(Theme.flaeche2, 0.55)

                Text {
                    id: versionAusgabe

                    x: 16
                    y: 14
                    width: parent.width - 32
                    text: root.versionText !== "" ? root.versionText : "…"
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    // Feste Zeilenhöhe wie CSS line-height (proportional vervielfacht Qt die Schrifthöhe)
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.5)
                    color: Theme.text
                    font.family: Theme.schriftMono
                    font.pixelSize: Theme.groesseLabel
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Prüfbericht"

            Column {
                width: parent.width
                spacing: 10

                Row {
                    spacing: 16

                    Knopf {
                        implicitHeight: 38
                        variante: "sekundaer"
                        text: pruefung.running ? "Prüft …" : "Kurz prüfen"
                        enabled: !pruefung.running
                        onClicked: {
                            root.pruefText = "";
                            pruefung.running = true;
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.pruefText !== ""
                        text: root.pruefText
                        color: root.pruefFehler ? Theme.fehler : Theme.text
                        font.family: Theme.schriftMono
                        font.pixelSize: Theme.groesseLabel
                    }
                }

                Text {
                    width: parent.width
                    text: "Den ausführlichen Bericht zeigt «zen doctor» im Terminal. Er enthält keine Geheimnisse und keine Inhalte aus deiner Konfiguration."
                    wrapMode: Text.WordWrap
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                }
            }
        }

        Feld {
            width: parent.width
            beschriftung: "Aktualisieren"

            Column {
                width: parent.width
                spacing: 10

                Text {
                    width: parent.width
                    text: "zenOS aktualisiert sich nicht von selbst. Im Terminal holt «zen update» den neuen Stand und installiert ihn; «zen rollback <tag>» geht zu einem früheren zurück."
                    wrapMode: Text.WordWrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.4)
                    color: Theme.text
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }

                Row {
                    spacing: 8

                    Kbd {
                        text: "zen update"
                    }

                    Kbd {
                        text: "zen doctor"
                    }

                    Kbd {
                        text: "zen version"
                    }
                }

                Knopf {
                    implicitHeight: 38
                    variante: "sekundaer"
                    symbol: "terminal"
                    text: "Terminal öffnen"
                    onClicked: Dienste.Aktionen.terminal()
                }
            }
        }

        fuss: SeitenFuss {
            width: seite.width - 88
            pfad: "/opt/zenos · Code aus dem Git-Repo, persönliche Daten nur unter ~/.config/zenos"
            onFertig: Dienste.Oberflaeche.einstellungenOffen = false
        }
    }
}
