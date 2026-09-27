import QtQuick
import qs.theme

// Formularfeld der Einstellungen: Beschriftung (13 px, gedämpft) über dem Inhalt, Abstand 8.
// Optional rechts neben der Beschriftung ein Hinweis (z. B. «angepasst»).
Column {
    id: root

    property string beschriftung
    property string hinweis
    // Inhalt unter der Beschriftung
    default property alias inhalt: platz.data
    // Hinweis-Text hervorheben (Akzent)
    property bool hinweisBetont: false
    property color akzent: Theme.akzent

    spacing: 8

    Row {
        spacing: 8
        visible: root.beschriftung.length > 0

        Text {
            text: root.beschriftung
            color: Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
        }

        Text {
            visible: root.hinweis.length > 0
            text: root.hinweis
            color: root.hinweisBetont ? root.akzent : Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Item {
        id: platz

        width: root.width
        height: childrenRect.height
    }
}
