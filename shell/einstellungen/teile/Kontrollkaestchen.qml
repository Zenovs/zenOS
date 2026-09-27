import QtQuick
import qs.theme
import qs.komponenten

// Kontrollkästchen (16 px, Radius 4) mit Beschriftung. Leertaste oder Enter schaltet um.
Item {
    id: root

    property bool an: false
    property string text
    property bool aktiv: true
    property color akzent: Theme.akzent
    property int groesse: 16

    // Nur bei Bedienung
    signal umgeschaltet(bool an)

    function _toggle(): void {
        if (!aktiv)
            return;
        an = !an;
        umgeschaltet(an);
    }

    implicitWidth: kasten.width + (label.visible ? 8 + label.implicitWidth : 0)
    implicitHeight: Math.max(groesse + 4, label.implicitHeight)
    activeFocusOnTab: aktiv
    opacity: aktiv ? 1 : 0.5

    Accessible.role: Accessible.CheckBox
    Accessible.name: text
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
        id: kasten

        anchors.verticalCenter: parent.verticalCenter
        width: root.groesse
        height: root.groesse
        radius: 4
        color: root.an ? root.akzent : Theme.flaeche
        border.width: root.an ? 0 : 1
        border.color: maus.containsMouse && root.aktiv ? Theme.gedaempft : Theme.eingabeRand

        Behavior on color {
            ColorAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }

        Symbol {
            visible: root.an
            anchors.centerIn: parent
            name: "haken"
            groesse: root.groesse - 4
            strichbreite: 3
            farbe: Theme.aufAkzent
        }

        Fokusrahmen {
            aktiv: root.activeFocus
            eckenRadius: 4
        }
    }

    Text {
        id: label

        visible: root.text.length > 0
        anchors.left: kasten.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Theme.text
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseText
    }

    MouseArea {
        id: maus

        anchors.fill: parent
        enabled: root.aktiv
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root._toggle()
    }
}
