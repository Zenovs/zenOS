import QtQuick
import qs.theme
import qs.komponenten
import "wlan.js" as Wlan

// WLAN-Symbol mit Signalstufe: 3 = alle Bögen, 2 und 1 zeichnen die fehlenden Bögen blass darunter (30 % der
// Farbe), 0 = «wlan-aus» (kein WLAN oder WLAN aus). Ruhig: Die Stufe wechselt ohne Animation.
Item {
    id: root

    property int stufe: 3
    property color farbe: Theme.text
    property real groesse: 15

    implicitWidth: groesse
    implicitHeight: groesse

    Symbol {
        anchors.fill: parent
        visible: root.stufe === 1 || root.stufe === 2
        name: "wlan"
        groesse: root.groesse
        farbe: Qt.alpha(root.farbe, 0.3)
    }

    Symbol {
        anchors.fill: parent
        name: Wlan.symbol(root.stufe)
        groesse: root.groesse
        farbe: root.farbe
    }
}
