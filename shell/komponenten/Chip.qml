import QtQuick
import qs.theme

// Chip (28 px, Radius 8) wie in der Leiste von Entwurf 2.
// Varianten: "gefuellt" (Fläche flaeche2, z. B. Modus), "umrandet" (1-px-Rahmen, z. B. Zustand),
// "still" (ohne Fläche, gedämpft, z. B. Raster), "abgesetzt" (leicht abgesetzte Fläche, z. B. System-Knopf).
Item {
    id: root

    property string text
    property string symbol
    property string zusatz
    property bool pfeil: false
    property bool mitPunkt: false
    property color punktFarbe: Theme.akzent
    property string variante: "gefuellt"
    property color randFarbe: Theme.eingabeRand
    property color textFarbe: variante === "still" ? Theme.gedaempft : Theme.text
    // Beschriftung in Geist Mono 12 (z. B. «4er»)
    property bool mono: false
    property int schriftGroesse: mono ? Theme.groesseKlein : Theme.groesseLabel

    signal clicked

    // Der 1-px-Rahmen von «umrandet» kommt zum Innenabstand hinzu (wie border + padding im CSS von Entwurf 2)
    readonly property int _rand: variante === "umrandet" ? 1 : 0

    implicitHeight: 28
    implicitWidth: content.implicitWidth + content.x + (pfeil ? 8 : 10) + _rand
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: clicked()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: root.variante === "gefuellt" ? Theme.flaeche2 : root.variante === "abgesetzt" ? Theme.abgesetzt : Theme.durchsichtig
        border.width: root.variante === "umrandet" ? 1 : 0
        border.color: root.randFarbe
    }

    // Zustände: Zeigen und Drücken
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: Theme.text
        opacity: mouse.pressed ? 0.09 : mouse.containsMouse ? 0.05 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Row {
        id: content

        x: 10 + root._rand
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.symbol.length > 0 ? 6 : 8

        Rectangle {
            visible: root.mitPunkt
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 3.5
            color: root.punktFarbe
        }

        Symbol {
            visible: root.symbol.length > 0
            anchors.verticalCenter: parent.verticalCenter
            name: root.symbol
            groesse: 14
            farbe: root.textFarbe
        }

        Text {
            visible: root.text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.textFarbe
            font.family: root.mono ? Theme.schriftMono : Theme.schriftText
            font.pixelSize: root.schriftGroesse
        }

        Text {
            visible: root.zusatz.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.zusatz
            color: Theme.gedaempft
            font.family: Theme.schriftMono
            font.pixelSize: Theme.groesseKlein
        }

        Symbol {
            visible: root.pfeil
            anchors.verticalCenter: parent.verticalCenter
            name: "pfeil-runter"
            groesse: 12
            farbe: Theme.gedaempft
        }
    }

    Fokusrahmen {
        eckenRadius: Theme.radiusChip
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
