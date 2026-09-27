import QtQuick
import qs.theme
import qs.komponenten

// Eintrag eines Leisten-Menüs (36 px, Radius 8): Symbol, Text, rechts ein Wert in Mono oder ein Haken.
// Zeigen und Tastaturfokus hinterlegen den Eintrag mit flaeche2 (wie die Auswahl im Befehlsfeld).
// Mit «bestaetigen» fragt der erste Klick nach (Text in fehler), erst der zweite löst aus.
Item {
    id: root

    property string text
    property string symbol
    // Platz für ein Symbol freihalten, damit Einträge mit und ohne Symbol bündig stehen
    property bool symbolPlatz: true
    property string wert
    property bool gewaehlt: false
    property bool bestaetigen: false
    property string frage
    readonly property bool gefragt: _armed

    signal ausgeloest

    property bool _armed: false

    function ausloesen(): void {
        if (!enabled)
            return;
        if (bestaetigen && !_armed) {
            _armed = true;
            disarm.restart();
            return;
        }
        _armed = false;
        disarm.stop();
        ausgeloest();
    }

    implicitHeight: 36
    implicitWidth: 200
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45

    Accessible.role: Accessible.MenuItem
    Accessible.name: _armed && frage !== "" ? frage : text
    Accessible.onPressAction: ausloesen()

    Keys.onPressed: event => {
        if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root.ausloesen();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: Theme.flaeche2
        opacity: mouse.containsMouse || root.activeFocus ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: Theme.text
        opacity: mouse.pressed ? 0.05 : 0
    }

    Row {
        id: row

        x: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Item {
            visible: root.symbolPlatz || root.symbol !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: 15
            height: 15

            Symbol {
                visible: root.symbol !== ""
                anchors.fill: parent
                name: root.symbol
                groesse: 15
                farbe: root._armed ? Theme.fehler : Theme.text2
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width - row.x - 10 - (wertText.visible ? wertText.implicitWidth + 12 : 0) - (hakenSymbol.visible ? 26 : 0) - 25)
            text: root._armed && root.frage !== "" ? root.frage : root.text
            color: root._armed ? Theme.fehler : Theme.text
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
            elide: Text.ElideRight
        }
    }

    Text {
        id: wertText

        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: root.wert !== "" && !root.gewaehlt
        text: root.wert
        color: Theme.gedaempft
        font.family: Theme.schriftMono
        font.pixelSize: Theme.groesseKlein
    }

    Symbol {
        id: hakenSymbol

        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: root.gewaehlt
        name: "haken"
        groesse: 14
        farbe: Theme.akzent
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.ausloesen()
    }

    // Nachfrage verfällt nach 4 s oder wenn der Eintrag den Fokus verliert
    Timer {
        id: disarm

        interval: 4000
        onTriggered: root._armed = false
    }

    onActiveFocusChanged: if (!activeFocus && !mouse.containsMouse) _armed = false
}
