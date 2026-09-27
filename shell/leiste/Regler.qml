import QtQuick
import qs.theme
import qs.komponenten

// Schieberegler (z. B. Lautstärke): Spur 4 px, gefüllter Teil im Akzent, Griff 14 px.
// Maus: klicken oder ziehen; Tastatur: Pfeile links/rechts (5 %), Pos1/Ende.
// «wert» bleibt von aussen gebunden; Bedienung meldet sich nur über verschoben(wert).
Item {
    id: root

    // 0.0–1.0
    property real wert: 0
    property real schritt: 0.05
    // gedämpft darstellen (z. B. stumm)
    property bool leise: false
    property string beschreibung

    signal verschoben(real wert)

    readonly property real _shown: Math.max(0, Math.min(1, mouse.pressed ? _dragValue : wert))
    property real _dragValue: 0

    function _fromX(x: real): real {
        const usable = width - knob.width;
        return usable > 0 ? Math.max(0, Math.min(1, (x - knob.width / 2) / usable)) : 0;
    }

    function _set(v: real): void {
        const value = Math.max(0, Math.min(1, v));
        verschoben(value);
    }

    implicitWidth: 200
    implicitHeight: 20
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45

    Accessible.role: Accessible.Slider
    Accessible.name: beschreibung
    Accessible.onIncreaseAction: _set(wert + schritt)
    Accessible.onDecreaseAction: _set(wert - schritt)

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Plus) {
            root._set(root.wert + root.schritt);
            event.accepted = true;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Minus) {
            root._set(root.wert - root.schritt);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home) {
            root._set(0);
            event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            root._set(1);
            event.accepted = true;
        }
    }

    Rectangle {
        id: track

        x: knob.width / 2
        width: root.width - knob.width
        height: 4
        radius: 2
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.flaeche2
    }

    Rectangle {
        anchors.left: track.left
        anchors.verticalCenter: track.verticalCenter
        width: track.width * root._shown
        height: 4
        radius: 2
        color: root.leise ? Theme.gedaempft : Theme.akzent
    }

    Rectangle {
        id: knob

        x: root._shown * (root.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        radius: 7
        color: root.leise ? Theme.gedaempft : Theme.akzent
        border.width: 2
        border.color: Theme.flaeche

        Fokusrahmen {
            aktiv: root.activeFocus
            eckenRadius: 7
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: event => {
            root.forceActiveFocus(Qt.MouseFocusReason);
            root._dragValue = root._fromX(event.x);
            root._set(root._dragValue);
        }
        onPositionChanged: event => {
            if (!pressed)
                return;
            const v = root._fromX(event.x);
            if (Math.abs(v - root._dragValue) >= 0.005) {
                root._dragValue = v;
                root._set(v);
            }
        }
    }
}
