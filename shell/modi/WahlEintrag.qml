import QtQuick
import qs.theme
import qs.komponenten

// Eintrag der Modus- und Zustandswahl (36 px, Radius 8): Punkt oder Symbol, Name, rechts ein Wert
// in Mono und ein Haken für das Aktive. Zeigen und Tastaturfokus hinterlegen mit flaeche2.
Item {
    id: root

    property string text
    property string symbol
    property bool mitPunkt: false
    property color punktFarbe: Theme.akzent
    property string wert
    property bool gewaehlt: false
    property bool gedaempft: false

    signal ausgeloest

    implicitHeight: 36
    implicitWidth: 240
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45

    Accessible.role: Accessible.MenuItem
    Accessible.name: text + (wert !== "" ? ", " + wert : "") + (gewaehlt ? ", aktiv" : "")
    Accessible.onPressAction: ausgeloest()

    Keys.onPressed: event => {
        if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root.ausgeloest();
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
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Item {
            width: 14
            height: 14
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                visible: root.mitPunkt
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: root.punktFarbe
            }

            Symbol {
                visible: !root.mitPunkt && root.symbol.length > 0
                anchors.centerIn: parent
                name: root.symbol
                groesse: 14
                farbe: root.gedaempft ? Theme.gedaempft : Theme.text
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.width - 10 - 14 - 10 - rechts.width - 10 - 8
            text: root.text
            color: root.gedaempft ? Theme.gedaempft : Theme.text
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseText
            elide: Text.ElideRight
        }
    }

    Row {
        id: rechts

        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
            visible: root.wert.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.wert
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }

        Symbol {
            visible: root.gewaehlt
            anchors.verticalCenter: parent.verticalCenter
            name: "haken"
            groesse: 14
            farbe: Theme.akzent
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.ausgeloest()
    }
}
