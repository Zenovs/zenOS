import QtQuick
import qs.theme
import qs.komponenten

// Fuss einer Seite: Pfad der Datei (Mono 12) links, rechts «… löschen» mit Rückfrage und «Fertig».
Item {
    id: root

    property string pfad
    // Leer: kein Löschen-Knopf
    property string loeschenText
    property string rueckfrage: "Wirklich löschen?"
    property color akzent: Theme.akzent

    signal loeschen
    signal fertig

    property bool _fragen: false

    implicitHeight: 40

    Text {
        anchors.left: parent.left
        anchors.right: knoepfe.left
        anchors.rightMargin: Theme.a4
        anchors.verticalCenter: parent.verticalCenter
        text: root._fragen ? root.rueckfrage : root.pfad
        color: root._fragen ? Theme.fehler : Theme.gedaempft
        font.family: root._fragen ? Theme.schriftText : Theme.schriftMono
        font.pixelSize: root._fragen ? Theme.groesseText : Theme.groesseKlein
        elide: Text.ElideMiddle
    }

    Row {
        id: knoepfe

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Knopf {
            visible: root.loeschenText.length > 0 && !root._fragen
            implicitHeight: 40
            variante: "gefahr"
            text: root.loeschenText
            onClicked: root._fragen = true
        }

        Knopf {
            visible: root._fragen
            implicitHeight: 40
            variante: "still"
            text: "Abbrechen"
            onClicked: root._fragen = false
        }

        Knopf {
            visible: root._fragen
            implicitHeight: 40
            variante: "gefahr"
            text: "Löschen"
            onClicked: {
                root._fragen = false;
                root.loeschen();
            }
        }

        Knopf {
            visible: !root._fragen
            implicitHeight: 40
            variante: "primaer"
            text: "Fertig"
            onClicked: root.fertig()
        }
    }
}
