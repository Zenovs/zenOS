pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.komponenten

// Linke Spalte des Erster-Start-Bildschirms (Entwurf 2): Zeichen 44 px im Akzent, Titel in
// Instrument Serif 76 px, Text 17 px gedämpft und eine Zeile in Geist Mono 12.
Column {
    id: root

    property string titel
    property string text
    // Kurze Aussagen, getrennt durch «·»
    property var fuss: []

    spacing: 24

    Zeichen {
        groesse: 44
        strichbreite: 1.8
        farbe: Theme.akzent
    }

    Text {
        width: parent.width
        text: root.titel
        color: Theme.text
        font.family: Theme.schriftAnzeige
        font.pixelSize: 76
        font.letterSpacing: -0.76
        lineHeightMode: Text.FixedHeight
        lineHeight: 78
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
    }

    Text {
        width: Math.min(440, parent.width)
        text: root.text
        color: Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: 17
        lineHeightMode: Text.FixedHeight
        lineHeight: 27
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
    }

    Row {
        spacing: 12

        Repeater {
            model: root.fuss.length > 0 ? root.fuss.length * 2 - 1 : 0

            Text {
                required property int index

                text: index % 2 === 1 ? "·" : root.fuss[index / 2]
                color: Theme.gedaempft
                font.family: Theme.schriftMono
                font.pixelSize: Theme.groesseKlein
            }
        }
    }
}
