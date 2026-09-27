//@ pragma IconTheme Adwaita
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

    Variants {
        model: Quickshell.screens

        Anmeldefenster {
            required property var modelData

            screen: modelData
            konten: kontoliste
            ablauf: anmeldung
            // Formular und Tastaturfokus auf dem ersten Bildschirm
            mitFormular: Quickshell.screens.length === 0 || Quickshell.screens[0] === modelData
        }
    }

    Component.onCompleted: {
        Erscheinung.erzwungen = "dunkel";
        Erscheinung.synchronisieren = false;
    }
}
