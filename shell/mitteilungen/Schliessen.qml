import QtQuick
import qs.theme
import qs.komponenten

// Kleiner Schliessen-Knopf (24 px) für Karten und die Zentrale.
Item {
    id: root

    property string beschriftung: "Schliessen"

    signal clicked

    implicitWidth: 24
    implicitHeight: 24
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: beschriftung
    Accessible.onPressAction: clicked()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusXs
        color: Theme.text
        opacity: maus.pressed ? 0.09 : maus.containsMouse ? 0.05 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Symbol {
        anchors.centerIn: parent
        name: "x"
        groesse: 13
        farbe: Theme.gedaempft
    }

    Fokusrahmen {
        eckenRadius: Theme.radiusXs
    }

    MouseArea {
        id: maus

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
