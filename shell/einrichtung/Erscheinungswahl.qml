pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten

// «Erscheinungsbild» wie in Entwurf 2 «Erster Start»: Fläche flaeche2 (Radius 10, Innenabstand 4),
// Segmente 36 px mit Auswahlpunkt; das gewählte hebt sich mit flaeche ab. Pfeiltasten wechseln.
Item {
    id: root

    property string wert: "hell"
    readonly property var optionen: [
        {
            wert: "hell",
            text: "Hell"
        },
        {
            wert: "dunkel",
            text: "Dunkel"
        },
        {
            wert: "tageszeit",
            text: "Nach Tageszeit"
        }
    ]

    // Nur bei Bedienung
    signal gewaehlt(string wert)

    readonly property int _index: Math.max(0, optionen.findIndex(o => o.wert === wert))

    function _waehlen(i: int): void {
        if (i < 0 || i >= optionen.length)
            return;
        wert = optionen[i].wert;
        gewaehlt(wert);
    }

    implicitWidth: reihe.implicitWidth + 8
    implicitHeight: 44
    activeFocusOnTab: true

    Accessible.role: Accessible.RadioButton
    Accessible.name: "Erscheinungsbild: " + optionen[_index].text

    Keys.onLeftPressed: _waehlen(_index - 1)
    Keys.onRightPressed: _waehlen(_index + 1)
    Keys.onUpPressed: _waehlen(_index - 1)
    Keys.onDownPressed: _waehlen(_index + 1)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusFeld
        color: Theme.flaeche2
    }

    Row {
        id: reihe

        x: 4
        y: 4
        spacing: 4

        Repeater {
            model: root.optionen

            Item {
                id: segment

                required property var modelData
                required property int index
                readonly property bool gewaehlt: root.wert === modelData.wert

                width: inhalt.implicitWidth + 28
                height: 36

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: Theme.flaeche
                    opacity: segment.gewaehlt ? 1 : maus.containsMouse ? 0.45 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.dauerKurz
                            easing.type: Theme.kurve
                        }
                    }
                }

                Row {
                    id: inhalt

                    anchors.centerIn: parent
                    spacing: 8

                    // Auswahlpunkt wie ein Radioknopf
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.flaeche
                        border.width: segment.gewaehlt ? 1.5 : 1
                        border.color: segment.gewaehlt ? Theme.akzent : Theme.gedaempft

                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.akzent
                            visible: segment.gewaehlt
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: segment.modelData.text
                        color: segment.gewaehlt ? Theme.text : Theme.gedaempft
                        font.family: Theme.schriftText
                        font.pixelSize: Theme.groesseText
                    }
                }

                MouseArea {
                    id: maus

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.forceActiveFocus();
                        root._waehlen(segment.index);
                    }
                }

                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.text
                Accessible.checked: gewaehlt
            }
        }
    }

    Fokusrahmen {
        eckenRadius: Theme.radiusFeld
    }
}
