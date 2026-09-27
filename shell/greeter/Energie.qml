import QtQuick
import Quickshell
import qs.theme
import qs.komponenten

// Neustart und Ausschalten im Login. Erst der zweite Klick (innert 5 s) führt aus, damit ein
// versehentlicher Klick den Pi nicht ausschaltet.
Row {
    id: root

    // "", "neustart" oder "ausschalten": wartet auf Bestätigung
    property string bestaetigen: ""

    spacing: Theme.a1

    function _ausloesen(aktion: string): void {
        if (bestaetigen !== aktion) {
            bestaetigen = aktion;
            zurueck.restart();
            return;
        }
        bestaetigen = "";
        Quickshell.execDetached(["systemctl", aktion === "neustart" ? "reboot" : "poweroff"]);
    }

    Timer {
        id: zurueck

        interval: 5000
        onTriggered: root.bestaetigen = ""
    }

    Knopf {
        implicitHeight: 32
        schriftGroesse: Theme.groesseLabel
        variante: root.bestaetigen === "neustart" ? "gefahr" : "still"
        text: root.bestaetigen === "neustart" ? "Jetzt neu starten" : "Neustart"
        onClicked: root._ausloesen("neustart")
    }

    Knopf {
        implicitHeight: 32
        schriftGroesse: Theme.groesseLabel
        variante: root.bestaetigen === "ausschalten" ? "gefahr" : "still"
        text: root.bestaetigen === "ausschalten" ? "Jetzt ausschalten" : "Ausschalten"
        onClicked: root._ausloesen("ausschalten")
    }
}
