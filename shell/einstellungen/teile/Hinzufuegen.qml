import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.komponenten

// «+ App»: Knopf mit gestricheltem Rahmen (30 px, Radius 8).
Item {
    id: root

    property string text

    signal clicked

    implicitWidth: label.implicitWidth + 24
    implicitHeight: 30
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: clicked()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked();
            event.accepted = true;
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: maus.containsMouse ? Theme.gedaempft : Theme.eingabeRand
            strokeWidth: 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [3, 3]
            fillColor: Theme.durchsichtig

            PathRectangle {
                x: 0.5
                y: 0.5
                width: root.width - 1
                height: root.height - 1
                radius: Theme.radiusChip
            }
        }
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: root.text
        color: Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseLabel
    }

    Fokusrahmen {
        eckenRadius: Theme.radiusChip
    }

    MouseArea {
        id: maus

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
