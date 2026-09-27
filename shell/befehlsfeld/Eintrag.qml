import QtQuick
import qs.theme
import qs.komponenten

// Eine Zeile im Befehlsfeld (44 px, Radius 8) nach Entwurf 2: Symbol-Kasten 28 px, Titel 15 px,
// rechts ein kurzer Hinweis in Geist Mono 12. Die Auswahl hat den Hintergrund flaeche2.
Item {
    id: root

    // {titel, hinweis, symbol, icon, punkt, buchstabe, frage, gefahr}
    property var eintrag: ({})
    property bool gewaehlt: false
    // Aktionen mit Folgen (Ausschalten …) fragen einmal nach
    property bool fragt: false

    // Maus bewegt sich über der Zeile bzw. Klick
    signal gezeigt
    signal ausgefuehrt

    implicitHeight: 44

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusChip
        color: root.gewaehlt ? Theme.flaeche2 : Theme.durchsichtig
    }

    Rectangle {
        id: kasten

        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        radius: 7
        color: root.gewaehlt ? Theme.flaeche : Theme.flaeche2

        // Akzentpunkt (Modus)
        Rectangle {
            visible: root.eintrag.punkt !== undefined
            anchors.centerIn: parent
            width: 8
            height: 8
            radius: 4
            color: root.eintrag.punkt ?? Theme.akzent
        }

        // Symbol der App aus dem Icon-Theme
        Image {
            id: bild

            visible: root.eintrag.punkt === undefined && (root.eintrag.icon ?? "").length > 0 && status === Image.Ready
            anchors.centerIn: parent
            width: 18
            height: 18
            sourceSize: Qt.size(18, 18)
            source: root.eintrag.icon ?? ""
            smooth: true
            fillMode: Image.PreserveAspectFit
        }

        Symbol {
            visible: root.eintrag.punkt === undefined && !bild.visible && (root.eintrag.symbol ?? "").length > 0
            anchors.centerIn: parent
            name: root.eintrag.symbol ?? ""
            groesse: 15
            farbe: Theme.text2
        }

        // Ohne Symbol: Anfangsbuchstabe
        Text {
            visible: root.eintrag.punkt === undefined && !bild.visible && (root.eintrag.symbol ?? "").length === 0
            anchors.centerIn: parent
            text: root.eintrag.buchstabe ?? ""
            color: Theme.text2
            font.family: Theme.schriftText
            font.pixelSize: Theme.groesseLabel
            font.weight: Font.Medium
        }
    }

    Text {
        id: titel

        anchors.left: kasten.right
        anchors.leftMargin: 12
        anchors.right: hinweis.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.fragt ? (root.eintrag.frage ?? "") : (root.eintrag.titel ?? "")
        color: Theme.text
        font.family: Theme.schriftText
        font.pixelSize: 15
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
    }

    Text {
        id: hinweis

        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.width * 0.45)
        horizontalAlignment: Text.AlignRight
        text: root.fragt ? "↵ bestätigen" : (root.eintrag.hinweis ?? "")
        color: root.fragt ? Theme.fehler : Theme.gedaempft
        font.family: Theme.schriftMono
        font.pixelSize: Theme.groesseKlein
        elide: Text.ElideMiddle
        maximumLineCount: 1
        textFormat: Text.PlainText
    }

    MouseArea {
        id: maus

        property point zuletzt: Qt.point(-1, -1)

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Nur echte Mausbewegungen wählen aus. Erscheint eine Zeile unter dem ruhenden Zeiger,
        // bleibt die Auswahl der Tastatur.
        onPositionChanged: mouse => {
            const p = mapToItem(null, mouse.x, mouse.y);
            if (zuletzt.x >= 0 && (p.x !== zuletzt.x || p.y !== zuletzt.y))
                root.gezeigt();
            zuletzt = p;
        }
        onExited: zuletzt = Qt.point(-1, -1)
        onClicked: root.ausgefuehrt()
    }
}
