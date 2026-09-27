pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten

// Segmentauswahl wie «Erscheinungsbild» in Entwurf 2: Fläche flaeche2, Radius 10, das gewählte
// Segment hebt sich mit flaeche ab. optionen: [{ wert, text }]. Pfeiltasten wechseln.
Item {
    id: root

    property var optionen: []
    property string wert
    property bool aktiv: true

    // Nur bei Bedienung
    signal gewaehlt(string wert)

    readonly property int _index: Math.max(0, optionen.findIndex(o => o.wert === wert))

    function _choose(i: int): void {
        if (i < 0 || i >= optionen.length || !aktiv)
            return;
        wert = optionen[i].wert;
        gewaehlt(optionen[i].wert);
    }

    implicitWidth: reihe.implicitWidth + 8
    implicitHeight: 38
    activeFocusOnTab: aktiv
    opacity: aktiv ? 1 : 0.5

    Accessible.role: Accessible.PageTabList

    Keys.onLeftPressed: _choose(_index - 1)
    Keys.onRightPressed: _choose(_index + 1)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusFeld
        color: Theme.flaeche2
    }

    Row {
        id: reihe

        x: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: root.optionen

            Item {
                id: segment

                required property var modelData
                required property int index
                readonly property bool gewaehlt: root.wert === modelData.wert

                width: beschriftung.implicitWidth + 28
                height: 30

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

                Text {
                    id: beschriftung

                    anchors.centerIn: parent
                    text: segment.modelData.text
                    color: segment.gewaehlt ? Theme.text : Theme.gedaempft
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                }

                MouseArea {
                    id: maus

                    anchors.fill: parent
                    enabled: root.aktiv
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._choose(segment.index)
                }

                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.text
                Accessible.checked: gewaehlt
            }
        }
    }

    Fokusrahmen {
        eckenRadius: Theme.radiusFeld
    }
}
