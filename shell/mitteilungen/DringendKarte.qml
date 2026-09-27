pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.komponenten

// Eine dringende Mitteilung (urgency critical). Bleibt, bis sie geschlossen, ausgeführt
// oder in der Zentrale angesehen wird.
Karte {
    id: root

    property var eintrag: null
    // Leitplanke: kein Inhalt, nur der Hinweis
    property bool verborgen: false
    property bool offen: true

    property bool _bereit: false

    // Nach dem Ausblenden: aus der Liste nehmen
    signal entfernt
    signal geklickt
    signal aktion(string kennung)

    function schliessen(): void {
        offen = false;
    }

    innenabstand: Theme.a4
    border.color: Theme.linie2
    opacity: _bereit && offen ? 1 : 0

    Accessible.role: Accessible.AlertMessage
    Accessible.name: verborgen ? "Dringende Mitteilung, Inhalt verborgen" : "Dringend: " + (eintrag?.titel ?? "")

    Behavior on opacity {
        NumberAnimation {
            duration: root.offen ? Theme.dauerKurz : Theme.dauerMax
            easing.type: Theme.kurve
        }
    }

    onOpacityChanged: if (!offen && opacity === 0)
        entfernt()
    Component.onCompleted: _bereit = true

    ColumnLayout {
        width: parent.width
        spacing: 0

        // Leitplanke: bei Bildschirmfreigabe kein Inhalt
        RowLayout {
            Layout.fillWidth: true
            visible: root.verborgen
            spacing: Theme.a3

            AppSymbol {
                Layout.alignment: Qt.AlignTop
                ersatz: "warnung"
                ersatzFarbe: Theme.warnung
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: "Dringende Mitteilung"
                    color: Theme.text
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                    font.weight: Font.Medium
                }

                Text {
                    Layout.fillWidth: true
                    text: "Inhalt verborgen, Bildschirm wird geteilt"
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

        // Leitplanke: bei Freigabe wird der Inhalt gar nicht erst erzeugt
        Loader {
            Layout.fillWidth: true
            active: !root.verborgen
            visible: active

            sourceComponent: Eintrag {
                eintrag: root.eintrag
                schliessbar: true
                textZeilen: 6
                onSchliessen: root.schliessen()
                onGeklickt: root.geklickt()
                onAktion: kennung => root.aktion(kennung)
            }
        }
    }
}
