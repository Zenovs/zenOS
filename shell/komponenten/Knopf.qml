import QtQuick
import qs.theme

// Knopf nach Entwurf 2 (44 px, Radius 10).
// Varianten: "primaer" (Akzentfläche), "sekundaer" (Rahmen), "still" (ohne Fläche), "gefahr" (Rahmen, Text in fehler).
// Mit Maus und Tastatur (Enter, Leertaste) bedienbar.
Item {
    id: root

    property string text
    property string symbol
    property string variante: "primaer"
    property int schriftGroesse: Theme.groesseText
    readonly property bool gedrueckt: mouse.pressed || _keyDown

    readonly property color textFarbe: {
        switch (variante) {
        case "primaer":
            return Theme.aufAkzent;
        case "still":
            return Theme.gedaempft;
        case "gefahr":
            return Theme.fehler;
        default:
            return Theme.text;
        }
    }

    signal clicked

    property bool _keyDown: false

    implicitHeight: 44
    implicitWidth: Math.max(implicitHeight, content.implicitWidth + 2 * (variante === "primaer" ? 20 : 16))
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: clicked()

    Keys.onPressed: event => {
        if (!event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root._keyDown = true;
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if (!event.isAutoRepeat && root._keyDown && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root._keyDown = false;
            event.accepted = true;
            root.clicked();
        }
    }
    onActiveFocusChanged: if (!activeFocus) _keyDown = false

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusFeld
        color: root.variante === "primaer" ? Theme.akzent : Theme.durchsichtig
        border.width: root.variante === "sekundaer" || root.variante === "gefahr" ? 1 : 0
        border.color: Theme.eingabeRand
    }

    // Zustände: auf Akzentflächen hellt bzw. dunkelt die Textfarbe ab, sonst die Textfarbe der Oberfläche
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusFeld
        color: root.variante === "primaer" ? Theme.aufAkzent : Theme.text
        opacity: root.gedrueckt ? (root.variante === "primaer" ? 0.2 : 0.09) : mouse.containsMouse ? (root.variante === "primaer" ? 0.12 : 0.05) : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: 8

        Symbol {
            visible: root.symbol.length > 0
            anchors.verticalCenter: parent.verticalCenter
            name: root.symbol
            groesse: 15
            farbe: root.textFarbe
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.text
            color: root.textFarbe
            font.family: Theme.schriftText
            font.pixelSize: root.schriftGroesse
            font.weight: root.variante === "primaer" ? Font.Medium : Font.Normal
        }
    }

    Fokusrahmen {
        eckenRadius: Theme.radiusFeld
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
