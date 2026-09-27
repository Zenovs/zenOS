import QtQuick
import qs.theme
import qs.komponenten

// Zahl mit − und + (38 px), z. B. Minuten. Pfeiltasten ändern, Bild auf/ab in grossen Schritten.
Item {
    id: root

    property int wert: 0
    property int min: 0
    property int max: 100
    property int schritt: 1
    property string einheit
    property bool aktiv: true

    // Nur bei Bedienung
    signal geaendert(int wert)

    function _set(n: int): void {
        const v = Math.min(max, Math.max(min, n));
        if (v === wert)
            return;
        wert = v;
        geaendert(v);
    }

    implicitWidth: minus.width + anzeige.width + plus.width
    implicitHeight: 38
    activeFocusOnTab: aktiv
    opacity: aktiv ? 1 : 0.5

    Accessible.role: Accessible.SpinBox
    Accessible.name: wert + " " + einheit

    Keys.onPressed: event => {
        if (!root.aktiv)
            return;
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Right) {
            root._set(root.wert + root.schritt);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Left) {
            root._set(root.wert - root.schritt);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) {
            root._set(root.wert + 10 * root.schritt);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
            root._set(root.wert - 10 * root.schritt);
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: Theme.flaeche
        border.width: 1
        border.color: root.activeFocus ? Theme.akzent : Theme.eingabeRand
    }

    Item {
        id: minus

        width: 38
        height: parent.height

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 6
            color: Theme.text
            opacity: minusMaus.containsMouse && root.wert > root.min ? 0.06 : 0
        }

        Text {
            anchors.centerIn: parent
            text: "−"
            color: root.wert > root.min ? Theme.text : Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseGross
        }

        MouseArea {
            id: minusMaus

            anchors.fill: parent
            enabled: root.aktiv
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root._set(root.wert - root.schritt)
        }
    }

    Text {
        id: anzeige

        anchors.left: minus.right
        width: Math.max(72, implicitWidth + 8)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: root.wert + (root.einheit.length > 0 ? " " + root.einheit : "")
        color: Theme.text
        font.family: Theme.schriftMono
        font.pixelSize: Theme.groesseLabel
    }

    Item {
        id: plus

        anchors.left: anzeige.right
        width: 38
        height: parent.height

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 6
            color: Theme.text
            opacity: plusMaus.containsMouse && root.wert < root.max ? 0.06 : 0
        }

        Text {
            anchors.centerIn: parent
            text: "+"
            color: root.wert < root.max ? Theme.text : Theme.gedaempft
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseGross
        }

        MouseArea {
            id: plusMaus

            anchors.fill: parent
            enabled: root.aktiv
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root._set(root.wert + root.schritt)
        }
    }

    Fokusrahmen {
        eckenRadius: Theme.radiusChip
    }
}
