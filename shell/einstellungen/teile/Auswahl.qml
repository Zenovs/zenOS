pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import qs.theme
import qs.komponenten

// Auswahlfeld (38 px, Radius 8) mit aufklappender Liste. optionen: [{ wert, text }].
// Enter/Leertaste öffnet, Pfeile wählen, Esc schliesst.
Item {
    id: root

    property var optionen: []
    property string wert
    property string platzhalter: "Bitte wählen"
    property bool aktiv: true

    // Nur bei Bedienung
    signal gewaehlt(string wert)

    readonly property var _gewaehlt: optionen.find(o => o.wert === wert) ?? null

    function _choose(o: var): void {
        liste.close();
        if (!o)
            return;
        wert = o.wert;
        gewaehlt(o.wert);
    }

    implicitWidth: 240
    implicitHeight: 38
    activeFocusOnTab: aktiv
    opacity: aktiv ? 1 : 0.5

    Accessible.role: Accessible.ComboBox
    Accessible.name: _gewaehlt ? _gewaehlt.text : platzhalter

    Keys.onPressed: event => {
        if (!root.aktiv)
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
            liste.open();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: Theme.flaeche
        border.width: 1
        border.color: liste.visible || root.activeFocus ? Theme.akzent : maus.containsMouse && root.aktiv ? Theme.gedaempft : Theme.eingabeRand

        Behavior on border.color {
            ColorAnimation {
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }
    }

    Text {
        x: 12
        width: parent.width - 12 - 32
        anchors.verticalCenter: parent.verticalCenter
        text: root._gewaehlt ? root._gewaehlt.text : root.platzhalter
        color: root._gewaehlt ? Theme.text : Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseText
        elide: Text.ElideRight
    }

    Symbol {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        name: "pfeil-runter"
        groesse: 12
        farbe: Theme.gedaempft
    }

    MouseArea {
        id: maus

        anchors.fill: parent
        enabled: root.aktiv
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: liste.visible ? liste.close() : liste.open()
    }

    T.Popup {
        id: liste

        y: root.height + 4
        width: Math.max(root.width, 200)
        height: Math.min(inhalt.implicitHeight + 2 * padding, 320)
        padding: 4
        focus: true
        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.dauerKurz
                easing.type: Theme.kurve
            }
        }

        background: Rectangle {
            radius: Theme.radiusFeld
            color: Theme.flaeche
            border.width: 1
            border.color: Theme.linie2
        }

        contentItem: ListView {
            id: inhalt

            implicitHeight: contentHeight
            clip: true
            model: root.optionen
            currentIndex: Math.max(0, root.optionen.findIndex(o => o.wert === root.wert))
            boundsBehavior: Flickable.StopAtBounds
            focus: true
            keyNavigationEnabled: true

            Keys.onReturnPressed: root._choose(root.optionen[currentIndex])
            Keys.onEnterPressed: root._choose(root.optionen[currentIndex])
            Keys.onSpacePressed: root._choose(root.optionen[currentIndex])

            delegate: Item {
                id: zeile

                required property var modelData
                required property int index

                width: ListView.view.width
                height: 34

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: Theme.flaeche2
                    opacity: zeilenMaus.containsMouse || zeile.ListView.isCurrentItem ? 1 : 0
                }

                Text {
                    x: 10
                    width: parent.width - 10 - 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: zeile.modelData.text
                    color: Theme.text
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                    elide: Text.ElideRight
                }

                Symbol {
                    visible: zeile.modelData.wert === root.wert
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "haken"
                    groesse: 14
                    farbe: Theme.akzent
                }

                MouseArea {
                    id: zeilenMaus

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._choose(zeile.modelData)
                }
            }
        }

        onClosed: root.forceActiveFocus()
    }

    Fokusrahmen {
        aktiv: root.activeFocus && !liste.visible
        eckenRadius: Theme.radiusChip
    }
}
