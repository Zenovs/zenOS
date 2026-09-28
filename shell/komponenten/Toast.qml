import QtQuick
import qs.theme

// Kurzer, ruhiger Hinweis: Pille mit Text, optional mit Symbol.
// zeigen(text) blendet ein (120 ms) und nach «dauer» wieder aus (200 ms).
// Das Symbol erscheint im Akzent, «warnung» in warnung, «x» in fehler.
Item {
    id: root

    property string text
    property string symbol: "haken"
    property color symbolFarbe: symbol === "warnung" ? Theme.warnung : symbol === "x" ? Theme.fehler : Theme.akzent
    property int dauer: 2500
    readonly property bool sichtbar: _shown || pill.opacity > 0

    property bool _shown: false

    function zeigen(neuerText: string): void {
        root.text = neuerText;
        _shown = true;
        timer.restart();
    }

    function verbergen(): void {
        timer.stop();
        _shown = false;
    }

    implicitWidth: pill.width
    implicitHeight: pill.height

    Rectangle {
        id: pill

        // ganze Pixel: das Fenster ist so breit wie die Pille, ein Bruchteil würde rechts abgeschnitten
        width: Math.ceil(Math.min(content.implicitWidth + 32, 560))
        height: 40
        radius: Theme.radiusPille
        color: Theme.flaeche
        border.width: 1
        border.color: Theme.linie2
        opacity: root._shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root._shown ? Theme.dauerKurz : Theme.dauerMax
                easing.type: Theme.kurve
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
                farbe: root.symbolFarbe
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 560 - 32 - 23)
                // Hinweise kommen auch über IPC (z. B. mit Dateinamen): nie als Rich Text
                textFormat: Text.PlainText
                text: root.text
                color: Theme.text
                font.family: Theme.schriftText
                font.pixelSize: Theme.groesseText
                elide: Text.ElideRight
            }
        }
    }

    Timer {
        id: timer

        interval: root.dauer
        onTriggered: root._shown = false
    }
}
