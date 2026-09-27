import QtQuick
import qs.theme

// Beschriftung einer Frage im Erster-Start-Formular (Entwurf 2): Nummer in Geist Mono 12 gedämpft,
// Abstand 12, Frage 14 px, optional ein gedämpfter Zusatz («(optional)»).
Row {
    id: root

    property string nummer
    property string text
    property string zusatz

    spacing: 12

    Text {
        anchors.baseline: frage.baseline
        text: root.nummer
        color: Theme.gedaempft
        font.family: Theme.schriftMono
        font.pixelSize: Theme.groesseKlein
    }

    Text {
        id: frage

        text: root.text
        color: Theme.text
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseText
    }

    Text {
        visible: root.zusatz.length > 0
        anchors.baseline: frage.baseline
        text: root.zusatz
        color: Theme.gedaempft
        font.family: Theme.schriftText
        font.pixelSize: Theme.groesseText
    }
}
