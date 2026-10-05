//@ pragma IconTheme Adwaita
//@ pragma Env QT_NO_XDG_DESKTOP_PORTAL=1
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.dienste
import qs.greeter

// Einstieg des Login-Greeters (greetd, Benutzer _greetd, gestartet von scripts/bin/zenos-greeter).
// Immer dunkel, überträgt nichts nach aussen. Kein Autologin.
ShellRoot {
    id: root

    Konten {
        id: kontoliste
    }

    Ablauf {
        id: anmeldung
    }

    // Im Akkubetrieb nach 30 Min. ohne Eingabe aus, dazu die Zeile der Vorwarnung (auch bei leerem Akku)
    Leerlauf {
        id: leerlauf
    }

    Variants {
        model: Quickshell.screens

        Anmeldefenster {
            required property var modelData

            screen: modelData
            konten: kontoliste
            ablauf: anmeldung
            leerlauf: leerlauf
            // Formular und Tastaturfokus auf dem ersten Bildschirm
            mitFormular: Quickshell.screens.length === 0 || Quickshell.screens[0] === modelData
        }
    }

    Component.onCompleted: {
        Erscheinung.erzwungen = "dunkel";
        Erscheinung.synchronisieren = false;
    }
}
