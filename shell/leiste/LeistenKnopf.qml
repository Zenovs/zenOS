import QtQuick
import qs.theme
import qs.komponenten

// Knopf der Leiste (28 px, Radius 8) mit freiem Inhalt, z. B. Symbole und Mono-Text
// (Mitteilungen, Hell/Dunkel, System). Zeigen und Drücken färben leicht ein wie beim Chip.
Item {
    id: root

    // Hintergrund, z. B. Theme.abgesetzt beim System-Knopf
    property color flaeche: Theme.durchsichtig
    // Innenabstand links und rechts (bei fester Breite egal, der Inhalt steht mittig)
    property int innenabstand: 10
    // Abstand zwischen den Inhalten
    property int abstand: 6
    // true, solange das zugehörige Menü offen ist (leicht eingefärbt wie beim Drücken)
    property bool aktiv: false
    property string beschreibung
    default property alias inhalt: row.data

    signal clicked

    implicitHeight: 28
    implicitWidth: row.implicitWidth + 2 * innenabstand
    activeFocusOnTab: enabled

    Accessible.role: Accessible.Button
    Accessible.name: beschreibung
    Accessible.onPressAction: clicked()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: root.flaeche
    }

    // Zustände: Zeigen und Drücken
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: Theme.text
        opacity: mouse.pressed || root.aktiv ? 0.09 : mouse.containsMouse ? 0.05 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: root.abstand
    }

    Fokusrahmen {
        eckenRadius: Theme.radiusChip
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
