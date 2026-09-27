pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import Quickshell
import qs.theme
import qs.komponenten

// Liste der Apps zum Hinzufügen (z. B. «Beim Wechsel öffnen»): Suchfeld, Pfeile, Enter.
T.Popup {
    id: root

    // Schon gewählte IDs (werden nicht angeboten)
    property var ausgenommen: []

    signal gewaehlt(string id)

    readonly property var _treffer: {
        const q = suche.text.trim().toLowerCase();
        return DesktopEntries.applications.values.filter(e => !e.noDisplay && root.ausgenommen.indexOf(e.id) < 0 && e.id !== "org.quickshell" && (q === "" || (e.name ?? "").toLowerCase().indexOf(q) >= 0 || e.id.toLowerCase().indexOf(q) >= 0)).sort((a, b) => (a.name ?? "").localeCompare(b.name ?? "")).slice(0, 50);
    }

    width: 320
    height: 360
    padding: 8
    focus: true
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside

    onOpened: {
        suche.leeren();
        suche.fokussieren();
        liste.currentIndex = 0;
    }

    background: Rectangle {
        radius: Theme.radiusFenster
        color: Theme.flaeche
        border.width: 1
        border.color: Theme.linie2
    }

    contentItem: Column {
        spacing: 8

        Eingabe {
            id: suche

            width: parent.width
            implicitHeight: 38
            schriftGroesse: Theme.groesseText
            platzhalter: "App suchen"
            onAccepted: {
                if (root._treffer.length > 0)
                    root._waehlen(root._treffer[Math.max(0, liste.currentIndex)]);
            }
        }

        Connections {
            target: suche.feld.Keys

            function onDownPressed(): void {
                liste.currentIndex = Math.min(liste.count - 1, liste.currentIndex + 1);
            }
            function onUpPressed(): void {
                liste.currentIndex = Math.max(0, liste.currentIndex - 1);
            }
        }

        ListView {
            id: liste

            width: parent.width
            height: root.availableHeight - suche.height - 8
            clip: true
            model: root._treffer
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: zeile

                required property var modelData
                required property int index

                width: ListView.view.width
                height: 36

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusChip
                    color: Theme.flaeche2
                    opacity: maus.containsMouse || zeile.ListView.isCurrentItem ? 1 : 0
                }

                Image {
                    id: symbol

                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    sourceSize: Qt.size(20, 20)
                    source: zeile.modelData.icon ? Quickshell.iconPath(zeile.modelData.icon, true) : ""
                    asynchronous: true
                }

                Text {
                    anchors.left: symbol.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: zeile.modelData.name ?? zeile.modelData.id
                    color: Theme.text
                    font.family: Theme.schriftText
                    font.pixelSize: Theme.groesseText
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: maus

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._waehlen(zeile.modelData)
                }
            }

            Text {
                visible: liste.count === 0
                anchors.centerIn: parent
                text: "Keine passende App"
                color: Theme.gedaempft
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
            }
        }
    }

    function _waehlen(entry: var): void {
        if (!entry)
            return;
        close();
        gewaehlt(entry.id);
    }
}
