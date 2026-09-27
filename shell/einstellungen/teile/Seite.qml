import QtQuick
import qs.theme

// Rahmen einer Einstellungen-Seite: Innenabstand 28 × 44, Inhalt scrollt, der Fuss bleibt unten.
Item {
    id: root

    default property alias inhalt: spalte.data
    property alias fuss: fussPlatz.data
    property alias flick: flick
    property int abstand: Theme.a5

    Flickable {
        id: flick

        anchors.fill: parent
        anchors.bottomMargin: fussPlatz.height > 0 ? fussPlatz.height + 28 + 20 : 0
        contentWidth: width
        contentHeight: spalte.implicitHeight + 28 + Theme.a5
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: spalte

            x: 44
            y: 28
            width: flick.width - 88
            spacing: root.abstand
        }
    }

    // Dünner Balken nur, wenn gescrollt werden kann
    Rectangle {
        visible: flick.contentHeight > flick.height
        anchors.right: flick.right
        anchors.rightMargin: 4
        y: flick.y + 4 + (flick.height - 8 - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
        width: 4
        height: Math.max(32, (flick.height - 8) * flick.height / flick.contentHeight)
        radius: 2
        color: Theme.gedaempft
        opacity: flick.moving ? 0.5 : 0.2

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dauerMax
                easing.type: Theme.kurve
            }
        }
    }

    // Trennlinie über dem Fuss, sobald der Inhalt darunter weitergeht
    Rectangle {
        visible: fussPlatz.height > 0 && flick.contentY + flick.height < flick.contentHeight - 1
        x: 44
        width: root.width - 88
        height: 1
        anchors.bottom: fussPlatz.top
        anchors.bottomMargin: 20
        color: Theme.trennlinie
    }

    Item {
        id: fussPlatz

        x: 44
        width: root.width - 88
        height: childrenRect.height
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
    }

    // Kleine Hilfe für die Seiten: ein Element sichtbar scrollen (Tastatur)
    function sichtbarMachen(item: Item): void {
        if (!item)
            return;
        const p = item.mapToItem(spalte, 0, 0);
        if (p.y < flick.contentY)
            flick.contentY = Math.max(0, p.y - 12);
        else if (p.y + item.height > flick.contentY + flick.height)
            flick.contentY = Math.min(flick.contentHeight - flick.height, p.y + item.height - flick.height + 12);
    }
}
