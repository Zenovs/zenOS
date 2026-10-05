pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.komponenten

// Ein Bildschirm des Logins, gestaltet wie der Sperrbildschirm in Entwurf 2: grosse Uhrzeit, Datum, Konto,
// Formular, unten die Bildmarke. Formular, Knöpfe und Tastaturfokus nur auf einem Bildschirm.
PanelWindow {
    id: root

    required property Konten konten
    required property Ablauf ablauf
    required property Leerlauf leerlauf
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

        // Vorwarnung vor dem Ausschalten (Leerlauf im Akkubetrieb oder leerer Akku), wie auf dem Sperrbildschirm: ruhig,
        // mit Uhrzeit statt Sekunden, auf jedem Bildschirm
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.leerlauf.text.length > 0
            implicitWidth: vorwarnungZeile.implicitWidth + 38
            implicitHeight: vorwarnungZeile.implicitHeight + 22
            radius: Theme.radiusPille
            color: Theme.durchsichtig
            border.width: 1
            border.color: Theme.linie2

            Row {
                id: vorwarnungZeile

                anchors.centerIn: parent
                spacing: 10

                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.leerlauf.akkuLeer ? "akku-leer" : "ausschalten"
                    groesse: 14
                    strichbreite: 1.8
                    farbe: root.leerlauf.akkuLeer ? Theme.warnung : Theme.text2
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.leerlauf.text
                    textFormat: Text.PlainText
                    color: Theme.text2
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }
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

    // Unten die Bildmarke (48 px, unterer Stein im Standardakzent), rechts Neustart und Ausschalten
    ZenZeichen {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.a6
        groesse: 48
        akzent: Theme.standardAkzent
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
