//@ pragma IconTheme Adwaita
//@ pragma Env QT_NO_XDG_DESKTOP_PORTAL=1
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste
import qs.greeter

// Einstieg des Login-Greeters (greetd, Benutzer _greetd, gestartet von scripts/bin/zenos-greeter).
// Immer dunkel, überträgt nichts nach aussen. Kein Autologin.
ShellRoot {
    id: root

    // Ein Update aus dem Kanal übernimmt gerade den Code (zenos-kanal: /run/zenos-kanal/uebernahme, für alle lesbar).
    // Die Automatik installiert am Login-Bildschirm erst, wenn er seit 5 Min. wartet; wer sich dann anmeldet, sieht es.
    property bool updateLaeuft: false

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
            updateLaeuft: root.updateLaeuft
            // Formular und Tastaturfokus auf dem ersten Bildschirm
            mitFormular: Quickshell.screens.length === 0 || Quickshell.screens[0] === modelData
        }
    }

    FileView {
        id: uebernahme

        path: "/run/zenos-kanal/uebernahme"
        blockLoading: true
        printErrors: false
        onLoaded: root.updateLaeuft = true
        onLoadFailed: root.updateLaeuft = false
    }

    // Der Ordner besteht nur während der Installation: kein watchChanges, nur ein ruhiger Takt
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: uebernahme.reload()
    }

    Component.onCompleted: {
        Erscheinung.erzwungen = "dunkel";
        Erscheinung.synchronisieren = false;
    }
}
