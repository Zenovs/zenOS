import QtQuick
import qs.theme

// Sichtbarer Tastaturfokus: 2-px-Ring im Akzent, 2 px ausserhalb des Elternelements.
// Einsetzen als Kind des fokussierbaren Elements (ohne clip).
Rectangle {
    id: root

    property bool aktiv: parent ? parent.activeFocus : false
    property real eckenRadius: Theme.radiusChip

    anchors.fill: parent
    anchors.margins: -3
    radius: eckenRadius + 3
    color: Theme.durchsichtig
    border.width: 2
    border.color: Theme.akzent
    opacity: aktiv ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.dauerKurz
            easing.type: Theme.kurve
        }
    }
}
