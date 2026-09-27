import QtQuick
import qs.theme
import qs.komponenten

// Eintrag als Chip mit «entfernen» (30 px, Radius 8), z. B. eine App oder ein Mail-Konto.
Rectangle {
    id: root

    property string text

    signal entfernen

    implicitWidth: label.implicitWidth + 12 + 4 + knopf.width + 4
    implicitHeight: 30
    radius: Theme.radiusChip
    color: Qt.alpha(Theme.flaeche2, 0.6)

    Text {
        id: label

        x: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Theme.text
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseLabel
    }

    Item {
        id: knopf

        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 22
        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: root.text + " entfernen"
        Accessible.onPressAction: root.entfernen()

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Delete) {
                root.entfernen();
                event.accepted = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: Theme.text
            opacity: maus.containsMouse ? 0.07 : 0
        }

        Symbol {
            anchors.centerIn: parent
            name: "x"
            groesse: 10
            strichbreite: 2.4
            farbe: Theme.gedaempft
        }

        Fokusrahmen {
            eckenRadius: 5
        }

        MouseArea {
            id: maus

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.entfernen()
        }
    }
}
