import QtQuick
import qs.theme
import qs.komponenten

// Kopf einer Seite: kleines Label (Mono, Grossbuchstaben) über dem Titel (Instrument Serif 44),
// rechts Platz für eine Pille oder Knöpfe.
Item {
    id: root

    property string label
    property string titel
    default property alias rechts: rechtsPlatz.data

    implicitHeight: spalte.implicitHeight

    Column {
        id: spalte

        width: root.width - rechtsPlatz.width - Theme.a4
        spacing: 4

        Abschnittstitel {
            text: root.label
        }

        Text {
            width: parent.width
            text: root.titel
            color: Theme.text
            font.family: Theme.schriftAnzeige
            font.pixelSize: 44
            lineHeight: 1
            elide: Text.ElideRight
        }
    }

    Row {
        id: rechtsPlatz

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: Theme.a2
    }
}
