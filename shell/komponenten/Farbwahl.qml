pragma ComponentBehavior: Bound

import QtQuick
import qs.theme

// Fünf Akzent-Kreise (28 px) wie in Entwurf 2 «Erster Start» und «Modi».
// Pfeiltasten wechseln, Leertaste/Enter wählt.
Item {
    id: root

    // Name des gewählten Akzents, z. B. "salbei"
    property string auswahl: Theme.standardAkzent
    // Farbe der Fläche, auf der die Kreise liegen (für den Abstand zum Auswahlring)
    property color hintergrund: Theme.grund
    property int abstand: 8
    property int kreis: 28

    // Wird nur bei Bedienung ausgelöst
    signal ausgewaehlt(string name)

    property int _cursor: Math.max(0, Theme.akzentNamen.indexOf(auswahl))

    function _choose(name: string): void {
        auswahl = name;
        ausgewaehlt(name);
    }

    implicitWidth: row.implicitWidth
    implicitHeight: kreis + 4
    activeFocusOnTab: enabled

    Accessible.role: Accessible.RadioButton
    Accessible.name: Theme.akzentAnzeige(auswahl)

    Keys.onPressed: event => {
        const n = Theme.akzentNamen.length;
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            root._cursor = (root._cursor + 1) % n;
            root._choose(Theme.akzentNamen[root._cursor]);
            event.accepted = true;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root._cursor = (root._cursor + n - 1) % n;
            root._choose(Theme.akzentNamen[root._cursor]);
            event.accepted = true;
        }
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        spacing: root.abstand - 4

        Repeater {
            model: Theme.akzentNamen

            Item {
                id: slot

                required property string modelData
                required property int index
                readonly property bool gewaehlt: root.auswahl === modelData
                readonly property color farbe: Theme.akzentFarbe(modelData)

                width: root.kreis + 4
                height: root.kreis + 4

                // Auswahlring (2 px Farbe, 2 px Abstand in der Hintergrundfarbe)
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: slot.gewaehlt ? slot.farbe : Theme.durchsichtig
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: root.kreis
                    height: root.kreis
                    radius: width / 2
                    color: slot.farbe
                    border.width: 2
                    border.color: root.hintergrund
                    scale: mouse.containsMouse && !slot.gewaehlt ? 1.06 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.dauerKurz
                            easing.type: Theme.kurve
                        }
                    }
                }

                // Tastaturfokus auf dem aktuellen Kreis
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: width / 2
                    color: Theme.durchsichtig
                    border.width: 2
                    border.color: Theme.gedaempft
                    visible: root.activeFocus && root._cursor === slot.index
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root._cursor = slot.index;
                        root._choose(slot.modelData);
                    }
                }

                Accessible.role: Accessible.RadioButton
                Accessible.name: "Farbe " + Theme.akzentAnzeige(slot.modelData)
                Accessible.checked: slot.gewaehlt
            }
        }
    }
}
