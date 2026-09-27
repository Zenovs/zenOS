import QtQuick
import qs.theme

// Karte: Fläche mit 1-px-Linie und Radius 12. Inhalt als Kinder, mit Innenabstand.
Rectangle {
    id: root

    property int innenabstand: Theme.a4
    default property alias inhalt: innen.data

    implicitWidth: innen.childrenRect.width + 2 * innenabstand
    implicitHeight: innen.childrenRect.height + 2 * innenabstand
    radius: Theme.radiusFenster
    color: Theme.flaeche
    border.width: 1
    border.color: Theme.linie

    Item {
        id: innen

        anchors.fill: parent
        anchors.margins: root.innenabstand
    }
}
