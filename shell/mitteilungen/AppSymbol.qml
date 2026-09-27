import QtQuick
import qs.theme
import qs.komponenten

// Symbol-Kasten einer Mitteilung (28 px, wie im Befehlsfeld): Bild der Mitteilung, sonst
// App-Symbol, sonst ein Strich-Symbol.
Rectangle {
    id: root

    // Bildquelle (URL) oder leer
    property string quelle
    // Strich-Symbol, wenn es kein Bild gibt
    property string ersatz: "glocke"
    property color ersatzFarbe: Theme.text2

    implicitWidth: 28
    implicitHeight: 28
    radius: 7
    color: Theme.flaeche2

    Image {
        id: bild

        anchors.centerIn: parent
        width: 18
        height: 18
        source: root.quelle
        sourceSize.width: 36
        sourceSize.height: 36
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: status === Image.Ready
    }

    Symbol {
        anchors.centerIn: parent
        visible: bild.status !== Image.Ready
        name: root.ersatz
        groesse: 15
        farbe: root.ersatzFarbe
    }
}
