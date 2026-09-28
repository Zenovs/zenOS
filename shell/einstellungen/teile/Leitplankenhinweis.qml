import QtQuick
import qs.theme
import qs.komponenten
import qs.dienste

// Hinweis auf die Leitplanken (Entwurf 2 «Modi»): Schloss, fett «Leitplanke:», Text.
// Entwurf: Innenabstand 14/16 px, 14 px Schrift mit line-height 1.5, also 21 px pro Zeile.
Rectangle {
    id: root

    property string text: Leitplanken.hinweis
    property string titel: "Leitplanke:"

    implicitWidth: 600
    implicitHeight: Math.max(1, inhalt.lineCount) * inhalt.lineHeight + 28
    radius: Theme.radiusFeld
    color: Qt.alpha(Theme.flaeche2, 0.55)

    Symbol {
        x: 16
        y: 14 + 2
        name: "schloss"
        groesse: 16
        farbe: Theme.gedaempft
    }

    // Feste Zeilenhöhe wie CSS line-height: Qt vervielfacht sonst die natürliche Zeilenhöhe der
    // Schrift (bei Geist 14 px rund 29 px statt 21). Qt setzt die Glyphen oben in die Zeile, der
    // Browser mittig; der Versatz gleicht das aus.
    Text {
        id: inhalt

        x: 16 + 16 + 12
        y: 14 + Math.round((lineHeight - schriftMass.height) / 2)
        width: root.width - x - 16
        text: "<b>" + root.titel + "</b> " + root.text
        textFormat: Text.StyledText
        wrapMode: Text.WordWrap
        lineHeightMode: Text.FixedHeight
        lineHeight: Math.round(Theme.groesseText * 1.5)
        color: Theme.text
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseText
    }

    FontMetrics {
        id: schriftMass

        font: inhalt.font
    }
}
