import QtQuick
import qs.theme

// Abschnittstitel: Geist Mono 11–12 px, Grossbuchstaben, Sperrung 0.1em, gedämpft.
Text {
    property int groesse: 11

    color: Theme.gedaempft
    font.family: Theme.schriftMono
    font.pixelSize: groesse
    font.capitalization: Font.AllUppercase
    font.letterSpacing: groesse * 0.1
    elide: Text.ElideRight
}
