import QtQuick
import qs.theme

// Tastenkappe: Geist Mono 12, Rahmen, Radius 6.
// leise: gedämpfter Text ohne Fläche (z. B. «Esc» im Befehlsfeld).
Rectangle {
    id: root

    property string text
    property bool leise: false

    implicitWidth: label.implicitWidth + 16 + 2
    implicitHeight: label.implicitHeight + 6 + 2
    radius: Theme.radiusXs
    color: leise ? Theme.durchsichtig : Theme.flaeche
    border.width: 1
    border.color: Theme.tasteRand

    Text {
        id: label

        anchors.centerIn: parent
        text: root.text
        color: root.leise ? Theme.gedaempft : Theme.text
        font.family: Theme.schriftMono
        font.pixelSize: Theme.groesseKlein
    }
}
