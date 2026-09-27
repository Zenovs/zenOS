import QtQuick
import qs.theme
import qs.komponenten
import qs.dienste

// Hinweis auf die Leitplanken (Entwurf 2 «Modi»): Schloss, fett «Leitplanke:», Text.
Rectangle {
    id: root

    property string text: Leitplanken.hinweis
    property string titel: "Leitplanke:"

    implicitWidth: 600
    implicitHeight: inhalt.implicitHeight + 28
    radius: Theme.radiusFeld
    color: Qt.alpha(Theme.flaeche2, 0.55)

    Symbol {
        x: 16
        y: 14 + 2
        name: "schloss"
        groesse: 16
        farbe: Theme.gedaempft
    }

    Text {
        id: inhalt

        x: 16 + 16 + 12
        y: 14
        width: root.width - x - 16
        text: "<b>" + root.titel + "</b> " + root.text
        textFormat: Text.StyledText
        wrapMode: Text.WordWrap
        lineHeight: 1.5
        color: Theme.text
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseText
    }
}
