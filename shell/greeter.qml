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

    // Ein Update aus dem Kanal übernimmt gerade den Code (zenos-kanal: /run/zenos-kanal/uebernahme) oder ein Basis-Update
    // läuft (zenos-basis: /run/zenos-basis/uebernahme), beide für alle lesbar. Die Automatik installiert am
    // Login-Bildschirm erst, wenn er seit 5 Min. wartet; wer sich dann anmeldet, sieht es.
    readonly property bool updateLaeuft: _kanalLaeuft || _basisLaeuft
    property bool _kanalLaeuft: false
    property bool _basisLaeuft: false

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

    // Ein kurzer Druck auf die Ein/Aus-Taste weckt nur (Hemmer «handle-power-key», solange dieser Login läuft)
    EinAusTaste {}

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
        id: uebernahme

        path: "/run/zenos-kanal/uebernahme"
        blockLoading: true
        printErrors: false
        onLoaded: root._kanalLaeuft = true
        onLoadFailed: root._kanalLaeuft = false
    }

    FileView {
        id: basisUebernahme

        path: "/run/zenos-basis/uebernahme"
        blockLoading: true
        printErrors: false
        onLoaded: root._basisLaeuft = true
        onLoadFailed: root._basisLaeuft = false
    }

    // Die Ordner bestehen nur während der Installation: kein watchChanges, nur ein ruhiger Takt
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            uebernahme.reload();
            basisUebernahme.reload();
        }
    }

    Component.onCompleted: {
        Erscheinung.erzwungen = "dunkel";
        Erscheinung.synchronisieren = false;
    }
}
