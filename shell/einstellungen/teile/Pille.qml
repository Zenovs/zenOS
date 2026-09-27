import QtQuick
import qs.theme

// Kleine Pille: «aktiv» (Rahmen und Text im Akzent, mit Punkt), «angepasst» (zarter Akzent),
// «vorlage» und «spaeter» (neutral).
Rectangle {
    id: root

    property string text
    property string variante: "vorlage"
    property color akzent: Theme.akzent
    property bool gross: variante === "aktiv"

    implicitWidth: reihe.implicitWidth + (gross ? 24 : 20)
    implicitHeight: gross ? 28 : 24
    radius: Theme.radiusPille
    color: variante === "angepasst" ? Qt.alpha(akzent, Theme.dunkel ? 0.18 : 0.12) : variante === "aktiv" ? Theme.durchsichtig : Qt.alpha(Theme.flaeche2, 0.8)
    border.width: variante === "aktiv" ? 1 : 0
    border.color: akzent

    Row {
        id: reihe

        anchors.centerIn: parent
        spacing: 8

        Rectangle {
            visible: root.variante === "aktiv"
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: root.akzent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.variante === "aktiv" || root.variante === "angepasst" ? root.akzent : Theme.gedaempft
            font.family: root.variante === "spaeter" ? Theme.schriftMono : Theme.schriftText
            font.pixelSize: root.gross ? Theme.groesseLabel : (root.variante === "spaeter" ? 11 : Theme.groesseKlein)
        }
    }
}
