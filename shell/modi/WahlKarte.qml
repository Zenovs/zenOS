import QtQuick
import qs.theme
import qs.komponenten

// Karte der Modus- und Zustandswahl: Fläche mit 1-px-Rahmen, Radius 12, blendet ruhig ein.
// Pfeil hoch/runter und Tab wandern zwischen den Einträgen, Esc schliesst.
FocusScope {
    id: root

    property string titel
    property int breite: 280
    default property alias inhalt: spalte.data

    signal schliessen

    implicitWidth: breite
    implicitHeight: spalte.implicitHeight + 2 * Theme.a2
    opacity: 0

    Component.onCompleted: opacity = 1

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.dauerKurz
            easing.type: Theme.kurve
        }
    }

    // Zum nächsten bzw. vorigen sichtbaren Eintrag (am Ende wieder von vorn)
    function _move(forward: bool): void {
        const items = [];
        for (const c of spalte.children) {
            if (c.visible && c.activeFocusOnTab)
                items.push(c);
        }
        if (items.length === 0)
            return;
        const i = items.findIndex(c => c.activeFocus);
        const next = i < 0 ? 0 : (i + (forward ? 1 : items.length - 1)) % items.length;
        items[next].forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }

    Keys.onEscapePressed: root.schliessen()
    Keys.onUpPressed: _move(false)
    Keys.onDownPressed: _move(true)
    Keys.onTabPressed: _move(true)
    Keys.onBacktabPressed: _move(false)

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

        Item {
            visible: root.titel.length > 0
            width: parent.width
            height: 30

            Abschnittstitel {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.titel
            }
        }
    }
}
