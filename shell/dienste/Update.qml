pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Lage der Updates von zenOS 1.0 für Leiste und System-Menü. Installiert wird im Terminal mit «zen update»; dabei
// legt zenos-update.service Marker unter /run/zenos/update an (für alle lesbar, flüchtig):
//   laeuft    ein Update wird gerade geladen, geprüft und in die freie Hälfte geschrieben
//   neustart  ein neuer Stand ist installiert und startet beim nächsten Neustart zur Probe
// Die Oberfläche liest nur; sie startet nie selbst ein Update.
Singleton {
    id: root

    readonly property bool laeuft: _laeuft
    readonly property bool neustartNoetig: _neustart && !_laeuft

    // Gleich nachsehen (beim Öffnen des System-Menüs)
    function aktualisieren(): void {
        laeuftMarker.reload();
        neustartMarker.reload();
    }

    // --- intern ---

    property bool _laeuft: false
    property bool _neustart: false

    FileView {
        id: laeuftMarker

        path: "/run/zenos/update/laeuft"
        printErrors: false
        onLoaded: root._laeuft = true
        onLoadFailed: root._laeuft = false
    }

    FileView {
        id: neustartMarker

        path: "/run/zenos/update/neustart"
        printErrors: false
        onLoaded: root._neustart = true
        onLoadFailed: root._neustart = false
    }

    // Die Marker bestehen nur kurz: kein watchChanges auf einem Ordner, der fehlen kann, nur ein ruhiger Takt
    Timer {
        interval: root._laeuft ? 3000 : 30000
        running: true
        repeat: true
        onTriggered: root.aktualisieren()
    }
}
