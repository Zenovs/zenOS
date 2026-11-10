//@ pragma IconTheme Adwaita
//@ pragma Env QT_NO_XDG_DESKTOP_PORTAL=1
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.dienste
import qs.greeter

// Einstieg des Login-Greeters (greetd, Benutzer _greetd, gestartet von /usr/lib/zenos/greeter).
// Immer dunkel, überträgt nichts nach aussen. Kein Autologin.
ShellRoot {
    id: root

    // Ein Update wird gerade installiert (zenos-update.service legt /run/zenos/update/laeuft an, für alle lesbar).
    // Wer sich dann anmeldet, sieht es; das Update läuft weiter.
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

    // Nach 1 Min. ohne Eingabe Bildschirm aus; die Eingabe, die weckt, wird verworfen
    Bildschirm {
        id: bildschirm

        leerlauf: leerlauf
    }

    // Ein kurzer Druck auf die Ein/Aus-Taste schaltet nicht aus: logind sperrt damit nur (HandlePowerKey=lock in
    // /etc/systemd/logind.conf.d/zenos.conf), am Login also nichts. Gedrückt halten schaltet aus.

    Variants {
        model: Quickshell.screens

        Anmeldefenster {
            required property var modelData

            screen: modelData
            konten: kontoliste
            ablauf: anmeldung
            leerlauf: leerlauf
            bildschirm: bildschirm
            updateLaeuft: root.updateLaeuft
            // Formular und Tastaturfokus auf dem ersten Bildschirm
            mitFormular: Quickshell.screens.length === 0 || Quickshell.screens[0] === modelData
        }
    }

    FileView {
        id: updateMarker

        path: "/run/zenos/update/laeuft"
        blockLoading: true
        printErrors: false
        onLoaded: root.updateLaeuft = true
        onLoadFailed: root.updateLaeuft = false
    }

    // Der Marker besteht nur während der Installation: kein watchChanges, nur ein ruhiger Takt
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: updateMarker.reload()
    }

    Component.onCompleted: {
        Erscheinung.erzwungen = "dunkel";
        Erscheinung.synchronisieren = false;
    }
}
