pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.komponenten

// Ein Bildschirm des Logins, gestaltet wie der Sperrbildschirm in Entwurf 2: Bogen als Wasserzeichen,
// grosse Uhrzeit, Datum, Konto, Formular. Formular, Knöpfe und Tastaturfokus nur auf einem Bildschirm.
PanelWindow {
    id: root

    required property Konten konten
    required property Ablauf ablauf
    property bool mitFormular: true

    readonly property var _konto: konten.liste.length === 1 ? konten.liste[0] : null

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: Theme.grund

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: mitFormular ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "zenos-greeter"

    SystemClock {
        id: uhr

        precision: SystemClock.Minutes
    }

    // Klick ins Leere: Fokus zurück ins Formular
    MouseArea {
        anchors.fill: parent
        enabled: root.mitFormular
        onClicked: formular.fokussieren()
    }

    Zeichen {
        anchors.centerIn: parent
        groesse: Math.min(760, root.height * 0.85)
        strichbreite: 0.9
        farbe: Theme.wasserzeichen
    }

    Column {
        anchors.centerIn: parent
        spacing: 28

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // Zeilenhöhe 0.9 wie im Entwurf: Kasten 0.9 × Schriftgrösse, Schrift darin mittig (wie CSS)
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: zeit.implicitWidth
                implicitHeight: Math.round(Theme.groesseAnzeige * 0.9)

                FontMetrics {
                    id: zeitMass

                    font: zeit.font
                }

                Text {
                    id: zeit

                    y: Math.round((parent.height - zeitMass.ascent - zeitMass.descent) / 2)
                    text: Qt.formatTime(uhr.date, "HH:mm")
                    color: Theme.text
                    font.family: Theme.schriftAnzeige
                    font.pixelSize: Theme.groesseAnzeige
                    font.letterSpacing: -Theme.groesseAnzeige * 0.01
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.locale("de_DE").toString(uhr.date, "dddd, d. MMMM")
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: 18
            }
        }

        // Genau ein Konto: als Pille wie die Mitteilungszeile im Sperrbildschirm
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mitFormular && root._konto !== null
            implicitWidth: pille.implicitWidth + 36
            implicitHeight: pille.implicitHeight + 20
            radius: Theme.radiusPille
            color: Theme.durchsichtig
            border.width: 1
            border.color: Theme.linie2

            Row {
                id: pille

                anchors.centerIn: parent
                spacing: 10

                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "schloss"
                    groesse: 14
                    farbe: Theme.gedaempft
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Anmelden als " + (root._konto?.anzeige ?? "")
                    color: Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }
            }
        }

        Item {
            visible: root.mitFormular
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: formular.implicitWidth
            implicitHeight: formular.implicitHeight + 24

            Formular {
                id: formular

                y: 24
                width: 380
                konten: root.konten
                ablauf: root.ablauf
            }
        }
    }

    // Unten: Bildmarke und Name, rechts Neustart und Ausschalten
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        spacing: 8

        Zeichen {
            anchors.verticalCenter: parent.verticalCenter
            groesse: 14
            farbe: Theme.akzent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "zenOS"
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }
    }

    Energie {
        visible: root.mitFormular
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Theme.a5
        anchors.bottomMargin: Theme.a5
    }

    Component.onCompleted: if (mitFormular) Qt.callLater(() => formular.fokussieren())
}
