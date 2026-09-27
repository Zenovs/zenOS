import QtQuick
import qs.theme

// Karte der Leisten-Menüs: Fläche mit 1-px-Rahmen, Radius 12, blendet ruhig ein (120 ms).
// Esc schliesst, Pfeil hoch/runter wandert zwischen den Einträgen, Tab ebenso.
FocusScope {
    id: root

    property int breite: 300
    default property alias inhalt: spalte.data

    signal schliessen

    implicitWidth: breite
    implicitHeight: spalte.implicitHeight + 2 * Theme.a2
    focus: true
    opacity: 0

    Component.onCompleted: opacity = 1

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.dauerKurz
            easing.type: Theme.kurve
        }
    }

    function _move(forward: bool): void {
        const current = Window.activeFocusItem;
        const start = current && current !== root ? current : root;
        const next = start.nextItemInFocusChain(forward);
        if (next)
            next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }

    Keys.onEscapePressed: root.schliessen()
    Keys.onUpPressed: _move(false)
    Keys.onDownPressed: _move(true)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusFenster
        color: Theme.flaeche
        border.width: 1
        border.color: Theme.linie2
    }

    Column {
        id: spalte

        x: Theme.a2
        y: Theme.a2
        width: root.width - 2 * Theme.a2
    }
}
