import QtQuick
import qs.theme

// Karte der Leisten-Menüs: Fläche mit 1-px-Rahmen, Radius 12, blendet ruhig ein (120 ms).
// Esc schliesst, Pfeil hoch/runter wandert zwischen den Einträgen (am Ende wieder von vorn), Tab ebenso.
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

    // Sichtbare, bedienbare Einträge in Reihenfolge, auch verschachtelte (z. B. der Regler in seiner Zeile)
    function _entries(): var {
        const result = [];
        const collect = parentItem => {
            for (const child of parentItem.children) {
                if (!child.visible || !child.enabled)
                    continue;
                if (child.activeFocusOnTab)
                    result.push(child);
                else
                    collect(child);
            }
        };
        collect(spalte);
        return result;
    }

    // Zum nächsten bzw. vorigen Eintrag (am Ende wieder von vorn). Ohne Auswahl beginnt
    // Pfeil runter beim ersten, Pfeil hoch beim letzten Eintrag.
    function _move(forward: bool): void {
        const items = _entries();
        if (items.length === 0)
            return;
        const i = items.findIndex(c => c.activeFocus);
        const next = i < 0 ? (forward ? 0 : items.length - 1) : (i + (forward ? 1 : items.length - 1)) % items.length;
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

    // Klicks auf Anzeigezeilen und Ränder der Karte nicht an die Fläche dahinter durchreichen (die schliesst)
    MouseArea {
        anchors.fill: parent
    }

    Column {
        id: spalte

        x: Theme.a2
        y: Theme.a2
        width: root.width - 2 * Theme.a2
    }
}
