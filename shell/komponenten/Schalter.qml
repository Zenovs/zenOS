import QtQuick
import qs.theme

// Ein/Aus-Schalter (36 × 20). Mit Maus und Tastatur (Leertaste, Enter) bedienbar.
Item {
    id: root

    property bool an: false
    property string beschriftung

    // Wird nur bei Bedienung ausgelöst, nicht bei Änderungen von aussen
    signal umgeschaltet(bool an)

    function _toggle(): void {
        an = !an;
        umgeschaltet(an);
    }

    implicitWidth: 36
    implicitHeight: 20
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45

    Accessible.role: Accessible.CheckBox
    Accessible.name: beschriftung
    Accessible.checkable: true
    Accessible.checked: an
    Accessible.onToggleAction: _toggle()
    Accessible.onPressAction: _toggle()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root._toggle();
            event.accepted = true;
        }
    }

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: root.an ? Theme.akzent : Theme.flaeche2
        border.width: root.an ? 0 : 1
        border.color: Theme.eingabeRand

        Behavior on color {
            ColorAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Rectangle {
        width: 14
        height: 14
        radius: 7
        y: 3
        x: root.an ? root.width - width - 3 : 3
        color: root.an ? Theme.aufAkzent : (Theme.dunkel ? Theme.gedaempft : Theme.flaeche)
        border.width: root.an || Theme.dunkel ? 0 : 1
        border.color: Theme.eingabeRand

        Behavior on x {
            NumberAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.text
        opacity: mouse.containsMouse ? 0.05 : 0
    }

    Fokusrahmen {
        eckenRadius: root.height / 2
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root._toggle()
    }
}
