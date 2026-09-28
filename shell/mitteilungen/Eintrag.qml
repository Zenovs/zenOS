pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.komponenten
import "format.js" as Format

// Eine Mitteilung: Symbol, App und Zeit (Mono), Titel, Text und Aktionen.
// Inhalte immer als reiner Text. Wer Inhalte verbergen muss, zeigt diesen Baustein nicht.
Item {
    id: root

    // Eintrag aus dem Dienst Mitteilungen
    property var eintrag: null
    // eine Zeile Text, keine Aktionen (Sammelkarte)
    property bool kompakt: false
    property int textZeilen: 3
    property bool schliessbar: false
    property string schliessenText: "Schliessen"
    property bool mitAktionen: !kompakt
    // Innenabstand und leichte Fläche beim Zeigen (Liste der Zentrale)
    property int polster: 0
    property bool hoverFlaeche: false
    property var jetzt: new Date()

    readonly property bool dringend: eintrag?.dringend ?? false
    readonly property var aktionen: mitAktionen ? (eintrag?.aktionen ?? []) : []

    // Klick auf die Mitteilung selbst
    signal geklickt
    signal schliessen
    signal aktion(string kennung)

    implicitHeight: zeilen.implicitHeight + 2 * polster

    Accessible.role: Accessible.ListItem
    Accessible.name: (dringend ? "Dringend: " : "") + (eintrag?.app ?? "") + ", " + (eintrag?.titel ?? "")

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: Theme.flaeche2
        opacity: root.hoverFlaeche && maus.containsMouse ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    MouseArea {
        id: maus

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.geklickt()
    }

    RowLayout {
        id: zeilen

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.polster
        spacing: Theme.a3

        AppSymbol {
            Layout.alignment: Qt.AlignTop
            quelle: String(root.eintrag?.bild || root.eintrag?.symbol || "")
            ersatz: root.dringend ? "warnung" : "glocke"
            ersatzFarbe: root.dringend ? Theme.warnung : Theme.text2
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumHeight: 24
                spacing: 6

                Abschnittstitel {
                    visible: root.dringend
                    text: "Dringend"
                    color: Theme.warnung
                }

                Text {
                    Layout.fillWidth: true
                    text: String(root.eintrag?.app ?? "")
                    textFormat: Text.PlainText
                    color: Theme.gedaempft
                    font.family: Theme.schriftMono
                    font.pixelSize: Theme.groesseKlein
                    elide: Text.ElideRight
                }

                Text {
                    text: String(Format.zeit(root.eintrag?.ankunft ?? null, root.jetzt) ?? "")
                    color: Theme.gedaempft
                    font.family: Theme.schriftMono
                    font.pixelSize: Theme.groesseKlein
                }

                Schliessen {
                    visible: root.schliessbar
                    beschriftung: root.schliessenText
                    onClicked: root.schliessen()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: String(root.eintrag?.titel ?? "")
                textFormat: Text.PlainText
                color: Theme.text
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
                font.weight: Font.Medium
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: root.kompakt ? 1 : 2
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: String(root.eintrag?.text ?? "")
                textFormat: Text.PlainText
                color: Theme.text2
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseLabel
                lineHeight: 1.15
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: root.kompakt ? 1 : root.textZeilen
                elide: Text.ElideRight
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Theme.a2
                visible: root.aktionen.length > 0
                spacing: 6

                Repeater {
                    model: root.aktionen

                    Chip {
                        required property var modelData

                        // im Dienst bereinigt und gekürzt (bereinigen.js)
                        text: String(modelData?.text ?? "")
                        variante: "umrandet"
                        onClicked: root.aktion(modelData.identifier)
                    }
                }
            }
        }
    }
}
