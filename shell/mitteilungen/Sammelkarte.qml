pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.komponenten
import "format.js" as Format

// Ruhige Karte für zugestellte Mitteilungen, oben rechts unter der Leiste.
// Eine Mitteilung erscheint ganz, mehrere als kurze Liste. Blendet in 120 ms ein und
// 200 ms aus, ohne Bewegung.
Karte {
    id: root

    // Einträge, neueste zuerst
    property var eintraege: []
    property bool offen: false
    // Leitplanke: nur die Anzahl zeigen
    property bool verborgen: false
    // Zeitpunkt der Zustellung
    property var zeitpunkt: null
    readonly property int maxZeilen: 3

    readonly property bool sichtbar: offen || opacity > 0

    property bool _bereit: false

    signal schliessen
    // ganz ausgeblendet
    signal ausgeblendet
    signal zentrale
    // Klick auf eine Mitteilung
    signal geklickt(var eintrag)
    signal aktion(var eintrag, string kennung)

    innenabstand: Theme.a4
    border.color: Theme.linie2
    opacity: _bereit && offen ? 1 : 0
    visible: sichtbar

    Accessible.role: Accessible.AlertMessage
    Accessible.name: verborgen ? Format.mitteilungen(eintraege.length) + ", Inhalte verborgen" : Format.mitteilungen(eintraege.length)

    Behavior on opacity {
        NumberAnimation {
            duration: root.offen ? Theme.dauerKurz : Theme.dauerMax
            easing.type: Theme.kurve
        }
    }

    onSichtbarChanged: if (!sichtbar)
        ausgeblendet()
    Component.onCompleted: {
        _bereit = true;
        if (!offen)
            Qt.callLater(ausgeblendet);
    }

    ColumnLayout {
        width: parent.width
        spacing: Theme.a3

        // Leitplanke: bei Bildschirmfreigabe nur die Anzahl
        RowLayout {
            Layout.fillWidth: true
            visible: root.verborgen
            spacing: Theme.a3

            AppSymbol {
                Layout.alignment: Qt.AlignTop
                ersatz: "glocke-aus"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: Format.mitteilungen(root.eintraege.length)
                    color: Theme.text
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                    font.weight: Font.Medium
                }

                Text {
                    Layout.fillWidth: true
                    text: "Inhalte verborgen, Bildschirm wird geteilt"
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseLabel
                    wrapMode: Text.WordWrap
                }
            }

            Schliessen {
                Layout.alignment: Qt.AlignTop
                onClicked: root.schliessen()
            }
        }

        // Eine Mitteilung: ganz
        Loader {
            Layout.fillWidth: true
            active: root.sichtbar && !root.verborgen && root.eintraege.length === 1
            visible: active

            sourceComponent: Eintrag {
                eintrag: root.eintraege[0] ?? null
                schliessbar: true
                onSchliessen: root.schliessen()
                onGeklickt: root.geklickt(eintrag)
                onAktion: kennung => root.aktion(eintrag, kennung)
            }
        }

        // Mehrere: Kopf und kurze Liste
        RowLayout {
            Layout.fillWidth: true
            visible: !root.verborgen && root.eintraege.length > 1
            spacing: Theme.a2

            Symbol {
                name: "glocke"
                groesse: 15
                farbe: Theme.akzent
            }

            Text {
                text: Format.mitteilungen(root.eintraege.length)
                color: Theme.text
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
                font.weight: Font.Medium
            }

            Text {
                Layout.fillWidth: true
                text: root.zeitpunkt ? "gesammelt · " + Format.uhrzeit(root.zeitpunkt) : "gesammelt"
                color: Theme.gedaempft
                font.family: Theme.schriftMono
                font.pixelSize: Theme.groesseKlein
                elide: Text.ElideRight
            }

            Schliessen {
                onClicked: root.schliessen()
            }
        }

        Trenner {
            Layout.fillWidth: true
            visible: !root.verborgen && root.eintraege.length > 1
        }

        Repeater {
            model: root.sichtbar && !root.verborgen && root.eintraege.length > 1 ? root.eintraege.slice(0, root.maxZeilen) : []

            Eintrag {
                required property var modelData

                Layout.fillWidth: true
                eintrag: modelData
                kompakt: true
                onGeklickt: root.geklickt(modelData)
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !root.verborgen && root.eintraege.length > root.maxZeilen
            text: "und " + (root.eintraege.length - root.maxZeilen) + " weitere · in der Zentrale"
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.zentrale()
            }
        }
    }
}
